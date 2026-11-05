import Foundation

/// Show/hide rule for live streaming text (orca native-chat-streaming parity;
/// spec Phase 2 §E). Returns nil when not working or streaming is empty; also nil
/// when streaming does not go beyond the last assistant text (contained/shorter) —
/// overlay drops when the transcript settles.
public func chatStreamingText(working: Bool, streaming: String?, lastAssistantText: String) -> String? {
    guard working, let text = streaming?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    if lastAssistantText.contains(text) || text.count <= lastAssistantText.count { return nil }
    return text
}
