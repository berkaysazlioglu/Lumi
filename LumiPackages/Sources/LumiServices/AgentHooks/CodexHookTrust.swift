import CryptoKit
import Foundation

/// Codex'in `config.toml` içindeki hook güven kaydı (karar 45).
///
/// Codex, `hooks.json`'daki her handler için `[hooks.state."<hooks.json yolu>:
/// <event etiketi>:<grup>:<handler>"] trusted_hash = "sha256:…"` bekler; hash
/// tutmazsa kullanıcıya "bu hook'a güveniyor musun" sorar. Algoritma Orca
/// `computeCodexTrustedHash` ile birebir doğrulandı (yerel `~/.codex`
/// vektörleri): kimlik nesnesi anahtarları sıralı, kompakt JSON, SHA-256.
enum CodexHookTrust {
    /// Codex event adı → TOML etiketi.
    static let eventLabels: [String: String] = [
        "SessionStart": "session_start",
        "UserPromptSubmit": "user_prompt_submit",
        "PreToolUse": "pre_tool_use",
        "PermissionRequest": "permission_request",
        "PostToolUse": "post_tool_use",
        "SubagentStart": "subagent_start",
        "SubagentStop": "subagent_stop",
        "Stop": "stop",
    ]

    struct Entry: Equatable, Sendable {
        let key: String
        let hash: String
    }

    /// `<hooksPath>:<label>:<group>:<handler>`
    static func key(hooksPath: String, label: String, group: Int, handler: Int = 0) -> String {
        "\(hooksPath):\(label):\(group):\(handler)"
    }

    /// `sha256:<hex>` — kimlik: `{async,command,timeout,type}` handler'ı içeren
    /// `{event_name, hooks[, matcher]}` nesnesi. Bizim handler'larda matcher yok.
    static func trustedHash(label: String, command: String, timeoutSeconds: Int) -> String {
        let handler = "{\"async\":false,\"command\":\(jsonString(command)),\"timeout\":\(max(1, timeoutSeconds)),\"type\":\"command\"}"
        let identity = "{\"event_name\":\(jsonString(label)),\"hooks\":[\(handler)]}"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// `JSON.stringify` string paritesi: yalnız `"` `\` ve kontrol karakterleri
    /// kaçışlanır; `/` ve ASCII dışı karakterler olduğu gibi kalır.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// `config.toml`'un satır tabanlı, geri kalanı byte-byte koruyan düzenleyicisi.
/// Yalnız `[hooks.state."…"]` tablolarına dokunur: istenenleri ekler/günceller,
/// Lumi'nin eski (anahtarı kaymış) kayıtlarını hash imzasından tanıyıp siler.
enum CodexConfigTomlEditor {
    private struct Section {
        let key: String
        let range: Range<Int>
        let hash: String?
    }

    static func apply(
        to source: String,
        desired: [CodexHookTrust.Entry],
        ownedHashes: Set<String>
    ) -> (result: String, changed: Bool) {
        var lines = source.components(separatedBy: "\n")
        // Sondaki boş satır `components` ile "" olarak gelir; işlem sonunda
        // tek trailing newline garanti edilir.
        if lines.last == "" { lines.removeLast() }
        let original = lines

        // 1) Eski Lumi kayıtları: bizim hash'lerimizden birini taşıyan ama artık
        //    istenmeyen anahtarlar silinir. Silinecek satırlar tek kümede
        //    toplanır (bölüm + önündeki tek boş satır); bitişik bölümlerde
        //    aralıklar çakışabilir, küme bunu sorunsuz yutar.
        let desiredKeys = Set(desired.map(\.key))
        var doomed = Set<Int>()
        for section in sections(in: lines)
            where !desiredKeys.contains(section.key) && section.hash.map(ownedHashes.contains) == true {
            doomed.formUnion(section.range)
            let before = section.range.lowerBound - 1
            if before >= 0, lines[before].trimmingCharacters(in: .whitespaces).isEmpty {
                doomed.insert(before)
            }
        }
        if !doomed.isEmpty {
            lines = lines.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        }

        // 2) İstenenler: var olan bölümün hash satırı güncellenir; yoksa sona eklenir.
        for entry in desired {
            if let section = sections(in: lines).first(where: { $0.key == entry.key }) {
                if section.hash == entry.hash { continue }
                let hashLine = "trusted_hash = \"\(entry.hash)\""
                if let index = lines[section.range].firstIndex(where: { isHashLine($0) }) {
                    lines[index] = hashLine
                } else {
                    lines.insert(hashLine, at: section.range.lowerBound + 1)
                }
            } else {
                if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "[hooks.state]" }) {
                    appendBlank(&lines)
                    lines.append("[hooks.state]")
                }
                appendBlank(&lines)
                lines.append("[hooks.state.\(CodexHookTrust.jsonString(entry.key))]")
                lines.append("trusted_hash = \"\(entry.hash)\"")
            }
        }

        guard lines != original else { return (source, false) }
        return (lines.joined(separator: "\n") + "\n", true)
    }

    /// Dosyadaki tüm `[hooks.state."…"]` bölümleri: başlıktan, sonraki tablo
    /// başlığından önceki son dolu satıra kadar (kuyruk boşlukları dışarıda).
    private static func sections(in lines: [String]) -> [Section] {
        var result: [Section] = []
        var index = 0
        while index < lines.count {
            guard let key = stateKey(in: lines[index]) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                end += 1
            }
            var lastContent = end
            while lastContent > index + 1, lines[lastContent - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                lastContent -= 1
            }
            let hash = lines[(index + 1) ..< lastContent].first(where: isHashLine).flatMap(hashValue)
            result.append(Section(key: key, range: index ..< lastContent, hash: hash))
            index = end
        }
        return result
    }

    private static func stateKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "[hooks.state.\""
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("\"]") else { return nil }
        let inner = trimmed.dropFirst(prefix.count).dropLast(2)
        return String(inner).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func isHashLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("trusted_hash")
    }

    private static func hashValue(_ line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        return line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
    }

    private static func appendBlank(_ lines: inout [String]) {
        if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("")
        }
    }
}
