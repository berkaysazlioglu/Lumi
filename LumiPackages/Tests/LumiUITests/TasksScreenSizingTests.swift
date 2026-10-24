import AppKit
import LumiKit
import LumiState
import LumiTestSupport
import SwiftUI
import XCTest

@testable import LumiUI

/// Tasks ekranı pencerenin minimum yüksekliğini büyütmemeli: kök view
/// `NSHostingView` içinde ve pencere en küçük boyutunu SwiftUI içeriğinin
/// minimumundan alır. Board'da yatay kaydırma içindeki dikey
/// `containerRelativeFrame` minimumu o anki yüksekliğe kilitliyordu — pencere
/// küçültülemiyordu.
@MainActor
final class TasksScreenSizingTests: XCTestCase {
    private static let tallHeight: CGFloat = 1400
    private static let maxAllowedMinHeight: CGFloat = 400

    private func connectedStore(layout: TasksStore.Layout) async -> TasksStore {
        let tasks = (1...30).map { TaskItem.fake(id: "\($0)", status: TaskStatus.allCases[$0 % 4]) }
        let provider = FakeTaskProvider(tasks: tasks)
        let store = TasksStore(
            factory: FakeTaskProviderFactory(providers: [.demo: provider]),
            config: FakeConfigService(), credentials: FakeTaskCredentialStore(),
            images: FakeTaskImageLoader(), agents: FakeTaskAgentRunner(), toasts: ToastStore()
        )
        store.beginConnect()
        store.selectConnectKind(.demo)
        await store.verifyConnect()
        await store.finishConnect()
        store.layout = layout
        return store
    }

    /// Önce büyük bir pencerede yerleşir, sonra en küçük boy sorulur.
    private func minimumHeight(_ store: TasksStore, selecting key: TaskKey? = nil) -> CGFloat {
        store.selectedTask = key
        let controller = NSHostingController(rootView: TasksScreen(store: store).environment(\.shell, ShellContext.preview()))
        controller.view.frame = CGRect(x: 0, y: 0, width: 1400, height: Self.tallHeight)
        controller.view.layoutSubtreeIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: 1400, height: 0)).height
    }

    func testBoardDoesNotRaiseMinimumHeight() async {
        let store = await connectedStore(layout: .board)
        XCTAssertLessThan(minimumHeight(store), Self.maxAllowedMinHeight)
    }

    func testListDoesNotRaiseMinimumHeight() async {
        let store = await connectedStore(layout: .list)
        XCTAssertLessThan(minimumHeight(store), Self.maxAllowedMinHeight)
    }

    func testDetailPanelDoesNotRaiseMinimumHeight() async {
        let store = await connectedStore(layout: .board)
        XCTAssertLessThan(minimumHeight(store, selecting: store.entries.first?.key), Self.maxAllowedMinHeight)
    }
}
