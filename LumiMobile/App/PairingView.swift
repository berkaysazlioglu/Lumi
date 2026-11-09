import SwiftUI
import LumiMobileKit

struct PairingView: View {
    let model: AppModel
    @State private var pastedLink = ""
    @AppStorage(DemoMode.storageKey) private var demoMode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("On the Mac, connect Lumi to a relay server in Remote ▸ Mobile, then scan its QR or paste the pairing link.")
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
                            await model.pair(from: pastedLink)
                        }
                    }
                    .accessibilityIdentifier("pairButton")
                    .disabled(pastedLink.isEmpty)
                    if let error = model.pairingError {
                        Text(error)
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
                        await model.pair(from: value)
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }
        }
    }
}
