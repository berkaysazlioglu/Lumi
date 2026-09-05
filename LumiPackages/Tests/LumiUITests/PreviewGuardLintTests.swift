import Foundation
import XCTest

/// `#Preview` blokları release derlemesinde de derlenir; fixture'lar ise
/// `#if DEBUG` içinde yaşar. Her preview'un DEBUG kapısı altında olması şart —
/// aksi halde `swift build -c release` / `make-app.sh` kırılır (Faz 7 regresyonu).
final class PreviewGuardLintTests: XCTestCase {
    func testEveryPreviewIsGuardedByDebugCondition() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LumiUI")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            var stack: [Bool] = [] // true = DEBUG koşulu
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if ") {
                    stack.append(trimmed.hasPrefix("#if DEBUG"))
                } else if trimmed.hasPrefix("#endif") {
                    _ = stack.popLast()
                } else if trimmed.hasPrefix("#Preview") && !stack.contains(true) {
                    offenders.append(url.lastPathComponent)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "DEBUG kapısı dışında #Preview: \(offenders)")
    }
}
