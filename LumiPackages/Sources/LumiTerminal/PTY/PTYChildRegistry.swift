import Darwin
import Foundation

/// Uygulama hangi yoldan ölürse ölsün zombi `claude` ağacı bırakmamak için
/// global child-pid kaydı (design/00 Ek A §A.3, design/01 §2).
/// atexit + SIGTERM süpürmesi yalnız async-signal-safe çağrılar kullanır:
/// pid'ler sabit kapasiteli C dizisinde tutulur, handler killpg dışında bir şey yapmaz.

/// Kapasite: spawn limiti kaldırıldıktan (karar 29) sonra üst sınır yok; 512 slot
/// pratik tavanın çok üstünde ve sabit dizi async-signal-safe süpürmeyi korur.
private let sweepCapacity = 512

// Signal handler'dan locksuz okunur; yazımlar registry lock'u altındadır.
nonisolated(unsafe) private let sweepSlots: UnsafeMutablePointer<pid_t> = {
    let pointer = UnsafeMutablePointer<pid_t>.allocate(capacity: sweepCapacity)
    pointer.initialize(repeating: 0, count: sweepCapacity)
    return pointer
}()

private func sweepRegisteredChildren() {
    for index in 0..<sweepCapacity {
        let pid = sweepSlots[index]
        if pid > 0 {
            killpg(pid, SIGHUP)
        }
    }
}

final class PTYChildRegistry: @unchecked Sendable {
    static let shared = PTYChildRegistry()

    private let lock = NSLock()

    private init() {
        atexit {
            sweepRegisteredChildren()
        }
        let handler: @convention(c) (Int32) -> Void = { signalNumber in
            sweepRegisteredChildren()
            signal(signalNumber, SIG_DFL)
            raise(signalNumber)
        }
        signal(SIGTERM, handler)
    }

    /// `PTYProcess.init`'ten (normal Swift bağlamı — signal handler DEĞİL) çağrılır,
    /// bu yüzden assert + stderr logu güvenlidir. Taşma sessiz kalırsa o child
    /// kapanış süpürmesinin dışında kalır (zombi ağaç riski) — görünür olmalı.
    func register(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<sweepCapacity where sweepSlots[index] == 0 {
            sweepSlots[index] = pid
            return
        }
        FileHandle.standardError.write(
            Data("lumi: PTYChildRegistry dolu (\(sweepCapacity)); pid \(pid) süpürme dışı\n".utf8)
        )
        assertionFailure("PTYChildRegistry kapasitesi doldu (\(sweepCapacity))")
    }

    func unregister(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<sweepCapacity where sweepSlots[index] == pid {
            sweepSlots[index] = 0
            return
        }
    }
}
