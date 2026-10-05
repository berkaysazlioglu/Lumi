import Foundation

/// The user's in-progress answer to a pending prompt card, keyed by question index.
/// Lives in AppModel (not the card's @State) so it survives leaving the chat
/// and card re-creation.
public struct PromptDraft: Sendable, Equatable {
    public var selections: [Int: [Int]] = [:]
    public var texts: [Int: String] = [:]

    public init() {}

    /// multiSelect toggles the option (tap order kept); single-select replaces.
    public func toggling(question: Int, option: Int, multiSelect: Bool) -> PromptDraft {
        var copy = self
        if multiSelect {
            var sel = copy.selections[question] ?? []
            if let at = sel.firstIndex(of: option) { sel.remove(at: at) } else { sel.append(option) }
            copy.selections[question] = sel
        } else {
            copy.selections[question] = [option]
        }
        return copy
    }

    public func isSelected(question: Int, option: Int) -> Bool {
        selections[question]?.contains(option) ?? false
    }

    public func withText(_ text: String, question: Int) -> PromptDraft {
        var copy = self
        copy.texts[question] = text
        return copy
    }
}
