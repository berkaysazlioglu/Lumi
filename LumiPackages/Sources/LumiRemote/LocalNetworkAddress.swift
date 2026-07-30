import Darwin
import Foundation

/// Anlık port uygunluk probe'u: IPv6 wildcard'a (FlyingFox'un bind ettiği
/// adres ailesi) SO_REUSEADDR'sız bind dener — dolu portu milisaniyede eler.
enum PortProbe {
    static func isAvailable(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        return result == 0
    }
}

/// Yerel ağ IPv4 adres keşfi — dashboard URL'i ve QR içeriği için.
public enum LocalNetworkAddress {
    /// Aktif, loopback olmayan ilk IPv4 adresi; Wi-Fi/Ethernet (`en0`) öncelikli.
    public static func primaryIPv4() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let host = numericHost(addr) else { continue }

            if String(cString: interface.ifa_name) == "en0" {
                return host
            }
            if fallback == nil {
                fallback = host
            }
        }
        return fallback
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }
}
