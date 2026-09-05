import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiServices

/// Karar 43: `ps` örnekleyicisi `ProcessRunning` üzerinden koşar.
final class PSProcessSamplerTests: XCTestCase {
    func testRunsPSWithOrcaColumnsAndParses() async {
        let runner = FakeProcessRunner()
        await runner.stub(executable: PSProcessSampler.executable, with: .success("1 0 0.5 2048\n7 1 3.0 4096\n"))
        let sampler = PSProcessSampler(runner: runner)

        let table = await sampler.sampleProcessTable()

        XCTAssertEqual(table?.samples.count, 2)
        XCTAssertEqual(table?.samples[7]?.parentPID, 1)
        let didRun = await runner.didRun(commandLine: "/bin/ps -eo pid=,ppid=,pcpu=,rss=")
        XCTAssertTrue(didRun)
    }

    func testFailedProcessYieldsNil() async {
        let runner = FakeProcessRunner()
        await runner.stub(executable: PSProcessSampler.executable, with: FakeProcessRunner.Result(exitCode: 1))
        let table = await PSProcessSampler(runner: runner).sampleProcessTable()
        XCTAssertNil(table)
    }
}

/// Karar 43: `computerAwakeMode` anahtarı additive okunur/yazılır.
final class ComputerAwakeModeCodecTests: XCTestCase {
    func testMissingOrInvalidKeyDecodesAsOff() {
        XCTAssertEqual(ConfigCodec.decodeConfig(from: [:]).computerAwakeMode, .off)
        XCTAssertEqual(ConfigCodec.decodeConfig(from: ["computerAwakeMode": "nope"]).computerAwakeMode, .off)
        XCTAssertEqual(ConfigCodec.decodeConfig(from: ["computerAwakeMode": "auto"]).computerAwakeMode, .auto)
    }

    func testOverlayWritesRawValue() {
        var config = AppConfig.defaults
        config.computerAwakeMode = .on
        XCTAssertEqual(ConfigCodec.configOverlay(config)["computerAwakeMode"] as? String, "on")
    }
}
