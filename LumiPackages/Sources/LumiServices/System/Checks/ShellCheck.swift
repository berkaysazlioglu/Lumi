import Foundation
import LumiKit

/// Kullanılabilir bir login shell var mı? (design/02 §8 — shell zinciri)
public struct ShellCheck: SystemCheck {
    public static let candidates = ["/bin/zsh", "/bin/bash", "/bin/sh"]

    public let id = "shell"
    private let isExecutableFile: @Sendable (String) -> Bool

    public init(
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.isExecutableFile = isExecutableFile
    }

    public func run(context: SystemCheckContext) async -> SystemCheckResult {
        guard let shell = Self.candidates.first(where: isExecutableFile) else {
            return SystemCheckResult(
                id: id, label: "Login shell", status: .fail,
                message: "No usable shell found (zsh/bash/sh)"
            )
        }
        return SystemCheckResult(id: id, label: "Login shell", status: .pass, message: shell)
    }
}
