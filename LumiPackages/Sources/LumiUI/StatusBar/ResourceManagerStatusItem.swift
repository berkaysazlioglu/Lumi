import LumiKit
import LumiState
import SwiftUI

/// Alt bar Resource Manager segmenti (karar 43; Orca `ResourceUsageTrigger`):
/// bellek ikonu + Σ RSS + `·` + terminal ikonu + oturum sayısı. Tıklama üstte
/// `ResourceManagerPopover`ı açar; popover açıkken örnekleme sıklaşır.
public struct ResourceManagerStatusItem: View {
    @Shell private var shell
    @State private var isOpen = false

    private var store: ResourceUsageStore { shell.resourceUsage }

    public init() {}

    public var body: some View {
        Button { isOpen.toggle() } label: {
            StatusBarSegmentLabel {
                Image(systemName: "memorychip")
                    .font(Theme.Typography.ui(.label))
                    .accessibilityHidden(true)
                Text(ResourceUsageFormat.memory(store.terminalMemoryBytes))
                    .monospacedDigit()
                Text("·").foregroundStyle(Theme.textMuted.opacity(Self.separatorOpacity)).accessibilityHidden(true)
                Image(systemName: "terminal")
                    .font(Theme.Typography.ui(.label))
                    .accessibilityHidden(true)
                Text("\(store.sessionCount)")
                    .font(Theme.Typography.ui(.label))
                    .monospacedDigit()
            }
        }
        .buttonStyle(StatusBarSegmentStyle())
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            ResourceManagerPopover()
        }
        .onChange(of: isOpen) { store.isPresented = isOpen }
    }

    private var tooltip: String {
        "Resource Manager — \(ResourceUsageFormat.memory(store.terminalMemoryBytes)) across \(store.sessionCount) terminal\(store.sessionCount == 1 ? "" : "s")"
    }

    private static let separatorOpacity = 0.5
}
