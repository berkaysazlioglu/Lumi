import Foundation

/// OSC dizilerini decode edilmiş stream üzerinde ayıklayan **saf byte state
/// machine**: `ESC ] kod ; payload (BEL | ESC \)` (önce gelen sonlandırıcı).
///
/// Faz 4.8'den beri yalnız ham `(code, payload)` üretir — hangi kodun ne anlama
/// geldiği `OSCSemantics` implementasyonlarının işidir (OCP: yeni ajan/OSC 7/133
/// desteği bu dosyaya dokunmadan eklenir). Emülatörden bilinçli olarak
/// bağımsızdır: SwiftTerm aynı sequence'leri kendi işler.
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

    func feed(_ text: String) -> [OSCRawEvent] {
        var events: [OSCRawEvent] = []
        for character in text {
            handle(character, into: &events)
        }
        return events
    }

    /// Terminal kapanışında parser durumu sıfırlanır (design/01 §6 adım 5):
    /// yarım kalmış sequence exit'ten sonra tamamlanıp hayalet event üretmez.
    func reset() {
        buffer = ""
        state = .ground
    }

    private func handle(_ character: Character, into events: inout [OSCRawEvent]) {
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

    private func finish(into events: inout [OSCRawEvent]) {
        defer {
            buffer = ""
            state = .ground
        }
        let parts = buffer.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let code = Int(first) else { return }
        let payload = parts.count > 1 ? String(parts[1]) : ""
        events.append(OSCRawEvent(code: code, payload: payload))
    }
}
