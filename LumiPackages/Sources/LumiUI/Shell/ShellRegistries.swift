import LumiKit
import SwiftUI

/// Kabuğun kayıt defteri (Faz 6.6).
///
/// Descriptor **tipleri** LumiUI'da, **kümesi** composition root'ta
/// (`LumiAppCore/Composition/ShellComposition.swift`) yaşar: her feature
/// assembly kendi panel öğesini / route'unu / overlay'ini buraya kaydeder.
/// Sonuç: **yeni feature = assembly'de birkaç `register(...)` satırı**; kabuk
/// dosyalarına hiç dokunulmaz.
@MainActor
public final class ShellRegistries {
    public var panels = PanelItemRegistry()
    public var routes = ContentRouteRegistry()
    public var overlays = OverlayRegistry()
    /// Top bar öğeleri (Faz 6.4) — `HeaderBarView` üç bölgeyi buradan çizer.
    public var toolbar = ToolbarRegistry()

    public init() {}
}
