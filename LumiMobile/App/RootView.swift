import SwiftUI
import LumiMobileKit

struct RootView: View {
    let model: AppModel

    @AppStorage(TUIStyle.sizeKey) private var textSize = TUIStyle.defaultSize

    var body: some View {
        Group {
            if model.isPaired {
                ProjectsView(model: model)
            } else {
                PairingView(model: model)
            }
        }
        .lumiThemed()
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

/// Applies the Appearance choice (color scheme + accent). Sheets re-apply it:
/// they are separate presentations and don't reliably inherit it.
private struct LumiThemed: ViewModifier {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default

    func body(content: Content) -> some View {
        content
            .tint(LumiPalette.accent)
            .preferredColorScheme(appearance.colorScheme)
    }
}

extension View {
    func lumiThemed() -> some View { modifier(LumiThemed()) }
}
