import Darwin
import XCTest
@testable import LumiTerminal

/// Remote dashboard regresyonu: PTY çocukları parent'ın dinleme soketini miras
/// alırsa, parent soketi kapatsa bile port çocuk yaşadıkça rehin kalır (istekler
/// kimsenin accept etmediği sokete düşer → telefonda kara ekran). Çocuk exec
/// öncesi 3+ tüm FD'leri kapatmalıdır.
final class PTYFDInheritanceTests: XCTestCase {
    private func makeListener() throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0, "bind başarısız: errno \(errno)")
        XCTAssertEqual(listen(fd, 8), 0)

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        XCTAssertEqual(nameResult, 0)
        return (fd, UInt16(bigEndian: bound.sin_port))
    }

    private func bindSamePort(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            close(fd)
            return -1
        }
        return fd
    }

    func testPTYChildDoesNotInheritListeningSocket() throws {
        let (listenerFD, port) = try makeListener()

        let queue = DispatchQueue(label: "fd-inheritance-test")
        let pty = try queue.sync {
            try PTYProcess(
                executable: "/bin/sleep",
                args: ["5"],
                cwd: NSTemporaryDirectory(),
                env: ["PATH": "/usr/bin:/bin"],
                initialCols: 80,
                initialRows: 24,
                queue: queue
            )
        }
        defer { pty.terminate() }
        pty.startReading { _ in .proceed }

        // exec'in tamamlanması için kısa bekleme (child FD kapatması exec öncesi)
        Thread.sleep(forTimeInterval: 0.5)

        // Parent kendi kopyasını kapatır; çocuk soketi miras aldıysa port
        // hâlâ meşguldür ve yeniden bind EADDRINUSE ile düşer.
        close(listenerFD)

        let reboundFD = bindSamePort(port)
        defer { if reboundFD >= 0 { close(reboundFD) } }
        XCTAssertGreaterThanOrEqual(
            reboundFD, 0,
            "port \(port) yeniden bind edilemedi — dinleme soketi PTY çocuğuna sızmış (errno \(errno))"
        )
    }
}
