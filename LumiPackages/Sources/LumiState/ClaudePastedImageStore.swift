import Foundation
import LumiKit

/// Terminal kartı header'ındaki görsel listesinin kaynağı (karar 139): Claude
/// terminalinin bu oturumda prompt'a yapıştırılan görselleri.
///
/// Dizin listesi enjekte edilir; testler diske dokunmaz. Liste popover her
/// açıldığında yeniden okunur — dosyaları yazan Claude'dur, izleyici kurulmaz.
@MainActor
public final class ClaudePastedImageStore {
    private let fileNames: @Sendable (String) -> [String]
    private let userID: UInt32

    public init(
        userID: UInt32 = getuid(),
        fileNames: @escaping @Sendable (String) -> [String] = ClaudePastedImageStore.diskFileNames
    ) {
        self.userID = userID
        self.fileNames = fileNames
    }

    /// Dizin henüz yoksa (görsel yapıştırılmadı) boş liste — hata değildir.
    public nonisolated static func diskFileNames(_ directory: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    }

    /// Header düğmesi yalnız görsel dizini bilinen terminalde görünür.
    public func hasImageDirectory(_ meta: TerminalMeta) -> Bool {
        ClaudePastedImages.directory(for: meta, userID: userID) != nil
    }

    /// Dizin listesi MainActor dışında okunur.
    public func images(for meta: TerminalMeta) async -> [ClaudePastedImage] {
        guard let directory = ClaudePastedImages.directory(for: meta, userID: userID) else { return [] }
        let list = fileNames
        let names = await Task.detached(priority: .userInitiated) { list(directory) }.value
        return ClaudePastedImages.images(fileNames: names, in: directory)
    }
}
