# 40 — Bug: Siyah Ekran + Kurtarma Sonrası Terminale "Random Karakter" Basılması

## Belirti

- Uygulama tamamen crash olmuyor; ekran birkaç saniye siyaha dönüyor, terminaller görünmüyor.
- Birkaç saniye sonra UI kendine geliyor; geldiğinde terminallerde kullanıcının yazmadığı "random karakterler" basılmış oluyor ("hata sırasında çıkan şeyler terminale kayıyor gibi").
- 04009f6 commit'i (renderer output cap) OOM crash'lerini azaltmayı hedefledi ama belirti zinciri devam ediyor.

## Kök neden hipotezi (kanıtlarla)

Tek bir bug değil, dört halkalı bir zincir: **(1) renderer'ı donduran/öldüren bellek baskısı → (2) siyah ekran penceresi → (3) reload sonrası backlog replay'i → (4) replay'in xterm.js üzerinden PTY'ye "cevap" yazması = random karakterler.**

### Halka 1 — Bellek baskısı: PTY chunk'ı başına O(500KB) string yeniden inşası + Map kopyası + React re-render

- `src/renderer/stores/useTerminalStore.ts:47-57` — `appendTerminalOutput` her PTY chunk'ında `base.text + chunk` ile **500KB'a kadar yeni bir string** üretip `trimOutputTail` ile tekrar kesiyor. Cap OOM'u engelliyor ama chunk başına ~1MB geçici allocation (eski + yeni string) yaratıyor.
- `src/renderer/stores/useTerminalStore.ts:277-283` — `appendOutput` her chunk'ta `new Map(state.outputs)` kopyası + Zustand `set` → her PTY chunk'ı bir React render turu tetikliyor.
- 12 terminale kadar (TerminalManager.ts:27 `maxTerminals=12`) yoğun çıktıda saniyede yüzlerce chunk × ~1MB allocation = V8 major GC fırtınası. Renderer main thread saniyeler boyunca duraklıyor (henüz crash yok) ya da en kötü durumda yine OOM ile `render-process-gone`'a düşüyor.
- Yani "tamamen crash olmuyor ama donuyor" gözlemi GC duraklamaları; "bazen reload oluyor" gözlemi OOM dalı. İkisi de aynı kaynaktan.

### Halka 2 — Siyah ekran

- `src/main/index.ts:58` — `backgroundColor: '#0a0a12'`: renderer öldüğünde/çizemediğinde pencere neredeyse siyah düz renge düşüyor.
- `src/main/index.ts:171-180` — `render-process-gone` handler'ı sadece `crashed`/`oom` için **1 saniye bekleyip** `webContents.reload()` çağırıyor. 1 sn gecikme + bundle load + `Layout` init + `syncFromMain` = kullanıcının gördüğü "birkaç saniye siyah ekran".
- `unresponsive` event handler'ı **yok** (repo genelinde tek eşleşme yok); GPU process için `child-process-gone` handler'ı da yok. Renderer donduğunda (crash olmadan) main process hiçbir kurtarma yapmıyor — kullanıcı donmuş/siyah compositing'e bakıyor.
- `src/renderer/components/Terminal/hooks/useXTermInstance.ts:48-54` — **her terminal kartı kendi WebGL context'ini açıyor** ve kartlar repo değişiminde unmount edilmiyor (`display:none`, components/CLAUDE.md). Tarayıcı WebGL context limiti ~16; bellek baskısında GPU context'leri evict edilir → `onContextLoss` addon'u dispose eder → terminal canvas'ları crash olmadan kararır. "Crash yok ama terminaller görünmüyor" senaryosunun ikinci açıklaması.

### Halka 3 — Reload sonrası backlog replay'i

- `src/renderer/components/Layout/Layout.tsx:71` — mount'ta `await syncFromMain()`.
- `src/main/terminal/TerminalManager.ts:199-210` — `getTerminalSnapshots()` her terminal için `outputBuffer.get()` ile **500KB'a kadar ham ANSI backlog'unu** döndürüyor (PTY'ler main'de yaşamaya devam ettiği için crash sırasında biriken her şey dahil; `safeSend.ts:20` sayesinde crash–reload arasında IPC'ye gitmeyen çıktı da buffer'da).
- `src/renderer/stores/useTerminalStore.ts:63-69` — taze renderer'da `current` boş olduğundan snapshot komple alınır, `epoch+1` → `useTerminalOutputRenderer.ts:36` `replace` patch'i → `useTerminalOutputRenderer.ts:59-63` `xterm.clear()` + `writeChunked` ile **ham backlog olduğu gibi xterm'e yeniden yazılır.**

### Halka 4 — "Random karakterler": replay'in PTY'ye geri yazılması (asıl tetik)

- `src/renderer/components/Terminal/hooks/useXTermInstance.ts:91-93`:
  ```ts
  xterm.onData((data) => {
    window.api.writeTerminal(terminalId, data)
  })
  ```
  xterm.js'in `onData`'sı **sadece klavye girdisi değil**, terminalin protokol gereği ürettiği otomatik yanıtları da emit eder: DSR/CPR (`\x1b[6n` → `\x1b[<row>;<col>R`), Primary/Secondary DA (`\x1b[c` → `\x1b[?…c`), DECRQM yanıtları, mouse-tracking raporları vb.
- Claude Code / Codex gibi TUI'lar normal çalışırken bu sorguları (DSR, DA, mod sorguları) çıktı akışına yazar; bunlar `OutputBuffer`'da saklanır. Reload sonrası bu **eski sorgular xterm'e yeniden oynatılınca xterm her birine yeniden cevap üretir** ve `onData` → `writeTerminal` → `TerminalManager.write` → `pty.write` zinciriyle canlı PTY'ye gönderir.
- `src/main/terminal/TerminalManager.ts:139-144` — `write()` yalnızca focus event'lerini (`\x1b[I`, `\x1b[O`) filtreliyor; CPR/DA yanıtları aynen geçer. O anda kimse bu yanıtları beklemediği için shell/TUI bunları **klavye girdisi sanıp echo'lar** → terminalde `;12R`, `?1;2c` benzeri "random karakterler". Bu, "hata sırasında çıkan şeylerin terminale kayması" gözleminin birebir mekanizması.
- Ek olarak backlog içindeki mod-set sekansları (`\x1b[?1000h` mouse tracking, `\x1b[?2004h` bracketed paste, `\x1b[?1049h` alt screen) replay'de xterm'de yeniden etkinleşir; kullanıcı mouse'u oynattığında xterm mouse raporları üretip yine PTY'ye yazar — ikinci bir çöp-karakter kaynağı.
- Aynı replay yolu yalnızca crash'te değil, her `replace` patch'inde (uyku/uyanma sync'i, diverged buffer — `mergeSnapshotOutput` epoch bump dalları `useTerminalStore.ts:68, 90`) tetiklenebilir; belirtinin "bazen" olması bununla tutarlı.

### Destekleyici kusur — Trim'in escape sequence / surrogate ortasından kesmesi

- `src/shared/output-trim.ts:18-26` — kesim noktası `\n` aranarak seçiliyor ama arama penceresi 2048 karakter; pencerede `\n` yoksa (**alt-screen TUI çıktısı newline yerine cursor adresleme kullanır, tipik durum budur**) kesim **rastgele UTF-16 code-unit indeksinden** yapılır:
  - Kesim bir ANSI escape sequence'ın ortasına denk gelirse replay edilen buffer yarım `\x1b[...` parametresiyle başlar → xterm kalan baytları **düz metin olarak basar** = çöp karakterler.
  - Kesim bir surrogate pair'in ortasına denk gelirse (emoji, CJK) lone surrogate → U+FFFD.
  - `\n` bulunsa bile kesilen baştaki kısım SGR/alt-screen/scroll-region durumunu kuran sekansları içerir; tail tek başına replay edildiğinde görsel durum tutarsızdır (`xterm.clear()` modları sıfırlamaz — `useTerminalOutputRenderer.ts:60`).
- `src/renderer/components/Terminal/utils.ts:16` — `writeChunked` 10.000 code-unit sınırından `slice` yapıyor; escape sequence bölünmesini xterm'in stateful parser'ı tolere eder ama **surrogate pair bölünmesi** ayrı `write()` çağrılarında U+FFFD üretir.
- Chunk sıra/bütünlük garantisi: aynı `webContents.mainFrame.send` kanalında IPC sıralıdır ve node-pty `StringDecoder` ile multibyte'ı chunk sınırında doğru birleştirir; canlı akışta sıra bozulması beklenmez. Sorun canlı akışta değil, **trim ve snapshot-replay** noktalarında.

### Zincirin özeti

Yoğun PTY çıktısı → renderer GC fırtınası/donması (veya OOM) → siyah pencere (1 sn'lik reload gecikmesi + `#0a0a12` arka plan; donma durumunda handler hiç yok) → reload'da 500KB ham backlog (trim yüzünden ortasından kesilmiş olabilir) xterm'e replay → xterm backlog'daki DSR/DA sorgularına yeniden cevap üretir → cevaplar `onData` ile canlı PTY'ye yazılır → TUI/shell bunları girdi sanır ve echo'lar → "random karakterler".

## Native rewrite için gereksinimler

1. **Replay ile canlı girdiyi ayır:** Terminal emülatör katmanı, snapshot/backlog replay'i sırasında üretilen otomatik yanıtları (CPR, DA, DECRQM, mouse raporları) PTY'ye **asla** yazmamalı. Replay "girdi kapalı" modda yapılmalı veya tarihsel içerik sorgu-yanıt üretmeyen bir yolla (ör. ekran durumunun serileştirilmesi) geri yüklenmeli.
2. **Buffer yerine terminal state snapshot'ı:** Ham ANSI byte backlog'u saklayıp yeniden oynatmak yerine, ana süreçte (native tarafta) kalıcı bir headless terminal state machine (grid + scrollback + modlar) tutulmalı; UI yeniden bağlandığında byte replay değil **render edilebilir state** aktarılmalı. Bu, trim/mid-sequence kesme sınıfı bugları kökten yok eder.
3. **Trim yapılacaksa sequence-safe yapılmalı:** Herhangi bir byte-buffer kesimi ANSI escape sequence ve UTF-8/UTF-16 karakter sınırlarına saygılı olmalı; alt-screen (newline'sız) çıktı için fallback "rastgele indeksten kes" davranışı yasak.
4. **Backpressure + chunk başına O(1) maliyet:** PTY çıktısı UI thread'inde chunk başına buffer kopyası/re-render tetiklememeli. Ring buffer / rope yapısı, üretici-tüketici backpressure (PTY pause/resume) ve frame başına birleştirilmiş (coalesced) render gerekli.
5. **Donma/crash gözetimi:** UI süreci için `unresponsive` eşdeğeri watchdog, GPU/compositor kaybı için kurtarma yolu ve kurtarma sırasında kullanıcıya siyah ekran yerine durum göstergesi ("yeniden bağlanıyor…") sağlanmalı.
6. **GPU context bütçesi:** Terminal başına ayrı GPU context açılmamalı; tek paylaşımlı renderer/atlas ile N terminal çizilmeli (context limiti ve evict kaynaklı kararma riski sıfırlanır).
7. **Girdi filtresi protokol-bilinçli olmalı:** PTY'ye giden veri yolunda yalnızca regex ile focus-event ayıklamak yerine, hangi sekansların gerçek kullanıcı girdisi olduğu ayrımı yapılmalı (replay kaynaklı yanıtlar işaretlenip düşürülmeli).
8. **Kurtarma senaryosu test edilmeli:** "Renderer ölür → PTY'ler yaşar → UI yeniden bağlanır" akışı için entegrasyon testi: yeniden bağlanma sonrası PTY'ye hiçbir istenmeyen byte yazılmadığı ve görüntünün bozulmadığı doğrulanmalı.
