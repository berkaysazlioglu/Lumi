import Foundation
import LumiKit

/// Plastic Changes listesinin gruplaması (karar 46 eki) — Plastic GUI'nin
/// "Changed items / Moved items / Added and private / Deleted items" düzeni.
/// Saf hesap: durum → grup, ad/yol araması, seçim sayacı.
public struct PlasticChangeGroup: Equatable, Sendable, Identifiable {
    public enum Kind: CaseIterable, Sendable, Hashable {
        case changed
        case moved
        case addedAndPrivate
        case deleted

        public var title: String {
            switch self {
            case .changed: return "Changed items"
            case .moved: return "Moved items"
            case .addedAndPrivate: return "Added and private"
            case .deleted: return "Deleted items"
            }
        }

        /// Renk/rozet için temsilî durum (renkler `Theme.fileChangeColor`dan).
        public var representativeStatus: FileChangeStatus {
            switch self {
            case .changed: return .modified
            case .moved: return .renamed
            case .addedAndPrivate: return .added
            case .deleted: return .deleted
            }
        }

        public var badgeLetter: String {
            switch self {
            case .changed: return "C"
            case .moved: return "M"
            case .addedAndPrivate: return "A"
            case .deleted: return "D"
            }
        }

        public static func kind(for status: FileChangeStatus) -> Kind {
            switch status {
            case .modified: return .changed
            case .renamed: return .moved
            case .added, .untracked: return .addedAndPrivate
            case .deleted: return .deleted
            }
        }
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let items: [PlasticFileChange]
    public let selectedCount: Int

    public init(kind: Kind, items: [PlasticFileChange], selectedCount: Int) {
        self.kind = kind
        self.items = items
        self.selectedCount = selectedCount
    }

    public var paths: [String] { items.map(\.path) }
    public var isFullySelected: Bool { !items.isEmpty && selectedCount == items.count }
    public var isPartiallySelected: Bool { selectedCount > 0 && selectedCount < items.count }

    /// `query` boşsa tüm öğeler; doluysa ad VEYA yolda büyük/küçük harf
    /// duyarsız alt dize eşleşmesi. Boş gruplar atlanır; sıra `Kind.allCases`.
    public static func group(
        _ changes: [PlasticFileChange],
        selected: Set<String>,
        query: String = ""
    ) -> [PlasticChangeGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let visible = needle.isEmpty
            ? changes
            : changes.filter { $0.path.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return Kind.allCases.compactMap { kind in
            let items = visible.filter { Kind.kind(for: $0.status) == kind }
            guard !items.isEmpty else { return nil }
            return PlasticChangeGroup(
                kind: kind,
                items: items,
                selectedCount: items.filter { selected.contains($0.path) }.count
            )
        }
    }
}
