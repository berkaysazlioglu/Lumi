import LumiKit
import SwiftUI

/// Panel öğesinin dikey pay politikası.
///
/// Bugünkü kabuğun iki davranışı: Sessions içeriği kadar yer kaplar (`fit`),
/// Project Context / git bölümleri kalan alanı paylaşır (`fill`).
public enum PanelItemSizing: Sendable {
    /// İçerik kadar yükseklik.
    case fit
    /// Kalan alanı diğer `fill` öğeleriyle eşit paylaşır.
    case fill
}

/// Bir panel öğesinin tanımı (K33, Faz 6.2).
///
/// `makeView` PARAMETRESİZDİR: öğe bağlamını `@Environment(\.shell)`'den okur.
/// Böylece kayıt tarafı (feature assembly) hiçbir store'u closure'a kapatmaz ve
/// aynı descriptor herhangi bir yuvada çizilebilir.
public struct PanelItemDescriptor: Identifiable {
    public let id: PanelItemID
    public let title: String
    public let icon: String
    /// Kullanıcı yerleşimi yoksa (yeni öğe) hangi yuvaya düşeceği.
    public let defaultSlot: PanelSlot
    public let sizing: PanelItemSizing
    /// Öğe şu an anlamlı mı (örn. aktif repo yokken git panelleri çizilmez).
    public let isAvailable: @MainActor (ShellContext) -> Bool
    public let makeView: @MainActor () -> AnyView

    public init(
        id: PanelItemID,
        title: String,
        icon: String,
        defaultSlot: PanelSlot,
        sizing: PanelItemSizing = .fill,
        isAvailable: @escaping @MainActor (ShellContext) -> Bool = { _ in true },
        makeView: @escaping @MainActor () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.defaultSlot = defaultSlot
        self.sizing = sizing
        self.isAvailable = isAvailable
        self.makeView = makeView
    }
}

/// Kayıtlı panel öğelerinin kümesi (Faz 6.2/6.6).
///
/// Kayıt yeri composition root'tur (`ShellComposition`); burada yalnız TİP ve
/// **saf çözümleme** yaşar: `resolved(slot:layout:context:)` view render etmeden
/// test edilir.
public struct PanelItemRegistry {
    private var descriptors: [PanelItemID: PanelItemDescriptor] = [:]
    /// Kayıt sırası — yerleşimde adı geçmeyen yeni öğeler bu sırayla eklenir.
    private var registrationOrder: [PanelItemID] = []

    public init() {}

    public mutating func register(_ descriptor: PanelItemDescriptor) {
        if descriptors[descriptor.id] == nil {
            registrationOrder.append(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    public var all: [PanelItemDescriptor] {
        registrationOrder.compactMap { descriptors[$0] }
    }

    public func descriptor(for id: PanelItemID) -> PanelItemDescriptor? {
        descriptors[id]
    }

    /// Bir yuvanın çizilecek öğeleri — **saf fonksiyon**.
    ///
    /// Kurallar:
    /// 1. Sıra `layout`'tan gelir (kullanıcının taşıdığı düzen otoritedir),
    /// 2. Yerleşimde adı geçen ama KAYITLI OLMAYAN id sessizce atlanır (eski
    ///    ui-state'te kalmış bir feature kabuğu bozmaz),
    /// 3. `isAvailable == false` olan öğe çizilmez,
    /// 4. Hiç yerleşim bilgisi olmayan kayıtlı öğe `defaultSlot`'una düşer ve
    ///    listenin sonuna eklenir (yeni feature ui-state migration'ı beklemez).
    @MainActor
    public func resolved(
        slot: PanelSlot,
        layout: PanelLayout,
        context: ShellContext
    ) -> [PanelItemDescriptor] {
        var seen = Set<PanelItemID>()
        var result: [PanelItemDescriptor] = []

        for id in layout.items(in: slot) {
            guard seen.insert(id).inserted, let descriptor = descriptors[id] else { continue }
            result.append(descriptor)
        }
        for id in registrationOrder where !seen.contains(id) {
            guard let descriptor = descriptors[id],
                  layout.slot(of: id) == nil,
                  descriptor.defaultSlot == slot else { continue }
            seen.insert(id)
            result.append(descriptor)
        }
        return result.filter { $0.isAvailable(context) }
    }
}
