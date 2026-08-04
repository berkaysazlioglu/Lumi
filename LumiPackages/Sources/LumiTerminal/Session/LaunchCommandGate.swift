import Foundation

/// Karar 23: launch komutu shell HAZIR olmadan PTY'ye yazılmaz.
///
/// Spawn'dan hemen sonra yazılan komut, login shell'in init'i sırasında
/// kaybolabiliyor: zsh raw-mode geçişlerinde (tcsetattr TCSAFLUSH) bekleyen
/// girdiyi atabilir — sahada `--session-id` claude'a hiç ulaşmadı (enjekte
/// edilen oturum dosyaları hiç oluşmadı). Bu kapı, shell'in ilk çıktısından
/// sonra `quietWindow` kadar sessizlik bekler (prompt çizimi bitti sinyali);
/// hiç çıktı gelmeyen uç durumda `maxWait`'te yine de ateşler. Tek atımlıktır.
@MainActor
final class LaunchCommandGate {
    private let quietWindow: Duration
    private let maxWait: Duration
    private var onFire: (() -> Void)?
    private var quietTask: Task<Void, Never>?
    private var maxWaitTask: Task<Void, Never>?
    private var hasFired = false

    init(
        quietWindow: Duration = .milliseconds(150),
        maxWait: Duration = .seconds(2)
    ) {
        self.quietWindow = quietWindow
        self.maxWait = maxWait
    }

    func start(onFire: @escaping () -> Void) {
        self.onFire = onFire
        maxWaitTask = Task { @MainActor [weak self, maxWait] in
            try? await Task.sleep(for: maxWait)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    /// Shell'den her çıktı batch'inde çağrılır; sessizlik sayacını sıfırlar.
    func noteOutput() {
        guard !hasFired, onFire != nil else { return }
        quietTask?.cancel()
        quietTask = Task { @MainActor [weak self, quietWindow] in
            try? await Task.sleep(for: quietWindow)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    func cancel() {
        hasFired = true
        quietTask?.cancel()
        maxWaitTask?.cancel()
        onFire = nil
    }

    private func fire() {
        guard !hasFired else { return }
        hasFired = true
        quietTask?.cancel()
        maxWaitTask?.cancel()
        onFire?()
        onFire = nil
    }
}
