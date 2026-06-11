import XCTest
import LumiKit
@testable import LumiTerminal

final class StatusStateMachineTests: XCTestCase {
    private var machine = StatusStateMachine()
    private var changes: [TerminalStatus] = []

    override func setUp() {
        super.setUp()
        machine = StatusStateMachine()
        changes = []
        machine.onChange = { [weak self] status in
            self?.changes.append(status)
        }
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(machine.status, .idle)
        XCTAssertTrue(changes.isEmpty)
    }

    func testTitleWorkingFromAnyNonWorkingState() {
        machine.onTitleChange(isWorking: true)
        XCTAssertEqual(machine.status, .working)
        machine.onExit(code: 1)
        XCTAssertEqual(machine.status, .error)
        machine.onTitleChange(isWorking: true)
        XCTAssertEqual(machine.status, .working)
    }

    func testTitleStopUnfocusedGoesUnseen() {
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        // focused başlangıçta false → effective focus yok
        XCTAssertEqual(machine.status, .waitingUnseen)
    }

    func testTitleStopEffectivelyFocusedGoesFocused() {
        machine.onFocus() // windowFocused başlangıçta true
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        XCTAssertEqual(machine.status, .waitingFocused)
    }

    func testTitleStopOnlyAppliesFromWorking() {
        machine.onTitleChange(isWorking: false)
        XCTAssertEqual(machine.status, .idle)
        XCTAssertTrue(changes.isEmpty)
    }

    func testFocusGainPromotesWaitingUnseen() {
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        XCTAssertEqual(machine.status, .waitingUnseen)
        machine.onFocus()
        XCTAssertEqual(machine.status, .waitingFocused)
    }

    func testFocusGainBlockedWhileWindowBlurred() {
        machine.onWindowBlur()
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        XCTAssertEqual(machine.status, .waitingUnseen)
        machine.onFocus()
        // Pencere arka planda → effective focus yok, terfi olmaz
        XCTAssertEqual(machine.status, .waitingUnseen)
        machine.onWindowFocus()
        XCTAssertEqual(machine.status, .waitingFocused)
    }

    func testBlurDropsFocusedToSeen() {
        machine.onFocus()
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        XCTAssertEqual(machine.status, .waitingFocused)
        machine.onBlur()
        XCTAssertEqual(machine.status, .waitingSeen)
    }

    func testWindowBlurDropsFocusedToSeen() {
        // App arka plana düşünce aktif tab bile waiting-seen'e iner → native bildirim yolu açılır (spec/10 §5)
        machine.onFocus()
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        machine.onWindowBlur()
        XCTAssertEqual(machine.status, .waitingSeen)
    }

    func testSeenRegainsFocusedOnRefocus() {
        machine.onFocus()
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        machine.onBlur()
        XCTAssertEqual(machine.status, .waitingSeen)
        machine.onFocus()
        XCTAssertEqual(machine.status, .waitingFocused)
    }

    func testUserInputResumesWorkFromWaiting() {
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: false)
        machine.onUserInput()
        XCTAssertEqual(machine.status, .working)
    }

    func testUserInputIgnoredFromIdleAndError() {
        machine.onUserInput()
        XCTAssertEqual(machine.status, .idle)
        machine.onExit(code: 3)
        machine.onUserInput()
        XCTAssertEqual(machine.status, .error)
    }

    func testOutputActivityStartsWork() {
        machine.onOutputActivity()
        XCTAssertEqual(machine.status, .working)
    }

    func testOutputSilenceOnlyFromWorking() {
        machine.onOutputSilence()
        XCTAssertEqual(machine.status, .idle)
        machine.onOutputActivity()
        machine.onOutputSilence()
        XCTAssertEqual(machine.status, .waitingUnseen)
    }

    func testExitCodes() {
        machine.onTitleChange(isWorking: true)
        machine.onExit(code: 0)
        XCTAssertEqual(machine.status, .idle)
        machine.onTitleChange(isWorking: true)
        machine.onExit(code: 2)
        XCTAssertEqual(machine.status, .error)
    }

    func testSameStateTransitionDoesNotFireCallback() {
        machine.onTitleChange(isWorking: true)
        machine.onTitleChange(isWorking: true)
        machine.onOutputActivity()
        XCTAssertEqual(changes, [.working])
    }

    func testReset() {
        machine.onTitleChange(isWorking: true)
        machine.reset()
        XCTAssertEqual(machine.status, .idle)
    }
}
