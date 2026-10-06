import AppKit
import LumiKit
import SwiftTerm

/// Hover'daki link'in durumu (karar 116).
struct TerminalLinkHoverState {
    /// Son bakılan hücre — algılama her piksel hareketinde değil, yalnız hücre
    /// değişince koşar.
    var cell: TerminalLinkHitTest.Cell?
    /// Diskte doğrulanmış (ya da diske sorulmayan) link.
    var link: TerminalLinkHit?
    var isCommandHeld = false
    var isShowingCursor = false
}

/// Aday listesinin diskin bugünkü bilgisiyle değerlendirilmesi.
private enum TerminalLinkLookup {
    case found(TerminalLinkHit)
    /// Daha uzun bir adayın cevabı bekleniyor.
    case pending(firstUnknown: TerminalLinkHit, paths: [String])
    case none
}

// MARK: - Link hover: altı çizgi + el imleci (karar 101 + 116)

extension DropAwareTerminalView {
    /// Monitörün (`TerminalEventMonitor`) her hover'da çağırdığı tek kapı.
    /// anyEvent (1003) modunda event yutulur: SwiftTerm hover'ı buglu "sol buton
    /// release" raporu olarak yollardı. Altı çizgi Lumi'nin olduğu için SwiftTerm'e
    /// yeniden oynatılması gerekmez. `true` → event yutuldu (AppKit dağıtmaz).
    func handleHover(locationInWindow: NSPoint, event: NSEvent?) -> Bool {
        linkHover.isCommandHeld = (event?.modifierFlags ?? NSEvent.modifierFlags).contains(.command)
        let cell = cell(atWindowPoint: locationInWindow)
        if cell != linkHover.cell {
            linkHover.cell = cell
            refreshLinkHover()
        }
        applyLinkPresentation()
        return shouldConsumeHover()
    }

    /// ⌘ basılıp bırakıldı: link actions kapalıyken çizgi ve el imleci ⌘ ister.
    func noteModifierFlags(_ flags: NSEvent.ModifierFlags) {
        linkHover.isCommandHeld = flags.contains(.command)
        applyLinkPresentation()
    }

    /// Hover bu terminalden ayrıldı (başka view / overlay): çizgi ve el bırakılır.
    func clearLinkHover() {
        linkHover.cell = nil
        linkHover.link = nil
        applyLinkPresentation()
    }

    /// İçerik hover'ın altından kaydı (scroll): bir sonraki hover yeniden arar.
    func invalidateLinkHover() {
        guard linkHover.cell != nil || linkHover.link != nil else { return }
        clearLinkHover()
    }

    /// PTY çıktısı işlendi: vurgulanan link hâlâ aynı metin mi? Yalnız bir link
    /// vurgulanırken koşar — akış sırasında hover'sız terminal ödeme yapmaz.
    func noteLinkContentChanged() {
        guard linkHover.link != nil else { return }
        refreshLinkHover()
        applyLinkPresentation()
    }

    /// Test gözlemi: imleç şu an link eli mi.
    var isPointingAtLink: Bool { linkHover.isShowingCursor }
    /// Test gözlemi: altı çizili link metni.
    var underlinedLinkText: String? { linkUnderline.spans.isEmpty ? nil : linkHover.link?.text }

    // MARK: - Tık

    /// Tık hücresindeki link metni. Hover zaten doğruladıysa o; değilse diskin
    /// bildiği kadarıyla en uzun aday. Cevabı bilinmeyen yol adayı iyimser
    /// seçilir (store ayrıca diske sorar) — çıplak dosya adı hariç: o, diskte
    /// görülmeden link sayılmaz.
    func linkText(atCell cell: TerminalLinkHitTest.Cell) -> String? {
        if let link = linkHover.link, link.contains(row: cell.row, col: cell.col) { return link.text }
        switch lookup(hits(at: cell)) {
        case .found(let hit): return hit.text
        case .pending(let hit, _): return hit.isBareFilename ? nil : hit.text
        case .none: return nil
        }
    }

    // MARK: - Değerlendirme

    private func refreshLinkHover() {
        guard let cell = linkHover.cell else {
            linkHover.link = nil
            return
        }
        switch lookup(hits(at: cell)) {
        case .found(let hit):
            linkHover.link = hit
        case .none:
            linkHover.link = nil
        case .pending(_, let paths):
            linkHover.link = nil
            // Cevap gelince GÜNCEL hücre yeniden değerlendirilir; imleç bu arada
            // başka yere geçtiyse sonuç zaten o hücreye göredir.
            linkPathCache.request(paths) { [weak self] in
                guard let self else { return }
                self.refreshLinkHover()
                self.applyLinkPresentation()
            }
        }
    }

    private func hits(at cell: TerminalLinkHitTest.Cell) -> [TerminalLinkHit] {
        let terminal = getTerminal()
        var hits: [TerminalLinkHit] = []
        if let explicit = TerminalLinkLocator.explicitHit(in: terminal, row: cell.row, col: cell.col) {
            // OSC 8: hedef payload'dır; yerel bir yola çıkıyorsa o da diske sorulur.
            let isPath: Bool = {
                guard case .path = candidate(for: explicit.text) else { return false }
                return true
            }()
            hits.append(TerminalLinkHit(
                text: explicit.text, spans: [explicit.span], requiresExistence: isPath, isBareFilename: false
            ))
        }
        return hits + TerminalLinkLocator.hits(rowCount: terminal.rows, row: cell.row, col: cell.col) {
            TerminalLinkLocator.rowText(in: terminal, row: $0)
        }
    }

    /// Adaylar sırayla denenir: diske sorulmayan (URL) ya da diskte VAR olan ilk
    /// aday link'tir; ondan önce cevabı bilinmeyen bir aday varsa beklenir.
    /// Çözümleyicinin kabul etmediği (`ssh:`, `mailto:`) aday atlanır.
    private func lookup(_ hits: [TerminalLinkHit]) -> TerminalLinkLookup {
        var unknown: [(hit: TerminalLinkHit, path: String)] = []
        for hit in hits {
            guard let candidate = candidate(for: hit.text) else { continue }
            let path: String? = {
                guard hit.requiresExistence, case let .path(path) = candidate else { return nil }
                return path
            }()
            guard let path else { return settle(.found(hit), unknown: unknown) }
            switch linkPathCache.exists(path) {
            case true?: return settle(.found(hit), unknown: unknown)
            case false?: continue
            case nil: unknown.append((hit, path))
            }
        }
        return settle(.none, unknown: unknown)
    }

    private func settle(_ result: TerminalLinkLookup, unknown: [(hit: TerminalLinkHit, path: String)]) -> TerminalLinkLookup {
        guard let first = unknown.first else { return result }
        return .pending(firstUnknown: first.hit, paths: unknown.map(\.path))
    }

    private func candidate(for text: String) -> TerminalLinkCandidate? {
        TerminalLinkResolver.candidate(link: text, basePath: linkBaseDirectory, homeDirectory: linkHomeDirectory)
    }

    // MARK: - Sunum

    /// Çizgi ve el imleci tıkla aynı kuralı izler: tık bir şey yapacaksa görünür.
    private func applyLinkPresentation() {
        let isActive = linkHover.link != nil && (isLinkActionsEnabled || linkHover.isCommandHeld)
        linkUnderline.cellSize = cellSize
        linkUnderline.color = nativeForegroundColor
        linkUnderline.spans = isActive ? (linkHover.link?.spans ?? []) : []
        setLinkCursor(isActive)
    }

    private func setLinkCursor(_ pointing: Bool) {
        guard pointing != linkHover.isShowingCursor else { return }
        linkHover.isShowingCursor = pointing
        if pointing {
            NSCursor.pointingHand.set()
        } else if let window {
            // SwiftTerm'in iBeam cursor rect'i yeniden değerlendirilsin; imleç
            // artık terminalin dışındaysa oradaki view'ın imleci geçerli olur.
            window.invalidateCursorRects(for: self)
            if bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                NSCursor.iBeam.set()
            }
        }
    }
}
