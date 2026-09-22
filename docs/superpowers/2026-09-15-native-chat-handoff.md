# Remote Native Chat — Devir Raporu (Handoff)

**Tarih:** 2026-09-15
**Branch:** `feat/remote-orca-main` (main'e commit YOK)
**Bağlam:** Lumi (macOS) + LumiMobile (iOS) remote — Claude Code oturumlarını telefona aynalar. Terminal-mirror telefonda okunamadığı için (Mac 120 kolon → yatay scroll) orca'nın `native-chat` yaklaşımına geçildi: transcript JSONL parse → native chat.

---

## 1. Özet — nerede duruyoruz

**Faz 1 (transcript-tail native chat) TAMAM ve deploy edildi.** Subagent-driven development ile 12 task + opus final review, hepsi testli. Telefonda chat görünümü varsayılan; terminal-mirror toggle olarak duruyor.

**Doğrulanan (otomatik):** tüm test suite'leri yeşil (LumiPackages build + LumiKit/LumiServices/LumiRemote, RelayServer 50, LumiMobileKit); iOS+Mac BUILD SUCCEEDED; relay `chat`/`chat_append` passthrough production'da canlı doğrulandı; chat input yolu (telefon→Mac terminal) cihazda çalışıyor.

**Bilinen açık sorun (kullanıcı bilerek erteledi):** chat composer'dan gönderilen mesaj Mac terminal input satırına **ulaşıyor ama Enter tetiklenmiyor** (§3).

---

## 2. Faz 1 — teslim edilen mimari

Kod `feat/remote-orca-main` üzerinde (23 commit, `186d453..HEAD`). Spec + plan:
- `docs/superpowers/specs/2026-09-15-native-chat-phase1-design.md`
- `docs/superpowers/plans/2026-09-15-native-chat-phase1.md`

**orca referans kaynağı:** `/Users/balkan/Desktop/side-projects/orca`
- Model: `src/shared/native-chat-types.ts`
- Host tail+decoder: `src/main/native-chat/transcript-{watch,reader,stream-lines,tail-boundary}.ts`, `transcript-line-decoders-claude.ts`
- Tool folding / ask / streaming: `src/shared/native-chat-{tool-fold,tool-activity,ask,streaming}.ts`
- Mobil UI: `mobile/src/session/MobileNativeChat*.tsx`, `mobile-native-chat-{send,send-classification}.ts`

**Katmanlar (Lumi'de):**
| Katman | Dosya(lar) | İş |
|---|---|---|
| Wire modeli | `LumiKit/Models/ChatMirrorModels.swift` (+ telefon kopyası `LumiMobileKit/…/ChatMirrorModels.swift`) | `ChatMessage`/`ChatBlock`/`ChatRole`/`ChatSubagentEntry` — orca `NativeChatMessage` alt kümesi |
| Decoder | `LumiServices/NativeChat/ClaudeTranscriptChatDecoder.swift` | Claude JSONL satırı → `ChatMessage` (text/tool-call/tool-result) |
| Kaynak | `LumiServices/NativeChat/TranscriptChatSource.swift` (+ `LumiKit/Protocols/ChatTranscriptSourcing.swift`) | `~/.claude/projects/<cwd>/<sid>.jsonl` polling tail → `.snapshot`/`.append` |
| Mac servis | `LumiRemote/RemoteService.swift`, `RemoteProtocol.swift` | `subscribe mode=chat` + `claudeSessionID` → chat stream → `chat`/`chat_append`; terminal mode korundu |
| Composition | `LumiAppCore/Features/RemoteFeatureAssembly.swift` | `TranscriptChatSource()` enjeksiyonu |
| Relay | `RelayServer/src/{protocol,bridge}.ts` | `chat`/`chat_append` mac→phone broadcast; `subscribe.mode` opak geçiş |
| Telefon model | `LumiMobileKit/…/{PhoneProtocol,AppModel,ChatFold}.swift` | decode + tool-fold + `chatBySession` merge + `subscribeChat` |
| Telefon UI | `LumiMobile/App/{MobileChatView,MobileChatMessageView,MobileChatToolRunView}.swift`, `TerminalSessionView.swift` | chat listesi + balonlar + katlanır araç satırı + chat/terminal toggle (varsayılan chat) |

**Bilinçli Faz 1 sınırları:** yalnız Claude + yalnız transcript kaynağı. streaming / ask-prompt / composer paritesi / subagent / Codex = Faz 2-5.

---

## 3. ÖNCELİKLİ AÇIK: chat composer gönder-submit etmiyor

**Belirti:** Telefon chat composer'ından "gönder" → metin Mac terminal input satırında görünüyor ama gönderilmiyor (Enter yok).

**Teşhis (kesin):** `LumiMobile/App/MobileChatView.swift:56` metni tek input frame'de `draft + "\r"` olarak yolluyor. Claude Code TUI bulk girişi **bracketed-paste**'e sarıyor; tek write'taki sondaki `\r` paste'in İÇİNDE kalıp "submit" sayılmıyor. orca bunu ayrı yönetir: metni paste eder, **Enter'ı AYRI bir keystroke** olarak (gerekirse Ctrl+U ile satır temizleyip, "budget"lı) yollar — bkz. `orca/mobile/src/session/mobile-native-chat-send{,-classification}.ts`.

**Fix yönü (küçük, standalone yapılabilir ya da Faz 4'e dahil):**
- Composer'da metni bir `input` frame'iyle, ardından `\r`'yi (Enter) **ayrı** bir `input` frame'iyle kısa gecikmeyle yolla. En basit haliyle `MobileChatView` send closure'ında iki `model.sendInput` çağrısı (araya ~50-100ms).
- Daha sağlam: orca'nın send-classification'ını taklit et — paste öncesi Ctrl+U (satır temizle), sonra metin, sonra Enter; hepsi tek "sending" penceresinde.
- Test: mevcut `RemoteServiceTests` input yolunu kapsıyor; composer davranışı SwiftUI (cihaz testi). Wire tarafında ek test gerekmez.

**Not:** Terminal-mode AccessoryBar da aynı `text + CR` desenini kullanıyor (`AccessoryBar.swift:71`); orada "çalışıyor" raporlanmıştı ama aynı bracketed-paste riskini taşır — fix ikisini de kapsamalı.

---

## 4. Kalan yol haritası — Faz 2-5 (orca paritesi)

Her faz kendi **spec → plan → subagent-driven implementasyon** döngüsü (Faz 1 ile aynı süreç). Kaynak referansları orca'da mevcut.

| Faz | İçerik | orca referansı | Not |
|---|---|---|---|
| **1.5 (hızlı)** | Composer send-submit fix (§3) | `mobile-native-chat-send*.ts` | Küçük; Faz 4'e de katılabilir ama UX'i hemen açar |
| **2 — Canlı** | Per-turn "Working for N" durumu, canlı araç ilerlemesi, token streaming, Stop/interrupt | `native-chat-streaming.ts`, `MobileNativeChatTurnStatus.tsx`, `MobileAgentWorkingIndicator` | Kaynak: transcript satır-tamamlanma + hook event; delta akışı. `turnId` gruplaması burada gerçek kullanım bulur (Faz 1'de self-ref, kullanılmıyor) |
| **3 — Prompt'lar** | Ask/permission/question kartları (tappable seçenek → keystroke) | `native-chat-ask.ts`, `MobileNativeChatAsk/Permission/Question/PromptCard.tsx` | Kaynak: hook + ekran-scrape; §K3 bare-screen. Claude 1/2/3 seçici keystroke'ları |
| **4 — Composer paritesi** | Görsel ekleme, diktasyon, @-dosya autocomplete, slash komut, model/session picker, optimistic echo, pagination, pinch-zoom | `MobileNativeChatComposer`, `use-mobile-native-chat-*`, `MobileNativeChatSessionOptionPickers` | §3 send fix'i buraya doğal olarak girer |
| **5 — Çoklu kaynak + genişlik** | transcript>hook>scrape merge, subagent grupları, Codex decoder, reasoning blokları, edit-patch diff gutter | `native-chat-types.ts` (source precedence), `native-chat-subagent-summary.ts`, `transcript-line-decoders-codex.ts` | `ChatBlock.subagentGroup`/`imageRef` modelde hazır (Faz 1'de decode+stub) |

---

## 5. Bilinen minor'lar (final review triage — non-blocking)

- **MobileChatMessageView:** owner mesajın tool blokları inline, folded siblings collapsed → karışık mesajda görsel tutarsızlık. Faz 2 fold refactor'da düzelt (owner tool bloklarını da tool-run'a besle).
- **Dual `KeyboardObserver`:** chat gösterilirken `TerminalSessionView` (idle) + `MobileChatView` (aktif) iki gözlemci — kaynak israfı, davranışsal değil. İstenirse tek gözlemciyi parent'a taşı.
- **LumiMobile literalleri** (`cornerRadius:14`, `maxWidth:300`): `DesignTokenLintTests` LumiUI'ı kapsar, LumiMobile'ı değil → lint ihlali değil. Faz 4'te mobil tema token'ları.
- **`turnId = message uuid`** (self-ref): Faz 1'de kullanılmıyor; Faz 2 turn-grouping'de yeniden ele al.
- **Non-active dead session chat cache:** `applySessions` yalnız aktif ölen oturumu temizler (pre-existing `replayBuffers` ile paralel). Düşük risk.
- **`/clear` sonrası yeni transcript dosyası takibi:** Faz 1 `claudeSessionID` sabit dosyayı izler; `/clear` yeni dosya açar → Faz 5 (lifecycle/çoklu-kaynak). Bkz. karar 21 / `clear-session-follow`.
- **Chat reconnect:** `AppModel.start()` reconnect'te `subscribeFrame(sessionId:)` (terminal mode) yolluyor — chat modda kopup dönünce terminal'e düşer. Faz 2'de mode-farkında reconnect.

---

## 6. Build / deploy / test komutları

```bash
# Testler
cd LumiPackages && swift test --scratch-path /tmp/lumi --filter "LumiKitTests|LumiServicesTests|LumiRemoteTests"
cd RelayServer && npm test
cd LumiMobile/LumiMobileKit && swift test

# Mac app (LumiRework.app → ~/Applications, com.lumi.rework, mevcut Lumi.app'ten ayrı)
Scripts/make-rework-app.sh

# iOS (proje GENERATED — yeni App/ dosyası → önce xcodegen!)
cd LumiMobile && xcodegen generate
xcodebuild -project LumiMobile.xcodeproj -scheme LumiMobile -configuration Debug \
  -destination 'platform=iOS,id=<DEVICE_ID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE_ID> <app-path>   # bundle: com.lumi.LumiRemoteNew

# Relay (Railway, servis: lumi-relay — canlı olan; lumi-relay-new 2026-09-22'de silindi)
cd RelayServer && railway up --detach
```

**Teşhis logları:** Mac `~/.lumi/logs/mac.log` (`[remote]` satırları), iOS `Documents/lumi-mobile.log`.

---

## 7. Nasıl devam edilir

1. §3 send fix'i hızlı bir "Faz 1.5" olarak ya da Faz 4 başında yap (composer UX'ini açar).
2. Her faz için: brainstorming → spec (`docs/superpowers/specs/`) → writing-plans (`docs/superpowers/plans/`) → subagent-driven-development. orca'nın ilgili dosyaları birebir referans.
3. main'e commit YOK — `feat/remote-orca-main`'de kal ([[no-commit-to-main]]).
4. Her `App/` dosyası eklemesinde `xcodegen generate` şart ([[ios-xcodeproj-is-generated]]).
