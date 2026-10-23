import Foundation
import LumiKit

/// Karar 130: relay `maxPayload` 1 MB'tır ve onu aşan bir Mac frame'i relay'in Mac
/// soketini kapatmasına (1009) yol açar — tüm telefonlar Mac'i çevrimdışı görür.
/// `chat` / `chat_append` gönderilmeden önce bu bütçeye oturtulur: tek başına dev
/// bloklar kırpılır, snapshot en yeni mesajlardan bütçeye sığanlardır, append'ler
/// bütçe altı parçalara bölünür. Mesaj kimlikleri değişmez (kırpma decode sonrası).
enum ChatFrameBudget {
    /// Zarf + `sessionId` + JSON kaçışları için 1 MB'ın altında pay.
    static let maxFrameBytes = 700_000
    /// Tek bir metin/araç bloğunun üst sınırı (karakter).
    static let maxBlockChars = 60_000
    static let truncationMarker = "\n…(truncated)"

    /// En yeni mesajlardan bütçeye sığanlar; `hasEarlier` = baştan mesaj düştü.
    static func fitSnapshot(_ messages: [ChatMessage], budget: Int = maxFrameBytes)
        -> (messages: [ChatMessage], hasEarlier: Bool) {
        var kept: [ChatMessage] = []
        var total = 0
        for message in messages.reversed() {
            let clamped = clamp(message, budget: budget)
            let size = byteSize(clamped)
            if total + size > budget, !kept.isEmpty { break }
            kept.append(clamped)
            total += size
        }
        return (kept.reversed(), kept.count < messages.count)
    }

    /// Append'i sırayı koruyarak her biri bütçe altı parçalara böler.
    static func chunkAppend(_ messages: [ChatMessage], budget: Int = maxFrameBytes) -> [[ChatMessage]] {
        var chunks: [[ChatMessage]] = []
        var current: [ChatMessage] = []
        var total = 0
        for message in messages {
            let clamped = clamp(message, budget: budget)
            let size = byteSize(clamped)
            if total + size > budget, !current.isEmpty {
                chunks.append(current)
                current = []
                total = 0
            }
            current.append(clamped)
            total += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Blokları `maxBlockChars`'a kırpar; mesaj yine de bütçeyi aşıyorsa blok başına
    /// payı bütçeye göre daraltır (tek mesaj hiçbir zaman frame'i tek başına taşırmaz).
    static func clamp(_ message: ChatMessage, budget: Int = maxFrameBytes) -> ChatMessage {
        var result = self.clamped(message, limit: maxBlockChars)
        if byteSize(result) > budget {
            // UTF-8'de karakter başına en fazla 4 bayt; JSON kaçışı için yarı pay.
            let perBlock = max(1, budget / max(1, message.blocks.count) / 8)
            result = self.clamped(message, limit: perBlock)
        }
        return result
    }

    static func byteSize(_ message: ChatMessage) -> Int {
        (try? JSONSerialization.data(withJSONObject: message.toDict()))?.count ?? 0
    }

    private static func clamped(_ message: ChatMessage, limit: Int) -> ChatMessage {
        let blocks = message.blocks.map { clamp($0, limit: limit) }
        guard blocks != message.blocks else { return message }
        return ChatMessage(id: message.id, role: message.role, blocks: blocks,
                           timestampMs: message.timestampMs, turnId: message.turnId)
    }

    private static func clamp(_ block: ChatBlock, limit: Int) -> ChatBlock {
        switch block {
        case let .text(text, presentation):
            return .text(truncate(text, limit), presentation: presentation)
        case let .toolCall(name, inputPreview, state):
            return .toolCall(name: name, inputPreview: truncate(inputPreview, limit), state: state)
        case let .toolResult(output, isError):
            return .toolResult(output: truncate(output, limit), isError: isError)
        case let .imageRef(path, url, alt):
            // Satır içi `data:` URL'i telefonda zaten çözülmez; sınırı aşanı düşür.
            return .imageRef(path: path, url: (url?.count ?? 0) > limit ? nil : url, alt: alt)
        case .subagentGroup, .unknown:
            return block
        }
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + truncationMarker
    }
}
