import AppKit
import Foundation
import LumiKit

/// `shell:open-external` paritesi: yalnız http/https whitelist'i; ihlal
/// GÖRÜNÜR hatadır (karar 5 — Electron'da sessizce yutuluyordu).
public struct ExternalURLOpener: Sendable {
    public static let allowedSchemes: Set<String> = ["http", "https"]

    private let opener: @Sendable (URL) -> Void

    public init(opener: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.opener = opener
    }

    public func open(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else {
            throw LumiError.externalURLBlocked(url)
        }
        opener(url)
    }
}
