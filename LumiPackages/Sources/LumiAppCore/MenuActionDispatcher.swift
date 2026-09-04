import AppKit
import LumiKit

/// Menü item'larının tek hedefi (design/03 §2, refactor 3.6).
///
/// 12 ayrı `@objc` aksiyon yerine tek selector + `CommandID → closure`
/// sözlüğü. Menü kurucusu item'a komut kimliğini `representedObject` ile
/// takar; indeksli komutlarda (⌘1…9) `tag` indeksi taşır.
///
/// Yeni komut = `AppCommands.all`'a bir satır + burada bir `register`.
@MainActor
final class MenuActionDispatcher: NSObject {
    /// Handler'ın parametresi yalnız indeksli komutlarda doludur.
    typealias Handler = (Int?) -> Void

    private var handlers: [CommandID: Handler] = [:]

    /// Kayıtlı komutlar — menü kurucusu doğrulaması ve testler için.
    var registeredIDs: Set<CommandID> { Set(handlers.keys) }

    func register(_ id: CommandID, _ handler: @escaping Handler) {
        handlers[id] = handler
    }

    /// Argümansız komutlar için kısayol.
    func register(_ id: CommandID, _ handler: @escaping () -> Void) {
        handlers[id] = { _ in handler() }
    }

    @objc
    func performCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? String else { return }
        perform(CommandID(raw), index: item.tag > 0 ? item.tag : nil)
    }

    /// Testler ve programatik tetikleme için doğrudan yol.
    func perform(_ id: CommandID, index: Int? = nil) {
        handlers[id]?(index)
    }
}
