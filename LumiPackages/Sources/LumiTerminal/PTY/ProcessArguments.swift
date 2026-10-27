import Darwin
import Foundation

/// Karar 141: bir sürecin argv'si, çekirdekten (`KERN_PROCARGS2`) — süreç
/// açılmaz, `ps` metni ayrıştırılmaz (argümandaki boşluk/satır sonu korunur).
/// Yalnız aynı kullanıcının süreçleri okunabilir; okunamazsa `nil`.
enum ProcessArguments {
    static func read(pid: Int32) -> [String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// Düzen: `argc` (Int32) · çalıştırılabilir yolu · NUL dolgusu · argv[0…argc-1]
    /// (her biri NUL sonlu) · ortam. Ortam okunmaz.
    static func parse(_ buffer: [UInt8]) -> [String]? {
        let headerSize = MemoryLayout<Int32>.size
        guard buffer.count > headerSize else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0 else { return nil }
        var index = headerSize
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < buffer.count {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start ..< index], as: UTF8.self))
            index += 1
        }
        return arguments.count == argc ? arguments : nil
    }
}
