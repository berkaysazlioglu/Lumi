import Darwin
import Foundation

/// Uygulama hangi yoldan ölürse ölsün zombi `claude` ağacı bırakmamak için
/// global child-pid kaydı (spec/00 §4.3, design/01 §2).
/// atexit + SIGTERM süpürmesi yalnız async-signal-safe çağrılar kullanır:
/// pid'ler sabit kapasiteli C dizisinde tutulur, handler killpg dışında bir şey yapmaz.

private let sweepCapacity = 128

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

    func register(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<sweepCapacity where sweepSlots[index] == 0 {
            sweepSlots[index] = pid
            return
        }
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
