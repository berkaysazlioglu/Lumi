import Foundation

struct OSCTitleEvent: Equatable {
    let rawTitle: String
    /// `/^.\s*/` paritesiyle ilk karakter + ardındaki boşluk soyulmuş hali; boşsa nil.
    let displayTitle: String?
    /// ✳ prefix → false (Claude idle); boş title → nil (karar yok); aksi → true.
    let isWorking: Bool?
    let providerHint: AgentHint?
}

enum OSCNotificationKind: Equatable {
    case codexTurnComplete
    case generic
}

enum OSCEvent: Equatable {
    case title(OSCTitleEvent)
    case notification(OSCNotificationKind)
}

/// Lumi'ye özgü OSC 0/2/9 semantiğini decode edilmiş stream üzerinde çıkaran parser (spec/10 §4).
/// Emülatörden bilinçli olarak bağımsızdır: SwiftTerm aynı sequence'leri kendi işler,
/// ama ✳-idle ve codex-turn-complete semantiği Lumi'nindir.
final class OSCStreamParser {
    static let maxBufferLength = 4096

    private enum State {
        case ground
        case escape
        case body
        case bodyEscape
    }

    private var state: State = .ground
    private var buffer = ""

    func feed(_ text: String) -> [OSCEvent] {
        var events: [OSCEvent] = []
        for character in text {
            handle(character, into: &events)
        }
        return events
    }

    private func handle(_ character: Character, into events: inout [OSCEvent]) {
        switch state {
        case .ground:
            if character == "\u{1B}" { state = .escape }
        case .escape:
            if character == "]" {
                state = .body
                buffer = ""
            } else if character != "\u{1B}" {
                state = .ground
            }
        case .body:
            if character == "\u{07}" {
                finish(into: &events)
            } else if character == "\u{1B}" {
                state = .bodyEscape
            } else {
                buffer.append(character)
                if buffer.count > Self.maxBufferLength {
                    buffer = ""
                    state = .ground
                }
            }
        case .bodyEscape:
            if character == "\\" {
                finish(into: &events)
            } else {
                // ESC + ST-olmayan: sequence iptal; görülen ESC yeni escape başlangıcıdır.
                buffer = ""
                state = .escape
                handle(character, into: &events)
            }
        }
    }

    private func finish(into events: inout [OSCEvent]) {
        defer {
            buffer = ""
            state = .ground
        }
        let parts = buffer.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let command = Int(first) else { return }
        let payload = parts.count > 1 ? String(parts[1]) : ""
        switch command {
        case 0, 2:
            events.append(.title(Self.interpretTitle(payload)))
        case 9:
            events.append(.notification(Self.interpretNotification(payload)))
        default:
            break
        }
    }

    // MARK: - Semantik yorumlama (spec/10 §4)

    static func interpretTitle(_ raw: String) -> OSCTitleEvent {
        let isIdleMark = raw.unicodeScalars.first == "\u{2733}"
        var hint: AgentHint?
        if isIdleMark {
            hint = .claude
        } else {
            let lower = raw.lowercased()
            if lower.contains("claude code")
                || lower.range(of: "\\bclaude\\b", options: .regularExpression) != nil {
                hint = .claude
            }
        }

        let isWorking: Bool?
        if isIdleMark {
            isWorking = false
        } else if raw.isEmpty {
            isWorking = nil
        } else {
            isWorking = true
        }

        let display = stripLeadingIconAndWhitespace(raw)
        return OSCTitleEvent(
            rawTitle: raw,
            displayTitle: display.isEmpty ? nil : display,
            isWorking: isWorking,
            providerHint: hint
        )
    }

    /// `/^.\s*/` paritesi: ilk karakter körlemesine atılır (✳/spinner ikonu hedeflenir,
    /// ikonsuz title'ın ilk harfi de gider — spec/10'da kayıtlı bilinen trade-off).
    static func stripLeadingIconAndWhitespace(_ string: String) -> String {
        guard !string.isEmpty else { return "" }
        var rest = string.dropFirst()
        while let first = rest.first, first.isWhitespace {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    static func interpretNotification(_ payload: String) -> OSCNotificationKind {
        let lower = payload.lowercased()
        let patterns = [
            "\\b(turn|task)\\s+(complete|completed|done|finished)\\b",
            "waiting for input",
            "all idle",
            "idle state",
        ]
        for pattern in patterns
        where lower.range(of: pattern, options: .regularExpression) != nil {
            return .codexTurnComplete
        }
        return .generic
    }
}
