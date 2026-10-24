import LumiKit
import SwiftUI

/// Custom View route'larının görünen kimliği (karar 135).
public enum CustomViewRoute {
    public static let icon = "square.grid.2x2"

    public static func route(_ id: CustomViewID) -> WorkspaceRoute {
        .content(.customView(id))
    }
}

/// Aile descriptor'ının görünümü: hangi view'ın çizileceğini aktif route'tan
/// okur — descriptor'ın `makeView`'ı yalnız repo yolu taşır.
public struct CustomViewRouteView: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let scope = shell.activeTerminalScope, scope.customViewID != nil {
            TerminalsRouteView(scope: scope)
        } else {
            WelcomeView()
        }
    }
}
