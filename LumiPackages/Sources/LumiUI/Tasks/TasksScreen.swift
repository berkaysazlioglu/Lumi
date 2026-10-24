import LumiKit
import LumiState
import SwiftUI

/// Tasks route'unun gövdesi (Tasks planı, Faz 1) — karar 55'in yer tutucusunun
/// yerini alır.
///
/// `.task` ömrü kullanıcı kararı 6'nın kendisidir: route açılınca güncel hâl
/// çekilir, açık kaldıkça tazelenir, kapanınca döngü iptal olur.
public struct TasksScreen: View {
    let store: TasksStore

    public init(store: TasksStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasSources {
                board
            } else {
                TasksEmptyState { store.beginConnect() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDeep)
        .task { await store.keepFresh() }
    }

    private var board: some View {
        VStack(spacing: 0) {
            TasksHeaderBar(store: store)
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            ForEach(store.visibleSources) { state in
                TaskSourceBanner(store: store, state: state)
            }
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let key = store.selectedTask, let entry = store.entry(key) {
                    Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                    TaskDetailPanel(store: store, entry: entry)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(Theme.Motion.standardEase, value: store.selectedTask)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty, store.visibleSources.allSatisfy({ $0.phase == .loading }) {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch store.layout {
            case .board:
                ScrollView(.horizontal) {
                    TaskBoardView(store: store)
                        .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                            axis == .horizontal ? max(length, TaskBoardView.minimumWidth) : length
                        }
                }
            case .list:
                TaskListView(store: store)
            }
        }
    }
}

extension TaskBoardView {
    /// Dört kolonun en dar hâli — pencere bundan darsa Board yatay kayar.
    static var minimumWidth: CGFloat { Theme.scaled(220) * 4 + Theme.Spacing.lg * 3 + Theme.Spacing.xl * 2 }
}

/// Kaynak sorunlarının bandı: çevrimdışı (son liste ekranda), token reddi,
/// desteklenmeyen sürüm. Sorun yoksa hiçbir şey çizmez.
private struct TaskSourceBanner: View {
    let store: TasksStore
    let state: TasksStore.SourceState

    var body: some View {
        if let content {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: content.icon)
                    .font(Theme.Typography.ui(.label, weight: .semibold))
                    .foregroundStyle(content.color)
                    .accessibilityHidden(true)
                Text(content.message)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let action = content.action {
                    Button(action.title, action: action.run)
                        .buttonStyle(HoverButtonStyle(foreground: Theme.textPrimary))
                        .font(Theme.Typography.labelMono)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm)
            .background(content.color.opacity(0.1))
        }
    }

    private struct Content {
        struct Action {
            let title: String
            let run: () -> Void
        }

        let icon: String
        let color: Color
        let message: String
        let action: Action?
    }

    private var content: Content? {
        let name = state.source.name
        switch state.phase {
        case .loading, .ready:
            return nil
        case .offline(let message):
            let age = state.lastUpdated.map { " · showing data from \(TaskPresentation.relative($0))" } ?? ""
            return Content(
                icon: "wifi.exclamationmark", color: Theme.warning,
                message: "\(name) is offline\(age). \(message)",
                action: .init(title: "Retry") { Task { await store.refreshAll() } }
            )
        case .reconnect:
            return Content(
                icon: "key.slash", color: Theme.error,
                message: "\(name) rejected the token. Reconnect with a new token.",
                action: .init(title: "Reconnect…") { store.beginConnect() }
            )
        case .unsupported(let message):
            return Content(icon: "exclamationmark.triangle", color: Theme.error, message: "\(name): \(message)", action: nil)
        }
    }
}

/// Hiç kaynak yokken: ne olduğunu anlatan kısa metin + `Connect Task Source`.
struct TasksEmptyState: View {
    let onConnect: () -> Void

    private static var textWidth: CGFloat { Theme.scaled(440) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(systemName: "checklist")
                .font(Theme.Typography.ui(.hero, weight: .light))
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityHidden(true)
            Text("Bring your own task board")
                .font(Theme.Typography.mono(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Connect a server you own — Heroku, Railway or anything else. Lumi gives you a setup prompt for your agent; paste the server's address and token here and your tasks show up on a board you can drive from Lumi.")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Self.textWidth)
            LumiActionButton(title: "Connect Task Source", kind: .primary, action: onConnect)
        }
        .padding(Theme.Spacing.xxxl)
    }
}
