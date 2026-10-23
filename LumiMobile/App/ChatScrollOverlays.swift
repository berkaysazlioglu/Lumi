// LumiMobile/App/ChatScrollOverlays.swift
import SwiftUI
import LumiMobileKit

/// Decision 131: each realized turn's extent in the "chatScroll" space, so the
/// chat can tell which prompt the topmost visible text answers.
struct ChatTurnFramesKey: PreferenceKey {
    static var defaultValue: [String: ChatTurnFrame] { [:] }
    static func reduce(value: inout [String: ChatTurnFrame], nextValue: () -> [String: ChatTurnFrame]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this turn's frame through `ChatTurnFramesKey`.
    func reportsChatTurnFrame(_ id: String) -> some View {
        background(
            GeometryReader { g in
                let frame = g.frame(in: .named("chatScroll"))
                Color.clear.preference(key: ChatTurnFramesKey.self,
                                       value: [id: ChatTurnFrame(minY: frame.minY, maxY: frame.maxY)])
            }
        )
    }
}

/// Decision 131 (Claude Code fullscreen parity): a dim row pinned over the top of the
/// transcript showing the prompt the visible text answers; tapping jumps to it.
struct ChatStickyPromptHeader: View {
    let text: String
    let action: () -> Void

    @Environment(\.tuiStyle) private var style

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("> ").foregroundStyle(Color(TUIColors.dim))
                Text(text.replacingOccurrences(of: "\n", with: " "))
                    .foregroundStyle(LumiPalette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up").font(.caption2).foregroundStyle(LumiPalette.textSecondary)
            }
            .font(style.swiftUIFont)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(LumiPalette.elevated.opacity(0.96))
            .overlay(alignment: .bottom) { LumiPalette.border.frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to prompt: \(text)")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Decision 131: floats over the bottom edge while scrolled up; counts the turns
/// that arrived meanwhile (`3 new messages`).
struct ChatJumpToBottomButton: View {
    let newCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                Text(label)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(newCount > 0 ? LumiPalette.accent : LumiPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(LumiPalette.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(LumiPalette.border))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel(label)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var label: String {
        switch newCount {
        case 0: "Jump to bottom"
        case 1: "1 new message"
        default: "\(newCount) new messages"
        }
    }
}

/// Decision 131: the head of a cut chat. While the Mac may still hold more it is a
/// button that asks for the whole chat; once asked (or loading) it says why it ends.
struct ChatEarlierMessagesRow: View {
    let canLoad: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading earlier messages…")
                }
                .foregroundStyle(LumiPalette.textSecondary)
            } else if canLoad {
                Button(action: action) {
                    Label("Load earlier messages", systemImage: "arrow.up.circle")
                        .foregroundStyle(LumiPalette.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text("Older messages are only on the Mac")
                    .foregroundStyle(LumiPalette.textSecondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
