import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiServices

/// Karar 122: `pmset disablesleep` okuma/yazma `ProcessRunning` üzerinden koşar.
final class PMSetLidSleepControlTests: XCTestCase {
    func testParsesSleepDisabledLine() {
        XCTAssertTrue(PMSetLidSleepControl.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n sleep 10\n"))
        XCTAssertFalse(PMSetLidSleepControl.parseSleepDisabled(" SleepDisabled\t\t0\n"))
        XCTAssertFalse(PMSetLidSleepControl.parseSleepDisabled(" sleep 10\n displaysleep 10\n"), "satır yoksa kapalı")
    }

    func testReadFailureYieldsNil() async {
        let runner = FakeProcessRunner()
        await runner.stub(executable: PMSetLidSleepControl.pmset, with: .failure())
        let value = await PMSetLidSleepControl(runner: runner).isSleepDisabled()
        XCTAssertNil(value)
    }

    func testSetRunsAdminScript() async {
        let runner = FakeProcessRunner()
        await runner.stub(executable: PMSetLidSleepControl.osascript, with: .success())
        let result = await PMSetLidSleepControl(runner: runner).setSleepDisabled(true)
        XCTAssertEqual(result, .applied)
        let script = PMSetLidSleepControl.script(disabled: true)
        XCTAssertTrue(script.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
        XCTAssertTrue(PMSetLidSleepControl.script(disabled: false).contains("disablesleep 0"))
    }

    func testUserCancelIsNotAFailure() async {
        let runner = FakeProcessRunner()
        await runner.stub(
            executable: PMSetLidSleepControl.osascript,
            with: .failure(stderr: "execution error: User canceled. (-128)")
        )
        let result = await PMSetLidSleepControl(runner: runner).setSleepDisabled(true)
        XCTAssertEqual(result, .cancelled)
    }

    func testOtherErrorsCarryMessage() async {
        let runner = FakeProcessRunner()
        await runner.stub(executable: PMSetLidSleepControl.osascript, with: .failure(stderr: "boom\n"))
        let result = await PMSetLidSleepControl(runner: runner).setSleepDisabled(false)
        XCTAssertEqual(result, .failed("boom"))
    }

    func testOwnershipKeyIsAdditive() {
        XCTAssertFalse(ConfigCodec.decodeConfig(from: [:]).lidSleepDisabledByLumi)
        XCTAssertTrue(ConfigCodec.decodeConfig(from: ["lidSleepDisabledByLumi": true]).lidSleepDisabledByLumi)
        var config = AppConfig.defaults
        config.lidSleepDisabledByLumi = true
        XCTAssertEqual(ConfigCodec.configOverlay(config)["lidSleepDisabledByLumi"] as? Bool, true)
    }
}
