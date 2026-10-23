import SwiftUI
import UIKit
import LumiMobileKit

/// Mac top bar quota indicators (decision 128) as separate buttons in a row
/// between the bar and the Projects title: Claude · Codex · DeepSeek, each
/// with its own popover (Mac `UsageIndicatorView` / `DeepSeekBalanceIndicatorView`).
struct ProjectsUsageStrip: View {
    let report: UsageReport?
    /// Mac offline: the numbers are the last known ones — shown dimmed.
    var isStale = false

    private static let staleOpacity = 0.45

    var body: some View {
        if let report, !report.isEmpty {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let nowMs = context.date.timeIntervalSince1970 * 1000
                HStack(spacing: 8) {
                    ForEach(report.providers) { provider in
                        UsageChipButton(id: provider.id, label: provider.indicatorLimit?.percent.map { "\($0)%" } ?? "—",
                                        tint: UsageToneColor.color(UsageTone(limit: provider.indicatorLimit, nowMs: nowMs))) {
                            UsagePopover(providers: [provider], deepSeek: nil)
                        }
                    }
                    if let deepSeek = report.deepSeek {
                        UsageChipButton(id: "deepseek", label: deepSeek.balanceLabel, tint: nil) {
                            UsagePopover(providers: [], deepSeek: deepSeek)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .opacity(isStale ? Self.staleOpacity : 1)
            }
        }
    }
}

/// One Mac-top-bar-style indicator: icon + value on an elevated, bordered capsule.
private struct UsageChipButton<Popover: View>: View {
    let id: String
    let label: String
    let tint: Color?
    @ViewBuilder let popover: () -> Popover

    @State private var showing = false

    private static var corner: CGFloat { 8 }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 5) {
                UsageProviderIcon(id: id)
                Text(label)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint ?? LumiPalette.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LumiPalette.elevated, in: RoundedRectangle(cornerRadius: Self.corner))
            .overlay(RoundedRectangle(cornerRadius: Self.corner).stroke(LumiPalette.border, lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(id) usage \(label)")
        .popover(isPresented: $showing) {
            popover()
                .presentationBackground(LumiPalette.background)
                .presentationCompactAdaptation(.popover)
                .lumiThemed()
        }
    }
}

/// Provider identity icon (Mac `ProviderIcon` parity): Claude / Codex / DeepSeek
/// artwork from the asset catalog; plain shells get an SF Symbol.
struct UsageProviderIcon: View {
    let id: String?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let asset {
                Image(asset).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(LumiPalette.textPrimary)
            } else {
                Image(systemName: "terminal").resizable().scaledToFit()
                    .foregroundStyle(LumiPalette.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var asset: String? {
        switch id {
        case "claude": "ProviderClaude"
        case "codex": "ProviderCodex"
        case "deepseek": "ProviderDeepSeek"
        default: nil
        }
    }
}

struct UsagePopover: View {
    let providers: [UsageProviderReport]
    let deepSeek: DeepSeekReport?

    private static let barHeight: CGFloat = 6
    private static let width: CGFloat = 300

    var body: some View {
        let nowMs = Date().timeIntervalSince1970 * 1000
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(providers) { provider in
                    providerSection(provider, nowMs: nowMs)
                }
                if let deepSeek { deepSeekSection(deepSeek) }
            }
            .padding(16)
        }
        .frame(width: Self.width)
        .frame(maxHeight: 420)
    }

    private func providerSection(_ provider: UsageProviderReport, nowMs: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(provider.title, id: provider.id)
            if let error = provider.error, provider.limits.isEmpty {
                Text(error).font(.caption).foregroundStyle(LumiPalette.textSecondary)
            }
            ForEach(provider.limits) { limit in
                limitRow(limit, nowMs: nowMs)
            }
        }
    }

    private func limitRow(_ limit: UsageLimitReport, nowMs: Double) -> some View {
        let tint = UsageToneColor.color(UsageTone(limit: limit, nowMs: nowMs)) ?? LumiPalette.textSecondary
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.caption).foregroundStyle(LumiPalette.textPrimary).lineLimit(1)
                Spacer()
                Text(limit.percent.map { "\($0)%" } ?? "—")
                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LumiPalette.elevated)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(100, limit.percent ?? 0)) / 100)
                    // Pace marker (Mac decision 74): how much of the window has passed.
                    if let elapsed = limit.elapsedFraction(nowMs: nowMs) {
                        Rectangle().fill(LumiPalette.textPrimary)
                            .frame(width: 1.5, height: Self.barHeight + 4)
                            .offset(x: geo.size.width * elapsed)
                    }
                }
            }
            .frame(height: Self.barHeight)
            if let reset = usageResetLabel(limit.resetsAt, nowMs: nowMs) {
                Text("Resets \(reset)").font(.caption2).foregroundStyle(LumiPalette.textSecondary)
            }
        }
    }

    private func deepSeekSection(_ deepSeek: DeepSeekReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("DeepSeek", id: "deepseek")
            HStack {
                Text("Balance").font(.caption).foregroundStyle(LumiPalette.textPrimary)
                Spacer()
                Text(deepSeek.balanceLabel).font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LumiPalette.textPrimary)
            }
            if deepSeek.available == false {
                Text("Requests unavailable").font(.caption2).foregroundStyle(Color(UIColor(hex: UsageToneColor.errorHex)))
            } else if let error = deepSeek.error {
                Text(error).font(.caption2).foregroundStyle(LumiPalette.textSecondary)
            }
        }
    }

    private func header(_ title: String, id: String) -> some View {
        HStack(spacing: 6) {
            UsageProviderIcon(id: id)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(LumiPalette.textPrimary)
        }
    }
}

/// Mac `UsageTint` ramp (decision 85): ice ← green → amber → red.
enum UsageToneColor {
    static let successHex: UInt32 = 0x4ADE80
    static let iceHex: UInt32 = 0x38BDF8
    static let warningHex: UInt32 = 0xFBBF24
    static let errorHex: UInt32 = 0xF87171
    /// Amber sits mid-way on the warm half; red only at the end.
    private static let warningStop = 0.5

    static func color(_ tone: UsageTone) -> Color? {
        switch tone {
        case .unknown:
            return nil
        case let .level(percent):
            if percent >= UsageTone.criticalThreshold { return Color(UIColor(hex: errorHex)) }
            if percent >= UsageTone.warningThreshold { return Color(UIColor(hex: warningHex)) }
            return Color(UIColor(hex: successHex))
        case let .pace(stop):
            if stop < 0 { return blend(successHex, iceHex, -stop) }
            if stop <= warningStop { return blend(successHex, warningHex, stop / warningStop) }
            return blend(warningHex, errorHex, (stop - warningStop) / (1 - warningStop))
        }
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ hex: UInt32, _ shift: UInt32) -> Double { Double((hex >> shift) & 0xFF) / 255 }
        func mix(_ shift: UInt32) -> Double { channel(a, shift) + (channel(b, shift) - channel(a, shift)) * t }
        return Color(red: mix(16), green: mix(8), blue: mix(0))
    }
}
