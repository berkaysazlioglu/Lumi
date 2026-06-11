# Lumi Native — Terminal Alt Sistemi Tasarımı

> `LumiTerminal` modülünün bağlayıcı tasarımı. Davranış kaynağı: [spec/10](../spec/10-main-terminal-pty.md), [spec/20](../spec/20-renderer-terminal.md); zorunlu gereksinimler: [spec/00 §4](../spec/00-overview.md); kök neden analizleri: [spec/40](../spec/40-bug-black-screen.md), [spec/41](../spec/41-bug-stream-oom.md).

---

## 1. Topoloji kararı: kalıcı view-attached emülatör (Seçenek A)

**Karar:** Oturum başına, PTY ömrü boyunca yaşayan **tek bir SwiftTerm `TerminalView`**. View'ı `TerminalViewRegistry` (@MainActor) sahiplenir; SwiftUI asla sahip olmaz. Görünmediğinde hierarchy'den ayrılır/gizlenir ama **asla yok edilmez**. Emülatörün grid + scrollback + mod state'i, oturumun ekran durumunun otoriter kaynağıdır.

**Sonuç:** Byte backlog, replay ve reconciliation protokolünün tamamı (**`syncFromMain` / `mergeSnapshotOutput` / `totalLength` / `epoch` / `preserveNewerLiveOutputs`**) silinir — [spec/21](../spec/21-renderer-state.md)'in iki-process yarışı telafisi tek process'te gereksizleşir ([spec/00 §5](../spec/00-overview.md) bunu öngörür).

**Reddedilen Seçenek B (headless `Terminal` + ayrı render view replikasyonu):** SwiftTerm'de `TerminalView` kendi gömülü `Terminal`'ını sahiplenir; harici bir `Terminal`'ın buffer'ını bir view'a çizdirmenin desteklenen yolu yoktur. B'yi seçmek şunlardan birini zorlar: (a) `TerminalView` renderer'ını fork'lamak, (b) emülatör state'ini byte'a geri serileştirip view tarafındaki ikinci emülatöre beslemek — ki bu, rewrite'ın yok etmek için var olduğu replay makinesini (ve bug 40'ın oto-yanıt tehlikesini) geri getirir, (c) özel renderer yazmak. Üçü de, artık var olmayan bir renderer/main process ayrımını çözmek için satın alınan en pahalı yollardır.

**A'nın gereksinimleri savuşturmadan karşıladığının gerekçesi:**
- §4.1-5'in tercih şıkkı ("replay ham byte yerine emülatör durumu") **yapısal olarak** karşılanır: replay adımı hiç yoktur. Attach = state'i hiç kaybolmamış bir NSView'ı görünür kılmak.
- §4.2-9 **yapısal olarak** karşılanır: oto-yanıtlar (CPR/DA/DECRQM) yalnızca **canlı** sorgulara üretilir — ki o durumda PTY'ye gitmeleri doğrudur. Tarihsel byte'lar asla yeniden beslenmediği için bayat-sorgu yanıtı üretilemez. (Defense-in-depth kapısı yine vardır, §4.)
- §4.1-6'nın amacı (görünmeyen terminale sınırsız buffer/render maliyeti yok): gizli NSView çizilmez; emülatörün satır-sınırlı (5000) scrollback'i "cap'li buffer"ın kendisidir; "attach'te tek snapshot resync", mevcut state'ten tek çizim geçişine indirgenir. Gizli oturumlarda coalescing aralığı genişler (§3) — main-thread uyanması ~6× düşer. Kalan maliyet (gizli terminal için parse-only `feed`) O(chunk)'tır ve aynı backpressure döngüsüyle sınırlıdır.
- Bug 40'ın `display:none` + WebGL-context-evict modu taşınmaz: CoreText render GPU context kullanmaz (§4.2-11), AppKit gizli view state'ini "evict" etmez.

**Maliyet:** En kötü durumda grid belleği ≈ 120 sütun × 5000 satır × ~16 B/hücre ≈ ~10 MB/terminal → 12 terminalde ~120 MB (scrollback satırları lazy ayrılır; tipik değer çok daha düşük). P1 prototipi bunu ölçer ([04](./04-prototype-plan.md)).

---

## 2. PTY katmanı: `PTYProcess`

SwiftTerm `LocalProcess` **kullanılmaz** (gerekçe: [00 §1 T2](./00-architecture.md)). ~200 satırlık kendi wrapper'ımız:

```swift
final class PTYProcess {
    init(executable: String, args: [String], cwd: String,
         env: [String: String], initialSize: (cols: UInt16, rows: UInt16)) throws

    enum ReadDirective { case `continue`, suspend }
    func startReading(on queue: DispatchQueue,
                      handler: @escaping (Data) -> ReadDirective)
    func resumeReading()            // her queue'dan güvenli; içeride dengelenir
    func write(_ bytes: Data)       // io queue'da çağrılmalı (assert'li)
    func resize(cols: UInt16, rows: UInt16)   // ioctl(TIOCSWINSZ) → SIGWINCH
    var onExit: ((Int32) -> Void)?  // DispatchSourceProcess(.exit), io queue'da
    func terminate()                // killpg(pid, SIGHUP); 3 sn sonra hâlâ canlıysa SIGKILL
}
```

İmplementasyon notları:

- `forkpty` çağrısı için SwiftTerm `PseudoTerminalHelpers` referans alınabilir; bizim kattığımız değer dispatch-source yaşam döngüsüdür.
- **Okuma:** master fd üzerinde `DispatchSourceRead`, terminal başına serial queue. Handler tek non-blocking `read()` (≤64 KB) yapar. `.suspend` dönerse source **kendini** suspend eder (eşzamanlı-suspend yarışı yok); `resumeReading()` lock altındaki `isSuspended` bayrağıyla dengeyi korur.
- **Spawn paritesi ([spec/10](../spec/10-main-terminal-pty.md)):** shell seçim zinciri (macOS: `zsh → bash → sh`, `which` ile doğrulanır, process ömrü boyunca cache), her zaman `<shell> -l` (login); `claude`/`codex` PTY argv'si değil, sonradan `write()` ile enjekte edilir. `TERM=xterm-256color`, başlangıç 120×30, `cwd: repoPath`, env = `fixProcessPath` sonucu.
- **Crash dayanıklılığı:** global, lock-korumalı child-pid registry + `atexit`/`SIGTERM` handler'ı `killpg` döngüsü (async-signal-safe) — yakalanmamış crash'te bile zombi `claude` ağacı kalmaz (§4.3).

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
    → OSCStreamParser.feed(decoded)          // OSC 0/2/9; 4096-char partial cap; BEL/ST
    │     └─ event'ler → StatusStateMachine (BURADA, io queue'da koşar)
    │           └─ durum değişimi → DispatchQueue.main.async → metadata publish + Notifier
    → CodexSilenceTimer.touch()              // 3 sn DispatchSourceTimer, aynı queue
    → OutputCoalescer.ingest(rawBytes)       // HAM byte — emülatör byte ister
         └─ flush koşulu: ilk byte'tan beri 16ms (view gizliyse 100ms) VEYA ≥128KB

[flush → DispatchQueue.main.async, flush başına tek Data]
  @MainActor TerminalSession.deliver(batch)
    → registry guard: oturum canlı mı? (native safeSend) — ölüyse sessiz drop,
      PTY oturum/view kurtarılana dek suspend kalır
    → terminalView.feed(byteArray: batch)    // SENKRON parse; SwiftTerm fiili çizimi
    │                                        // kendi frame'ler; gizli view: yalnız parse
    → ack: FlowController.noteConsumed(batch.count)
         └─(LOW 128KB altına indi)──▶ ioQueue.async { pty.resumeReading() }
```

**Ack'in SwiftTerm'in senkron feed'iyle çalışması:** `Terminal.feed` byte'lar grid'e tamamen işlendikten sonra döner — xterm.js'in aksine **iç async write kuyruğu yoktur** (bu, §4.1-8'i bedavaya çözer). "Tüketildi" = "feed döndü". *In-flight* = fd'den okunmuş ama henüz feed edilmemiş byte'lar: coalescer içeriği + main queue'da bekleyen batch'ler. `FlowController`, io queue'dan (produce) ve MainActor'dan (consume) dokunulan `OSAllocatedUnfairLock` korumalı küçük bir sayaçtır. High/low = terminal başına **512 KB / 128 KB** → 12 terminalde toplam in-flight bellek ≤ 6 MB, hard-bounded.

**Chunk başına maliyet her aşamada O(chunk)** (decoder, sınırlı-taşımalı OSC taraması, coalescer append, feed) — hiçbir aşama birikmiş geçmişi yeniden taramaz; emülatör dışında birikmiş geçmiş **yoktur** (§4.1-3).

**Hiçbir yerde byte backlog buffer'ı yoktur.** Tutulan tek metin artefaktları: emülatör scrollback'i (5000 satır, `TerminalOptions`), OSC parser'ın 4096-char partial taşıması ve ActionEngine'in `wait_for` regex'i için **4 KB sabit rolling ring** (tek-chunk eşleşme bug'ının spec-önerili düzeltmesi). Electron'un 500 KB tail cap'i yalnız snapshot replay'i beslemek için vardı; replay yokken parite garantisi scrollback-5000'dir.

**Output fan-out:** Decode edilmiş chunk'lar ayrıca oturum başına `AsyncStream<String>` (`.bufferingNewest`, sınırlı) ile yayınlanır — ActionEngine `wait_for` tüketicisi; tüketici yavaşlığı terminali asla durduramaz, 4 KB ring drop'a toleranslıdır.

---

## 4. Yazma yolu

PTY'ye giden **tüm** byte'lar tek metodda toplanır, sonra tek serial queue'dan akar:

```
klavye / IME / paste ──▶ TerminalViewDelegate.send(source:data:)     ┐
SwiftTerm oto-yanıtları (CPR/DA/DECRQM/mouse — view iletir)          ┤
ActionEngine write step'leri (\r-sonlu)                              ├─▶ @MainActor
Persona spawn komut enjeksiyonu                                      ┤   TerminalSession.write(_:)
drag-drop path (quote'lanmış — karar 11)                             ┘
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

---

## 5. Gereksinim → mekanizma haritası

[spec/00 §4](../spec/00-overview.md)'ün tamamı:

| # | Gereksinim | Bu tasarımdaki mekanizma |
|---|---|---|
| 4.1-1 | Ham çıktı UI state'inde tutulmaz | Ekran modeli yalnız her oturumun `TerminalView`'ındaki `Terminal`'da. `TerminalListStore` yalnız metadata taşır (id, repoPath, status, oscTitle, task, createdAt). `outputs` map'inin karşılığı **yoktur** |
| 4.1-2 | Ack tabanlı flow control | `FlowController` (lock'lu sayaç): io queue'da `noteProduced` → 512 KB'de `.suspend` (DispatchSourceRead kendini durdurur → kernel PTY buffer dolar → yazan bloklanır, sıfır kayıp); MainActor'da senkron `feed` dönüşünde `noteConsumed` → 128 KB'de io queue'ya resume |
| 4.1-3 | ~16ms batching, O(chunk) | Terminal başına `OutputCoalescer`: 16ms (gizli 100ms) veya 128 KB'de flush; chunk başına değil **flush başına** tek MainActor sıçraması. Her aşama chunk boyutunda lineer; geçmiş yeniden taranmaz (geçmiş yok) |
| 4.1-4 | Sabit kapasiteli ring buffer | Snapshot/replay byte buffer'ı **hiç yok** (replay silindi). Kalan sabit buffer'lar: OSC 4096-char taşıma, ActionEngine 4 KB `wait_for` ring'i, flush'lar arası yeniden kullanılan kapasite-sınırlı coalescer `Data`'sı. String-concat birikimi sıfır |
| 4.1-5 | Sequence-güvenli kesim / emülatör-durum replay'i | **Tercih şıkkı alındı:** kalıcı emülatör durumu byte replay'in yerini tamamen alır. Tüm "kesim", emülatörün kendi satır-tabanlı scrollback tahliyesidir (5000 satır) — asla byte-index kesimi değil. UTF-8 bölünmesi `UTF8StreamDecoder` taşımasıyla |
| 4.1-6 | Detached/görünmeyen terminal politikası | Gizli = hierarchy dışı/`isHidden`, frame senkron tutulur; AppKit çizmez; coalescer 100ms'e genişler. Sınırlı emülatör state'i "cap'li buffer"dır; attach = göster + tek çizim + visible-fit ("tek snapshot resync"). Parse backpressure döngüsünün içinde kalır |
| 4.1-7 | Terminal başına seri yazım | Tek `@MainActor write()` hunisi → tek serial io queue → tek fd yazarı. Resize aynı queue'da sıralı |
| 4.1-8 | Emülatör iç write buffer'ı sınırlı | SwiftTerm `feed` senkron — sınırlanacak iç bekleyen-yazım kuyruğu yok. Tek ara buffer'lar (coalescer + kuyruktaki flush'lar) in-flight sayacının, dolayısıyla backpressure döngüsünün içinde |
| 4.2-9 | Replay'de oto-yanıt yok; protokol-bilinçli girdi filtresi | Yapısal: replay yolu yok → bayat-sorgu yanıtı üretilemez. `PTYInputFilter` byte-level state machine: `ESC[I/O` daima ayıklanır; `suppressResponses` kapısı gelecekteki canlı-olmayan feed'leri kapsar; entegrasyon testi detach/attach boyunca sıfır istenmeyen PTY yazımı assert eder |
| 4.2-10 | Donma/crash gözetimi | `FeedWatchdog`: background heartbeat → MainActor ping; >2 sn stall → log + bayrak; flush başına feed süresi ölçülür, >4ms bütçe aşımı flush eşiğini küçültür. UI'da "yeniden bağlanıyor" durumu siyah ekran yerine |
| 4.2-11 | Tek paylaşımlı GPU context | CoreText renderer = **sıfır** GPU context (varsayılan). Metal'e geçilirse (yalnız P1/P2 çizim-bağlı çıkarsa) tek paylaşımlı `MTLDevice` zorunlu |
| 4.2-12 | Crash dayanıklılığı + entegrasyon testi | Registry-korumalı teslimat (native `safeSend`: ölü oturum ⇒ drop + suspend kalır); `atexit`/signal `killpg` süpürmesi; oturumlar canlı emülatör state'inden yeniden bağlanır. "View yok edilir → PTY yaşar → reattach → PTY'ye sıfır istenmeyen byte" testi zorunlu ([04 P4](./04-prototype-plan.md)) |
| 4.3 | Korunan korumalar | Scrollback 5000 (`TerminalOptions`); login-shell spawn + komut enjeksiyonu birebir; process-group SIGHUP + atexit süpürme; registry guard = `safeSend` dersi |

---

## 6. Davranış paritesi notları

Aşağıdakiler [spec/10](../spec/10-main-terminal-pty.md)'dan **birebir** taşınır:

- **OSC parser semantiği:** `ESC ] cmd ; payload (BEL | ESC \)` (önce gelen sonlandırıcı); OSC 0/2 → title event (✳ U+2733 prefix = Claude idle/`isWorking=false`; `claude` kelime-sınırı → hint; boş title → karar yok; ilk karakter + boşluk strip paritesi); OSC 9 → `turn/task (complete|completed|done|finished)`, `waiting for input`, `all idle`, `idle state` regex'i → `codex-turn-complete`; diğer tüm OSC kodları sessizce düşer; 4096-char partial cap; terminal kapanışında buffer temizliği.
- **StatusStateMachine:** 6 durum; `focused × windowFocused` etkin odak; geçiş tablosu (onTitleChange/onOutputActivity/onOutputSilence-3sn/onUserInput/onFocus/onBlur/onWindowFocus/onWindowBlur/onExit/reset) ve "codex hint'i output'la asla düşürülmez" asimetrisi dahil birebir.
- **Provider inference:** input `^claude/^codex`, output `"openai codex"`/`"claude code"`, OSC kaynaklı hint'ler; codex silence heuristiği yalnız hint==codex iken aktif.
- **Exit-cleanup sırası (spec/10 §9, bug'a duyarlı):** (1) timer iptal → (2) registry'den çıkar (**status machine exit'i işlemeden ÖNCE** — bayat status push'u engeller) → (3) `notifier.terminalRemoved` → (4) `statusMachine.onExit(code)` → (5) OSC buffer sil → (6) exit yayınla.
- **Resize:** view tarafında 150ms debounce (`ResizeDebouncer`), cols/rows 0/undefined ise atla; gizliyken fit yapılmaz, attach'te fit zorunlu (TUI reflow paritesi).
- **Spawn limiti:** yalnız `TerminalService` uygular (renderer'daki sabit-kullanan üç call-site bug'ı taşınmaz — karar 11); aşım `LumiError.terminalLimitReached` ile **görünür** hata (karar 5).

---

## 7. Tip envanteri

### Saf, PTY'siz unit-test edilebilir (öncelikli test hedefleri)

| Tip | Tür | Not |
|---|---|---|
| `StatusStateMachine` | struct/final class | Geçiş tablosu birebir; exit-sıralaması guard'ı dahil |
| `OSCStreamParser` | final class | Decode edilmiş string girdisi; §6'daki semantik; BEL/ST önceliği |
| `ProviderInferencer` | struct | Hint kuralları + asimetri |
| `PTYInputFilter` | struct (stateful) | Byte tarayıcı; CSI I/O strip; `suppressResponses` modu |
| `OutputCoalescer` | final class | Injectable clock → 16ms/128KB/gizli-aralık politikasının deterministik testi |
| `FlowController` | final class | Lock'lu sayaç; watermark histerezis testleri |
| `UTF8StreamDecoder` | struct | **Chunk'lar arasında bölünmüş ✳ testi zorunlu** |
| `CodexSilenceTimer` | final class | Injectable scheduler; 3 sn; claude-hint'te iptal |
| `ResizeDebouncer` | struct | 150ms |
| `AgentCommandBuilder` | struct | `buildAgentCommand` portu; temp-dir protokolü verildiğinde saf ([02 §6](./02-services.md)) |

### Entegrasyon katmanı (PTY / AppKit gerektirir)

| Tip | Tür | Not |
|---|---|---|
| `PTYProcess` | final class | §2. CI'da `/bin/cat`'e karşı test edilebilir |
| `TerminalSession` | `@MainActor` final class | Bir `PTYProcess` + io queue + pipeline + `LumiTerminalView: TerminalView` sahibi; `TerminalViewDelegate` implementasyonu; `write`/`resize`/`setHidden`/`kill` + metadata |
| `TerminalSessionManager` | `@MainActor`, `TerminalServicing` implementasyonu | **Sıralı array** registry (Map-insertion-order tuzağı yok); spawn (`maxTerminals` aşımında throw), kill/killAll, `setFocused(id?)`, `setWindowFocused(Bool)` |
| `TerminalViewRegistry` | `@MainActor`, `TerminalViewProviding` | View sahipliği + attach/detach ([03 §3](./03-ui-shell.md)) |
| `FeedWatchdog` | final class | §5 / 4.2-10 |

---

## 8. Riskler

| Risk | Hafifletme |
|---|---|
| 12-yönlü flood'da gizli-parse CPU'su | Backpressure üst sınırı koyar; fallback knob'ları: gizli coalescing 250ms'e, gizli oturumlara düşük-watermark önyargısı — mimari değişmez. P1 ölçer |
| SwiftTerm API drift'i (`TerminalViewDelegate.send` kaynak birleştirmesi) | Koşulsuz-filtre tasarımı kaynak ayrımına ihtiyaç duymaz; sürüm pinlenir, gerekirse fork |
| 5000×12 scrollback belleği | P1 ölçer; `TerminalOptions.scrollback` knob'u hazır |
| `feed` main-thread maliyeti | P2 ölçer; flush boyut eşiği knob'u (>4ms'de küçült) |
