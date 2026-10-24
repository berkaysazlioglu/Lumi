import AppKit
import LumiKit
import LumiState
import SwiftUI

public extension OverlayID {
    /// Tasks planı: başarısız isteklerin ayrıntılı kaydı.
    static let taskFailureLog = OverlayID("taskFailureLog")
}

/// Hata kaydı sheet'i: solda başarısız istekler, sağda seçilenin ayrıntısı
/// (istek, HTTP durumu, sunucu kodu/mesajı, beklenen davranış, yanıtın başı)
/// ve `Copy for Agent`.
public struct TaskFailureLogOverlay: View {
    let store: TasksStore

    @Shell private var shell
    @State private var selection: UUID?

    public init(store: TasksStore) {
        self.store = store
    }

    private static var panelWidth: CGFloat { Theme.scaled(860) }
    private static var panelHeight: CGFloat { Theme.scaled(560) }
    private static var listWidth: CGFloat { Theme.scaled(300) }

    private var selected: TaskFailureEntry? {
        store.failureLog.first { $0.id == selection } ?? store.failureLog.first
    }

    public var body: some View {
        ModalOverlay(onDismiss: close) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    if store.failureLog.isEmpty {
                        EmptyStatePlaceholder("No failed requests", density: .full)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: 0) {
                            list.frame(width: Self.listWidth)
                            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                            if let selected { TaskFailureDetail(store: store, entry: selected) }
                        }
                    }
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
    }

    private func close() {
        store.isFailureLogPresented = false
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Request Errors")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("What failed, what the server said, and what Lumi expected")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if !store.failureLog.isEmpty {
                LumiActionButton(title: "Clear") {
                    store.clearFailureLog()
                    selection = nil
                }
            }
            IconButton(systemName: "xmark", label: "Close", side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: close)
        }
        .padding(Theme.Spacing.xl)
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: Theme.Spacing.xxs) {
                ForEach(store.failureLog) { entry in
                    row(entry)
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    private func row(_ entry: TaskFailureEntry) -> some View {
        let isSelected = entry.id == selected?.id
        return Button { selection = entry.id } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.error)
                        .accessibilityHidden(true)
                    Text(entry.failure.operation.title + (entry.failure.taskID.map { " · \($0)" } ?? ""))
                        .font(Theme.Typography.mono(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.count > 1 {
                        Badge(text: "×\(entry.count)", color: Theme.error)
                    }
                }
                Text(entry.failure.summary)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Text(sourceName(entry) + " · " + TaskPresentation.relative(entry.lastAt))
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.bgElevated : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sourceName(_ entry: TaskFailureEntry) -> String {
        store.state(of: entry.source)?.source.name ?? "Removed source"
    }
}

/// Seçili hatanın ayrıntısı.
private struct TaskFailureDetail: View {
    let store: TasksStore
    let entry: TaskFailureEntry

    @Shell private var shell

    private static var labelWidth: CGFloat { Theme.scaled(110) }

    private var failure: TaskRequestFailure { entry.failure }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(failure.summary)
                        .font(Theme.Typography.mono(.base, weight: .semibold))
                        .foregroundStyle(Theme.error)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        field("Operation", failure.operation.title)
                        if let request = failure.request { field("Request", request) }
                        if let taskID = failure.taskID { field("Task", taskID) }
                        if let status = failure.httpStatus { field("HTTP status", "\(status)") }
                        if let code = failure.serverCode { field("Server code", code) }
                        if let message = failure.serverMessage { field("Server message", message) }
                        field("When", TaskPresentation.relative(entry.lastAt) + (entry.count > 1 ? " · \(entry.count) times" : ""))
                    }
                    section("WHAT LUMI EXPECTED") {
                        Text(failure.hint)
                            .font(Theme.Typography.bodyMono)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let excerpt = failure.responseExcerpt, !excerpt.isEmpty {
                        section("RESPONSE BODY") {
                            Text(excerpt)
                                .font(Theme.Typography.mono(.label))
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                                .padding(Theme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.bgDeep)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            HStack {
                Spacer()
                LumiActionButton(title: "Copy for Agent", kind: .primary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failure.agentReport, forType: .string)
                    shell.toasts.show(.success, title: "Copied error report")
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(value)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.ui(.caption, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            content()
        }
    }
}
