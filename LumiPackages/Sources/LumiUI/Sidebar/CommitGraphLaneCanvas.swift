import LumiKit
import SwiftUI

/// TEK commit satırının lane çizimi (Orca `GitHistoryGraphSvg` portu).
///
/// Koordinat sistemi: lane `i` x = `laneWidth * (i + 1)`; satırın üst kenarı
/// y = 0, alt kenarı y = `height`, düğüm y = `height / 2`. Komşu satırlar aynı
/// x ızgarasını paylaştığı için çizgiler satır sınırında kesintisiz birleşir.
struct CommitGraphLaneCanvas: View {
    let row: CommitGraphRow
    /// Listenin TAMAMI için sabit lane sayısı (metin hizası).
    let laneCount: Int
    let height: CGFloat

    private var laneWidth: CGFloat { Theme.Graph.laneWidth }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, height: size.height)
        }
        .frame(width: Theme.Graph.columnWidth(laneCount: laneCount), height: height)
        .accessibilityHidden(true)
    }

    // MARK: - Çizim

    private func draw(in context: inout GraphicsContext, height: CGFloat) {
        let nodeY = height / 2
        let nodeX = x(row.laneIndex)

        drawPassThroughLanes(in: &context, height: height, nodeX: nodeX, nodeY: nodeY)
        drawMergeParent(in: &context, height: height, nodeX: nodeX, nodeY: nodeY)
        drawNodeStems(in: &context, height: height, nodeX: nodeX, nodeY: nodeY)
        drawNode(in: &context, center: CGPoint(x: nodeX, y: nodeY))
    }

    /// Giriş lane'lerini çıkışlarına bağlar: aynı indekste kalanlar düz, indeks
    /// değiştirenler S-eğrisiyle; bu commit'te kapanan fazladan lane'ler
    /// düğüme doğru kıvrılır.
    private func drawPassThroughLanes(
        in context: inout GraphicsContext,
        height: CGFloat,
        nodeX: CGFloat,
        nodeY: CGFloat
    ) {
        var outputIndex = 0
        for (index, lane) in row.inputLanes.enumerated() {
            if lane.targetHash == row.commit.hash {
                if index == row.laneIndex {
                    outputIndex += 1
                } else {
                    // Orca: dikey iniş + laneWidth yarıçaplı çeyrek yay + düğüme
                    // yatay kol. Eskiden yay satırın yarı yüksekliğine yayılıyordu
                    // ve 40pt satırda basık bir elips gibi görünüyordu.
                    let radius = cornerRadius(nodeY)
                    var path = Path()
                    path.move(to: CGPoint(x: x(index), y: 0))
                    path.addLine(to: CGPoint(x: x(index), y: nodeY - radius))
                    path.addQuadCurve(
                        to: CGPoint(x: x(index) - radius, y: nodeY),
                        control: CGPoint(x: x(index), y: nodeY)
                    )
                    path.addLine(to: CGPoint(x: nodeX, y: nodeY))
                    stroke(path, color: lane.colorIndex, in: &context)
                }
                continue
            }
            guard outputIndex < row.outputLanes.count,
                  lane.targetHash == row.outputLanes[outputIndex].targetHash else { continue }
            if index == outputIndex {
                var path = Path()
                path.move(to: CGPoint(x: x(index), y: 0))
                path.addLine(to: CGPoint(x: x(index), y: height))
                stroke(path, color: lane.colorIndex, in: &context)
            } else {
                stroke(
                    shiftPath(from: index, to: outputIndex, height: height),
                    color: lane.colorIndex, in: &context
                )
            }
            outputIndex += 1
        }
    }

    /// Merge'ün ikinci parent'ı: düğümden sola uzanan yatay kol + alt kenara
    /// inen çeyrek yay.
    private func drawMergeParent(
        in context: inout GraphicsContext,
        height: CGFloat,
        nodeX: CGFloat,
        nodeY: CGFloat
    ) {
        guard let parentLane = row.mergeParentLaneIndex,
              parentLane < row.outputLanes.count else { return }
        let radius = cornerRadius(height - nodeY)
        var path = Path()
        path.move(to: CGPoint(x: nodeX, y: nodeY))
        path.addLine(to: CGPoint(x: x(parentLane) - radius, y: nodeY))
        path.addQuadCurve(
            to: CGPoint(x: x(parentLane), y: nodeY + radius),
            control: CGPoint(x: x(parentLane), y: nodeY)
        )
        path.addLine(to: CGPoint(x: x(parentLane), y: height))
        stroke(path, color: row.outputLanes[parentLane].colorIndex, in: &context)
    }

    /// Düğümün kendi dikey parçaları: üstten düğüme (çocuğu varsa) ve düğümden
    /// alta (parent'ı varsa).
    private func drawNodeStems(
        in context: inout GraphicsContext,
        height: CGFloat,
        nodeX: CGFloat,
        nodeY: CGFloat
    ) {
        if let incoming = row.inputLanes.first(where: { $0.targetHash == row.commit.hash }) {
            var path = Path()
            path.move(to: CGPoint(x: nodeX, y: 0))
            path.addLine(to: CGPoint(x: nodeX, y: nodeY))
            stroke(path, color: incoming.colorIndex, in: &context)
        }
        guard !row.commit.parentHashes.isEmpty else { return }
        var path = Path()
        path.move(to: CGPoint(x: nodeX, y: nodeY))
        path.addLine(to: CGPoint(x: nodeX, y: height))
        stroke(path, color: row.nodeColorIndex, in: &context)
    }

    /// Düğüm: HEAD çift halka, merge çift daire, gerisi dolu daire.
    private func drawNode(in context: inout GraphicsContext, center: CGPoint) {
        let color = Theme.Graph.laneColor(row.nodeColorIndex)
        let radius = Theme.Graph.nodeRadius
        if row.isHead {
            context.fill(circle(center, radius + Theme.Graph.ringInset), with: .color(color))
            context.fill(circle(center, Theme.Stroke.graph), with: .color(Theme.bgSurface))
            return
        }
        if row.isMerge {
            context.fill(circle(center, radius + Theme.Stroke.graph), with: .color(color))
            context.fill(circle(center, radius - Theme.Stroke.graph), with: .color(Theme.bgSurface))
            return
        }
        context.fill(circle(center, radius), with: .color(color))
    }

    // MARK: - Geometri yardımcıları

    private func x(_ laneIndex: Int) -> CGFloat { laneWidth * CGFloat(laneIndex + 1) }

    /// Dal açılış/kapanış köşesinin yarıçapı: bir lane adımı (Orca `A 11 11`),
    /// ama düğümle satır kenarı arasındaki mesafeyi aşamaz.
    private func cornerRadius(_ available: CGFloat) -> CGFloat {
        min(laneWidth, max(available, 0))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
    }

    /// Lane indeksi değişen çizgi: dikey → yatay → dikey, köşelerde quad eğri.
    private func shiftPath(from input: Int, to output: Int, height: CGFloat) -> Path {
        let startX = x(input)
        let endX = x(output)
        let midY = height / 2
        let radius = min(Theme.Graph.curveRadius, abs(startX - endX) / 2, midY)
        let direction: CGFloat = startX > endX ? -1 : 1

        var path = Path()
        path.move(to: CGPoint(x: startX, y: 0))
        path.addLine(to: CGPoint(x: startX, y: midY - radius))
        path.addQuadCurve(
            to: CGPoint(x: startX + direction * radius, y: midY),
            control: CGPoint(x: startX, y: midY)
        )
        path.addLine(to: CGPoint(x: endX - direction * radius, y: midY))
        path.addQuadCurve(
            to: CGPoint(x: endX, y: midY + radius),
            control: CGPoint(x: endX, y: midY)
        )
        path.addLine(to: CGPoint(x: endX, y: height))
        return path
    }

    private func stroke(_ path: Path, color index: Int, in context: inout GraphicsContext) {
        context.stroke(
            path,
            with: .color(Theme.Graph.laneColor(index)),
            style: StrokeStyle(lineWidth: Theme.Stroke.graph, lineCap: .round, lineJoin: .round)
        )
    }
}
