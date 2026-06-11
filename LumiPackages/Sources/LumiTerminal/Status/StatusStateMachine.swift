import LumiKit

/// 6 durumlu, provider-agnostic terminal durum makinesi (spec/10 §5, birebir port).
/// Saf mantıktır; io queue'ya confine edilerek kullanılır, kendi senkronizasyonu yoktur.
final class StatusStateMachine {
    private(set) var status: TerminalStatus = .idle
    private var focused = false
    private var windowFocused = true

    /// Aynı duruma geçiş no-op'tur; onChange yalnızca gerçek değişimde tetiklenir.
    var onChange: ((TerminalStatus) -> Void)?

    private var isEffectivelyFocused: Bool { focused && windowFocused }

    func onTitleChange(isWorking: Bool) {
        if isWorking {
            transition(to: .working)
        } else {
            guard status == .working else { return }
            transition(to: isEffectivelyFocused ? .waitingFocused : .waitingUnseen)
        }
    }

    /// Codex fallback: hint codex iken her output chunk'ında çağrılır.
    func onOutputActivity() {
        transition(to: .working)
    }

    /// Codex fallback: 3 sn output sessizliği.
    func onOutputSilence() {
        guard status == .working else { return }
        transition(to: isEffectivelyFocused ? .waitingFocused : .waitingUnseen)
    }

    /// Codex: Enter basıldı → "çalışmaya başladı" varsayımı (idle/error hariç).
    func onUserInput() {
        guard status != .idle, status != .error else { return }
        transition(to: .working)
    }

    func onFocus() {
        focused = true
        applyFocusGain()
    }

    func onBlur() {
        focused = false
        dropFocusedToSeen()
    }

    func onWindowFocus() {
        windowFocused = true
        applyFocusGain()
    }

    func onWindowBlur() {
        windowFocused = false
        dropFocusedToSeen()
    }

    func onExit(code: Int32) {
        transition(to: code == 0 ? .idle : .error)
    }

    func reset() {
        transition(to: .idle)
    }

    private func applyFocusGain() {
        guard isEffectivelyFocused else { return }
        if status == .waitingUnseen || status == .waitingSeen {
            transition(to: .waitingFocused)
        }
    }

    private func dropFocusedToSeen() {
        if status == .waitingFocused {
            transition(to: .waitingSeen)
        }
    }

    private func transition(to newStatus: TerminalStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onChange?(newStatus)
    }
}
