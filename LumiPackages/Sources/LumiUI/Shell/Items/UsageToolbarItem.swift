import LumiKit
import SwiftUI

/// Sağlayıcı başına kullanım göstergesi (karar 32, Faz 6.4).
///
/// Eski `ForEach(enabledProviders)` döngüsünün yerine geçer: her sağlayıcı
/// artık KENDİ descriptor'ıdır (`UsageFeatureAssembly` `AgentProvider.allCases`
/// için birer tane kaydeder), ayarın açık/kapalı durumu descriptor'ın
/// `isVisible` kapısında okunur. Store yoksa (kompozisyonda o sağlayıcı hiç
/// kurulmamışsa) hiçbir şey çizilmez — eski `if let store` koşulu.
public struct UsageToolbarItem: View {
    private let provider: AgentProvider

    @Shell private var shell

    public init(provider: AgentProvider) {
        self.provider = provider
    }

    public var body: some View {
        if let store = shell.usage[provider] {
            UsageIndicatorView(store: store)
        }
    }
}
