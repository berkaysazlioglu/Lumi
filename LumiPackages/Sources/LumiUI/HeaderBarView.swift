import LumiKit
import LumiState
import SwiftUI

/// Üst header çubuğu (ince yerleşim karar 30 — Orca paritesi). 36px,
/// traffic light'lar doğal macOS konumunda (karar 27/30: yükseklik ve leading
/// padding bu dosyanın DEĞİŞMEZLERİ — `TrafficLightLayout` aynı ölçüleri okur).
///
/// **Faz 6.4:** gövde artık elle dizilmiş bir HStack değil, üç bölgenin
/// (`leading` · `center` · `trailing`) `ToolbarRegistry`'den çözülüp
/// çizilmesidir. Header hiçbir özel kontrolün adını bilmez; hamburger, logo,
/// tab şeridi, grid ayarı, New <Provider>, usage göstergeleri, focus/git/
/// settings ikonlarının hepsi birer `ToolbarItemDescriptor`'dır ve kayıt yeri
/// composition root'tur. Yeni bir feature'ın bar'a öğe koyması = kendi
/// assembly'sinde tek `registries.toolbar.register(...)` satırı.
///
/// Focus mode'da header hiç çizilmez (`AppShellView`); bu view o kararı bilmez.
struct HeaderBarView: View {
    static let height: CGFloat = TopBarMetrics.height

    let registry: ToolbarRegistry

    @Shell private var shell

    var body: some View {
        HStack(spacing: 0) {
            region(.leading)
            // Gezinme ile üretim arasındaki esneme payı. Tab şeridi zaten
            // `maxWidth: .infinity` olduğu için bu Spacer minimumda kalır;
            // şerit yokken (hiç öğe yoksa) üretim bölgesini sağa iter.
            Spacer(minLength: TopBarMetrics.regionGap)
            region(.center)
            region(.trailing)
        }
        // Sol: traffic light alanı — içerik butonların sağından başlar
        .padding(.leading, TopBarMetrics.contentLeading)
        .padding(.trailing, TopBarMetrics.trailingPadding)
        .frame(height: Self.height)
        // Renk hit-test'i kapalı: boş alanlardaki tıklamalar arkadaki
        // WindowDragArea'ya geçsin (pencere sürükleme + çift-tık zoom).
        .background(Theme.bgSurface.allowsHitTesting(false))
        .background(WindowDragArea())
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }

    private func region(_ region: ToolbarRegion) -> some View {
        HStack(spacing: region.spacing) {
            ForEach(registry.items(in: region, context: shell)) { item in
                item.makeView()
            }
        }
    }
}
