import Foundation
import LumiKit
import Observation

/// Terminal listesinin UI-yüzlü metadata store'u (design/03 §4).
/// Ham çıktı burada ASLA tutulmaz — yalnız TerminalMeta.
///
/// Değişmez kural: minimize edilmiş terminal asla odak alamaz;
/// tek istisna bildirim/bell tıklamasıdır ve `restoreAndFocus` üzerinden
/// (önce restore, sonra odak) akar.
@Observable
@MainActor
public final class TerminalListStore: StoreLifecycle {
    public private(set) var terminals: [TerminalMeta] = []
    public private(set) var activeTerminalID: TerminalID?
    public private(set) var minimizedIDs: Set<TerminalID> = []
    /// "Karar bekliyor" (izin promptu) sinyali — ephemeral, persist edilmez.
    /// Prompt kuyruğu bunu görünce duraklar (status'ten ayrı sinyal).
    public private(set) var awaitingDecisionIDs: Set<TerminalID> = []
    /// Feed akışı donmuş terminaller (design/00 Ek A §A.2-10) — ephemeral,
    /// persist EDİLMEZ: `TerminalMeta` formatı değişmez (karar 9).
    public private(set) var stalledIDs: Set<TerminalID> = []

    /// Karar 24: açıkken working'e geçen terminal otomatik minimize edilir ve
    /// turn bitince / girdi beklenince otomatik restore edilir. Config aynası —
    /// composition root günceller.
    @ObservationIgnored public private(set) var autoMinimizeOnSend = false
    /// Yalnız BU özelliğin minimize ettikleri — elle minimize edilenler otomatik
    /// restore edilmez; elle restore takibi düşürür (kullanıcı niyeti kazanır).
    @ObservationIgnored private var autoMinimizedIDs: Set<TerminalID> = []

    @ObservationIgnored private var lastActiveByRepo: [String: TerminalID] = [:]
    /// Terminal yüzeyinin şu an hangi repo için önde olduğu (Faz 4.9). Tab/route
    /// geçişinde eski repo'yu arkaya almanın tek kaynağıdır; `activeTerminalID`
    /// bundan ayrıdır (yüzey gizliyken de korunur).
    @ObservationIgnored private var surfaceRepoPath: String?
    /// Kullanıcının kapattığı terminaller: exit kodu ne olursa olsun toast
    /// gösterilmez (kendi kill'imiz hata değildir). Tek atımlıdır.
    @ObservationIgnored private var userClosedIDs: Set<TerminalID> = []
    @ObservationIgnored private let service: any TerminalSessionControlling
    @ObservationIgnored private let toasts: ToastStore
    @ObservationIgnored private let consumer = EventConsumer()

    public init(service: any TerminalSessionControlling, toasts: ToastStore) {
        self.service = service
        self.toasts = toasts
    }

    /// Config aynasının tek yazarı (kapsülleme, refactor 5.4) — bootstrap ve
    /// `configDidChange` buradan geçer.
    public func applyAutoMinimize(_ enabled: Bool) {
        autoMinimizeOnSend = enabled
    }

    /// Event tüketicisi canlı mı — `StoreLifecycle` sözleşmesinin
    /// gözlemlenebilir yüzü (kapanış sırası testleri için).
    public var isConsuming: Bool { consumer.isRunning }

    public func start() {
        consumer.start(service.events()) { [weak self] event in
            self?.apply(event)
        }
    }

    public func stop() {
        consumer.stop()
    }

    // MARK: - Selector'lar

    public func terminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath }
    }

    public func visibleTerminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath && !minimizedIDs.contains($0.id) }
    }

    public func minimizedTerminals(in repoPath: String) -> [TerminalMeta] {
        terminals.filter { $0.repoPath == repoPath && minimizedIDs.contains($0.id) }
    }

    public func isMinimized(_ id: TerminalID) -> Bool {
        minimizedIDs.contains(id)
    }

    /// Terminal donmuş mu (feed watchdog sinyali). Kart header'ındaki rozet
    /// bunu okur — siyah/boş kart yerine görünür durum.
    public func isStalled(_ id: TerminalID) -> Bool {
        stalledIDs.contains(id)
    }

    public var totalCount: Int {
        terminals.count
    }

    public func meta(for id: TerminalID) -> TerminalMeta? {
        terminals.first { $0.id == id }
    }

    // MARK: - Intent'ler

    public func spawn(in repoPath: String, command: String? = nil, task: String? = nil) {
        toasts.reporting {
            _ = try self.service.spawn(repoPath: repoPath, task: task, command: command)
        }
    }

    public func close(_ id: TerminalID) {
        userClosedIDs.insert(id)
        let didKill = toasts.reporting {
            try self.service.kill(id: id)
        }
        if !didKill {
            userClosedIDs.remove(id)
        }
    }

    public func closeAll(in repoPath: String) {
        for meta in terminals(in: repoPath) {
            close(meta.id)
        }
    }

    /// setActiveTerminal paritesi: id map'te olmasa bile set edilir
    /// (yeni spawn henüz yansımamış olabilir); minimize edilmişe odak verilmez.
    public func focus(_ id: TerminalID?) {
        guard let id else {
            activeTerminalID = nil
            service.setFocused(nil)
            return
        }
        guard !minimizedIDs.contains(id) else { return }
        activeTerminalID = id
        if let repoPath = meta(for: id)?.repoPath {
            lastActiveByRepo[repoPath] = id
        }
        service.setFocused(id)
    }

    /// Orta alanın terminal yüzeyini gösteren/gizleyen TEK intent (Faz 4.9).
    ///
    /// Üç odak otoritesi (`activeTerminalID` / `statusMachine.focused` /
    /// AppKit first responder) burada birleşir: yüzey gizlenince servise
    /// `setFocused(nil)` gider — ekranda olmayan terminal "odaklı" sayılmaz,
    /// `waitingUnseen` doğru yükselir ve karar 24 auto-minimize'ı bozulmaz —
    /// ama `activeTerminalID` KORUNUR, böylece dönüşte aynı terminal geri
    /// odaklanır. Route değişimi (Faz 6.3) ve tab geçişi aynı intent'i kullanır.
    public func setTerminalSurfaceVisible(_ visible: Bool, in repoPath: String) {
        service.setSurfaceState(visible ? .foreground : .background, in: repoPath)
        guard visible else {
            service.setFocused(nil)
            return
        }
        guard let active = activeTerminalID,
              meta(for: active)?.repoPath == repoPath,
              !minimizedIDs.contains(active) else { return }
        service.setFocused(active)
    }

    /// Minimize: aktifse görünür komşuya proaktif odak kayar.
    public func minimize(_ id: TerminalID) {
        guard let repoPath = meta(for: id)?.repoPath else { return }
        minimizedIDs.insert(id)
        // Karar 24 akışı dahil: gizlenen kart arka plan politikasına düşer
        // (coalescer 100ms + onBlur) — "görünmüyor ama odaklı" hâli kalmaz.
        service.setSurfaceState(.minimized, for: id)
        if activeTerminalID == id {
            let visibleBefore = terminals.filter {
                $0.repoPath == repoPath && ($0.id == id || !minimizedIDs.contains($0.id))
            }
            focus(Self.neighborID(closing: id, among: visibleBefore))
        }
        if lastActiveByRepo[repoPath] == id {
            lastActiveByRepo[repoPath] = visibleTerminals(in: repoPath).first?.id
        }
    }

    /// Restore odaklamaz — odaklı restore yalnız bildirim/bell tıklamasıyla.
    /// Yüzey öne alınır ama odak verilmez (`setSurfaceState` odağı servisin
    /// kendi otoritesinden okur). Arka plandaki tab'da restore edilen terminal
    /// (karar 24 otomatik restore'u her repoda çalışır) ekrana dönmediği için
    /// arka plan politikasında kalır; tab'a geçişte `activateRepo` öne alır.
    public func restore(_ id: TerminalID) {
        minimizedIDs.remove(id)
        autoMinimizedIDs.remove(id)
        guard let repoPath = meta(for: id)?.repoPath, isSurfaceForeground(repoPath) else { return }
        service.setSurfaceState(.foreground, for: id)
    }

    /// Terminal yüzeyi şu an bu repo için önde mi. Henüz hiçbir repo aktive
    /// edilmediyse (bootstrap penceresi) kısıtlama uygulanmaz.
    private func isSurfaceForeground(_ repoPath: String) -> Bool {
        surfaceRepoPath == nil || surfaceRepoPath == repoPath
    }

    /// Bildirim tıklaması istisnası: önce restore, sonra odak.
    public func restoreAndFocus(_ id: TerminalID) {
        restore(id)
        focus(id)
    }

    /// Tab değişimi yan etkisi: repo'nun lastActive'i geçerli ve
    /// görünürse o, değilse ilk görünür, hiç yoksa nil.
    ///
    /// Faz 4.9 davranış düzeltmesi: eski reponun terminalleri artık gerçekten
    /// arkaya alınır (`onBlur` + 100ms). Önceden yalnız SwiftUI detach'i
    /// coalescer aralığını genişletiyor, odak bayrağı eski repoda takılı
    /// kalıyordu. Yüzey geçişi odak seçiminden ÖNCE yapılır: o an
    /// `activeTerminalID` hâlâ eski repoya aittir, dolayısıyla foreground
    /// geçişi odağı yeniden yaymaz — odağı aşağıdaki tek `focus` çağrısı verir.
    public func activateRepo(_ repoPath: String) {
        if let previous = surfaceRepoPath, previous != repoPath {
            setTerminalSurfaceVisible(false, in: previous)
        }
        surfaceRepoPath = repoPath
        setTerminalSurfaceVisible(true, in: repoPath)

        let visible = visibleTerminals(in: repoPath)
        if let last = lastActiveByRepo[repoPath], visible.contains(where: { $0.id == last }) {
            focus(last)
        } else {
            focus(visible.first?.id)
        }
    }

    // MARK: - Klavye navigasyonu (görünür küme, aynı repo)

    public func focusIndex(_ index: Int, in repoPath: String) {
        let visible = visibleTerminals(in: repoPath)
        guard visible.indices.contains(index) else { return }
        focus(visible[index].id)
    }

    public func focusNext(in repoPath: String) {
        stepFocus(in: repoPath, offset: 1)
    }

    public func focusPrevious(in repoPath: String) {
        stepFocus(in: repoPath, offset: -1)
    }

    private func stepFocus(in repoPath: String, offset: Int) {
        let visible = visibleTerminals(in: repoPath)
        guard !visible.isEmpty else { return }
        guard let current = activeTerminalID,
              let index = visible.firstIndex(where: { $0.id == current }) else {
            focus(visible.first?.id)
            return
        }
        let next = (index + offset + visible.count) % visible.count
        focus(visible[next].id)
    }

    // MARK: - Event uygulama (testler doğrudan sürebilsin diye internal)

    func apply(_ event: TerminalEvent) {
        switch event {
        case .spawned(let meta):
            terminals.append(meta)
            // Spawn eden path açıkça odaklar (store sözleşmesi)
            focus(meta.id)
        case .exited(let id, let code):
            let name = meta(for: id)?.name ?? "Terminal"
            let wasUserClose = userClosedIDs.remove(id) != nil
            remove(id)
            if !wasUserClose, Self.isFailureExit(code) {
                toasts.show(.error, title: name, message: "Terminal exited with code \(code)")
            }
        case .statusChanged(let id, let status):
            update(id) { $0.status = status }
            applyAutoMinimize(id, status: status)
        case .titleChanged(let id, let title):
            update(id) { $0.oscTitle = title }
        case .awaitingDecisionChanged(let id, let awaiting):
            if awaiting {
                awaitingDecisionIDs.insert(id)
                // İzin promptu da "girdi bekliyor"dur (karar 24) — status
                // working'de kalsa bile otomatik minimize edilen geri açılır.
                if autoMinimizedIDs.contains(id) {
                    restore(id)
                }
            } else {
                awaitingDecisionIDs.remove(id)
            }
        case .writeFailed(let id, let errno):
            // Karar 5: ölü PTY'ye yazım sessizce yutulmaz
            toasts.show(
                .error,
                title: meta(for: id)?.name ?? "Terminal",
                message: "Write failed (errno \(errno))"
            )
        case .stalled(let id, let stalled):
            // Ephemeral donma sinyali: yalnız rozet; status/odak etkilenmez.
            if stalled {
                stalledIDs.insert(id)
            } else {
                stalledIDs.remove(id)
            }
        case .viewFocused(let id):
            // Terminal NSView'ına tıklama: store odağı senkronlanır. `focus`
            // kuralları aynen geçerli (minimize edilmiş odak alamaz).
            focus(id)
        case .bell(let id):
            // Emülatör BEL karakteri — status-güdümlü bell'ler ayrıca
            // NotificationService'ten gelir
            if let meta = meta(for: id) {
                toasts.show(.bell, title: meta.name, message: "Bell", terminalID: id)
            }
        }
    }

    /// Kullanıcıya bildirilecek çıkışlar: sıfır olmayan ve kill sinyalinden
    /// (SIGHUP/SIGTERM/SIGKILL → 128+signo) doğmayan kodlar. Negatif kod
    /// "çözülemedi" demektir (PTYProcess.exitCode) — gürültü yapılmaz.
    static let normalExitCodes: Set<Int32> = [0, 128 + 1, 128 + 15, 128 + 9]

    static func isFailureExit(_ code: Int32) -> Bool {
        code > 0 && !normalExitCodes.contains(code)
    }

    /// Karar 24: working → otomatik minimize (yalnız toggle açıkken ve zaten
    /// minimize değilken); diğer tüm durumlar (waiting-*/idle/error) turn'ün
    /// bittiği ya da girdi beklendiği anlamına gelir → otomatik minimize edilen
    /// restore edilir. Restore branch'i toggle'a bakmaz — özellik kapatılsa bile
    /// önceden gizlenen terminal minimize'da mahsur kalmaz. Odak verilmez
    /// (odaklı restore yalnız bildirim tıklamasıyla).
    private func applyAutoMinimize(_ id: TerminalID, status: TerminalStatus) {
        if status == .working {
            guard autoMinimizeOnSend, !minimizedIDs.contains(id) else { return }
            minimize(id)
            autoMinimizedIDs.insert(id)
        } else if autoMinimizedIDs.contains(id) {
            restore(id)
        }
    }

    private func update(_ id: TerminalID, _ mutate: (inout TerminalMeta) -> Void) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        var copy = terminals[index]
        mutate(&copy)
        terminals[index] = copy
    }

    /// Kapanışta komşu odaklama (Electron paritesi): silmeden ÖNCE hesaplanır;
    /// adaylar aynı repo'nun görünür terminalleridir — odak başka repo'ya atlamaz.
    private func remove(_ id: TerminalID) {
        guard let index = terminals.firstIndex(where: { $0.id == id }) else { return }
        let repoPath = terminals[index].repoPath

        if activeTerminalID == id {
            let candidates = terminals.filter {
                $0.repoPath == repoPath && ($0.id == id || !minimizedIDs.contains($0.id))
            }
            let neighbor = Self.neighborID(closing: id, among: candidates)
            activeTerminalID = neighbor
            if let neighbor {
                lastActiveByRepo[repoPath] = neighbor
                service.setFocused(neighbor)
            } else {
                service.setFocused(nil)
            }
        }

        if lastActiveByRepo[repoPath] == id {
            let remaining = terminals.filter {
                $0.repoPath == repoPath && $0.id != id && !minimizedIDs.contains($0.id)
            }
            if let first = remaining.first {
                lastActiveByRepo[repoPath] = first.id
            } else {
                lastActiveByRepo.removeValue(forKey: repoPath)
            }
        }

        minimizedIDs.remove(id)
        autoMinimizedIDs.remove(id)
        awaitingDecisionIDs.remove(id)
        stalledIDs.remove(id)
        terminals.remove(at: index)
    }

    /// Komşu kuralı: önceki; ilk kapanıyorsa sonraki; id listede
    /// yoksa ilki; liste boşsa nil. `candidates` kapanan terminali İÇERİR.
    static func neighborID(closing id: TerminalID, among candidates: [TerminalMeta]) -> TerminalID? {
        let others = candidates.filter { $0.id != id }
        guard !others.isEmpty else { return nil }
        guard let index = candidates.firstIndex(where: { $0.id == id }) else {
            return others.first?.id
        }
        if index > 0 {
            return candidates[index - 1].id
        }
        return others.first?.id
    }
}
