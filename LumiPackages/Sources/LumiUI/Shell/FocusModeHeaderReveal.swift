import LumiKit
import LumiState
import SwiftUI

/// Focus mode'da top bar'ın üst kenar hover'ıyla içeriğin ÜSTÜNE inmesi.
///
/// Focus mode header'ı kabuktan kaldırır (`AppShellView`). Fare pencerenin üst
/// kenarındaki görünmez şeride gelince `revealDelay` sonra GERÇEK top bar
/// (`HeaderBarView` — aynı toolbar registry'si, focus mode ikonu dahil)
/// overlay olarak yukarıdan kayar; orta alan yeniden yerleşmez, terminaller
/// boyut değiştirmez. Fare bar'dan çıkınca bar kapanır. Çıkışın kısayol
/// dışındaki yolu bar'daki focus mode ikonudur.
///
/// Hover'ın kaynağı SwiftUI `.onHover` DEĞİL, `PointerPresence` sensörüdür:
/// terminal fare raporlarken `.mouseMoved` yutulur ve `.onHover` hiç tetiklenmez
/// (eski focus bar'ın terminal üstünde açılmamasının sebebi buydu). Sensör
/// bar'dan açılan popover'ları (grid ayarı, New <Provider> listesi) da içeride
/// sayar; popover açıkken bar kapanmaz.
struct FocusModeHeaderReveal: View {
    static let revealDelay = Theme.Motion.hoverRevealDelay

    let registries: ShellRegistries

    @Shell private var shell

    @State private var pendingTask: Task<Void, Never>?

    /// Görünmez tetikleme şeridinin yüksekliği.
    private static var triggerHeight: CGFloat { Theme.Spacing.md }

    var body: some View {
        let isRevealed = shell.layout.isFocusHeaderRevealed
        let barHeight = TopBarMetrics.height + Theme.Stroke.hairline

        // Tek, kalıcı tracking bölgesi: kapalıyken ince şerit, açıkken bar
        // yüksekliği. Yalnız bar animasyon alır, hover sınırı hareket etmez.
        Color.clear
            .frame(height: isRevealed ? barHeight : Self.triggerHeight)
            .frame(maxWidth: .infinity)
            .background(PointerPresence(onChange: pointerPresenceChanged))
            .overlay(alignment: .top) {
                ZStack {
                    if isRevealed {
                        HeaderBarView(registry: registries.toolbar)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(height: barHeight, alignment: .top)
                .clipped()
                .animation(
                    isRevealed ? Theme.Motion.standardOut : Theme.Motion.quickEase,
                    value: isRevealed
                )
                .allowsHitTesting(isRevealed)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onDisappear {
                cancelPending()
                shell.layout.setFocusHeaderRevealed(false)
            }
    }

    private func pointerPresenceChanged(_ isInside: Bool) {
        guard isInside else {
            cancelPending()
            shell.layout.setFocusHeaderRevealed(false)
            return
        }
        guard !shell.layout.isFocusHeaderRevealed, pendingTask == nil else { return }
        pendingTask = Task { @MainActor in
            defer { pendingTask = nil }
            do {
                try await Task.sleep(for: Self.revealDelay)
            } catch {
                return
            }
            shell.layout.setFocusHeaderRevealed(true)
        }
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
