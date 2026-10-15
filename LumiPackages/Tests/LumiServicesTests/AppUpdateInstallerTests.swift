import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 118: checksum ayrıştırma, dosya özeti ve kurulum script'inin gerçek
/// bash koşusu (launchd'siz — `LABEL` boş verilir).
final class AppUpdateInstallerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - SHA256SUMS

    func testParsesShasumAndBinaryModeLines() {
        let a = String(repeating: "a", count: 64)
        let b = String(repeating: "B", count: 64)
        let sums = SHA256Sums.parse("""
        \(a)  Lumi-0.9.0-arm64-mac.zip
        \(b) *Lumi-0.9.0-x86_64-mac.zip
        nothex  garbage.zip

        """)
        XCTAssertEqual(sums["Lumi-0.9.0-arm64-mac.zip"], a)
        XCTAssertEqual(sums["Lumi-0.9.0-x86_64-mac.zip"], b.lowercased())
        XCTAssertNil(sums["garbage.zip"])
    }

    func testSHA256MatchesKnownDigest() throws {
        let file = dir.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(
            try AppUpdateInstaller.sha256(of: file),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // MARK: - Destek

    func testUnsignedBuildCannotUpdateItself() async throws {
        let installer = AppUpdateInstaller(
            root: dir, bundleURL: dir.appendingPathComponent("Lumi.app"),
            signatures: StubSignatures(team: nil), trustedTeamOverride: nil
        )
        XCTAssertEqual(installer.installSupport(), .unsignedBuild)
        do {
            _ = try await installer.prepare(.init(version: AppVersion("9.0.0")!, pageURL: dir, publishedAt: nil))
            XCTFail("imzasız kopya hazırlık yapmamalı")
        } catch {}
    }

    /// Geliştirici anahtarı imzasız yerel build'de güncelleyiciyi açar; bozuk değer yok sayılır.
    func testTrustedTeamOverrideEnablesUnsignedLocalBuild() throws {
        let app = dir.appendingPathComponent("Lumi.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let overridden = AppUpdateInstaller(
            root: dir, bundleURL: app, signatures: StubSignatures(team: nil), trustedTeamOverride: "S5P38S66SM"
        )
        XCTAssertEqual(overridden.installSupport(), .supported)
        let garbage = AppUpdateInstaller(
            root: dir, bundleURL: app, signatures: StubSignatures(team: nil), trustedTeamOverride: "x\" or true"
        )
        XCTAssertEqual(garbage.installSupport(), .unsignedBuild)
    }

    func testTranslocatedOrReadOnlyBundleIsReported() throws {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Lumi.app")
        let installer = AppUpdateInstaller(root: dir, bundleURL: translocated, signatures: StubSignatures(team: "TEAM"))
        XCTAssertEqual(installer.installSupport(), .readOnlyLocation(path: translocated.path))

        let app = dir.appendingPathComponent("Lumi.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let writable = AppUpdateInstaller(root: dir, bundleURL: app, signatures: StubSignatures(team: "TEAM"))
        XCTAssertEqual(writable.installSupport(), .supported)
    }

    /// Yalnız tutulan sürümün klasörü kalır; `nil` hepsini siler.
    func testDiscardStagedKeepsOnlyTheGivenVersion() async throws {
        let staged = dir.appendingPathComponent("staged")
        for version in ["0.9.0", "0.9.1"] {
            try FileManager.default.createDirectory(
                at: staged.appendingPathComponent("\(version)/Lumi.app"), withIntermediateDirectories: true
            )
        }
        let installer = AppUpdateInstaller(root: dir, signatures: StubSignatures(team: nil), trustedTeamOverride: nil)
        let keep = StagedAppUpdate(
            release: AppRelease(version: AppVersion("0.9.1")!, pageURL: dir, publishedAt: nil),
            appPath: staged.appendingPathComponent("0.9.1/Lumi.app").path
        )
        await installer.discardStaged(except: keep)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staged.path), ["0.9.1"])
        await installer.discardStaged(except: nil)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staged.path), [])
    }

    // MARK: - Script

    func testScriptReplacesAppAndCleansUp() throws {
        let fixture = try makeScriptFixture()
        let status = try runScript(fixture, pid: deadPID())
        XCTAssertEqual(status, 0)
        XCTAssertEqual(try String(contentsOf: fixture.target.appendingPathComponent("version")), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.staging.path), "sahne silinir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.failure.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.target.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["Lumi.app"], "yedek ve yan kopya silinir")
    }

    /// Kurulum anında yeniden doğrulama: sahne imza gereksinimini karşılamıyorsa
    /// hiçbir şeye dokunulmaz.
    func testUnsignedStageIsRejectedAtInstallTime() throws {
        let fixture = try makeScriptFixture()
        let status = try runScript(fixture, pid: deadPID(), requirement: "anchor apple generic")
        XCTAssertEqual(status, 1)
        XCTAssertEqual(try String(contentsOf: fixture.target.appendingPathComponent("version")), "old")
        XCTAssertTrue(try String(contentsOf: fixture.failure).contains("signature"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "sahne yerinde kalır")
    }

    /// Kurulu kopya yokken de kurulur (kullanıcı silmiş olabilir).
    func testInstallsWhenTargetIsMissing() throws {
        let fixture = try makeScriptFixture()
        try FileManager.default.removeItem(at: fixture.target)
        XCTAssertEqual(try runScript(fixture, pid: deadPID()), 0)
        XCTAssertEqual(try String(contentsOf: fixture.target.appendingPathComponent("version")), "new")
    }

    func testMissingSourceLeavesAppInPlaceAndRecordsFailure() throws {
        let fixture = try makeScriptFixture()
        try FileManager.default.removeItem(at: fixture.source)
        let status = try runScript(fixture, pid: deadPID())
        XCTAssertEqual(status, 1)
        XCTAssertEqual(try String(contentsOf: fixture.target.appendingPathComponent("version")), "old")
        XCTAssertTrue(try String(contentsOf: fixture.failure).contains("missing"))
    }

    func testPlistRunsScriptWithArgumentsAndLogs() throws {
        let data = AppUpdateInstallScript.plist(script: "/s.sh", arguments: ["1", "2"], logPath: "/l.log")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, AppUpdateInstallScript.label)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/bin/bash", "/s.sh", "1", "2"])
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/l.log")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    // MARK: - Yardımcılar

    private struct ScriptFixture {
        let script: URL, source: URL, target: URL, staging: URL, failure: URL
    }

    private func makeScriptFixture() throws -> ScriptFixture {
        let files = FileManager.default
        let staging = dir.appendingPathComponent("staged")
        let source = staging.appendingPathComponent("0.9.0/Lumi.app")
        let target = dir.appendingPathComponent("Applications/Lumi.app")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        try files.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("version"))
        try Data("old".utf8).write(to: target.appendingPathComponent("version"))
        let script = dir.appendingPathComponent("install.sh")
        try Data(AppUpdateInstallScript.source.utf8).write(to: script)
        return ScriptFixture(
            script: script, source: source, target: target, staging: staging,
            failure: dir.appendingPathComponent("install-failed")
        )
    }

    private func runScript(_ fixture: ScriptFixture, pid: Int32, requirement: String = "") throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            fixture.script.path, String(pid), fixture.source.path, fixture.target.path, "0",
            "", dir.appendingPathComponent("agent.plist").path, fixture.staging.path, fixture.failure.path,
            requirement,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Çıkmış bir sürecin PID'i — script beklemeden kuruluma geçer.
    private func deadPID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }
}

private struct StubSignatures: CodeSignatureVerifying {
    let team: String?
    func runningDeveloperIDTeam() -> String? { team }
    func isSignedByDeveloperID(_ appURL: URL, team: String) -> Bool { team == self.team }
}
