import LumiKit
import LumiState
import SwiftUI

/// Faz 1 walking skeleton kök görünümü: terminal sekmeleri + tek/grid görünüm.
/// Sekme değişimi attach/detach yolunu, "tümü" modu çoklu-attach'i egzersiz eder
/// (design/04 faz 1 kanıtları). Gerçek Layout/Header/Sidebar yapısı Faz 3+.
public struct RootView: View {
    private let store: TerminalListStore
    private let viewProvider: any TerminalViewProviding
    private let repoPath: String
    @State private var showAll = false

    public init(store: TerminalListStore, viewProvider: any TerminalViewProviding, repoPath: String) {
        self.store = store
        self.viewProvider = viewProvider
        self.repoPath = repoPath
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.top, 38)
                .padding(.bottom, 10)
                .background(Theme.bgSurface)
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        }
        .background(Theme.bgDeep)
        .preferredColorScheme(.dark)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("New Terminal") {
                store.spawn(in: repoPath)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)

            Toggle("Show All", isOn: $showAll)
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.textSecondary)

            tabChips

            Spacer()

            if let message = store.lastErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.error)
                    .lineLimit(1)
            }

            Text("\(store.terminals.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.terminals) { meta in
                    chip(for: meta)
                }
            }
        }
    }

    private func chip(for meta: TerminalMeta) -> some View {
        let isActive = store.activeTerminalID == meta.id
        // Odak ve kapatma AYRI butonlar: iç içe Button'da iç buton tıklamayı
        // dış butona kaptırır (kapatma yerine odaklama bug'ı)
        return HStack(spacing: 6) {
            Button {
                store.focus(meta.id)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.statusColor(for: meta.status))
                        .frame(width: 8, height: 8)
                    Text(meta.oscTitle ?? meta.task ?? meta.name)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button {
                store.close(meta.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Theme.bgElevated : Theme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
    }

    @ViewBuilder
    private var content: some View {
        if store.terminals.isEmpty {
            VStack(spacing: 8) {
                Text("Lumi")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accentPrimary)
                Text("New Terminal ile başla")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showAll {
            allTerminalsGrid
        } else if let activeID = store.activeTerminalID {
            terminalCard(for: activeID)
        }
    }

    private var allTerminalsGrid: some View {
        // Spec/20 grid matematiği Faz 3'te; skeleton 400px-min adaptive ile yetinir
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 400), spacing: 12)],
                spacing: 12
            ) {
                ForEach(store.terminals) { meta in
                    terminalCard(for: meta.id)
                        .frame(height: 320)
                }
            }
        }
    }

    private func terminalCard(for id: TerminalID) -> some View {
        TerminalHostView(terminalID: id, provider: viewProvider)
            .id(id)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        store.activeTerminalID == id ? Theme.accentPrimary : Theme.border,
                        lineWidth: 1
                    )
            )
    }
}
