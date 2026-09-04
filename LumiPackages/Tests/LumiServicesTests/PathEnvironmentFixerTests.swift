import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Refactor 3.1/3.9: `fixProcessPath` gövdesi ayrı bir tipe indi ve artık
/// gerçek `$SHELL` çağrısı olmadan test edilebilir (design/02 §8 paritesi).
final class PathEnvironmentFixerTests: XCTestCase {
    private func fixer(
        runner: FakeProcessRunner,
        environment: [String: String],
        existingDirectories: Set<String> = []
    ) -> PathEnvironmentFixer {
        PathEnvironmentFixer(
            runner: runner,
            environment: { environment },
            fileExists: { existingDirectories.contains($0) },
            apply: { _ in }
        )
    }

    func testShellPathComesFirstThenProcessPath() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("/shell/bin:/usr/bin"))
        let subject = fixer(
            runner: runner,
            environment: ["SHELL": "/bin/zsh", "PATH": "/proc/bin:/usr/bin"]
        )

        let merged = await subject.mergedPath()

        XCTAssertEqual(merged, "/shell/bin:/usr/bin:/proc/bin")
    }

    func testUsesInteractiveLoginShellInvocation() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("/shell/bin"))
        let subject = fixer(runner: runner, environment: ["SHELL": "/bin/fish", "PATH": ""])

        _ = await subject.mergedPath()

        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, "/bin/fish")
        XCTAssertEqual(invocation?.arguments, ["-ilc", "echo -n \"$PATH\""])
        XCTAssertEqual(invocation?.timeout, PathEnvironmentFixer.commandTimeout)
    }

    func testDefaultsToZshWhenShellVariableMissing() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(""))
        let subject = fixer(runner: runner, environment: ["PATH": "/usr/bin"])

        _ = await subject.mergedPath()

        let executable = await runner.invocations.first?.executable
        XCTAssertEqual(executable, "/bin/zsh")
    }

    func testShellFailureIsSilentAndKeepsProcessPath() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.timeout)
        let subject = fixer(runner: runner, environment: ["SHELL": "/bin/zsh", "PATH": "/usr/bin"])

        let merged = await subject.mergedPath()
        XCTAssertEqual(merged, "/usr/bin")
    }

    func testNonZeroShellExitIsIgnored() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 1, stdout: "/ignored"))
        let subject = fixer(runner: runner, environment: ["SHELL": "/bin/zsh", "PATH": "/usr/bin"])

        let merged = await subject.mergedPath()
        XCTAssertEqual(merged, "/usr/bin")
    }

    func testAppendsOnlyExistingKnownDirectories() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(""))
        let subject = fixer(
            runner: runner,
            environment: ["SHELL": "/bin/zsh", "PATH": "/usr/bin"],
            existingDirectories: ["/opt/homebrew/bin"]
        )

        let merged = await subject.mergedPath()
        XCTAssertEqual(merged, "/usr/bin:/opt/homebrew/bin")
    }

    func testDeduplicatesAndDropsEmptyEntries() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("/a::/b:/a"))
        let subject = fixer(runner: runner, environment: ["SHELL": "/bin/zsh", "PATH": "/b:/c"])

        let merged = await subject.mergedPath()
        XCTAssertEqual(merged, "/a:/b:/c")
    }

    func testApplyReceivesMergedPath() async {
        final class Box: @unchecked Sendable {
            var value: String?
        }
        let box = Box()
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("/a"))
        let subject = PathEnvironmentFixer(
            runner: runner,
            environment: { ["SHELL": "/bin/zsh", "PATH": "/b"] },
            fileExists: { _ in false },
            apply: { box.value = $0 }
        )

        await subject.fix()

        XCTAssertEqual(box.value, "/a:/b")
    }
}
