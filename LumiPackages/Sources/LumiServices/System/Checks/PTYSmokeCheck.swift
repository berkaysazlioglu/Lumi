import Foundation
import LumiKit

/// PTY spawn+kill smoke testi. İmplementasyon `LumiTerminal`dedir
/// (bağımlılık yönü, design/00 §2); burada yalnız dikiş yeri kullanılır.
public struct PTYSmokeCheck: SystemCheck {
    public let id = "pty"
    private let smokeTester: any TerminalSmokeTesting

    public init(smokeTester: any TerminalSmokeTesting) {
        self.smokeTester = smokeTester
    }

    public func run(context: SystemCheckContext) async -> SystemCheckResult {
        do {
            try await smokeTester.runSmokeTest()
            return SystemCheckResult(id: id, label: "PTY", status: .pass, message: "PTY spawn OK")
        } catch {
            return SystemCheckResult(
                id: id, label: "PTY", status: .fail,
                message: "PTY smoke test failed: \(error.localizedDescription)"
            )
        }
    }
}
