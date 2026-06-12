import LumiKit
import LumiState
import SwiftUI

/// Terminal topbar'ındaki kuyruk toggle butonu: liste ikonu + bekleyen prompt
/// sayısı rozeti. Duraklatıldıysa rozet renk değiştirir.
struct PromptQueueToggleButton: View {
    let count: Int
    let isPaused: Bool
    @Binding var isOpen: Bool

    @State private var isHovering = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: isPaused ? "pause.rectangle" : "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)
                    .background(isHovering || isOpen ? Theme.bgSurface : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(isPaused ? Theme.warning : Theme.accentVivid)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Prompt kuyruğu")
    }

    private var iconColor: Color {
        if isOpen || isHovering { return Theme.textPrimary }
        return count > 0 ? Theme.accentPrimary : Theme.textMuted
    }
}

// MARK: - Merkezi overlay

/// Toggle açıkken terminalin ortasında, kartın %90 genişliğinde bir panel açar;
/// arka planı karartır, dışına tıklama/Escape kapatır. `.popover` yerine in-card
/// overlay: merkezi konum ve geniş textfield için.
struct PromptQueueOverlayModifier: ViewModifier {
    @Binding var isOpen: Bool
    let terminalID: TerminalID
    var store: PromptQueueStore

    func body(content: Content) -> some View {
        content.overlay {
            if isOpen {
                GeometryReader { geo in
                    ZStack {
                        Theme.bgDeep.opacity(0.55)
                            .contentShape(Rectangle())
                            .onTapGesture { isOpen = false }
                        PromptQueuePanel(
                            terminalID: terminalID,
                            store: store,
                            onClose: { isOpen = false }
                        )
                        .frame(width: min(geo.size.width * 0.9, 760))
                        .frame(maxHeight: geo.size.height * 0.92)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: isOpen)
    }
}

extension View {
    func promptQueueOverlay(
        isOpen: Binding<Bool>,
        terminalID: TerminalID,
        store: PromptQueueStore
    ) -> some View {
        modifier(PromptQueueOverlayModifier(isOpen: isOpen, terminalID: terminalID, store: store))
    }
}

// MARK: - Panel

/// Aktif terminalin prompt kuyruğunu düzenleyen panel: prompt ekle, sırala,
/// sil, duraklat/devam. Kuyruk, terminal "bekliyor"a geçtikçe sıradakini
/// otomatik gönderir; izin promptunda (karar bekliyor) duraklar.
struct PromptQueuePanel: View {
    let terminalID: TerminalID
    @Bindable var store: PromptQueueStore
    let onClose: () -> Void

    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

    private var prompts: [String] { store.prompts(for: terminalID) }
    private var isPaused: Bool { store.isPaused(terminalID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(Theme.border)
            queueList
            composer
            footerHint
        }
        .padding(16)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        .onAppear {
            DispatchQueue.main.async { isDraftFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentPrimary)
            Text("Prompt Kuyruğu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if !prompts.isEmpty {
                Button(isPaused ? "Devam" : "Duraklat") {
                    store.setPaused(!isPaused, for: terminalID)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isPaused ? Theme.warning : Theme.textSecondary)

                Button("Temizle") { store.clear(for: terminalID) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if prompts.isEmpty {
            Text("Sırada prompt yok. Aşağıya yazıp ekle; terminal her işini bitirip beklemeye geçtikçe sıradaki gönderilir.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            List {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                    PromptQueueRow(index: index, text: prompt) {
                        store.remove(at: index, for: terminalID)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1, for: terminalID) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(prompts.count) * 44 + 8, 180))
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Prompt yaz…  (Enter: sıraya ekle · Shift+Enter: alt satır)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3)
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
                .padding(10)
                .background(Theme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDraftFocused ? Theme.accentPrimary : Theme.border, lineWidth: 1)
                )

            Button(action: addDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canAdd ? Theme.accentPrimary : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .help("Sıraya ekle (Enter)")
        }
    }

    private var footerHint: some View {
        Label(
            "İzin/onay sorusunda kuyruk otomatik duraklar; sen cevaplayınca devam eder.",
            systemImage: "info.circle"
        )
        .font(.system(size: 11))
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

/// Kuyruktaki tek prompt satırı: sıra no + metin önizleme + sil butonu.
private struct PromptQueueRow: View {
    let index: Int
    let text: String
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovering ? Theme.error : Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }
}
