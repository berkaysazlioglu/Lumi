import SwiftUI
import LumiMobileKit

struct RootView: View {
    let model: AppModel

    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @AppStorage(TUIStyle.sizeKey) private var textSize = TUIStyle.defaultSize

    var body: some View {
        Group {
            if model.isPaired {
                ProjectsView(model: model)
            } else {
                PairingView(model: model)
            }
        }
        .tint(LumiPalette.accent)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.isLumiTheme, appearance.isLumi)
        .environment(\.tuiStyle, TUIStyle(
            macFamily: model.projectsSnapshot.display.terminalFontFamily, size: textSize))
    }
}

/// Sample-data mode (no Mac): `AppModel` runs on `DemoRelayClient`. A build
/// can start in it by default (`LumiDemoByDefault` in Info.plist, set by
/// `DEMO=1 Scripts/make-mobile.sh`); the toggle then lives in Settings.
enum DemoMode {
    static let storageKey = "demoMode"

    static var buildDefault: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LumiDemoByDefault") as? String == "YES"
    }
}
