import SwiftUI
import LumiMobileKit

struct RootView: View {
    let model: AppModel

    var body: some View {
        if model.isPaired {
            ProjectsView(model: model)
        } else {
            PairingView(model: model)
        }
    }
}
