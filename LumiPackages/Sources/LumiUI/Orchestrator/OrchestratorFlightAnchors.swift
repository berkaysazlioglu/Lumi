import LumiKit
import SwiftUI

/// Işık süzmelerinin (karar 126) iniş/kalkış noktası olabilen görünümler.
public enum FlightAnchorKey: Hashable, Sendable {
    case orchestratorPopup
    case orchestratorPanel
    case orchestratorButton
    /// Ekrandaki terminal kartının header'ı (grid ya da maximize).
    case terminalHeader(TerminalID)
    /// Projects panelindeki ajan satırı.
    case agentRow(TerminalID)
    /// Projects panelindeki checkout satırı ya da `Other` dizini.
    case checkoutRow(String)
    case projectRow(String)
    /// Projects listesinin görünür alanı — kaymış satırın noktası buraya sıkıştırılır.
    case projectsViewport
}

/// Anahtar → pencere koordinatlarında (`.global`) çerçeve.
///
/// Bilerek `@Observable` DEĞİLDİR: çerçeveler her layout'ta yazılır ve bunu
/// izleyen bir view yoktur; overlay yalnız uçuş sürerken her karede okur.
/// Aynı anahtarı kısa süre iki view taşıyabilir (grid kartı → maximize);
/// kayıt sahibinin belirteciyle silinir ki gidenin `onDisappear`'ı geleni
/// düşürmesin.
@MainActor
public final class FlightAnchorRegistry {
    private var entries: [FlightAnchorKey: (owner: UUID, rect: CGRect)] = [:]

    public init() {}

    public func set(_ key: FlightAnchorKey, rect: CGRect, owner: UUID) {
        entries[key] = (owner, rect)
    }

    public func remove(_ key: FlightAnchorKey, owner: UUID) {
        if entries[key]?.owner == owner { entries[key] = nil }
    }

    public func rect(_ key: FlightAnchorKey) -> CGRect? {
        guard let rect = entries[key]?.rect, !rect.isEmpty else { return nil }
        return rect
    }
}

extension View {
    /// Görünümün çerçevesini ışık süzmelerine iniş/kalkış noktası olarak bildirir.
    func flightAnchor(_ key: FlightAnchorKey) -> some View {
        modifier(FlightAnchorModifier(key: key))
    }
}

private struct FlightAnchorModifier: ViewModifier {
    let key: FlightAnchorKey
    /// Kabuk dışında (preview, test) çizilen view'da kayıt yapılmaz.
    @Environment(\.shell) private var shell
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                shell?.flightAnchors.set(key, rect: rect, owner: owner)
            }
            .onDisappear { shell?.flightAnchors.remove(key, owner: owner) }
    }
}
