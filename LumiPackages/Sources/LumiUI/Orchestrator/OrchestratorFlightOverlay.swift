import LumiKit
import LumiState
import SwiftUI

/// Orchestrator ile terminaller/projeler arasında uçan ışık süzmeleri
/// (karar 126). Kabuğun overlay'idir: popup'ın üstünde, Settings ve
/// dialog'ların altında çizilir; tıklamaları hiç almaz ve uçtuğu ya da
/// indiği yerde hiçbir şeye dokunmaz — yalnız A noktasından B noktasına
/// eğimli bir yolla giden bir ışıktır.
///
/// Uçların konumu her karede `FlightAnchorRegistry`'den çözülür: orchestrator
/// tarafı popup → docked panel → top bar butonu; terminal tarafı ekrandaki
/// kartın header'ı → Projects'teki ajan satırı → checkout → proje satırı.
/// Hiçbiri görünmüyorsa o uçuş çizilmez.
public struct OrchestratorFlightOverlay: View {
    @Shell private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            if !reduceMotion {
                TimelineView(.animation) { timeline in
                    let segments = resolve(at: timeline.date, origin: proxy.frame(in: .global).origin)
                    Canvas { context, _ in
                        for segment in segments {
                            Self.draw(segment, in: &context)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Çözüm

    struct Segment {
        let path: OrchestratorFlightPath
        let progress: Double
        let color: Color
    }

    private func resolve(at date: Date, origin: CGPoint) -> [Segment] {
        guard let orchestrator = orchestratorPoint() else { return [] }
        return shell.orchestrator.flights.active.compactMap { flight in
            let progress = flight.progress(at: date)
            guard progress > 0, progress < 1, let target = point(for: flight.endpoint) else { return nil }
            let (from, to) = flight.direction == .outbound ? (orchestrator, target) : (target, orchestrator)
            let path = OrchestratorFlightPath(
                from: CGPoint(x: from.x - origin.x, y: from.y - origin.y),
                to: CGPoint(x: to.x - origin.x, y: to.y - origin.y),
                variation: CGFloat(flight.id.uuid.0) / CGFloat(UInt8.max),
                maxBow: Self.maxBow
            )
            // Giden ışık orchestrator'ın rengi, dönen ışık soğuk mavi.
            let color = flight.direction == .outbound ? Theme.accentPrimary : Theme.accentCyan
            return Segment(path: path, progress: progress, color: color)
        }
    }

    private var anchors: FlightAnchorRegistry { shell.flightAnchors }

    private func orchestratorPoint() -> CGPoint? {
        let keys: [FlightAnchorKey] = [.orchestratorPopup, .orchestratorPanel, .orchestratorButton]
        return keys.lazy.compactMap { anchors.rect($0) }.first.map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    private func point(for endpoint: OrchestratorFlights.Endpoint) -> CGPoint? {
        switch endpoint {
        case .terminal(let id):
            if let header = anchors.rect(.terminalHeader(id)) {
                return CGPoint(x: header.midX, y: header.midY)
            }
            if let row = anchors.rect(.agentRow(id)) { return rowPoint(row) }
            guard let meta = shell.terminals.meta(for: id) else { return nil }
            return point(for: .checkout(meta.repoPath))
        case .checkout(let path):
            if let row = anchors.rect(.checkoutRow(path)) { return rowPoint(row) }
            guard let project = shell.navigation.projectPath(containing: path) else { return nil }
            return point(for: .project(project))
        case .project(let path):
            return anchors.rect(.projectRow(path)).map(rowPoint)
        }
    }

    /// Satırın adının durduğu yer; liste kaymışsa görünür alanın kenarı.
    private func rowPoint(_ row: CGRect) -> CGPoint {
        var y = row.midY
        if let viewport = anchors.rect(.projectsViewport) {
            y = min(max(y, viewport.minY), viewport.maxY)
        }
        return CGPoint(x: row.minX + row.width * Self.rowAnchorRatio, y: y)
    }

    // MARK: - Çizim

    /// Kuyruğun yol üzerindeki uzunluğu (0…1 ilerleme cinsinden).
    static let trailRatio = 0.3
    static let trailSamples = 18
    static let rowAnchorRatio: CGFloat = 0.3
    static var maxBow: CGFloat { Theme.scaled(180) }
    static var glowBlur: CGFloat { Theme.scaled(7) }
    static var glowSize: CGFloat { Theme.scaled(14) }
    static var trailSize: CGFloat { Theme.scaled(4) }
    static var coreSize: CGFloat { Theme.scaled(5) }

    private static func draw(_ segment: Segment, in context: inout GraphicsContext) {
        let head = OrchestratorFlightPath.eased(segment.progress)
        let tail = max(0, head - trailRatio)
        let fade = OrchestratorFlightPath.fade(segment.progress)
        let samples = (0...trailSamples).map { index -> (point: CGPoint, weight: Double) in
            let fraction = Double(index) / Double(trailSamples)
            return (segment.path.point(at: CGFloat(tail + (head - tail) * fraction)), fraction * fraction)
        }

        // Hale: bulanık, eklemeli harmanlanan geniş katman.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: glowBlur))
            layer.blendMode = .plusLighter
            for sample in samples {
                let size = glowSize * CGFloat(0.35 + 0.65 * sample.weight)
                layer.fill(circle(at: sample.point, size: size), with: .color(segment.color.opacity(0.55 * sample.weight * fade)))
            }
        }
        // Kuyruk: incelen parlak iz.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for sample in samples {
                let size = trailSize * CGFloat(0.2 + 0.8 * sample.weight)
                layer.fill(circle(at: sample.point, size: size), with: .color(segment.color.opacity(0.8 * sample.weight * fade)))
            }
            // Baş: beyaza yakın çekirdek.
            if let headPoint = samples.last?.point {
                layer.fill(circle(at: headPoint, size: coreSize), with: .color(.white.opacity(0.95 * fade)))
            }
        }
    }

    private static func circle(at center: CGPoint, size: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
    }
}
