# Lumi Native — Terminal Alt Sistemi Tasarımı

> `LumiTerminal` modülünün bağlayıcı tasarımı. Zorunlu gereksinimler: [00-architecture.md Ek A](./00-architecture.md) (kök neden analizleri de orada özetlidir).
>
> Durum: 2026-09-05 refactor (Faz 1–7) ile güncellendi.

---

## 1. Topoloji kararı: kalıcı view-attached emülatör (Seçenek A)

**Karar:** Oturum başına, PTY ömrü boyunca yaşayan **tek bir SwiftTerm `TerminalView`**. View'ı `TerminalViewRegistry` (@MainActor) sahiplenir; SwiftUI asla sahip olmaz. Görünmediğinde hierarchy'den ayrılır/gizlenir ama **asla yok edilmez**. Emülatörün grid + scrollback + mod state'i, oturumun ekran durumunun otoriter kaynağıdır.

**Sonuç:** Byte backlog, replay ve reconciliation protokolünün tamamı (**`syncFromMain` / `mergeSnapshotOutput` / `totalLength` / `epoch` / `preserveNewerLiveOutputs`**) silinir — Electron'daki iki-process yarışı telafisi tek process'te gereksizleşir.

**Reddedilen Seçenek B (headless `Terminal` + ayrı render view replikasyonu):** SwiftTerm'de `TerminalView` kendi gömülü `Terminal`'ını sahiplenir; harici bir `Terminal`'ın buffer'ını bir view'a çizdirmenin desteklenen yolu yoktur. B'yi seçmek şunlardan birini zorlar: (a) `TerminalView` renderer'ını fork'lamak, (b) emülatör state'ini byte'a geri serileştirip view tarafındaki ikinci emülatöre beslemek — ki bu, rewrite'ın yok etmek için var olduğu replay makinesini (ve bug 40'ın oto-yanıt tehlikesini) geri getirir, (c) özel renderer yazmak. Üçü de, artık var olmayan bir renderer/main process ayrımını çözmek için satın alınan en pahalı yollardır.

**A'nın gereksinimleri savuşturmadan karşıladığının gerekçesi:**
- §4.1-5'in tercih şıkkı ("replay ham byte yerine emülatör durumu") **yapısal olarak** karşılanır: replay adımı hiç yoktur. Attach = state'i hiç kaybolmamış bir NSView'ı görünür kılmak.
- §4.2-9 **yapısal olarak** karşılanır: oto-yanıtlar (CPR/DA/DECRQM) yalnızca **canlı** sorgulara üretilir — ki o durumda PTY'ye gitmeleri doğrudur. Tarihsel byte'lar asla yeniden beslenmediği için bayat-sorgu yanıtı üretilemez. (Defense-in-depth kapısı yine vardır, §4.)
- §4.1-6'nın amacı (görünmeyen terminale sınırsız buffer/render maliyeti yok): gizli NSView çizilmez; emülatörün satır-sınırlı (5000) scrollback'i "cap'li buffer"ın kendisidir; "attach'te tek snapshot resync", mevcut state'ten tek çizim geçişine indirgenir. Gizli oturumlarda coalescing aralığı genişler (§3) — main-thread uyanması ~6× düşer. Kalan maliyet (gizli terminal için parse-only `feed`) O(chunk)'tır ve aynı backpressure döngüsüyle sınırlıdır.
- Bug 40'ın `display:none` + WebGL-context-evict modu taşınmaz: CoreText render GPU context kullanmaz (§4.2-11), AppKit gizli view state'ini "evict" etmez.

**Maliyet:** En kötü durumda grid belleği ≈ 120 sütun × 5000 satır × ~16 B/hücre ≈ ~10 MB/terminal → 12 terminalde ~120 MB (scrollback satırları lazy ayrılır; tipik değer çok daha düşük). P1 prototipi bunu ölçer ([04](./04-prototype-plan.md)).

---

## 2. PTY katmanı: `PTYProcess`

SwiftTerm `LocalProcess` **kullanılmaz** (gerekçe: [00 §1 T2](./00-architecture.md)). Kendi wrapper'ımız:

```swift
public final class PTYProcess: @unchecked Sendable {          // PTY/PTYProcess.swift
    public enum ReadDirective: Equatable { case proceed, suspend }

    public init(executable: String, args: [String], cwd: String,
                env: [String: String], initialCols: UInt16, initialRows: UInt16,
                queue: DispatchQueue) throws         // io queue init'te verilir

    public func startReading(handler: @escaping @Sendable (Data) -> ReadDirective)
    public func resumeReading()            // her queue'dan güvenli; içeride dengelenir
    public func write(_ data: Data)        // io queue'ya kendi hop'unu yapar
    public func resize(cols: UInt16, rows: UInt16)   // ioctl(TIOCSWINSZ) → SIGWINCH
    public func pokeRepaint()              // attach sonrası TUI redraw'ı (SIGWINCH poke)
    public func terminate()                // killpg(pid, SIGHUP); 3 sn sonra SIGKILL
    public var onExit: (@Sendable (Int32) -> Void)?        // DispatchSourceProcess(.exit)
    public var onWriteFailure: (@Sendable (Int32) -> Void)? // EPIPE/EIO — karar 5
}
```

**Bağımlılık yönü (Faz 4.1 / DIP):** oturum somut `PTYProcess`'i tanımaz. `PTYControlling` yukarıdaki yüzeyin protokolüdür (`extension PTYProcess: PTYControlling`), `PTYSpawning` ise üretimi soyutlar; üretim implementasyonu `SystemPTYSpawner`'dır. `TerminalSession.init(... ptySpawner:viewMaker:pipeline:)` üçünü de enjekte alır — Ek A §A.2-12 reattach testinin (`TerminalSessionReattachTests`) ön koşulu budur.

İmplementasyon notları:

- `forkpty` çağrısı için SwiftTerm `PseudoTerminalHelpers` referans alınabilir; bizim kattığımız değer dispatch-source yaşam döngüsüdür.
- **Okuma:** master fd üzerinde `DispatchSourceRead`, terminal başına serial queue. Handler tek non-blocking `read()` (≤64 KB, `readChunkSize`) yapar. `.suspend` dönerse source **kendini** suspend eder.
- **Kayıp-uyanma (lost wakeup) koruması — `resumeRequested`:** İlk tasarımdaki "eşzamanlı-suspend yarışı yok" iddiası **yanlıştı**. `handleReadable` `.suspend` döndürdüğü an ile `suspendReading()`'in kilidi alması arasında bir pencere vardır; MainActor bu pencerede `noteConsumed` → `resumeReading()` çağırırsa `readSuspended == false` görülür ve resume **no-op** olur, hemen ardından suspend uygulanır — DispatchSource askıda kalır, `FlowController` ise "in-flight boş" der ve terminal **kalıcı donar**. Düzeltme: `resumeReading()` suspend edilmemiş bir kaynak görürse `resumeRequested = true` bırakıp döner; `suspendReading()` kilidi aldığında bu bayrağı görürse suspend'i hiç uygulamaz ve bayrağı temizler. Suspend episode'u başına en fazla bir resume isteği doğduğu için tek bayrak yeterlidir; bayrak `cleanupIO`'da da sıfırlanır. Regresyon kalkanı: `PTYProcessTests` + `TerminalBackpressureIntegrationTests`.
- **Kilit disiplini (`cleanupIO`):** `readSource`/`writeSource` alanları **kilit altında** yerel değişkene alınıp `nil`'lenir, `cancel()` çağrıları kilit **dışında** yapılır. Alan mutasyonu kilit dışında kalırsa MainActor tarafındaki kilitli okumalarla veri yarışı doğar (kapanışta crash). Askıda bir kaynak cancel edilemeyeceği için `wasSuspended`/`wasWriteDisarmed` de kilit altında okunur ve cancel'dan önce `resume()` uygulanır.
- **`deinit` emniyeti:** normal yol kill/exit üzerinden temizler; `deinit` yalnız test ve hata yollarına karşıdır. Askıdaki bir `DispatchSource` release edilirse libdispatch trap'ler ("Release of a suspended object") — bu yüzden `deinit` önce `resume()` sonra `cancel()` uygular ve fd'yi **değerle yakalayan** yeni bir cancel handler kurar (mevcut handler'lar `[weak self]` yakaladığı için artık koşmaz).
- **Spawn paritesi:** shell seçim zinciri (macOS: `zsh → bash → sh`, `which` ile doğrulanır, process ömrü boyunca cache), her zaman `<shell> -l` (login); `claude`/`codex` PTY argv'si değil, sonradan `write()` ile enjekte edilir. `TERM=xterm-256color` + `COLORTERM=truecolor` (her ikisi de miras değeri ezer — Lumi'nin kendi yeteneğini deklare eder, karar 22), başlangıç 120×30, `cwd: repoPath`, env = `fixProcessPath` sonucu. Launch komutu `claude` ise `ClaudeSessionCommand.prepare` `--session-id <uuid>` enjekte eder ve ID `TerminalMeta.claudeSessionID`'de taşınır — quit'te persist edilip yeniden açılışta `claude --resume <id> || claude` ile aynı chat'ten devam edilir (karar 23).
- **Crash dayanıklılığı:** global, lock-korumalı child-pid registry (`PTYChildRegistry`) + `atexit`/`SIGTERM` handler'ı `killpg` döngüsü (async-signal-safe) — yakalanmamış crash'te bile zombi `claude` ağacı kalmaz (§4.3).

### 2.1 Oturum kompozisyonu

`TerminalSession` (@MainActor) tek başına bir god-object değildir; dört parçaya ayrılmıştır (Faz 4.1 / SRP):

| Parça | Yeri | Sorumluluk |
|---|---|---|
| `TerminalSession` | `Session/TerminalSession.swift` | Yaşam döngüsü + kablolama: bir `any PTYControlling`, io queue, `TerminalPipeline`, `TerminalPresentation` sahibi; `TerminalSessionDelegate` üzerinden manager'a status/title/stalled/exit/writeFailed/bell bildirir |
| `TerminalPipeline` | `Session/TerminalPipeline.swift` | Byte pompasının io-queue yarısı: flow, decoder, OSC, semantik zinciri, inference, status makinesi, silence timer, coalescer, watchdog (`@unchecked Sendable`) |
| `TerminalPresentation` | `Session/TerminalPresentation.swift` | Emülatör view'ına giden **tek** kanal: `feed(_:)`, `redrawFromBuffer()`, `setCursorStyle(_:)`, `setFont(_:)`; hücre boyutu değişince `onLayoutInvalidated` |
| `TerminalSessionViewDelegate` | `Session/TerminalSessionViewDelegate.swift` | SwiftTerm `TerminalViewDelegate` uyumu (`send`/`sizeChanged`/`setTerminalTitle`/`bell`/`clipboardCopy`/`requestOpenLink`) ayrı bir extension'da |

Görsel komutlar `TerminalSessionAppearance` extension'ında toplanır ve doğrudan `presentation`'a iner. **Katman sınırı:** oturum `terminalView.superview?.needsLayout` yazmaz; yalnız `onLayoutInvalidated` sinyali verir, `TerminalSessionManager` bunu `TerminalViewRegistry.invalidateLayout(for:)`'a bağlar — yerleşim otoritesi host'tadır ([03 §3](./03-ui-shell.md)).

---

## 3. Okuma yolu (uçtan uca veri akışı)

**Concurrency modeli:** Byte pompasının çekirdeği **GCD**, kenarları `@MainActor`. Hot path'te actor **bilinçli olarak yok**: `DispatchSourceRead` queue-native'dir, suspend/resume'un actor karşılığı yoktur, actor reentrancy watermark muhasebesini karmaşıklaştırır. `AsyncStream` pompada reddedilir: buffer politikaları (sınırsız veya drop) kernel-seviyesi backpressure'ı ifade edemez.

Terminal başına:

```
[io queue: "lumi.terminal.<id>" — serial, .utility QoS]
  DispatchSourceRead tetiklenir
    → read() ≤ 64KB ham byte
    → FlowController.noteProduced(n) ──(≥ HIGH 512KB)──▶ .suspend döndür
    │     (source durur; kernel PTY buffer'ı dolar; yazan süreç doğal bloklanır — veri kaybı yok)
    → UTF8StreamDecoder.decode(bytes)        // chunk sınırında bölünen çok-byte karakter
    │                                        // taşıması (✳ U+2733 = 3 byte!)
    → ProviderInferencer.observeOutput(...)  // "openai codex" / "claude code" hint'leri
    → OSCStreamParser.feed(decoded) -> [OSCRawEvent]   // YALNIZ (code, payload);
    │                                        // 4096-char partial cap; BEL/ST
    │     └─ OSCSemanticsChain.interpret(raw, hint:) → [OSCEvent]   (§3.3)
    │           └─ StatusStateMachine / DecisionTracker (BURADA, io queue'da koşar)
    │                 └─ durum değişimi → hopToMain → metadata publish + Notifier
    → CodexSilenceTimer.touch()              // 3 sn DispatchSourceTimer, aynı queue
    → OutputCoalescer.ingest(rawBytes)       // HAM byte — emülatör byte ister
         └─ flush koşulu: ilk byte'tan beri 16ms (yüzey görünmüyorsa 100ms)
            VEYA ≥ AdaptiveBatchBudget.threshold (default 128KB, §3.2)

[flush → DispatchQueue.main.async, flush başına tek Data]
  @MainActor TerminalSession.deliver(batch)
    → registry guard: oturum canlı mı? (native safeSend) — ölüyse sessiz drop,
      PTY oturum/view kurtarılana dek suspend kalır
    → watchdog.measureFeed { presentation.feed(batch) }   // SENKRON parse; süre ölçülür
    │                                        // SwiftTerm fiili çizimi kendi frame'ler;
    │                                        // gizli view: yalnız parse
    → ack: FlowController.noteConsumed(batch.count)
         └─(LOW 128KB altına indi)──▶ ioQueue.async { pty.resumeReading() }
```

**Ack'in SwiftTerm'in senkron feed'iyle çalışması:** `Terminal.feed` byte'lar grid'e tamamen işlendikten sonra döner — xterm.js'in aksine **iç async write kuyruğu yoktur** (bu, §4.1-8'i bedavaya çözer). "Tüketildi" = "feed döndü". *In-flight* = fd'den okunmuş ama henüz feed edilmemiş byte'lar: coalescer içeriği + main queue'da bekleyen batch'ler. `FlowController`, io queue'dan (produce) ve MainActor'dan (consume) dokunulan `OSAllocatedUnfairLock` korumalı küçük bir sayaçtır. High/low = terminal başına **512 KB / 128 KB** → 12 terminalde toplam in-flight bellek ≤ 6 MB, hard-bounded.

**Chunk başına maliyet her aşamada O(chunk)** (decoder, sınırlı-taşımalı OSC taraması, coalescer append, feed) — hiçbir aşama birikmiş geçmişi yeniden taramaz; emülatör dışında birikmiş geçmiş **yoktur** (§4.1-3).

**Hiçbir yerde byte backlog buffer'ı yoktur.** Tutulan tek metin artefaktları: emülatör scrollback'i (5000 satır, `TerminalSession.scrollbackLines`) ve OSC parser'ın 4096-char partial taşıması (`OSCStreamParser.maxBufferLength`). Electron'un 500 KB tail cap'i yalnız snapshot replay'i beslemek için vardı; replay yokken parite garantisi scrollback-5000'dir.

**Output fan-out YOKTUR (Faz 1.19, YAGNI).** Tasarımın ilk hâlindeki oturum başına `AsyncStream<String>` çıktı yayını ve onu besleyecek 4 KB `wait_for` ring'i hiçbir zaman tüketici bulmadı (ActionEngine native'e taşınmadı) — `TerminalServicing.outputStream` / `onOutputText` dikişi kaldırıldı. Böylece sıcak yolda decode edilmiş metnin tek tüketicisi pipeline'ın kendisidir.

**Event yayını:** servis→store olayları `EventBroadcaster<TerminalEvent>` üzerinden akar. Broadcaster `init(bufferingPolicy:)` alır; varsayılan `.unbounded` (yaşam döngüsü olayları düşük hacimli ve kayıpsız olmalı), yüksek hacimli/drop'a toleranslı akışlar `.bufferingNewest(_:)` ile sınırlanabilir.

### 3.1 OSC ayrıştırma ve semantik katmanı (OCP)

Ayrıştırma ile **yorum** ayrılmıştır (Faz 4.8):

- `OSCStreamParser` bir state machine'dir ve yalnız **ham** olay üretir: `OSCRawEvent(code:payload:)`. Hangi kodun ne anlama geldiğini bilmez; 4096-char partial cap, BEL/ST sonlandırıcı önceliği ve kapanışta `reset()` burada kalır.
- `OSCSemantics` protokolü (`interpret(code:payload:hint:) -> [OSCEvent]`) yorumu taşır. `OSCSemanticsDefaults.all` sırası anlamlıdır: `ClaudeSemantics` → `CodexSemantics` → `GenericTitleSemantics`.
- `OSCSemanticsChain` **ilk-eşleşen-kazanır** çalışır: bir sequence başına en fazla **tek** olay üretilir (aksi hâlde aynı title iki kez yayınlanırdı).
- Üretilen olay `OSCEvent`'tir: `.title(OSCTitleEvent)` veya `.notification(OSCNotificationKind)` (`.codexTurnComplete` / `.permissionRequest`).
- Ajandan bağımsız title yorumu (✳ U+2733 idle işareti, `/^.\s*/` strip paritesi, boş title → karar yok) tek saf yardımcıda toplanır: `OSCTitleInterpreter`.

**`AgentHint` kapalı enum değil açık struct'tır:** `rawValue: String` + `.unknown` / `.claude` / `.codex` sabitleri. Yeni bir ajan semantiği eklemek (yeni `OSCSemantics` dosyası + kendi hint sabiti) mevcut hiçbir `switch`'i kırmaz. **Yeni ajan ya da yeni OSC kodu (7 cwd, 133 shell integration) = yeni bir dosya + varsayılan diziye tek satır.**

`ProviderInferencer` sıcak yolda çalıştığı için iki optimizasyon taşır (Faz 1.24): komut kalıpları `CachedRegex` ile bir kez derlenir (`^codex(\s|$)`, `^claude(\s|$)`), output taramasında `lowercased()` kopyası yerine `.caseInsensitive` arama kullanılır ve `hint == .codex` iken **erken çıkılır** (asimetri: codex hint'i output'la asla düşmez).

### 3.2 Adaptif batch bütçesi

`AdaptiveBatchBudget` coalescer'ın **boyut** eşiğini taşır (aralık eşiği yüzey durumundan gelir, §3.3). Feed MainActor'da 4 ms bütçeyi (`FeedWatchdog.feedBudget`) aşarsa eşik yarıya iner (`noteOverrun`), bütçe içinde kalan her feed eşiği iki katına çıkarır (`noteWithinBudget`) ve default'u aşmaz. Alt sınır `defaultMinimumThreshold = 8 KB`'dir: bunun altında flush başına MainActor sıçraması kazancı yer. io queue'dan (okuma) ve MainActor'dan (ölçüm) dokunulduğu için lock korumalıdır.

### 3.3 Donma gözetimi: `FeedWatchdog` (Ek A §A.2-10)

Ek A §A.2-10 Faz 4.2'ye kadar **hiç implemente edilmemişti**; terminaller arka planda yaşamaya başlayınca (§3.4) donmayı kimsenin görmemesi gerçek bir risk hâline geldi. `FeedWatchdog` iki iş yapar:

1. **Stall tespiti.** `measureFeed { … }` her feed'i sarar; süreyi bütçeye, zaman damgasını (`MonotonicClock` — `DispatchTime` uptime'ı, NTP sıçramalarından etkilenmez) stall tespitine yazar. `HeartbeatScheduling` (üretimde `DispatchHeartbeatScheduler`, io queue'da `DispatchSourceTimer`) `defaultHeartbeatInterval = 2 sn`'de bir `tick()` çağırır: **in-flight byte varken** son başarılı feed'in üzerinden `defaultStallThreshold = 2 sn` geçtiyse terminal donmuş sayılır. `onStallChange` yalnız **değişimde** ateşlenir.
2. **Adaptif batching.** Feed 4 ms'i aşarsa `AdaptiveBatchBudget.noteOverrun()`, aşmazsa `noteWithinBudget()` (§3.2).

Sinyalin UI'a yolu: `TerminalPipeline.onStallChange` → `TerminalSessionDelegate.session(_:didChangeStalled:)` → `TerminalEvent.stalled(TerminalID, Bool)` → `TerminalListStore.stalledIDs: Set<TerminalID>` → terminal kartındaki rozet. **`TerminalMeta` formatı değişmez** — stall efemer bir UI durumudur, metadata değil, dolayısıyla persist edilmez. Testler saat ve heartbeat'i enjekte ederek deterministik koşar (`FeedWatchdogTests`).

### 3.4 Yüzey durumu: `TerminalSurfaceState`

Faz 4.3'ten önce **görünürlük ve odak iki bağımsız kanaldı**: registry attach/detach yalnız coalescer aralığını değiştiriyor, `setFocused` yalnız durum makinesine dokunuyordu. Orta alan başka bir görünüme geçtiğinde terminal ekranda olmadığı hâlde `focused` kalıyor, `waitingUnseen` yerine `waitingFocused`'a çıkıyordu — yanlış rozet, yanlış bildirim, karar 24 auto-minimize'ının bozulması.

`LumiKit.TerminalSurfaceState` iki kanalı **tek atomik geçişte** birleştirir:

| Durum | Anlamı | Akış politikası | Durum makinesi |
|---|---|---|---|
| `.foreground` | ekranda ve çizilebilir | coalescer 16 ms | odak servisin bildiği `focusedID` ile eşleşiyorsa `onFocus()` |
| `.background` | canlı ama görünmüyor (route/tab değişimi) | coalescer 100 ms | `onBlur()` |
| `.minimized` | kullanıcı (ya da karar 24) kartı gizledi | bugün `.background` ile aynı | `onBlur()` |

`isVisible` yalnız `.foreground` için `true` döner. Servis yüzü iki intent taşır: `setSurfaceState(_:for:)` (tek terminal) ve `setSurfaceState(_:in:)` (repo başına toplu; `nil` ⇒ tümü). İkisi de `TerminalSession.setSurfaceState(_:isFocused:)`'a iner, o da io queue'da `TerminalPipeline.applySurfaceState(_:isFocused:)` ile coalescer aralığını ve `statusMachine.onFocus/onBlur`'u **aynı adımda** uygular. **Foreground olmak tek başına odak kazandırmaz:** odağın otoritesi `TerminalSessionManager.focusedID`'dir.

Eski `TerminalSession.setHidden(_:)` yüzeyi **yoktur**; `setHidden` yalnızca `OutputCoalescer`'ın iç aralık anahtarı olarak kalmıştır ve dışarıdan çağrılmaz.

Store tarafındaki tek intent kümesi (Faz 4.9): `TerminalListStore.setTerminalSurfaceVisible(_:in:)`, `deactivateSurface()` ve dahili `surfaceRepoPath` — hangi repo'nun yüzeyinin önde olduğunun tek kaydı. Route geçiş sözleşmesi `NavigationStore.applySurfaceTransition(from:to:)`'dadır (view'da değil):

| Olay | View | PTY | Status makinesi | Coalescer |
|---|---|---|---|---|
| Terminals → başka route (ör. Tasks) | `detachAll()` — detach, **yok edilmez** | çalışır | `onBlur()` | 100 ms |
| Başka route açıkken resize | frame donuk | resize yok | değişmez | 100 ms |
| Terminals'a dönüş | `refreshAttachedViews()` + host'un tek fit'i | tek resize | `onFocus()` yalnız aktif terminale | 16 ms |
| Başka route açıkken exit | — | reap | `onExit(code)` | flush |

---

## 4. Yazma yolu

PTY'ye giden **tüm** byte'lar tek metodda toplanır, sonra tek serial queue'dan akar:

```
klavye / IME / paste ──▶ TerminalViewDelegate.send(source:data:)     ┐
SwiftTerm oto-yanıtları (CPR/DA/DECRQM/mouse — view iletir)          ┤
launch komut enjeksiyonu (LaunchCommandGate, \r-sonlu)               ├─▶ @MainActor
prompt kuyruğu enjeksiyonu (PromptInjection — [03 §4.1])             ┤   TerminalSession.write(_:)
drag-drop path (ShellQuoting, karar 11)                              ┘
        │
        ▼
  PTYInputFilter.filter(bytes)     // stateful BYTE tarayıcı, regex DEĞİL:
        │                          //  • ESC [ I ve ESC [ O daima ayıklanır (focus'u
        │                          //    StatusStateMachine sahiplenir; agent "focused" bilmeli)
        │                          //  • session.suppressResponses açıksa: CPR/DA/DECRQM/
        │                          //    mouse-report biçimli diziler de düşürülür
        ▼
  ProviderInferencer.observeInput(...)        // ^claude / ^codex hint
  \r içeriyorsa lastActivityAt; hint==codex ise statusMachine.onUserInput()
        ▼
  ioQueue.async { pty.write(filtered) }       // terminal başına TEK serial queue = toplam sıra
```

- **§4.1-7 (seri sıralama):** per-terminal io queue fd'nin tek yazarıdır; üstündeki MainActor hunisi üreticileri serileştirir. Araya girme imkânsızdır. Resize ioctl'leri de aynı queue'ya dispatch edilir (yazımlara karşı sıralı).
- **Oto-yanıt politikası:** `TerminalViewDelegate.send` tuş vuruşlarını ve emülatör oto-yanıtlarını birleştirir; **varsayılan olarak iletmek doğrudur** — oto-yanıtlar yalnız gerçek foreground uygulamasının canlı sorgularından doğar (DSR gönderen TUI, CPR'ını bekler). Bug-40 tehlikesi (*replay edilmiş* sorgulara yanıt) hiçbir şey replay edilmediği için oluşamaz.
- **Mode 1004:** Agent `?1004h` set ederse SwiftTerm focus değişimlerinde `ESC[I`/`ESC[O` üretir; bunlar **koşulsuz** ayıklanır — Electron'daki filtrenin birebir paritesi, ama protokol-bilinçli tarayıcı olarak (UTF-8'i bozmaz, yalnız tam 3-byte'lık dizileri çıkarır).
- **`suppressResponses` kapısı (defense-in-depth, §4.2-9):** İleride eklenebilecek herhangi bir canlı-olmayan `feed` etrafına sarılacak per-session bayrak (bugün hiç set edilmez). Varlığının amacı invariant'ı **test edilebilir** kılmaktır: §4.2-12 entegrasyon testi ("UI kurtarılır → PTY'ye sıfır istenmeyen byte") mock PTY'ye karşı bunu assert eder.
- **Yazım hatası yutulmaz (karar 5, Faz 1.15):** `drainWrites` kalıcı EPIPE/EIO görürse `PTYProcess.onWriteFailure(errno)` ateşlenir → `TerminalSessionDelegate.session(_:didFailWriteWithErrno:)` → `TerminalEvent.writeFailed(TerminalID, errno:)` → toast. Ölü terminale yapılan yazım sessizce kaybolmaz.

### 4.1 Girdi yönlendirme: `TerminalEventMonitor`

Terminal alt sisteminin **tek** uygulama-seviyesi `NSEvent` monitörü budur (Faz 4.7). Öncesinde `TerminalSessionManager.init` içinde global keyDown/leftMouseDown monitörleri, `DropAwareTerminalView`'da ise N adet wheel/hover monitörü vardı; hepsi tek `@MainActor` tipte toplandı.

- **Enjekte edilir:** `TerminalSessionManager.init(font:eventMonitor:)`. Testler gerçek bir global monitör kurmadan koşabilir (`TerminalEventMonitorTests`).
- **Kapanış simetrisi:** `TerminalSessionControlling.shutdown()` (idempotent) `removeMonitor` çağırır; composition root shutdown yolunda bunu çağırır.
- **`NSEvent` izolasyon sınırından geçirilmez:** her event senkron işlenir, closure'dan yalnız `Bool` (tüketildi mi) döner.
- **Hedef terminal hit-test ile bulunur:** `window.contentView?.hitTest(locationInWindow)` zinciri `DropAwareTerminalView`'a kadar yürütülür. Global bir `TerminalInputGate.shared` bayrağı **yoktur** (kaldırıldı, Faz 4.6): overlay üstteyse hit-test zaten terminale ulaşmaz, dolayısıyla yeni bir görünüm eklendiğinde "kapıyı güncellemeyi unutma" riski yapısal olarak sıfırdır.
- Kart tıklamasında `TerminalViewRegistry.terminalID(for:)` ile çözülen id `TerminalEvent.viewFocused(TerminalID)` olarak yayınlanır (Electron'daki karta-tıkla → setActiveTerminal paritesi); kayıtlı olmayan view sessizce yok sayılır (bayat first-responder koruması).

---

## 5. Gereksinim → mekanizma haritası

[00-architecture.md Ek A](./00-architecture.md)'ün tamamı:

| # | Gereksinim | Bu tasarımdaki mekanizma |
|---|---|---|
| 4.1-1 | Ham çıktı UI state'inde tutulmaz | Ekran modeli yalnız her oturumun `TerminalView`'ındaki `Terminal`'da. `TerminalListStore` yalnız metadata taşır (id, repoPath, status, oscTitle, task, createdAt). `outputs` map'inin karşılığı **yoktur** |
| 4.1-2 | Ack tabanlı flow control | `FlowController` (lock'lu sayaç): io queue'da `noteProduced` → 512 KB'de `.suspend` (DispatchSourceRead kendini durdurur → kernel PTY buffer dolar → yazan bloklanır, sıfır kayıp); MainActor'da senkron `feed` dönüşünde `noteConsumed` → 128 KB'de io queue'ya resume. Suspend/resume yarışı `PTYProcess.resumeRequested` ile kapatılır (§2) |
| 4.1-3 | ~16ms batching, O(chunk) | Terminal başına `OutputCoalescer`: 16ms (yüzey görünmüyorsa 100ms) veya `AdaptiveBatchBudget.threshold`'da (default 128 KB, alt sınır 8 KB) flush; chunk başına değil **flush başına** tek MainActor sıçraması. Her aşama chunk boyutunda lineer; geçmiş yeniden taranmaz (geçmiş yok) |
| 4.1-4 | Sabit kapasiteli ring buffer | Snapshot/replay byte buffer'ı **hiç yok** (replay silindi). Kalan sabit buffer'lar: OSC 4096-char taşıma ve flush'lar arası yeniden kullanılan kapasite-sınırlı coalescer `Data`'sı. (`wait_for` ring'i output fan-out'uyla birlikte kaldırıldı — §3.) String-concat birikimi sıfır |
| 4.1-5 | Sequence-güvenli kesim / emülatör-durum replay'i | **Tercih şıkkı alındı:** kalıcı emülatör durumu byte replay'in yerini tamamen alır. Tüm "kesim", emülatörün kendi satır-tabanlı scrollback tahliyesidir (5000 satır) — asla byte-index kesimi değil. UTF-8 bölünmesi `UTF8StreamDecoder` taşımasıyla |
| 4.1-6 | Detached/görünmeyen terminal politikası | `TerminalSurfaceState` (§3.4): `.background`/`.minimized` = hierarchy dışı; AppKit çizmez; coalescer 100ms'e genişler, durum makinesi blur alır. Sınırlı emülatör state'i "cap'li buffer"dır; attach = reparent + görünürlük sinyali + host'un tek fit'i ("tek snapshot resync"). Parse backpressure döngüsünün içinde kalır |
| 4.1-7 | Terminal başına seri yazım | Tek `@MainActor write()` hunisi → tek serial io queue → tek fd yazarı. Resize aynı queue'da sıralı |
| 4.1-8 | Emülatör iç write buffer'ı sınırlı | SwiftTerm `feed` senkron — sınırlanacak iç bekleyen-yazım kuyruğu yok. Tek ara buffer'lar (coalescer + kuyruktaki flush'lar) in-flight sayacının, dolayısıyla backpressure döngüsünün içinde |
| 4.2-9 | Replay'de oto-yanıt yok; protokol-bilinçli girdi filtresi | Yapısal: replay yolu yok → bayat-sorgu yanıtı üretilemez. `PTYInputFilter` byte-level state machine: `ESC[I/O` daima ayıklanır; `suppressResponses` kapısı gelecekteki canlı-olmayan feed'leri kapsar; `TerminalSessionReattachTests` gerçek `/bin/cat` PTY'sine karşı detach/attach/`refreshAttachedViews` turunda **sıfır** istenmeyen PTY yazımı assert eder |
| 4.2-10 | Donma/crash gözetimi | **Implemente edildi (Faz 4.2, §3.3):** `FeedWatchdog` + `HeartbeatScheduling` + `MonotonicClock`: io queue heartbeat'i (2 sn) in-flight varken 2 sn'lik feed sessizliğini stall sayar → `TerminalEvent.stalled` → `TerminalListStore.stalledIDs` → kart rozeti (siyah ekran yerine görünür durum). Feed süresi `measureFeed` ile ölçülür; >4 ms bütçe aşımı `AdaptiveBatchBudget` üzerinden flush eşiğini yarıya indirir |
| 4.2-11 | Tek paylaşımlı GPU context | CoreText renderer = **sıfır** GPU context (varsayılan). Metal'e geçilirse (yalnız P1/P2 çizim-bağlı çıkarsa) tek paylaşımlı `MTLDevice` zorunlu |
| 4.2-12 | Crash dayanıklılığı + entegrasyon testi | Registry-korumalı teslimat (native `safeSend`: ölü oturum ⇒ drop + suspend kalır); `atexit`/signal `killpg` süpürmesi; oturumlar canlı emülatör state'inden yeniden bağlanır. "View yok edilir → PTY yaşar → reattach → PTY'ye sıfır istenmeyen byte" testi zorunlu ([04 P4](./04-prototype-plan.md)) |
| 4.3 | Korunan korumalar | Scrollback 5000 (`TerminalOptions`); login-shell spawn + komut enjeksiyonu birebir; process-group SIGHUP + atexit süpürme; registry guard = `safeSend` dersi |

---

## 6. Davranış paritesi notları

Aşağıdakiler Electron sürümünden **birebir** taşınır:

- **OSC parser semantiği:** `ESC ] cmd ; payload (BEL | ESC \)` (önce gelen sonlandırıcı); OSC 0/2 → title event (✳ U+2733 prefix = Claude idle/`isWorking=false`; `claude` kelime-sınırı → hint; boş title → karar yok; ilk karakter + boşluk strip paritesi); OSC 9 → `turn/task (complete|completed|done|finished)` regex'i ve `waiting for input` / `all idle` / `idle state` literalleri → `codexTurnComplete`; diğer tüm OSC kodları sessizce düşer; 4096-char partial cap; terminal kapanışında buffer temizliği. **Parite üstü ekleme:** `ClaudeSemantics` OSC 9'da "needs your permission" / `\bpermission\b` kalıbını `.permissionRequest` olarak yorumlar (turn-complete DEĞİL) ve zincirde codex'ten önce sınanır — prompt kuyruğu "karar bekliyor"da duraklar, "turn bitti"de akar (`DecisionTracker`).
- **StatusStateMachine:** 6 durum; `focused × windowFocused` etkin odak; geçiş tablosu (onTitleChange/onOutputActivity/onOutputSilence-3sn/onUserInput/onFocus/onBlur/onWindowFocus/onWindowBlur/onExit/reset) ve "codex hint'i output'la asla düşürülmez" asimetrisi dahil birebir.
- **Provider inference:** input `^claude/^codex`, output `"openai codex"`/`"claude code"`, OSC kaynaklı hint'ler; codex silence heuristiği yalnız hint==codex iken aktif.
- **Exit-cleanup sırası (bug'a duyarlı — Faz 1.5'te fiilen uygulandı):**
  1. io queue'da `TerminalPipeline.prepareForExit()`: watchdog durdur → silence timer iptal → decision tracker sıfırla → coalescer `flushNow()`.
  2. MainActor'a hop; `isTerminated = true` (oturum kayıttan düşmüş sayılır — bayat status push'u yapısal olarak imkânsız).
  3. io queue'da `TerminalPipeline.finishExit(code:)`: `silenceTimer.cancel()` → `oscParser.reset()` → `statusMachine.onExit(code:)`. **Delegate bildiriminden önce sıraya konur.**
  4. `TerminalSessionDelegate.session(_:didExitWithCode:)` → manager oturumu `sessions`'tan çıkarır, `focusedID`'yi temizler, `viewRegistry.unregister(id)` ve `TerminalEvent.exited(id, code:)` yayınlar.
  
  Exit kodu artık yok sayılmaz: `TerminalListStore.isFailureExit(_:)` sıfır olmayan ve kill sinyalinden doğmayan kodları (`normalExitCodes = {0, 129, 143, 137}` dışındakiler, negatif = "çözülemedi") ayırt eder; kullanıcı kapatmadıysa toast basılır.
- **Resize:** `TerminalSession.requestResize(cols:rows:)` içinde 150 ms debounce (`resizeDebounceInterval`, iptal edilebilir `DispatchWorkItem`), cols/rows ≤ 0 ise atla; ayrı bir `ResizeDebouncer` tipi yoktur. Fit'in tek sahibi host'tur (§3.4, [03 §3](./03-ui-shell.md)): attach frame'e dokunmaz, yalnız görünürlük sinyali verir.
- **Spawn limiti:** yok (karar 29) — v1'deki `maxTerminals` ayarı ve limit kontrolü native'e taşınmaz.

---

## 7. Tip envanteri

Modül klasörleri sorumluluğa göre bölünmüştür: `PTY/`, `Parsing/`, `Flow/`, `Status/`, `Input/`, `Session/`.

### Saf, PTY'siz unit-test edilebilir (öncelikli test hedefleri)

| Tip | Yer | Not |
|---|---|---|
| `StatusStateMachine` | `Status/` | 6 durum, geçiş tablosu birebir; exit-sıralaması guard'ı dahil |
| `DecisionTracker` | `Status/` | "karar bekleniyor" bayrağı (`.permissionRequest` ↔ turn-complete) |
| `CodexSilenceTimer` | `Status/` | Injectable scheduler (`OneShotScheduling`); 3 sn; claude-hint'te iptal |
| `OSCStreamParser` | `Parsing/` | Yalnız `OSCRawEvent(code:payload:)`; 4096-char cap; BEL/ST önceliği; `reset()` |
| `OSCSemantics` zinciri | `Parsing/` | `ClaudeSemantics` / `CodexSemantics` / `GenericTitleSemantics` + `OSCSemanticsChain` (ilk-eşleşen-kazanır) |
| `OSCTitleInterpreter` | `Parsing/` | Paylaşılan saf title yorumu (✳ işareti, strip paritesi, `isWorking`) |
| `AgentHint` | `Parsing/` | Açık struct (`.unknown`/`.claude`/`.codex`) |
| `ProviderInferencer` | `Parsing/` | Hint kuralları + asimetri; `CachedRegex` + erken çıkış |
| `CachedRegex` | `Parsing/` | Sıcak yolda regex yeniden derlemesini önler |
| `UTF8StreamDecoder` | `Parsing/` | **Chunk'lar arasında bölünmüş ✳ testi zorunlu** |
| `FlowController` | `Flow/` | Lock'lu sayaç; watermark histerezis testleri |
| `OutputCoalescer` | `Flow/` | Injectable clock → 16 ms / eşik / gizli-aralık politikasının deterministik testi |
| `AdaptiveBatchBudget` | `Flow/` | 4 ms bütçe → yarıya in, kademeli geri aç, alt sınır 8 KB |
| `FeedWatchdog` | `Flow/` | §3.3; `MonotonicClock` + `HeartbeatScheduling` enjekte edilir |
| `PTYInputFilter` | `Input/` | Byte tarayıcı; CSI I/O strip; `suppressResponses` modu |
| `ShellQuoting` | `Input/` | Drag-drop path quote'lama (karar 11) |
| `NaturalEditingKeyMap` | `Input/` | ⌥←/⌥→/⌘← gibi macOS düzenleme tuşlarının PTY karşılığı |
| `ClaudeSessionCommand` | `Session/` | `--session-id` enjeksiyonu / `--resume` (karar 23) |
| `MouseWheelTranslator` | `Session/` | Tekerlek → scroll satırı çevrimi |
| `TerminalGridFit` (LumiKit) | `LumiKit/Support/` | Hücre katına yuvarlama + ortalama; idempotent |

### Entegrasyon katmanı (PTY / AppKit gerektirir)

| Tip | Tür | Not |
|---|---|---|
| `PTYProcess` | final class, `PTYControlling` | §2. CI'da `/bin/cat`'e karşı test edilir (`PTYProcessTests`) |
| `PTYSpawning` / `SystemPTYSpawner` | protokol + struct | Oturumun PTY üretimi dikişi (Faz 4.1) |
| `PTYChildRegistry` | final class, `@unchecked Sendable` | `atexit`/signal süpürmesi; sweep kapasitesi 512, taşmada log |
| `TerminalSession` | `@MainActor` final class | §2.1; `write`/`requestResize`/`setSurfaceState`/`terminate` + metadata |
| `TerminalPipeline` | `@unchecked Sendable` final class | io-queue yarısı; `processOutput`/`processInput`/`applySurfaceState`/`prepareForExit`/`finishExit` |
| `TerminalPresentation` | `@MainActor` final class | Emülatör view'ına giden tek kanal |
| `TerminalSessionManager` | `@MainActor`, `TerminalServicing` | **Sıralı array** registry (Map-insertion-order tuzağı yok); spawn (limitsiz, karar 29), kill/killAll, `setFocused(id?)`, `setWindowFocused(Bool)`, `setSurfaceState`, `shutdown()`; `init(font:eventMonitor:)` |
| `TerminalEventMonitor` | `@MainActor` final class | §4.1; tek NSEvent local monitörü + hit-test |
| `TerminalViewRegistry` | `@MainActor`, `TerminalViewProviding` | View sahipliği + `attachView`/`detachView`/`isAttached`/`detachAll`/`refreshAttachedViews`/`invalidateLayout` ([03 §3](./03-ui-shell.md)) |
| `TerminalViewMaking` / `DropAwareTerminalViewMaker` | protokol + struct | View üretimi dikişi (reattach testinin ön koşulu) |

### Servis yüzeyi (LumiKit `Protocols/TerminalServicing.swift`)

ISP gereği ikiye bölünmüştür (Faz 3.7):

- **`TerminalSessionControlling`** — store'ların gördüğü yüz: `spawn`/`write`/`kill`/`killAll`/`resize`/`setFocused`/`setWindowFocused`/`setSurfaceState(_:for:)`/`setSurfaceState(_:in:)`/`terminals`/`events()`/`shutdown()`.
- **`TerminalAppearanceControlling`** — yalnız composition root'un çağırdığı yüz: `applyFont(_ font: NSFont)`, `applyCursor(shape:blink:)`. Font `NSFont` olarak geçer (aile+boyut primitifleri değil): aile→font çözümlemesi bundle'ın sahibi olan LumiUI'daki `LumiFonts`'tadır, primitif imza LumiTerminal'de ikinci bir kopya doğururdu.
- `TerminalServicing` bu ikisinin `typealias` birleşimidir; somut `TerminalSessionManager` her ikisini uygular.
- **`TerminalViewProviding`** (LumiKit) LumiUI'ın LumiTerminal'i import etmeden host edebilmesi için ayrı yaşar: `attachView(for:into:)`, `detachView(for:from:)`, `isAttached(_:)`, `detachAll()`, `refreshAttachedViews()`.

### Zorunlu testler

| Test | Neyi kilitler |
|---|---|
| `TerminalSessionReattachTests` | Ek A §A.2-12: gerçek `/bin/cat` PTY'si, attach→detach→attach→`refreshAttachedViews`, PTY'ye yazılan byte = 0 |
| `TerminalBackpressureIntegrationTests` | Watermark döngüsü + suspend/resume yarışı (§2) uçtan uca |
| `TerminalPipelineTests` | Orkestrasyon: turn-complete chunk'ta timer resetlenmez, `applyHint` → timer iptali, exit sırası |
| `FeedWatchdogTests` | Stall eşiği, heartbeat, bütçe aşımı → eşik yarıya (§3.3) |
| `TerminalSurfaceStateTests` | Yüzey geçişinin atomikliği: aralık + `onBlur/onFocus` tek adımda (§3.4) |
| `TerminalEventMonitorTests` | Tek monitör, hit-test yönlendirmesi, `shutdown()` simetrisi (§4.1) |

---

## 8. Riskler

| Risk | Hafifletme |
|---|---|
| 12-yönlü flood'da gizli-parse CPU'su | Backpressure üst sınırı koyar; fallback knob'ları: `.background` coalescing 250ms'e, arka plan oturumlarına düşük-watermark önyargısı — mimari değişmez. P1 ölçer |
| SwiftTerm API drift'i (`TerminalViewDelegate.send` kaynak birleştirmesi) | Koşulsuz-filtre tasarımı kaynak ayrımına ihtiyaç duymaz; sürüm pinlenir, gerekirse fork |
| 5000×12 scrollback belleği | P1 ölçer; `TerminalOptions.scrollback` knob'u hazır |
| `feed` main-thread maliyeti | Knob artık otomatik: `FeedWatchdog.measureFeed` + `AdaptiveBatchBudget` 4 ms bütçe aşımında eşiği yarıya indirir (§3.2/§3.3). P2 kalan payı ölçer |
