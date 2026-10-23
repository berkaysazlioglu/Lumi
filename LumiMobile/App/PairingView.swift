import SwiftUI
import LumiMobileKit

struct PairingView: View {
    let model: AppModel
    @State private var pastedLink = ""
    @State private var showError = false
    @AppStorage(DemoMode.storageKey) private var demoMode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("On the Mac, scan the QR from Lumi → Settings → Remote, or paste the pairing link.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                scannerSection
                Section("Paste connection") {
                    TextField("lumi-remote://pair?...", text: $pastedLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pairingField")
                    Button("Pair") {
                        Task {
                            let ok = await model.pair(from: pastedLink)
                            showError = !ok
                        }
                    }
                    .accessibilityIdentifier("pairButton")
                    .disabled(pastedLink.isEmpty)
                    if showError {
                        Text("Couldn't resolve the connection. It must be in the form `lumi-remote://pair?...`.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        demoMode = true
                    } label: {
                        Label("Try with demo data", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Explore Lumi with sample projects and chats — no Mac needed.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LumiPalette.background)
            .navigationTitle("Pairing")
        }
    }

    @ViewBuilder private var scannerSection: some View {
        if QRScannerView.isAvailable {
            Section("Scan QR") {
                QRScannerView { value in
                    Task {
                        let ok = await model.pair(from: value)
                        showError = !ok
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}
