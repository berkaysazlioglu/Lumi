import LumiKit
import SwiftUI

/// Overlay kimliği — panel/route id'leriyle aynı açık-küme kalıbı.
public struct OverlayID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public extension OverlayID {
    /// Karar 44: gizli yuvaların kenar hover'ıyla içeriğin üstünde açılması.
    static let panelReveal = OverlayID("panelReveal")
    static let focusModeBar = OverlayID("focusModeBar")
    static let fileViewer = OverlayID("fileViewer")
    static let settings = OverlayID("settings")
    static let toasts = OverlayID("toasts")
    static let closeTabDialog = OverlayID("closeTabDialog")
    static let quitDialog = OverlayID("quitDialog")
    /// Karar 46/49: Projects paneline ait modal ve onay dialogu.
    static let createWorkspace = OverlayID("createWorkspace")
    static let deleteWorkspaceDialog = OverlayID("deleteWorkspaceDialog")
}

/// Kabuğun üstüne binen bir katmanın tanımı (K33, Faz 6.5).
///
/// `confirmationDialog`'lar da birer descriptor'dır: `makeView` sıfır boyutlu
/// bir taşıyıcıya modifier'ı takar. Böylece "şu an bir overlay açık mı?"
/// sorusunun elle `||` listesi kalkar — cevap `DialogRouter.active` ile
/// descriptor'ların `isPresented` predikatlarından türer.
public struct OverlayDescriptor: Identifiable {
    public let id: OverlayID
    public let alignment: Alignment
    public let isPresented: @MainActor (ShellContext) -> Bool
    public let makeView: @MainActor () -> AnyView

    public init(
        id: OverlayID,
        alignment: Alignment = .center,
        isPresented: @escaping @MainActor (ShellContext) -> Bool,
        makeView: @escaping @MainActor () -> AnyView
    ) {
        self.id = id
        self.alignment = alignment
        self.isPresented = isPresented
        self.makeView = makeView
    }
}

/// Kayıtlı overlay'ler (Faz 6.5/6.6). `presented(in:)` **saf** çözümlemedir.
public struct OverlayRegistry {
    private var descriptors: [OverlayDescriptor] = []

    public init() {}

    public mutating func register(_ descriptor: OverlayDescriptor) {
        if let index = descriptors.firstIndex(where: { $0.id == descriptor.id }) {
            descriptors[index] = descriptor
        } else {
            descriptors.append(descriptor)
        }
    }

    public var all: [OverlayDescriptor] { descriptors }

    @MainActor
    public func presented(in context: ShellContext) -> [OverlayDescriptor] {
        descriptors.filter { $0.isPresented(context) }
    }
}

/// Açık overlay'leri kayıt sırasıyla üst üste çizer (Faz 6.5).
struct OverlayHost: View {
    let registry: OverlayRegistry

    @Shell private var shell

    var body: some View {
        let presented = registry.presented(in: shell)
        if !presented.isEmpty {
            ZStack {
                ForEach(presented) { descriptor in
                    descriptor.makeView()
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: descriptor.alignment
                        )
                }
            }
        }
    }
}
