import SwiftUI
import UIKit
import LumiMobileKit

/// The gear's settings screen (decision 133) — a sheet, not a popover menu.
/// Always reachable, even offline or on a stale pairing, so a dead relay
/// connection can be recovered by disconnecting and re-pairing.
struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @AppStorage(TUIStyle.sizeKey) private var textSize = TUIStyle.defaultSize
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    @AppStorage(ClaudeModelShortcuts.storageKey) private var showsClaudeModels = ClaudeModelShortcuts.defaultValue
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: notificationsBinding) {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }
                Section("Display") {
                    Picker(selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    Picker(selection: $textSize) {
                        ForEach(Int(TUIStyle.sizeRange.lowerBound)...Int(TUIStyle.sizeRange.upperBound), id: \.self) {
                            Text("\($0) pt").tag(Double($0))
                        }
                    } label: {
                        Label("Chat Text Size", systemImage: "textformat.size")
                    }
                }
                Section {
                    Toggle(isOn: $showsClaudeModels) {
                        Label("Claude Models", systemImage: "cpu")
                    }
                } header: {
                    Text("New Agent")
                } footer: {
                    Text("Adds Fable, Opus, Sonnet and Haiku to a checkout's + menu.")
                }
                Section {
                    if demoMode {
                        Button("Exit Demo Data", role: .destructive) {
                            demoMode = false
                            dismiss()
                        }
                    } else {
                        Button("Disconnect", role: .destructive) { confirmUnpair = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Disconnect from this Mac?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    dismiss()
                    Task { await model.unpair() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll return to the pairing screen and can scan a new QR code.")
            }
        }
        .lumiThemed()
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled },
            set: { isOn in
                Task {
                    if isOn {
                        if await model.enableNotifications() == .needsSettings,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    } else {
                        await model.disableNotifications()
                    }
                }
            }
        )
    }
}

/// Settings ▸ New Agent ▸ Claude Models: whether the `+` menu lists Claude's
/// model shortcuts (Mac decision 121). Off by default.
enum ClaudeModelShortcuts {
    static let storageKey = "showsClaudeModelShortcuts"
    static let defaultValue = false
}
