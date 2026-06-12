import Foundation
import LumiKit
import LumiState

/// Config yan etki propagasyonu (design/02 §2, karar 3'ün altyapısı).
/// Alanlar EŞİTLİKLE karşılaştırılır — Electron'un truthiness bug'ı (0/boş
/// string yan etkiyi atlardı, karar 11) yapısal olarak imkânsız.
@MainActor
final class ConfigSideEffectCoordinator {
    private let config: any ConfigServicing
    private let terminal: any TerminalServicing
    private let repo: any RepoServicing
    private let repoStore: RepoStore
    private let notifications: any NotificationServicing
    private var consumeTask: Task<Void, Never>?

    /// Font değişimi protokole sızdırılmaz — composition root somut manager'a bağlar.
    var onTerminalFontSizeChanged: ((Int) -> Void)?
    var onTerminalFontSmoothingChanged: ((Bool) -> Void)?
    /// Font ailesi de aynı NSFont'a font size ile birlikte çözülür — boyutla
    /// AYNI callback'i tetikler (composition root taze AppConfig'den font kurar).
    var onTerminalFontFamilyChanged: (() -> Void)?
    var onTerminalThemeChanged: ((String) -> Void)?
    /// Cursor stil VE blink tek köprüden akar (ikisi birlikte bir CursorStyle olur).
    var onTerminalCursorChanged: ((TerminalCursorShape, Bool) -> Void)?

    init(
        config: any ConfigServicing,
        terminal: any TerminalServicing,
        repo: any RepoServicing,
        repoStore: RepoStore,
        notifications: any NotificationServicing
    ) {
        self.config = config
        self.terminal = terminal
        self.repo = repo
        self.repoStore = repoStore
        self.notifications = notifications
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.config.events()
            for await event in stream {
                guard case .configChanged(let old, let new) = event else { continue }
                if old.maxTerminals != new.maxTerminals {
                    self.terminal.setMaxTerminals(new.maxTerminals)
                }
                if old.projectsRoot != new.projectsRoot
                    || old.additionalPaths != new.additionalPaths {
                    self.repoStore.additionalPaths = new.additionalPaths
                    await self.repo.setRoots(
                        projectsRoot: new.projectsRoot,
                        additionalPaths: new.additionalPaths
                    )
                }
                if old.notifications != new.notifications {
                    self.notifications.updateSettings(new.notifications)
                }
                if old.terminalFontSize != new.terminalFontSize {
                    self.onTerminalFontSizeChanged?(new.terminalFontSize)
                }
                if old.terminalFontSmoothing != new.terminalFontSmoothing {
                    self.onTerminalFontSmoothingChanged?(new.terminalFontSmoothing)
                }
                if old.terminalFontFamily != new.terminalFontFamily {
                    self.onTerminalFontFamilyChanged?()
                }
                if old.terminalTheme != new.terminalTheme {
                    self.onTerminalThemeChanged?(new.terminalTheme)
                }
                if old.terminalCursorStyle != new.terminalCursorStyle
                    || old.terminalCursorBlink != new.terminalCursorBlink {
                    self.onTerminalCursorChanged?(
                        TerminalCursorShape.parse(new.terminalCursorStyle),
                        new.terminalCursorBlink
                    )
                }
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }
}
