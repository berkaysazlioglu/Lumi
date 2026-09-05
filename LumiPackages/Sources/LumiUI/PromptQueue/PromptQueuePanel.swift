import LumiKit
import LumiState
import SwiftUI

/// Aktif terminalin prompt kuyruğunu düzenleyen panel: prompt ekle, sırala,
/// sil, duraklat/devam. Kuyruk, terminal "bekliyor"a geçtikçe sıradakini
/// otomatik gönderir; izin promptunda (karar bekliyor) duraklar.
///
/// Yüzey ortak `Panel`'in `.floating` varyantıdır (Faz 7.2): zemin ve kenarlık
/// v1'deki gibi `bgElevated` + hairline; yalnız gölge burada kalır, çünkü
/// `Panel` gölgeyi yalnız `.modal` varyantında taşır.
struct PromptQueuePanel: View {
    let terminalID: TerminalID
    @Bindable var store: PromptQueueStore
    let onClose: () -> Void

    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

    /// Ölçek dışı geometri (refactor 7.8: magic sayılar isimlendirildi).
    private enum Metrics {
        /// Bir kuyruk satırının yaklaşık yüksekliği.
        static let rowHeight: CGFloat = 44
        /// Liste kenar boşluğu payı.
        static let listPadding: CGFloat = 8
        /// Liste bu yüksekliği geçerse kendi içinde kaydırılır.
        static let maxListHeight: CGFloat = 180
        /// Kapatma butonunun kare kenarı.
        static let closeSide: CGFloat = 22
        /// Panel gölgesi.
        static let shadowRadius: CGFloat = 24
        static let shadowOffsetY: CGFloat = 8
    }

    private var prompts: [QueuedPrompt] { store.prompts(for: terminalID) }
    private var isPaused: Bool { store.isPaused(terminalID) }

    var body: some View {
        Panel(variant: .floating) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                Divider().overlay(Theme.border)
                queueList
                composer
                footerHint
            }
            .padding(Theme.Spacing.xl)
        }
        .shadow(color: .black.opacity(0.4), radius: Metrics.shadowRadius, y: Metrics.shadowOffsetY)
        // Focus, view hiyerarşisi kurulduktan SONRA verilir; `DispatchQueue.main`
        // hack'i yerine MainActor görevi (refactor 7.8).
        .task { isDraftFocused = true }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(Theme.Typography.ui(.body, weight: .bold))
                .foregroundStyle(Theme.accentPrimary)
                .accessibilityHidden(true)
            Text("Prompt Queue")
                // 14pt → ölçekte `base` (13); yuvarlama asla büyütmez.
                .font(Theme.Typography.ui(.base, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(isPaused ? "Resume" : "Pause") {
                store.setPaused(!isPaused, for: terminalID)
            }
            .buttonStyle(.plain)
            .font(Theme.Typography.ui(.body, weight: .medium))
            .foregroundStyle(isPaused ? Theme.warning : Theme.textSecondary)

            if !prompts.isEmpty {
                Button("Clear") { store.clear(for: terminalID) }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.ui(.body, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
            IconButton(
                systemName: "xmark",
                label: "Close prompt queue",
                side: Metrics.closeSide,
                showsHoverBackground: false,
                action: onClose
            )
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if prompts.isEmpty {
            EmptyStatePlaceholder(
                "No prompts queued. Type one below to add it; each is sent as the "
                    + "terminal finishes its work and goes idle."
            )
        } else {
            List {
                // Stabil kimlik: `.onMove` ve silme sırasında satır kimliği
                // indeksle birlikte kaymaz (refactor 7.8).
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    PromptQueueRow(index: index, text: prompt.text) {
                        store.remove(prompt.id, for: terminalID)
                    }
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xxs,
                        leading: 0,
                        bottom: Theme.Spacing.xxs,
                        trailing: 0
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1, for: terminalID) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(
                CGFloat(prompts.count) * Metrics.rowHeight + Metrics.listPadding,
                Metrics.maxListHeight
            ))
        }
    }

    private var composer: some View {
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        HStack(alignment: .bottom, spacing: 10) {
            draftField
            // `IconButton` DEĞİL: rengi hover'a değil, `canAdd` durumuna bağlı
            // (accent ↔ muted) — ortak butonun üç rolünden hiçbiri bu değil.
            Button(action: addDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    // 28pt → ölçekte `display` (22); yuvarlama asla büyütmez.
                    .font(Theme.Typography.ui(.display))
                    .foregroundStyle(canAdd ? Theme.accentPrimary : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityLabel("Add prompt to queue")
            .help("Add to queue (Enter)")
        }
    }

    private var draftField: some View {
        TextField(
            "Type a prompt…  (Enter: add to queue · Shift+Enter: new line)",
            text: $draft,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(Theme.Typography.baseMono)
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(1 ... 3)
        .focused($isDraftFocused)
        .onKeyPress(keys: [.return, .escape], phases: .down) { press in
            switch press.key {
            case .escape:
                onClose()
                return .handled
            case .return where !press.modifiers.contains(.shift):
                addDraft()
                return .handled
            default:
                return .ignored // Shift+Enter → alt satır
            }
        }
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        .padding(10)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(
                    isDraftFocused ? Theme.accentPrimary : Theme.border,
                    lineWidth: Theme.Stroke.hairline
                )
        )
    }

    private var footerHint: some View {
        Label(
            "The queue auto-pauses on a permission/confirmation prompt; it resumes once you answer.",
            systemImage: "info.circle"
        )
        .font(Theme.Typography.label)
        .foregroundStyle(Theme.textMuted)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addDraft() {
        guard canAdd else { return }
        store.enqueue(draft, for: terminalID)
        draft = ""
        isDraftFocused = true
    }
}

#if DEBUG
#Preview("PromptQueuePanel") {
    let shell = ShellContext.preview()
    let terminalID = TerminalID()
    PromptQueuePanel(terminalID: terminalID, store: shell.promptQueue, onClose: {})
        .frame(width: 620)
        .padding(Theme.Spacing.xxxl)
        .background(Theme.bgDeep)
        .task {
            shell.promptQueue.enqueue("Run the full test suite", for: terminalID)
            shell.promptQueue.enqueue("Summarise the failures", for: terminalID)
        }
}
#endif
