import LumiKit
import LumiState
import SwiftUI

/// Alt gözcünün `chatScroll` uzayındaki üst kenarı — liste dipte mi?
private struct ChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct ChatViewportKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Uzak Claude terminalinin chat görünümü (karar 143 ek): telefonun chat hattı, Mac'te.
/// Liste Claude Code TUI'si gibi çizilir; altta turn şeridi (Stop = Esc), bekleyen izin /
/// soru kartı ve mesaj kutusu (`RemoteChatComposer`). Boyut farkı yoktur: metin controller'ın genişliğinde kırılır.
struct RemoteChatView: View {
    let chat: RemoteChatSession
    let style: RemoteChatStyle

    /// Dipteyken yeni çıktı listeyi aşağıda tutar; kullanıcı yukarı kaydırınca bırakır.
    @State private var isFollowing = true
    @State private var bottomMinY: CGFloat?
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        let turns = chat.turns
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if chat.hasEarlier, !turns.isEmpty { earlierRow }
                        if turns.isEmpty { emptyRow }
                        ForEach(turns) { turn in
                            RemoteChatTurnView(turn: turn, style: style).id(turn.id)
                        }
                        Color.clear
                            .frame(height: Theme.Stroke.hairline)
                            .id(Self.bottomId)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: ChatBottomKey.self,
                                                       value: geometry.frame(in: .named(Self.space)).minY)
                            })
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.lg)
                }
                .coordinateSpace(name: Self.space)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ChatViewportKey.self, value: geometry.size.height)
                })
                .onPreferenceChange(ChatBottomKey.self) { minY in
                    bottomMinY = minY
                    updateFollowing()
                }
                .onPreferenceChange(ChatViewportKey.self) { height in
                    viewportHeight = height
                    updateFollowing()
                }
                .onChange(of: contentSignature(turns)) { _, _ in
                    if isFollowing { scrollToBottom(proxy) }
                }
                .onAppear { scrollToBottom(proxy) }
                .overlay(alignment: .top) { if chat.isSyncing, !turns.isEmpty { syncingBadge } }
                .overlay(alignment: .bottomTrailing) {
                    if !isFollowing { jumpButton(proxy) }
                }
            }
            if chat.status.working { statusBar }
            if let prompt = chat.activePrompt {
                RemoteChatPromptCard(
                    prompt: prompt,
                    draft: chat.draft(for: prompt),
                    onDraftChange: { chat.updateDraft($0, for: prompt) },
                    onAnswer: { chat.respond(to: prompt, with: $0) })
                    .id(prompt.itemId)
            }
            RemoteChatComposer(chat: chat, style: style) { isFollowing = true }
        }
        .background(Theme.bgDeep)
        .onAppear { chat.start() }
        .onDisappear { chat.stop() }
    }

    // MARK: - Liste

    private var emptyRow: some View {
        Text(chat.isSyncing ? "Loading chat…" : "Nothing here yet — type below to talk to Claude.")
            .font(Theme.Typography.bodyMono)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xxxl)
    }

    private var earlierRow: some View {
        Button {
            chat.loadEarlier()
        } label: {
            Text(chat.fullHistoryRequested ? "Loading earlier messages…" : "Load earlier messages")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.accentPrimary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(chat.fullHistoryRequested)
    }

    private var syncingBadge: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.mini)
            Text("Syncing…").font(Theme.Typography.labelMono)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.bgElevated, in: Capsule())
        .padding(.top, Theme.Spacing.sm)
    }

    private func jumpButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            isFollowing = true
            scrollToBottom(proxy)
        } label: {
            Label("Jump to bottom", systemImage: "arrow.down")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.bgElevated, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: Theme.Stroke.hairline))
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.lg)
    }

    /// Canlı metin ve büyüyen araç çıktısı turn sayısını değiştirmeden listeyi uzatır.
    private func contentSignature(_ turns: [FoldedTurn]) -> [String] {
        guard let last = turns.last else { return [] }
        let tail = ([last.message] + last.toolActivity).map { message in
            "\(message.id):\(message.blocks.count):\(chatCopyText(FoldedTurn(id: message.id, message: message, toolActivity: []))?.count ?? 0)"
        }
        return ["\(turns.count)"] + tail
    }

    private func updateFollowing() {
        guard let bottomMinY, viewportHeight > 0 else { return }
        let atBottom = bottomMinY - viewportHeight <= Self.followSlack
        if atBottom != isFollowing { isFollowing = atBottom }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
    }

    // MARK: - Turn şeridi

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.small)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(now: context.date))
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let tool = chat.status.tool {
                Text(tool)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            Spacer(minLength: Theme.Spacing.md)
            Button(chat.isStopping ? "Stopping…" : "Stop") { chat.interrupt() }
                .buttonStyle(.borderless)
                .font(Theme.Typography.mono(.label, weight: .semibold))
                .foregroundStyle(Theme.error)
                .disabled(chat.isStopping)
                .help("Interrupt Claude (Esc)")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.bgSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
    }

    private func elapsed(now: Date) -> String {
        guard let startedAtMs = chat.status.startedAtMs else { return "Working" }
        let started = Date(timeIntervalSince1970: Double(startedAtMs) / 1000)
        return "Working \(max(0, Int(now.timeIntervalSince(started))))s"
    }

    private static let space = "remoteChatScroll"
    private static let bottomId = "remoteChatBottom"
    private static var followSlack: CGFloat { Theme.scaled(40) }
}
