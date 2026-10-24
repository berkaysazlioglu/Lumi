import Foundation
import LumiKit

/// Task yazımları — hepsi iyimserdir: yerel kopya hemen değişir, sunucu
/// reddederse geri alınır ve toast gösterilir (plan: "Kullanıcıda X yoksa").
extension TasksStore {
    public func move(_ key: TaskKey, to status: TaskStatus) async {
        guard let current = entry(key), current.item.status != status || current.item.needsAttention else { return }
        await apply(TaskPatch(status: status), to: key)
    }

    public func assign(_ key: TaskKey, to user: TaskUser?) async {
        guard info(of: key.source)?.canAssign == true else { return }
        await apply(TaskPatch(assignee: user.map { .assign($0) } ?? .unassign), to: key)
    }

    public func setPriority(_ key: TaskKey, to priority: TaskPriority) async {
        guard info(of: key.source)?.canWrite(.priority) == true else { return }
        await apply(TaskPatch(priority: priority), to: key)
    }

    public func rename(_ key: TaskKey, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entry(key)?.item.title != trimmed else { return }
        await apply(TaskPatch(title: trimmed), to: key)
    }

    public func delete(_ key: TaskKey) async {
        guard info(of: key.source)?.supports(.delete) == true,
              let provider = providers[key.source],
              let index = entries.firstIndex(where: { $0.key == key })
        else { return }
        let removed = entries.remove(at: index)
        if selectedTask == key { selectedTask = nil }
        deletions[key] = beginWrite(key)
        defer { endWrite(key) }
        do {
            try await provider.delete(taskID: key.id)
        } catch TaskProviderError.notFound {
            // Zaten silinmiş — hedeflenen sonuç bu.
        } catch {
            deletions[key] = nil
            entries.insert(removed, at: min(index, entries.count))
            report(error, title: "Couldn't delete task")
        }
    }

    /// Ortak iyimser yazım yolu.
    func apply(_ patch: TaskPatch, to key: TaskKey) async {
        guard let provider = providers[key.source], let index = entries.firstIndex(where: { $0.key == key }) else { return }
        let original = entries[index]
        entries[index].item = patch.applied(to: original.item, now: now())
        beginWrite(key)
        defer { endWrite(key) }
        do {
            let saved = try await provider.update(taskID: key.id, patch: patch)
            replace(key, with: saved)
        } catch TaskProviderError.notFound {
            entries.removeAll { $0.key == key }
            if selectedTask == key { selectedTask = nil }
            toasts.show(.info, title: "Task removed", message: "\"\(original.item.title)\" no longer exists on the server.")
        } catch {
            replace(key, with: original.item)
            if case .unauthorized = error as? TaskProviderError {
                update(key.source) { $0.phase = .reconnect }
            }
            report(error, title: "Couldn't update task")
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

    func report(_ error: any Error, title: String) {
        toasts.show(.error, title: title, message: Self.message(error))
    }
}
