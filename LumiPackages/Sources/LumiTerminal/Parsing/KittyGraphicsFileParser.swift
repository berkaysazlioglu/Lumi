import Foundation

/// Kitty grafik protokolüyle DOSYADAN okunan bir görselin aktarımı (karar 149):
/// `ESC _ G a=T,t=f,i=<kimlik>,… ; base64(mutlak yol) ESC \`.
struct KittyImageFile: Equatable, Sendable {
    let imageID: UInt32
    let path: String
}

/// PTY çıktısındaki kitty grafik APC dizilerinden yalnız dosya aktarımlarını
/// (`t=f`) ayıklayan **saf byte state machine** (karar 149).
///
/// Neden var: Claude Code bir `Image`'ı (`source: { file }`) terminale yolu
/// base64'lü bir `t=f` aktarımıyla gönderir, ekrana ise yalnız görsel
/// kimliğini ön plan renginde taşıyan Unicode placeholder hücreleri basar.
/// SwiftTerm görseli çözüp saklar ama yolu ve deposunu dışarı açmaz; tıklanan
/// hücrenin hangi dosya olduğu ancak aktarımın kendisinden bilinir.
///
/// Emülatörden bağımsızdır (SwiftTerm aynı diziyi kendi işler) ve
/// `OSCStreamParser` gibi yalnız gözlemler. Ham `Data` üzerinde koşar: düz
/// metin `memchr` ile ESC'ye atlanır, bayt taşıyan (`t=d`) aktarımların
/// payload'ı hiç biriktirilmez — büyük bir görsel akışı bellek ya da zaman
/// maliyeti doğurmaz.
final class KittyGraphicsFileParser {
    /// Kontrol bölümünün (`a=T,t=f,…`) üst sınırı; aşan dizi atlanır.
    static let maxControlLength = 512
    /// Base64 payload üst sınırı: `PATH_MAX` (1024) yolun base64'ü rahat sığar.
    static let maxPayloadLength = 8192
    /// Yolun kendisinin üst sınırı (bayt).
    static let maxPathLength = 4096

    private static let escape: UInt8 = 0x1B
    private static let apcIntroducer = UInt8(ascii: "_")
    private static let graphicsKey = UInt8(ascii: "G")
    private static let stringTerminator = UInt8(ascii: "\\")
    private static let payloadSeparator = UInt8(ascii: ";")

    private enum State {
        case ground
        /// ESC görüldü; `_` APC'yi başlatır.
        case escape
        /// `ESC _` görüldü; `G` kitty grafiğidir, başka her şey atlanan bir APC.
        case introducer
        case control
        /// Kabul edilen bir dosya aktarımının base64 yolu.
        case payload(imageID: UInt32)
        /// Bizi ilgilendirmeyen APC gövdesi: ST'ye kadar okunup atılır.
        case skip
    }

    private var state: State = .ground
    /// Gövdede ESC görüldü: `\` gelirse dizi biter (ST), gelmezse yarıda kesilmiştir.
    private var isAwaitingTerminator = false
    private var control: [UInt8] = []
    private var payload: [UInt8] = []

    func feed(_ data: Data) -> [KittyImageFile] {
        var files: [KittyImageFile] = []
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = raw.count
            var index = 0
            while index < count {
                if case .ground = state {
                    guard let found = memchr(base + index, Int32(Self.escape), count - index) else { return }
                    index = base.distance(to: found.assumingMemoryBound(to: UInt8.self)) + 1
                    state = .escape
                    continue
                }
                handle(base[index], into: &files)
                index += 1
            }
        }
        return files
    }

    /// Terminal kapanışında yarım kalan dizi atılır (OSC parser'la aynı kural).
    func reset() {
        state = .ground
        isAwaitingTerminator = false
        control.removeAll(keepingCapacity: false)
        payload.removeAll(keepingCapacity: false)
    }

    // MARK: - Durum geçişleri

    private func handle(_ byte: UInt8, into files: inout [KittyImageFile]) {
        if isAwaitingTerminator {
            isAwaitingTerminator = false
            if byte == Self.stringTerminator {
                finish(into: &files)
                return
            }
            // ST değil: dizi yarıda kesildi; bu ESC yeni bir dizinin başıdır.
            discard()
            state = .escape
        }
        switch state {
        case .ground:
            return
        case .escape:
            if byte == Self.apcIntroducer {
                state = .introducer
            } else if byte != Self.escape {
                state = .ground
            }
        case .introducer:
            if byte == Self.escape {
                state = .skip
                isAwaitingTerminator = true
            } else {
                state = byte == Self.graphicsKey ? .control : .skip
            }
        case .control, .payload, .skip:
            handleBody(byte)
        }
    }

    private func handleBody(_ byte: UInt8) {
        if byte == Self.escape {
            isAwaitingTerminator = true
            return
        }
        switch state {
        case .control:
            if byte == Self.payloadSeparator {
                beginPayload()
            } else if control.count < Self.maxControlLength {
                control.append(byte)
            } else {
                discard()
                state = .skip
            }
        case .payload:
            if payload.count < Self.maxPayloadLength {
                payload.append(byte)
            } else {
                discard()
                state = .skip
            }
        default:
            return
        }
    }

    private func beginPayload() {
        let imageID = Self.fileTransferImageID(control: control)
        control.removeAll(keepingCapacity: true)
        state = imageID.map { .payload(imageID: $0) } ?? .skip
    }

    private func finish(into files: inout [KittyImageFile]) {
        if case let .payload(imageID) = state, let path = Self.decodePath(payload) {
            files.append(KittyImageFile(imageID: imageID, path: path))
        }
        discard()
    }

    private func discard() {
        state = .ground
        control.removeAll(keepingCapacity: true)
        payload.removeAll(keepingCapacity: true)
    }

    // MARK: - Ayrıştırma

    /// Kontrol bölümü bir dosya aktarımıysa görselin kimliği. Kabul: eylem
    /// aktarım (`a=T` göster ya da `a=t` yalnız aktar; yoksa `t`), ortam dosya
    /// (`t=f` — geçici dosya `t=t` okununca silinir, paylaşılan bellek `t=s`
    /// dosya değildir), sıfırdan farklı `i=` ve parçasız (`m=0`). Sorgu (`a=q`)
    /// görsel kaydetmez.
    static func fileTransferImageID(control: [UInt8]) -> UInt32? {
        var action = "t"
        var medium = "d"
        var more = "0"
        var imageID: UInt32 = 0
        for field in String(decoding: control, as: UTF8.self).split(separator: ",") {
            let pair = field.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let value = String(pair[1])
            switch pair[0] {
            case "a": action = value
            case "t": medium = value
            case "m": more = value
            case "i": imageID = UInt32(value) ?? 0
            default: continue
            }
        }
        guard action == "T" || action == "t", medium == "f", more == "0", imageID != 0 else { return nil }
        return imageID
    }

    /// Base64 payload'dan mutlak, NUL'suz, makul uzunlukta bir yol.
    static func decodePath(_ payload: [UInt8]) -> String? {
        guard !payload.isEmpty,
              let data = Data(base64Encoded: Data(payload)),
              data.count <= maxPathLength,
              !data.contains(0),
              let path = String(data: data, encoding: .utf8),
              path.hasPrefix("/") else { return nil }
        return path
    }
}
