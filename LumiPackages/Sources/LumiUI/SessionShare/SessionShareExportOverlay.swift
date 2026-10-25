import LumiKit
import LumiState
import SwiftUI

/// Agent History ▸ sağ tık ▸ Export to Server onayı (karar 138): başlık ve
/// proje adı düzenlenebilir, yükleyen token'ın sahibidir. Bağlantı yoksa
/// kurulum popup'ına yönlendirir.
public struct SessionShareExportOverlay: View {
    @Shell private var shell

    public init() {}

    private static var width: CGFloat { Theme.scaled(520) }

    public var body: some View {
        if let store = shell.sessionShare, let draft = store.exportDraft {
            ModalOverlay(onDismiss: store.cancelExport) {
                Panel(variant: .modal) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Export to Server")
                            .font(Theme.Typography.titleMono)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.bottom, Theme.Spacing.lg)
                        if store.isConnected {
                            ExportForm(store: store, draft: draft)
                        } else {
                            notConnected(store)
                        }
                    }
                    .padding(Theme.Spacing.xxl)
                    .frame(width: Self.width)
                }
            }
        }
    }

    private func notConnected(_ store: SessionShareStore) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("No session server is connected. Set one up once and every teammate with a token can import your sessions.")
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                LumiActionButton(title: "Cancel", action: store.cancelExport)
                LumiActionButton(title: "Set Up Server…", kind: .primary, action: store.setUpServerFromExport)
            }
        }
    }
}

private struct ExportForm: View {
    @Bindable var store: SessionShareStore
    let draft: SessionShareStore.ExportDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiField(title: "Title", hint: nil) {
                LumiTextInput(text: binding(\.title), placeholder: "What was this session about?", autofocus: true)
            }
            LumiField(title: "Project", hint: "A plain name teammates will see, e.g. Backend API") {
                LumiTextInput(text: binding(\.project), placeholder: "Project name")
            }
            LumiField(title: "Uploader", hint: nil, isLast: draft.failure == nil) {
                Text(uploaderLine)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = draft.failure {
                LumiField(title: "Upload failed", hint: nil, isLast: true) {
                    SessionShareFailureView(failure: failure)
                }
            }
            HStack {
                Spacer()
                LumiActionButton(title: "Cancel", action: store.cancelExport)
                    .disabled(draft.isUploading)
                LumiActionButton(title: draft.isUploading ? "Uploading…" : "Upload", kind: .primary) {
                    Task { await store.confirmExport() }
                }
                .disabled(!draft.canUpload)
            }
            .padding(.top, Theme.Spacing.lg)
        }
    }

    private var uploaderLine: String {
        let who = store.info?.me.name ?? "You"
        let server = store.server?.name ?? "the server"
        return "\(who) on \(server). Personal records (CLAUDE.md contents, e-mail, costs, local backups) are stripped, as in file export; tool inputs and outputs are uploaded as they are."
    }

    private func binding(_ path: WritableKeyPath<SessionShareStore.ExportDraft, String>) -> Binding<String> {
        Binding(
            get: { store.exportDraft?[keyPath: path] ?? "" },
            set: { value in
                store.exportDraft?[keyPath: path] = value
                store.exportDraft?.failure = nil
            }
        )
    }
}
