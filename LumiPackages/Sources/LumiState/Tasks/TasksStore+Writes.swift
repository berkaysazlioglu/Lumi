import Foundation
import LumiKit

/// Gecikmesi süren birleşik yazım: aynı task'e yapılan düzenlemeler tek
/// yamada birikir; `baseline` sunucunun bildiği son hâldir (hata olursa
/// buraya dönülür).
struct PendingWrite {
    var patch: TaskPatch
    var baseline: TaskItem
    var timer: Task<Void, Never>?
}

/// Task yazımları (Tasks planı: "Birleşik yazım").
///
/// Düzenleme ekranda HEMEN görünür; sunucuya gidiş task başına
/// `writeDelay` kadar ertelenir ve o sürede yapılan tüm düzenlemeler tek
/// `PATCH`'te birleşir (sürükleyip fikir değiştirmek, durum + öncelik + atama
/// art arda). Route'tan çıkınca ve uygulama kapanırken bekleyenler hemen
/// gönderilir (`flushAll`). Sunucu reddederse task son onaylı hâline döner,
/// hata kaydı + toast düşer. Silme ve oluşturma ertelenmez.
extension TasksStore {
    public func move(_ key: TaskKey, to status: TaskStatus) {
        guard let current = entry(key), current.item.status != status || current.item.needsAttention else { return }
        schedule(TaskPatch(status: status), for: key)
    }

    public func assign(_ key: TaskKey, to user: TaskUser?) {
        guard info(of: key.source)?.canAssign == true else { return }
        schedule(TaskPatch(assignee: user.map { .assign($0) } ?? .unassign), for: key)
    }

    public func setPriority(_ key: TaskKey, to priority: TaskPriority) {
        guard info(of: key.source)?.canWrite(.priority) == true else { return }
        schedule(TaskPatch(priority: priority), for: key)
    }

    public func rename(_ key: TaskKey, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entry(key)?.item.title != trimmed else { return }
        schedule(TaskPatch(title: trimmed), for: key)
    }

    public var hasPendingWrites: Bool { pendingWriteCount > 0 }

    /// Bekleyen tüm yazımları beklemeden gönderir.
    public func flushAll() async {
        for key in Array(pendingWrites.keys) {
            await flush(key)
        }
    }

    public func delete(_ key: TaskKey) async {
        guard info(of: key.source)?.supports(.delete) == true,
              let provider = providers[key.source],
              let index = entries.firstIndex(where: { $0.key == key })
        else { return }
        // Silinecek task'in bekleyen düzenlemesi anlamsızlaşır.
        pendingWrites.removeValue(forKey: key)?.timer?.cancel()
        pendingWriteCount = pendingWrites.count
        let removed = entries.remove(at: index)
        if selectedTask == key { selectedTask = nil }
        deletions[key] = beginWrite(key)
        defer { endWrite(key) }
        do {
            try await provider.delete(taskID: key.id)
            cleanUpImages(of: [removed])
        } catch let error where Self.isNotFound(error) {
            // Zaten silinmiş — hedeflenen sonuç bu.
            cleanUpImages(of: [removed])
        } catch {
            deletions[key] = nil
            entries.insert(removed, at: min(index, entries.count))
            let failure = record(error, operation: .delete, source: key.source, taskID: key.id)
            toasts.show(.error, title: "Couldn't delete \(key.id)", message: failure.summary)
        }
    }

    // MARK: - Birleştirme ve gönderim

    func schedule(_ patch: TaskPatch, for key: TaskKey) {
        guard providers[key.source] != nil, let index = entries.firstIndex(where: { $0.key == key }) else { return }
        let current = entries[index].item
        var write = pendingWrites[key] ?? PendingWrite(patch: TaskPatch(), baseline: current)
        write.patch = write.patch.merging(patch)
        write.timer?.cancel()
        entries[index].item = patch.applied(to: current, now: now())
        writeSequence += 1
        lastWrite[key] = writeSequence
        let delay = Self.writeDelay
        write.timer = Task { [weak self, debounce] in
            do {
                try await debounce(delay)
            } catch {
                return
            }
            // `flush` bekleyen zamanlayıcıyı iptal eder; o zamanlayıcı BU görev
            // olduğu için referans önce bırakılır — yoksa gönderilen istek
            // CancellationError ile düşüp task eski durumuna dönüyordu.
            self?.pendingWrites[key]?.timer = nil
            await self?.flush(key)
        }
        pendingWrites[key] = write
        pendingWriteCount = pendingWrites.count
    }

    func flush(_ key: TaskKey) async {
        guard let write = pendingWrites.removeValue(forKey: key) else { return }
        pendingWriteCount = pendingWrites.count
        write.timer?.cancel()
        guard !write.patch.isEmpty, let provider = providers[key.source] else { return }
        beginWrite(key)
        defer { endWrite(key) }
        do {
            let saved = try await provider.update(taskID: key.id, patch: write.patch)
            if pendingWrites[key] != nil {
                // Gönderim sürerken yeni düzenleme geldi: yerel kopya onu
                // gösteriyor, sunucunun cevabı yalnız yeni taban olur.
                pendingWrites[key]?.baseline = saved
            } else {
                replace(key, with: saved)
            }
        } catch let error where Self.isNotFound(error) {
            pendingWrites.removeValue(forKey: key)?.timer?.cancel()
            pendingWriteCount = pendingWrites.count
            entries.removeAll { $0.key == key }
            if selectedTask == key { selectedTask = nil }
            toasts.show(.info, title: "Task removed", message: "\(key.id) no longer exists on the server.")
        } catch {
            if pendingWrites[key] != nil {
                pendingWrites[key]?.baseline = write.baseline
            } else {
                replace(key, with: write.baseline)
            }
            if Self.phase(for: error) == .reconnect {
                update(key.source) { $0.phase = .reconnect }
            }
            let failure = record(error, operation: .update, source: key.source, taskID: key.id)
            toasts.show(.error, title: "Couldn't save \(key.id)", message: failure.summary)
        }
    }

    /// Silinen/kaldırılan task'lerin ajan ekleri ve — başka task kullanmıyorsa —
    /// önbellekteki görselleri.
    func cleanUpImages(of removed: [TaskEntry]) {
        guard !removed.isEmpty else { return }
        let stillUsed = Set(entries.flatMap { $0.item.images.flatMap { [$0.url] + ($0.thumbnailURL.map { [$0] } ?? []) } })
        let urls = removed
            .flatMap { $0.item.images.flatMap { [$0.url] + ($0.thumbnailURL.map { [$0] } ?? []) } }
            .filter { !stillUsed.contains($0) }
        let keys = removed.map(\.key)
        Task { [images] in
            await images.removeAttachments(for: keys)
            await images.evict(urls)
        }
    }

    func replace(_ key: TaskKey, with item: TaskItem) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        entries[index].item = item
    }

    @discardableResult
    func beginWrite(_ key: TaskKey) -> Int {
        writeSequence += 1
        inFlightWrites[key, default: 0] += 1
        lastWrite[key] = writeSequence
        return writeSequence
    }

    func endWrite(_ key: TaskKey) {
        let remaining = inFlightWrites[key, default: 1] - 1
        inFlightWrites[key] = remaining > 0 ? remaining : nil
    }

    static func isNotFound(_ error: any Error) -> Bool {
        ((error as? TaskRequestFailure)?.kind ?? (error as? TaskProviderError)) == .notFound
    }
}
