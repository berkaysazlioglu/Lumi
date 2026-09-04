import AppKit
import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Faz 4.3 — `TerminalSurfaceState`: görünürlük ve odak artık iki bağımsız
/// kanal değil, TEK atomik geçiştir. Bugün `setHidden` yalnız coalescer
/// aralığını genişletiyordu; `statusMachine.focused` true kalıyor ve orta alan
/// başka bir view'e geçtiğinde terminal `waitingUnseen` yerine `waitingFocused`
/// oluyordu (yanlış rozet + karar 24 auto-minimize bozulması).
final class TerminalSurfaceStateTests: XCTestCase {
    private func makePipeline() -> (TerminalPipeline, TestScheduler) {
        let queue = DispatchQueue(label: "lumi.test.surface.\(UUID().uuidString)")
        let coalescerScheduler = TestScheduler()
        let pipeline = TerminalPipeline(
            queue: queue,
            coalescerScheduler: coalescerScheduler,
            silenceScheduler: TestScheduler()
        )
        return (pipeline, coalescerScheduler)
    }

    /// working → (✳ idle title) → waiting. Odaksızken `waitingUnseen`.
    private func driveToWaiting(_ pipeline: TerminalPipeline) {
        _ = pipeline.processOutput(Data("\u{1B}]0;claude working\u{07}".utf8))
        _ = pipeline.processOutput(Data("\u{1B}]0;\u{2733} claude idle\u{07}".utf8))
    }

    /// Coalescer aralığı yalnız yeni bir ingest'te okunur — sahte scheduler'ın
    /// kaydettiği son aralık, o anki görünürlük politikasının kanıtıdır.
    private func scheduledInterval(
        _ pipeline: TerminalPipeline,
        _ scheduler: TestScheduler
    ) -> TimeInterval? {
        scheduler.fire()
        _ = pipeline.processOutput(Data("x".utf8))
        return scheduler.lastInterval
    }

    // MARK: - Atomik geçiş: aralık + odak birlikte

    func testForegroundOnFocusedSessionRaisesWaitingToFocused() {
        let (pipeline, scheduler) = makePipeline()
        driveToWaiting(pipeline)
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)

        pipeline.applySurfaceState(.foreground, isFocused: true)

        XCTAssertEqual(pipeline.statusMachine.status, .waitingFocused)
        XCTAssertEqual(
            scheduledInterval(pipeline, scheduler),
            OutputCoalescer.defaultVisibleInterval
        )
    }

    func testForegroundOnUnfocusedSessionKeepsWaitingUnseen() {
        // Görünür olmak odaklı olmak değildir: grid'deki 8 karttan yalnız biri
        // odaklıdır, diğerleri "unseen" kalmalı (rozet + bildirim semantiği).
        let (pipeline, scheduler) = makePipeline()
        driveToWaiting(pipeline)

        pipeline.applySurfaceState(.foreground, isFocused: false)

        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
        XCTAssertEqual(
            scheduledInterval(pipeline, scheduler),
            OutputCoalescer.defaultVisibleInterval
        )
    }

    func testBackgroundBlursFocusedSessionAndWidensInterval() {
        // 4.3'ün düzelttiği bug: yüzey arkaya düşünce odak da düşer.
        let (pipeline, scheduler) = makePipeline()
        driveToWaiting(pipeline)
        pipeline.applySurfaceState(.foreground, isFocused: true)
        XCTAssertEqual(pipeline.statusMachine.status, .waitingFocused)

        pipeline.applySurfaceState(.background, isFocused: false)

        XCTAssertEqual(
            pipeline.statusMachine.status,
            .waitingSeen,
            "arka plana düşen terminal hâlâ odaklı sayılıyor"
        )
        XCTAssertEqual(
            scheduledInterval(pipeline, scheduler),
            OutputCoalescer.defaultHiddenInterval
        )
    }

    func testMinimizedBehavesLikeBackground() {
        let (pipeline, scheduler) = makePipeline()
        driveToWaiting(pipeline)
        pipeline.applySurfaceState(.foreground, isFocused: true)

        pipeline.applySurfaceState(.minimized, isFocused: false)

        XCTAssertEqual(pipeline.statusMachine.status, .waitingSeen)
        XCTAssertEqual(
            scheduledInterval(pipeline, scheduler),
            OutputCoalescer.defaultHiddenInterval
        )
    }

    /// Odak state'i manager'dan gelir: `isFocused: true` gelmediği sürece
    /// foreground geçişi asla odak KAZANDIRMAZ (setFocused ile tutarlılık).
    func testForegroundDoesNotStealFocusFromAnotherTerminal() {
        let (pipeline, _) = makePipeline()
        driveToWaiting(pipeline)
        pipeline.applySurfaceState(.background, isFocused: false)

        pipeline.applySurfaceState(.foreground, isFocused: false)
        _ = pipeline.processOutput(Data("\u{1B}]0;claude working\u{07}".utf8))
        _ = pipeline.processOutput(Data("\u{1B}]0;\u{2733} claude idle\u{07}".utf8))

        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
    }
}

/// Oturum + manager düzeyinde yüzey durumu yönlendirmesi.
@MainActor
final class TerminalSurfaceStateRoutingTests: XCTestCase {
    private func makeSession(repoPath: String? = nil) throws -> (TerminalSession, FakePTY) {
        let pty = FakePTY()
        let session = try TerminalSession(
            repoPath: repoPath ?? FileManager.default.temporaryDirectory.path,
            name: "surface",
            task: nil,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            ptySpawner: FakePTYSpawner(pty: pty),
            viewMaker: DropAwareTerminalViewMaker()
        )
        return (session, pty)
    }

    func testSessionStartsInBackgroundAndRecordsSurfaceState() throws {
        let (session, _) = try makeSession()

        XCTAssertEqual(session.surfaceState, .background, "spawn anında hiçbir container'a bağlı değil")

        session.setSurfaceState(.foreground, isFocused: true)
        XCTAssertEqual(session.surfaceState, .foreground)

        session.setSurfaceState(.minimized, isFocused: false)
        XCTAssertEqual(session.surfaceState, .minimized)
    }

    private func makeTempRepo() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-surface-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    func testBulkSurfaceStateTargetsOnlyMatchingRepo() throws {
        let manager = TerminalSessionManager()
        let repoA = try makeTempRepo()
        let repoB = try makeTempRepo()
        defer {
            manager.killAll()
            manager.shutdown()
            try? FileManager.default.removeItem(atPath: repoA)
            try? FileManager.default.removeItem(atPath: repoB)
        }

        _ = try manager.spawn(repoPath: repoA, task: nil, command: nil)
        _ = try manager.spawn(repoPath: repoB, task: nil, command: nil)

        manager.setSurfaceState(.foreground, in: nil)
        XCTAssertEqual(manager.sessions.map(\.surfaceState), [.foreground, .foreground])

        manager.setSurfaceState(.background, in: repoA)
        XCTAssertEqual(manager.sessions.map(\.surfaceState), [.background, .foreground])
    }

    func testSingleSurfaceStateTargetsOneTerminal() throws {
        let manager = TerminalSessionManager()
        let repo = try makeTempRepo()
        defer {
            manager.killAll()
            manager.shutdown()
            try? FileManager.default.removeItem(atPath: repo)
        }

        let first = try manager.spawn(repoPath: repo, task: nil, command: nil)
        _ = try manager.spawn(repoPath: repo, task: nil, command: nil)
        manager.setSurfaceState(.foreground, in: nil)

        manager.setSurfaceState(.minimized, for: first.id)

        XCTAssertEqual(manager.sessions.map(\.surfaceState), [.minimized, .foreground])
    }
}
