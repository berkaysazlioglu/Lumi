import CoreGraphics
import LumiKit
import SwiftUI

/// Top bar'ın üç bölgesi (Faz 6.4).
///
/// Bölge = Gestalt grubu, konum değil: `leading` gezinme (panel toggle, logo,
/// tab'lar), `center` üretim (grid ayarı, New <Provider>), `trailing` durum ve
/// global kontroller (usage, focus, git, settings). `HeaderBarView` bu üç
/// bölgeyi Spacer ile dizer; hangi öğenin hangi bölgeye düştüğü descriptor'ın
/// kararıdır.
public enum ToolbarRegion: String, Hashable, Sendable, CaseIterable {
    case leading
    case center
    case trailing

    /// Grup içi boşluk — bölgenin görsel yoğunluğu (karar 30 ince bar):
    /// gezinme geniş (8), üretim orta (6), durum sık (4).
    public var spacing: CGFloat {
        switch self {
        case .leading: return 8
        case .center: return 6
        case .trailing: return 4
        }
    }
}

/// Bir toolbar öğesinin kimliği — `PanelItemID` / `ContentRouteID` / `OverlayID`
/// ile aynı açık-küme kalıbı (yeni öğe = yeni sabit, enum değişikliği yok).
public struct ToolbarItemID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public extension ToolbarItemID {
    /// Bir panel yuvasının görünürlük toggle'ı — id yuvadan TÜRETİLİR, elle
    /// yazılmaz (yeni yuva eklendiğinde yeni sabit gerekmez).
    static func panelToggle(_ slot: PanelSlot) -> ToolbarItemID {
        ToolbarItemID("panelToggle.\(slot.rawValue)")
    }

    /// Sağlayıcı başına kullanım göstergesi (karar 32).
    static func usageIndicator(_ provider: AgentProvider) -> ToolbarItemID {
        ToolbarItemID("usageIndicator.\(provider.rawValue)")
    }

    static let logo = ToolbarItemID("logo")
    static let repoTabs = ToolbarItemID("repoTabs")
    static let gridSettings = ToolbarItemID("gridSettings")
    static let newTerminal = ToolbarItemID("newTerminal")
    static let focusMode = ToolbarItemID("focusMode")
    static let settings = ToolbarItemID("settings")
}

/// Top bar'daki bir öğenin tanımı (K33, Faz 6.4).
///
/// `makeView` PARAMETRESİZDİR (panel/overlay descriptor'larıyla aynı sözleşme):
/// öğe bağlamını `@Environment(\.shell)`'den okur, kayıt tarafı hiçbir store'u
/// closure'a kapatmaz. Böylece yeni bir feature kendi toolbar öğesini TEK
/// `registries.toolbar.register(...)` satırıyla ekler.
public struct ToolbarItemDescriptor: Identifiable {
    public let id: ToolbarItemID
    public let region: ToolbarRegion
    /// Bölge içi sıra — küçük önce. Eşitlikte kayıt sırası korunur.
    public let order: Int
    /// Öğe şu an anlamlı mı (örn. grid ayarı yalnız aktif repo route'unda).
    public let isVisible: @MainActor (ShellContext) -> Bool
    public let makeView: @MainActor () -> AnyView

    public init(
        id: ToolbarItemID,
        region: ToolbarRegion,
        order: Int,
        isVisible: @escaping @MainActor (ShellContext) -> Bool = { _ in true },
        makeView: @escaping @MainActor () -> AnyView
    ) {
        self.id = id
        self.region = region
        self.order = order
        self.isVisible = isVisible
        self.makeView = makeView
    }
}

/// Kayıtlı toolbar öğeleri (Faz 6.4/6.6).
///
/// Kayıt yeri composition root'tur (`ShellComposition` + feature assembly'ler);
/// burada yalnız TİP ve **saf çözümleme** yaşar: `items(in:context:)` view
/// render etmeden test edilir.
///
/// **Aynı id ikinci kez kaydedilirse ÖNCEKİNİ EZER** (panel/overlay
/// registry'leriyle aynı kural). Gerekçe: (a) kayıt kümesi birden çok
/// katkıcıdan (kabuk + feature assembly'ler) toplanır ve bir feature'ın
/// kabuğun default öğesini kendi sürümüyle değiştirebilmesi gerekir —
/// yığılma olsaydı bar'da iki kopya çizilirdi; (b) çözümleme kompozisyon
/// sırasından bağımsız kalır (aynı id iki kez gelirse sonuç tekildir);
/// (c) testler tek bir öğeyi izole edip yerine sahte koyabilir. Ezen kayıt
/// öğenin **kayıt sırasındaki yerini korur** — bir override, eşit `order`
/// değerine sahip komşularının sırasını kaydırmaz.
public struct ToolbarRegistry {
    private var descriptors: [ToolbarItemID: ToolbarItemDescriptor] = [:]
    /// Kayıt sırası — eşit `order` değerlerinde tie-break.
    private var registrationOrder: [ToolbarItemID] = []

    public init() {}

    public mutating func register(_ descriptor: ToolbarItemDescriptor) {
        if descriptors[descriptor.id] == nil {
            registrationOrder.append(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    public mutating func register(contentsOf descriptors: [ToolbarItemDescriptor]) {
        for descriptor in descriptors { register(descriptor) }
    }

    public var all: [ToolbarItemDescriptor] {
        registrationOrder.compactMap { descriptors[$0] }
    }

    public func descriptor(for id: ToolbarItemID) -> ToolbarItemDescriptor? {
        descriptors[id]
    }

    /// Bir bölgenin çizilecek öğeleri — **saf fonksiyon**.
    ///
    /// 1. bölge filtresi, 2. `isVisible` filtresi, 3. `order` sıralaması
    /// (eşitlikte kayıt sırası — `sorted` kararsız olduğu için tie-break
    /// açıkça yazılır).
    @MainActor
    public func items(in region: ToolbarRegion, context: ShellContext) -> [ToolbarItemDescriptor] {
        all.enumerated()
            .filter { $0.element.region == region && $0.element.isVisible(context) }
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}
