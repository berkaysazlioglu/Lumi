import CoreGraphics

/// Kabuğun geometri sabitleri (Faz 6.4).
///
/// Top bar ölçüleri LumiApp ile PAYLAŞILIR (`TrafficLightLayout` titlebar
/// container'ı `TopBarMetrics.height`'a büyütür — karar 27/30), bu yüzden
/// header view'ının içinde değil, kabuğun ortak metrik dosyasında dururlar.
public enum TopBarMetrics {
    /// İnce bar (karar 30).
    public static let height: CGFloat = 36
    /// Traffic light ilk butonunun sol kenarı (Orca `TRAFFIC_LIGHT_X`).
    public static let trafficLightLeading: CGFloat = 16
    /// İçeriğin başladığı x: 3 buton (16 + 2×20 + 12 = 68) + nefes payı.
    public static let contentLeading: CGFloat = 80
    /// Bar içi kontrol yüksekliği (ikon buton, chip, usage, grid).
    public static let controlHeight: CGFloat = 26
    /// Bar'ın sağ kenar payı.
    public static let trailingPadding: CGFloat = 10
    /// Sol grup ile üretim bölgesi arasındaki en küçük boşluk.
    public static let regionGap: CGFloat = 8
}

/// Panel yuvalarının genişlik default'u burada **tekrarlanmaz**: tek kaynak
/// LumiKit'teki `PanelLayout.defaultWidth`'tir (280) ve çizim tarafı ona
/// `LayoutStore.width(for:)` → `PanelLayout.width(for:)` zinciriyle ulaşır
/// (`PanelHostView`). UI'da ikinci bir 280 literali yoktur; olsaydı persist
/// edilen yerleşimle sessizce ayrışabilirdi.
