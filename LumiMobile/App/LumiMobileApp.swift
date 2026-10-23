import SwiftUI
import LumiMobileKit
import LumiWire

@main
struct LumiMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    /// Sample-data model, alive only while demo mode is on.
    @State private var demoModel: AppModel?
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    private let coordinator: PushCoordinator

    init() {
        // Persistent diagnostic log — Documents/lumi-mobile.log; can be retrieved
        // from the Mac via `xcrun devicectl device copy from` for inspection.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            DiagLog.shared.configure(directory: docs, filename: "lumi-mobile.log")
        }
        DiagLog.shared.log("app", "started")
        // A demo build starts in demo mode until the user turns it off.
        UserDefaults.standard.register(defaults: [DemoMode.storageKey: DemoMode.buildDefault])
        let model = AppModel(client: RelayClient(), store: KeychainStore())
        let coordinator = PushCoordinator(
            model: model,
            authorizer: SystemNotificationAuthorizer(),
            registrar: SystemRemoteRegistrar()
        )
        model.pushControl = coordinator
        _model = State(initialValue: model)
        self.coordinator = coordinator
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if demoMode {
                    if let demoModel {
                        RootView(model: demoModel)
                    } else {
                        ProgressView()
                    }
                } else {
                    RootView(model: model)
                }
            }
            .task {
                appDelegate.coordinator = coordinator
                await coordinator.refreshAuthStatus()
                await model.start()
            }
            .task(id: demoMode) { await switchDemo(on: demoMode) }
            .onOpenURL { url in
                // A real pairing link ends demo mode — otherwise the live model
                // pairs behind the demo and the user never sees it.
                demoMode = false
                Task { await model.pair(from: url.absoluteString) }
            }
        }
    }

    private func switchDemo(on: Bool) async {
        if let old = demoModel, !on {
            demoModel = nil
            await old.unpair()   // stops the demo client
        }
        guard on, demoModel == nil else { return }
        let demo = AppModel(client: DemoRelayClient(), store: DemoSecureStore())
        demoModel = demo
        await demo.start()
    }
}
