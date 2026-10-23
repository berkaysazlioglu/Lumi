import Foundation
import LumiKit

/// Orchestrator'ın iki sunumu arasındaki geçiş kuralları (karar 124): orta
/// alan ile sağ panelin arasındaki docked panel (`.orchestrator` öğesinin
/// yuvası, varsayılan `.innerRight`) ve %80'lik popup.
///
/// ⌘J, top bar butonu ve iki yüzeyin başlık butonları aynı kapıdan geçer.
/// Durum tutmaz: panel görünürlüğü `LayoutStore`'da (kalıcı), popup
/// `DialogRouter`'dadır (oturumluk).
@MainActor
public struct OrchestratorPresentation {
    private let layout: LayoutStore
    private let dialogs: DialogRouter
    private let orchestrator: OrchestratorStore

    public init(layout: LayoutStore, dialogs: DialogRouter, orchestrator: OrchestratorStore) {
        self.layout = layout
        self.dialogs = dialogs
        self.orchestrator = orchestrator
    }

    /// Panel öğesinin yuvası (yerleşimde yoksa varsayılan yuva).
    public var panelSlot: PanelSlot {
        layout.panelLayout.slot(of: .orchestrator) ?? .innerRight
    }

    public var isPanelVisible: Bool { layout.isSlotVisible(panelSlot) }
    public var isPopupOpen: Bool { dialogs.isOrchestratorOpen }
    /// Top bar butonunun "açık" vurgusu.
    public var isPresented: Bool { isPanelVisible || isPopupOpen }

    /// ⌘J / top bar: popup açıksa kapatır (varsa panele döner); focus mode'da
    /// paneller çizilmediği için popup açar; aksi halde paneli aç/kapat.
    public func toggle() {
        if isPopupOpen {
            closePopup()
        } else if layout.isFocusMode {
            openPopup()
        } else if isPanelVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        layout.setSlotVisible(panelSlot, true)
        orchestrator.focusTerminal()
    }

    public func closePanel() {
        layout.setSlotVisible(panelSlot, false)
    }

    /// Panel başlığındaki "popup olarak aç" butonu.
    public func openPopup() {
        dialogs.isOrchestratorOpen = true
        orchestrator.focusTerminal()
    }

    public func closePopup() {
        dialogs.isOrchestratorOpen = false
    }

    /// Popup başlığındaki "panele yerleştir" butonu.
    public func dock() {
        closePopup()
        showPanel()
    }
}
