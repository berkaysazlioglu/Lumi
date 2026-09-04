import Foundation
import XCTest

/// Sabit uyku yerine koşul yoklaması (plan 2.9 kalıbı): koordinatörün
/// `for await` döngüsü bir sonraki turda çalıştığından event'ler senkron
/// gözlemlenemez.
@MainActor
func waitUntil(
    timeout: Duration = .milliseconds(2000),
    pollInterval: Duration = .milliseconds(5),
    _ description: String = "koşul sağlanmadı",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: pollInterval)
    }
    XCTAssertTrue(condition(), description, file: file, line: line)
}
