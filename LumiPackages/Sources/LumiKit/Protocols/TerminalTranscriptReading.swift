import Foundation
import LumiWire

/// Bir ajan terminalinin konuşma transkriptini okuyan yüz (karar 103 Faz 2):
/// orchestrator'ın `read_terminal` aracı Claude terminallerinde ekranı değil
/// transkripti okur — TUI çerçevesi, renk ve kırpılmış satırlar olmadan.
public protocol TerminalTranscriptReading: Sendable {
    /// `<cwd>`'de koşan Claude oturumunun SON mesajları (dosyanın kuyruğundan;
    /// eski mesajlar kesilebilir). Transkript yoksa boş.
    func recentClaudeMessages(sessionID: String, cwd: String) async -> [ChatMessage]
}
