import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Terminal kartının sağ üstündeki arama çubuğu (karar 144 — Orca
/// `TerminalSearch` paritesi). Çubuk yalnız o terminalin araması açıkken
/// görünür; durum `TerminalSearchStore`'da, tarama ve vurgu motordadır.
///
/// Tuşlar (Orca): yazdıkça arar, Enter sonraki, ⇧Enter önceki, Esc kapatır.
/// ⌘G / ⇧⌘G ve ⌘F menü komutlarıdır (`AppMenuCommands`).
struct TerminalSearchOverlay: View {
    let terminalID: TerminalID

    @Shell private var shell

    var body: some View {
        if let session = shell.terminalSearch.session(for: terminalID), session.isOpen {
            TerminalSearchBar(terminalID: terminalID, session: session, store: shell.terminalSearch)
                .padding(Theme.Spacing.sm)
                .transition(.opacity)
        }
    }
}

struct TerminalSearchBar: View {
    /// Orca: 340 px, dar kartta kart genişliğine iner.
    static var width: CGFloat { Theme.scaled(340) }
    private static let backgroundOpacity = 0.95
    private static let shadowOpacity = 0.35

    let terminalID: TerminalID
    let session: TerminalSearchStore.Session
    let store: TerminalSearchStore

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            field
            SearchOptionToggle(glyph: "Aa", help: "Case sensitive", isOn: binding(\.isCaseSensitive) {
                store.toggleCaseSensitive(terminalID)
            })
            SearchOptionToggle(glyph: ".*", help: "Regex", isOn: binding(\.isRegex) {
                store.toggleRegex(terminalID)
            })
            Text(session.statusText)
                .font(Theme.Typography.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.xxs)
                .accessibilityLabel("Search results: \(session.statusText)")
            separator
            IconButton(systemName: "chevron.up", label: "Previous match", size: .caption) {
                store.previous(terminalID)
            }
            IconButton(systemName: "chevron.down", label: "Next match", size: .caption) {
                store.next(terminalID)
            }
            separator
            IconButton(systemName: "xmark", label: "Close", size: .caption) {
                store.close(terminalID)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: Self.width)
        .background(Theme.bgElevated.opacity(Self.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: .black.opacity(Self.shadowOpacity), radius: Theme.Radius.lg, y: Theme.Spacing.xs)
        .onAppear(perform: focusFieldIfRequested)
        .onChange(of: session.focusRequest) { focusFieldIfRequested() }
    }

    private var field: some View {
        TextField("Search...", text: Binding(
            get: { session.query.text },
            set: { store.setText($0, for: terminalID) }
        ))
        .textFieldStyle(.plain)
        .font(Theme.Typography.ui(.body))
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .focused($isFieldFocused)
        .accessibilityLabel("Search terminal")
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) {
                store.previous(terminalID)
            } else {
                store.next(terminalID)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            store.close(terminalID)
            return .handled
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: Theme.Stroke.hairline, height: Theme.Spacing.xl)
    }

    /// Seçenek anahtarı store intent'ine gider; değer oturumdan okunur.
    private func binding(_ key: KeyPath<TerminalSearchQuery, Bool>, toggle: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { session.query[keyPath: key] }, set: { _ in toggle() })
    }

    /// ⌘F (açıkken de): alan odaklanır ve metni seçilir — yeni sorgu üstüne
    /// yazılır (Orca `input.select()`). Seçim, alan editörü first responder
    /// olduktan sonraki turda yapılır.
    private func focusFieldIfRequested() {
        guard session.isFocusRequested else { return }
        store.didFocusField(terminalID)
        isFieldFocused = true
        DispatchQueue.main.async {
            // Yalnız alan editörüne: odak henüz geçmediyse `selectAll` terminale
            // düşüp tüm buffer'ı seçerdi.
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
            editor.selectAll(nil)
        }
    }
}

#if DEBUG
#Preview("Terminal search bar") {
    let store = ShellContext.preview().terminalSearch
    let id = TerminalID()
    store.open(id)
    store.setText("error", for: id)
    return TerminalSearchBar(terminalID: id, session: store.session(for: id)!, store: store)
        .padding(Theme.Spacing.xxl)
        .background(Theme.bgDeep)
}
#endif
