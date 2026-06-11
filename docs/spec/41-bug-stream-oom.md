# Bug 41 — Terminal Stream OOM (V8 Renderer Crash)

## Belirti

Bir terminalde yoğun çıktı üreten bir süreç çalıştığında (ör. büyük bir dosyanın `cat`'lenmesi, verbose build/test çıktısı, agent CLI'larının uzun stream'leri) renderer process'i V8 "JavaScript heap out of memory" hatasıyla çöküyordu. Çökme sonrası recovery reload'a kadar PTY çıktısı akmaya devam ettiği için main process konsolu "Error sending from webFrameMain" hatalarıyla doluyordu.

## Kök neden

### Veri yolu (uçtan uca)

```
node-pty onData (string chunk)
  └─ src/main/terminal/TerminalManager.ts:77   ptyProcess.onData(...)
      ├─ :115  terminal.outputBuffer.append(data)      → main tarafı 500KB cap'li (OutputBuffer)
      └─ :117  safeSend(window, TERMINAL_OUTPUT, id, data)  → chunk başına 1 IPC mesajı
preload
  └─ src/preload/index.ts:26  onTerminalOutput → createIpcListener(TERMINAL_OUTPUT)
renderer
  └─ src/renderer/stores/useTerminalStore.ts:312-313  bridge → appendOutput(id, data)
      └─ zustand set: her chunk'ta yeni Map + string append
  └─ src/renderer/components/Terminal/hooks/useTerminalOutputRenderer.ts
      └─ React effect → computeOutputPatch → xterm.write / writeChunked
```

### Sınırsız birikim nerede oluyordu?

İki katmanlı bir asimetri vardı: **main process'teki `OutputBuffer` 500KB ile cap'liyken, renderer tarafı hiç cap'lemiyordu.**

1. **Sınırsız store buffer'ı** — fix öncesi `useTerminalStore.appendTerminalOutput`:
   ```ts
   export function appendTerminalOutput(current: string, chunk: string): string {
     return current + chunk
   }
   ```
   `outputs: Map<string, string>` içindeki string her chunk'ta büyüyordu; hiçbir trim yoktu. Saatlerce çalışan ya da yoğun çıktı basan bir terminal için bu, yüzlerce MB'lık tek bir JS string'i demekti.

2. **Chunk başına O(n) tarama + ikinci tam kopya** — fix öncesi `computeOutputPatch(previous, next)`:
   ```ts
   if (previous.length > 0 && next.startsWith(previous)) {
     return { kind: 'append', chunk: next.slice(previous.length) }
   }
   ```
   Her chunk'ta tüm birikmiş çıktı üzerinde `startsWith` taraması (O(n)) yapılıyor ve `renderedOutputRef.current = output` ile **tam bir referans kopyası daha** tutuluyordu. Toplam maliyet O(n²); V8 string concat'leri rope/flatten döngüsüne girip allocation fırtınası yaratıyordu. OOM'a giden asıl mekanizma bu ikilinin birleşimiydi: sınırsız büyüyen string × chunk başına tam tarama/kopya.

3. **İkincil etkenler:**
   - Her chunk'ta `new Map(state.outputs)` + zustand `set` → her PTY chunk'ı bir React render turu tetikliyordu.
   - Chunk başına 1 IPC mesajı (batching yok) → renderer event loop'u doygunluğa ulaşıp GC'ye nefes aldırmıyordu.
   - Hiçbir backpressure yok: PTY okuma hızı, renderer'ın tüketme hızından tamamen bağımsızdı.

## Mevcut fix analizi

Commit: `04009f6` — "fix: cap renderer terminal output to prevent V8 OOM crashes" (branch `fix/terminal-output-oom`).

### Yaklaşım

1. **Renderer buffer cap'i** — `src/renderer/stores/useTerminalStore.ts:9` `RENDERER_OUTPUT_MAX_SIZE = 500_000`; `appendTerminalOutput` artık `trimOutputTail(base.text + chunk, ...)` ile cap'liyor. Trim mantığı `src/shared/output-trim.ts`'e taşındı ve main'in `OutputBuffer`'ı ile paylaşılıyor (DRY).
2. **Offset tabanlı delta render** — `TerminalOutput { text, totalLength, epoch }`: `totalLength` monoton mutlak stream offset'i, `epoch` non-incremental rewrite sinyali. `computeOutputPatch` artık string karşılaştırması değil, `delta = output.totalLength - rendered.totalLength` aritmetiği ile O(delta) çalışıyor (`useTerminalOutputRenderer.ts:33-50`). `delta > text.length` veya epoch değişimi → `replace` (xterm.clear + tail rewrite).
3. **Race koruması** — `preserveNewerLiveOutputs` (`useTerminalStore.ts`): `syncFromMain` IPC'si uçuştayken gelen canlı `appendOutput`'lar, snapshot commit'i tarafından ezilip `totalLength`'in geri sarmasını (ve yıkıcı redraw'u) engelliyor.
4. **safeSend sertleştirmesi** — `src/main/safeSend.ts`: `webContents.isDestroyed() || webContents.isCrashed()` kontrolü; crash ile recovery reload arasında PTY çıktısının konsolu floodlamasını kesiyor.

### Sınırları

- **Semptomu cap'liyor, akışı kontrol etmiyor.** Chunk başına IPC mesajı, chunk başına zustand `set` + Map kopyası + React render turu aynen duruyor. Bellek artık patlamıyor ama CPU/IPC baskısı değişmedi.
- **Veri kaybı:** 500KB cap'i aşıldığında baş taraf atılıyor. Canlı `append` akışında xterm kendi 5000 satırlık scrollback'ini koruduğu için kullanıcı bunu hemen hissetmez; ama her `replace` (epoch bump, snapshot diverge, store reset) `xterm.clear()` yapıp **yalnızca cap'li 500KB tail'i** yeniden yazar — scrollback'in geri kalanı kalıcı olarak gider.
- **Escape-sequence güvenliği sadece sezgisel:** `trimOutputTail` (`src/shared/output-trim.ts:11-27`) kesim noktasını 2048 karakterlik pencere içindeki ilk `\n`'e kaydırıyor. Bu bir VT parser değil:
  - 2048 karakter içinde newline yoksa hard cut → ANSI sequence'in ortasından kesilebilir (replace'te bozuk render).
  - Alt-screen (`\x1b[?1049h`), SGR durumu, OSC sequence'leri gibi satır sınırlarını aşan durumsal sequence'ler hiç hesaba katılmıyor; tail'in başı "yanlış terminal modunda" başlayabilir.
  - UTF-16 surrogate pair sınırı kontrol edilmiyor; hard cut bir emoji/CJK karakterini ikiye bölebilir.
- **xterm.write'ın kendi iç buffer'ı hâlâ sınırsız:** xterm.js, renderer parse hızından hızlı `write` çağrılarını kendi iç write buffer'ında biriktirir. Store cap'li olsa da, `write` çağrı hızı parse hızını sürekli aşarsa bu buffer ikinci bir OOM vektörüdür.
- **`writeChunked` sıralama riski:** `replace` patch'i 10KB'lık rAF dilimleriyle yazılırken (`Terminal/utils.ts:5-24`) yeni bir `append` patch'i gelirse yazımlar interleave olabilir.

### Backpressure / flow-control eksikleri

- **`xterm.write(data, callback)` ack mekanizması kullanılmıyor** (`useTerminalOutputRenderer.ts:58` callback'siz çağrı). xterm.js'in önerdiği desen: yazılan/ack'lenen byte sayacı tut, fark watermark'ı aşınca kaynağı durdur.
- **`node-pty`'nin `pty.pause()` / `pty.resume()` API'si hiç kullanılmıyor** (repo genelinde tek `pause/resume` referansı yok). PTY fd'si her zaman tam hızda okunuyor; kernel PTY buffer'ının doğal backpressure'ı (yazan süreci blocklama) hiç devreye sokulmuyor.
- **Batching/coalescing yok:** PTY chunk'ları frame başına birleştirilmeden, geldikleri granülaritede IPC'ye basılıyor.

## Native rewrite için gereksinimler

PTY → terminal view veri yolu, "string biriktiren state store" yerine uçtan uca **akış + backpressure** olarak tasarlanmalı:

1. **State store'da ham çıktı tutulmamalı.** Terminal ekran modeli (grid + scrollback) tek bir yerde, terminal emülatöründe (ör. xterm.js'in kendisi ya da native bir VT emülatörü) yaşamalı. UI state yalnızca metadata (id, status, title) taşımalı.
2. **Ack tabanlı uçtan uca flow control:**
   - Renderer/view, tükettiği byte'ları ack'lemeli (`xterm.write(chunk, callback)` veya eşdeğeri).
   - Main/native taraf "in-flight (gönderilmiş ama ack'lenmemiş) byte" sayacı tutmalı.
   - High watermark (ör. 256KB–1MB) aşıldığında `pty.pause()` (fd okumayı durdur), low watermark altına inince `pty.resume()`. Kernel PTY buffer'ı dolunca yazan süreç doğal olarak bloklanır — veri kaybı olmaz.
3. **Frame hızında batching:** PTY chunk'ları main/native tarafta biriktirilip ~16ms'de bir (veya boyut eşiğinde) tek mesaj olarak gönderilmeli. Chunk başına IPC + render turu yasak.
4. **Byte tabanlı, sınırlı tampon:** Snapshot/replay buffer'ı string concat değil, sabit kapasiteli ring buffer (`Uint8Array`) olmalı; chunk başına O(chunk) maliyet, sıfır flatten/GC fırtınası.
5. **Sequence-güvenli kesim:** Tail trim, newline sezgisi yerine gerçek bir VT/UTF-8 parser sınırında yapılmalı (escape sequence ortası, OSC gövdesi, çok byte'lı karakter ortası asla bölünmemeli). Alternatif: replay'i ham byte yerine emülatör durum serileştirmesi (grid + scrollback snapshot) üzerinden yap.
6. **Offset + epoch resync protokolü korunmalı:** Mevcut fix'in `totalLength` (monoton mutlak offset) + `epoch` (non-incremental rewrite sinyali) modeli doğru; native protokolde view attach/detach ve crash-recovery resync'i bu sözleşmeyle yapılmalı: `delta ≤ buffered tail` → incremental append, aksi halde snapshot replace.
7. **Görünmeyen terminaller için ayrı politika:** View detach'ken tam hız stream gönderilmemeli; native taraf cap'li buffer'da biriktirip attach anında tek snapshot ile resync etmeli.
8. **Crash dayanıklılığı:** Gönderim katmanı, hedef view yok/çökmüş ise göndermeyi sessizce atlamalı (mevcut `safeSend` davranışının eşdeğeri) ve PTY'yi pause edip recovery sonrası snapshot'tan devam etmeli.
9. **Sıralama garantisi:** Tek terminal için tüm yazımlar tek seri kuyruktan akmalı; `replace` uygulanırken araya `append` giremez (mevcut `writeChunked` rAF interleave riskinin tasarımsal çözümü).
