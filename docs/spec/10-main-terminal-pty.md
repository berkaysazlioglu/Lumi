# Terminal / PTY Yönetimi (src/main/terminal)

## Amaç ve sorumluluk

Main process içinde çalışan, uygulamanın **tek doğruluk kaynağı (single source of truth)** olan terminal alt sistemi. Sorumlulukları:

- node-pty üzerinden shell PTY process'leri spawn etmek ve yaşam döngülerini yönetmek (spawn / write / resize / kill / killAll)
- PTY çıktısını renderer'a stream etmek ve main tarafında 500KB'lık bir tail buffer'da tutmak (snapshot/restore için)
- Çıktı içindeki OSC escape sequence'lerini (title OSC 0/2, notification OSC 9) parse ederek agent'ın (Claude Code / Codex) **çalışıyor / bekliyor** durumunu çıkarsamak
- Terminal başına bir status state machine işletmek (`idle`, `working`, `waiting-unseen`, `waiting-focused`, `waiting-seen`, `error`) ve durum değişikliklerini hem renderer'a hem notification sistemine iletmek
- Hangi agent'ın (claude/codex/unknown) çalıştığını input/output/title ipuçlarından çıkarsamak (provider inference)

Önemli mimari karar: **PTY, Claude Code CLI'yi doğrudan spawn ETMEZ.** Her terminal bir login shell başlatır; `claude` / `codex` komutları ya kullanıcı tarafından elle yazılır ya da Action/Persona sistemleri tarafından `write()` ile shell'e "yazılarak" başlatılır.

## Feature envanteri

### 1. PTY spawn

**Davranış:**
- `spawn(repoPath, window)` çağrısı yeni bir PTY oluşturur.
- Shell seçimi platform zincirinden yapılır (`getDefaultShell`): macOS → `zsh` → `bash` → `sh`; Linux → `bash` → `zsh` → `sh`; Windows → `powershell.exe` → `cmd.exe`. Her aday `which`/`where` ile doğrulanır (5 sn timeout), ilk bulunan kullanılır ve **process ömrü boyunca cache'lenir**. Hiçbiri yoksa açıklayıcı hata fırlatılır.
- Shell argümanları: Unix'te `['-l']` (login shell — kullanıcının profili, PATH'i, alias'ları yüklenir), Windows'ta boş.
- PTY parametreleri: `name: 'xterm-256color'`, başlangıç boyutu **120 sütun × 30 satır**, `cwd: repoPath`, `env: process.env` (startup'ta `fixProcessPath()` ile zenginleştirilmiş — bkz. Electron bölümü), Windows'ta `useConpty: false` (winpty fallback).
- Her terminale bir **UUID v4 id** ve rastgele bir **codename** atanır: 50 sıfat × 50 isim listesinden `sıfat-isim` formatında (ör. `brave-falcon`), toplam 2500 kombinasyon. Çakışma kontrolü YOK (rastgele tekrar mümkün, id zaten UUID).
- `SpawnResult = { id, name, isNew }` döner; `isNew` şu an **hardcoded `false`** (codename keşif/achievement mekanizması için ayrılmış ama spawn içinde kullanılmıyor — `ICodenameTracker.addDiscoveredCodename` interface'i enjekte ediliyor fakat çağrılmıyor; ConfigManager'da implementasyonu var. Rewrite'ta ya bağlanmalı ya da atılmalı).

**Edge-case'ler:**
- **Max terminal limiti:** Varsayılan 12, ConfigManager'dan gelir, `setMaxTerminals()` ile runtime'da güncellenebilir. Limit doluyken `spawn` `console.error` yazıp `null` döner; IPC handler bu `null`'ı renderer'a aynen iletir (exception yok).
- Main window yoksa IPC handler `'No main window'` hatası fırlatır.
- Spawn'a opsiyonel `task` etiketi iliştirilebilir (`TERMINAL_SPAWN` ikinci parametre) — `setTask()` ile sonradan da atanır; sadece metadata, snapshot'ta taşınır.

**Kullanıcıya görünen etki:** Yeni terminal kartı açılır, codename başlık olarak görünür, shell prompt'u repo dizininde hazır gelir.

### 2. Claude Code / Codex CLI başlatma (komut enjeksiyonu)

**Davranış:**
- Agent CLI'leri PTY argümanı olarak değil, **çalışan shell'e satır yazılarak** başlatılır. Üç kaynak:
  1. Kullanıcı elle `claude` yazar.
  2. **ActionEngine** (YAML quick action'lar): `write` step içeriği `buildAgentCommand()` ile dönüştürülüp `terminalManager.write()` ile gönderilir. Tüm write step'leri `\r` (Enter) ile biter.
  3. **Persona spawn** IPC handler'ı: terminal spawn + `setTask(persona.label)` + `write(command)`.
- `buildAgentCommand(content, action)` provider'a göre komutu yeniden yazar:
  - Önce `remapProviderCommand`: satır başındaki `claude` kelimesi seçili provider'ın binary'sine map edilir (claude → `claude`, codex → `codex`).
  - **Claude için** `buildClaudeCommand`: içerik `claude ` ile başlıyorsa config'den CLI flag'leri enjekte edilir, başlamıyorsa (ör. `git pull\r`) dokunulmaz. Flag'ler: `--system-prompt-file '<temp>'`, `--append-system-prompt-file '<temp>'`, `--model X`, `--allowedTools "A" "B"`, `--disallowedTools ...`, `--tools "..."`, `--permission-mode X`, `--max-turns N`. Sistem prompt'ları `getTempDir()` (os.tmpdir()/lumi) altına `system-prompt-<timestamp>.txt` olarak yazılır. Flag'ler prompt argümanından `--` ayracıyla ayrılır: `claude <flags> -- "prompt"`.
  - **Codex için** `buildCodexCommand`: yalnızca `config.model` varsa ve komutta zaten `--model` yoksa `codex --model X` enjekte eder.
- Temp dizin `app will-quit`'te `rmSync(recursive, force)` ile temizlenir.

**Edge-case'ler:** Komut `claude`/`codex` ile başlamıyorsa builder no-op'tur. Prompt güvenliği için Codex create-action akışında randomized heredoc delimiter kullanılır (ipc handler tarafında).

**Kullanıcıya görünen etki:** Action butonuna basınca terminalde komutun "yazıldığı" görülür ve agent başlar.

### 3. Veri stream'i: PTY → renderer

**Davranış (her `onData` chunk'ında sırasıyla):**
1. **Provider inference (output):** lowercase chunk'ta `"openai codex"` geçiyorsa hint=codex; hint hâlâ `unknown` iken `"claude code"` geçiyorsa hint=claude.
2. **OSC parse:** chunk OscTitleParser'dan geçirilir (aşağıda).
3. **Codex aktivite timer'ı:** hint=codex ve bu chunk'ta "turn complete" notification görülmediyse 3 saniyelik silence timer'ı resetlenir (bkz. status detection).
4. **Main-side buffer:** chunk `OutputBuffer.append()` ile birikir — buffer **500.000 karakter** ile sınırlıdır; taşınca baş taraftan kesilir. Kesim noktası, ANSI sequence'leri ortadan bölmemek için cut index'ten ileriye doğru **2048 karakterlik pencere** içinde ilk `\n`'e hizalanır (`trimOutputTail`, shared util — renderer da aynısını kullanır).
5. **Renderer'a push:** `safeSend(window, 'terminal:output', id, data)` — chunk **olduğu gibi, batch'lenmeden** gönderilir.
6. **EventEmitter:** `emit('output', { terminalId, data })` — ActionEngine'in `wait_for` regex step'i bu event'i dinler.

**Buffering / batching / flow-control gerçeği:**
- Main tarafında **batching ve backpressure YOK**: her PTY chunk'ı ayrı bir IPC mesajıdır. `pty.pause()/resume()` veya xterm flow-control (write callback) kullanılmıyor.
- OOM koruması iki kademeli tail-trim ile sağlanır: main `OutputBuffer` 500KB + renderer store'da `TerminalOutput { text, totalLength, epoch }` yapısı yine 500KB cap'li. `totalLength` monoton mutlak stream offset'idir; renderer xterm'e yazarken string karşılaştırması yerine `totalLength` delta'sı ile **O(delta) append** yapar. `epoch` artarsa (snapshot merge'de incremental olmayan rewrite) xterm `clear()` + full redraw yapar; full redraw'lar UI donmasın diye `requestAnimationFrame` ile **10KB'lık chunk'lar** halinde yazılır (`writeChunked`). Bu tasarım, sınırsız birikim + O(n) prefix taramalarının yol açtığı renderer V8 OOM crash'lerinin düzeltmesidir (commit `04009f6`).
- xterm scrollback: 5000 satır.

**Kullanıcıya görünen etki:** Canlı, düşük gecikmeli terminal çıktısı; çok uzun oturumlarda en eski çıktı sessizce kaybolur (yalnızca son ~500KB restore edilebilir).

### 4. OSC parser (OscTitleParser)

**Davranış:**
- Terminal başına partial buffer tutarak chunk sınırlarında bölünen OSC sequence'lerini birleştirir. Partial buffer **4096 karakteri** aşarsa atılır (bozuk/sonsuz sequence koruması).
- Tanınan formlar: `ESC ] <cmd> ; <payload> (BEL | ESC \)`. BEL (`\x07`) ve ST (`\x1b\`) terminatörlerinden hangisi önce gelirse o kullanılır.
- **OSC 0 / OSC 2 → title event:** `{ source:'title', title, isWorking, providerHint? }`
  - Title `✳` (U+2733) ile başlıyorsa → Claude **idle** sinyali: `isWorking=false`, providerHint=claude. (Claude Code çalışırken spinner'lı title, bitince `✳ ...` title basar.)
  - Title'da `claude code` ya da kelime sınırlı `claude` geçiyorsa providerHint=claude.
  - Aksi halde: title boş değilse `isWorking=true`, boşsa `null` (karar verme).
- **OSC 9 → notification event** (iTerm2 protokolü; Codex turn bitiminde basar): payload şu regex'lerden birine uyarsa `kind='codex-turn-complete'` (+providerHint=codex), yoksa `generic`: `turn/task (complete|completed|done|finished)`, `waiting for input`, `all idle`, `idle state`.
- Diğer OSC komutları sessizce atlanır. Terminal kapanınca `delete(id)`, toplu temizlikte `clear()`.

**TerminalManager'ın event işleyişi:**
- `providerHint` varsa terminal hint'i güncellenir; hint **claude'a** dönerse codex aktivite timer'ı iptal edilir (Claude title-tabanlı, timer'a gerek yok).
- `codex-turn-complete` → timer iptal + state machine'e `onTitleChange(false)` (kesin "bitti" sinyali); aynı chunk'ta timer reset edilmez.
- Title event'inde: title'ın **ilk karakteri + ardından gelen boşluk** soyulur (`replace(/^.\s*/, '')` — spinner/✳ ikonunu atar), kalan boş değilse `terminal.oscTitle` set edilir ve `terminal:title` ile renderer'a push edilir (sekme başlığında görünür).
- `isWorking === null` ise state machine'e dokunulmaz; `true` ise `lastActivityAt` güncellenip `onTitleChange(true)`.

### 5. Status state machine (StatusStateMachine)

**Durumlar:** `idle`, `working`, `waiting-unseen`, `waiting-focused`, `waiting-seen`, `error`.

**İç durum:** `focused` (tab seviyesi, başlangıç false) ve `windowFocused` (OS pencere seviyesi, başlangıç true). **Effective focus = tab focused AND window focused.**

**Geçişler:**
- `onTitleChange(true)`: working değilse → `working`.
- `onTitleChange(false)`: yalnızca `working` ise → effectively-focused ise `waiting-focused`, değilse `waiting-unseen`.
- `onOutputActivity()` (codex fallback): working değilse → `working`.
- `onOutputSilence()` (3 sn sessizlik): `working` ise → focus'a göre `waiting-focused` / `waiting-unseen`.
- `onUserInput()` (codex, Enter basıldı): `idle` ve `error` dışındaki durumlarda → `working`.
- `onFocus()`: focused=true; effectively-focused olduysa ve durum `waiting-unseen`/`waiting-seen` ise → `waiting-focused`.
- `onBlur()`: focused=false; durum `waiting-focused` ise → `waiting-seen` ("görüldü ama artık bakılmıyor").
- `onWindowFocus()/onWindowBlur()`: pencere focus'u; aynı mantıkla `waiting-*` geçişleri. Pencere blur olduğunda aktif tab'ın `waiting-focused`'ı `waiting-seen`'e düşer — böylece app arka plandayken aktif tab için bile **native OS notification** tetiklenebilir.
- `onExit(code)`: code===0 → `idle`, değilse → `error`.
- `reset()` → `idle`.
- Aynı duruma geçiş no-op'tur (onChange tetiklenmez).

**onChange callback'i:** Pencere destroyed değilse ve terminal hâlâ kayıtlıysa `terminal:status` push edilir ve `notifier.notifyStatusChange(id, status, window, repoPath)` çağrılır (NotificationManager — toast/`terminal:bell`/native bildirim kararı orada).

**Kullanıcıya görünen etki:** Terminal kartındaki durum rozeti; agent işi bitirince app arka plandaysa OS bildirimi/bell.

### 6. Provider inference (agentHint)

`agentHint: 'claude' | 'codex' | 'unknown'`, üç kaynaktan beslenir:
1. **Input:** Kullanıcı yazısı trim'lenip `^codex(\s|\r|$)` veya `^claude(\s|\r|$)` ile eşleşirse hint set edilir.
2. **Output:** `"openai codex"` → codex (her zaman, hint codex değilken); `"claude code"` → claude (yalnızca hint `unknown` iken — codex'ten claude'a output ile düşmez).
3. **OSC:** ✳ prefix / claude regex → claude; codex-turn-complete → codex.

Hint'in tek işlevsel etkisi: **Codex fallback status detection** yalnızca `agentHint==='codex'` iken aktiftir (Codex eskiden çalışma durumunu title ile yansıtmadığı için): her output chunk'ı `onOutputActivity()` + 3000 ms'lik timer reset; timer dolunca `onOutputSilence()`. Claude için tamamen title-tabanlıdır. Hint claude'a geçtiği an aktif timer iptal edilir.

### 7. write() — kullanıcı/otomasyon girdisi

**Davranış:**
- Terminal yoksa `false` döner.
- **Focus reporting filtreleme:** `\x1b[I` (focus-in) ve `\x1b[O` (focus-out) sequence'leri PTY'ye yazılmadan önce sökülür. Sebep: agent CLI'leri `\x1b[?1004h` ile focus reporting açıp focus-out'ta spinner animasyonunu (dolayısıyla title güncellemelerini) durdurabiliyor; focus durumunu zaten StatusStateMachine yönettiği için CLI'nin daima "focused" sanması istenir. Filtre sonrası boş kalan veri için `true` dönülür, PTY'ye yazılmaz.
- Girdiden provider inference yapılır.
- Veri `\r` içeriyorsa `lastActivityAt` güncellenir; hint codex ise `onUserInput()` (Enter → "çalışmaya başladı" varsayımı).
- Renderer tarafında kaynaklar: xterm `onData` (klavye/paste), drag-drop edilen dosyanın path'inin yazılması, ActionEngine write step'leri.

### 8. resize()

- Renderer: FitAddon + container üzerinde **ResizeObserver** ve **IntersectionObserver** (görünür olunca da fit — repo sekmesi değişiminde `display:none`'dan dönen terminaller için; threshold 0.01). **150 ms debounce** sonrası `fit()` çağrılıp yeni `cols/rows` `terminal:resize` ile main'e gönderilir.
- Main: `pty.resize(cols, rows)`; terminal yoksa `false`.

### 9. kill / killAll / exit cleanup

**`kill(id)`:** aktivite timer'ı temizle → `pty.kill()` (Unix'te node-pty varsayılanı **SIGHUP**) → map'ten sil → OSC buffer sil → notifier'dan context sil. Terminal yoksa `false`.

**`killAll()`:** tüm terminaller için aynı sıra + `oscParser.clear()`. Çağrı noktaları:
- Pencere kapatma: `close` event'inde terminal sayısı > 0 ve quit onaylanmamışsa kapatma **engellenir** ve renderer'a `app:confirm-quit` (terminal sayısıyla) gönderilir; renderer onayı `app:quit-confirmed` ile dönünce `killAll()` + quit.
- `uncaughtException` handler'ı (zombie PTY önleme, `app.exit(1)`).

**PTY `onExit` (process kendi öldüğünde):** sıra kritiktir — (1) aktivite timer temizle, (2) terminal map'ten **önce** silinir, (3) `notifier.removeTerminal(id)`, (4) `statusMachine.onExit(exitCode)` (map'ten silindiği için onChange callback'i içindeki `terminals.has(id)` guard'ı stale status push/bildirimi engeller), (5) OSC buffer sil, (6) `terminal:exit` push, (7) `emit('exit')`. Renderer `onTerminalExit` ile terminali store'dan düşürür ve komşu terminale focus kaydırır.

### 10. Snapshot / senkronizasyon

- `getTerminalSnapshots()` → `terminal:snapshot` invoke kanalıyla pull edilir: `{ id, name, repoPath, createdAt(ISO), task?, oscTitle?, status, output(≤500KB) }`.
- Renderer `syncFromMain()` reconciliation'ı: spawn/kill sonrası, sayfa yüklenince ve **macOS sleep→resume** sonrası (main, `powerMonitor.on('resume')` ile `terminal:sync` push eder, renderer bunu sync tetiklemek için dinler).
- Merge stratejisi (renderer): snapshot mevcut text'in devamıysa incremental uzat (epoch sabit, redraw yok); renderer ileridebir durumda mevcut korunur (rollback flicker önleme); diverge ise uzun olan tercih edilir, snapshot kazanırsa epoch++ (full redraw). In-flight live append'ler `preserveNewerLiveOutputs` ile korunur. Sync sırasında gelen sync istekleri `pendingSync` flag'iyle kuyruğa alınır.

### 11. safeSend guard'ı

Tüm push'lar `safeSend` üzerinden: window null/destroyed, webContents destroyed/**crashed** kontrolü + `mainFrame.send` try-catch. Gerekçe: renderer crash ↔ recovery reload arasında PTY output akmaya devam eder; `window.isDestroyed()` false dönerken WebFrameMain disposed olabilir ve Electron içeriden console'a hata basar — tek çözüm send'i hiç çağırmamak.

### 12. Pencere focus takibi

BrowserWindow `focus`/`blur` event'leri `setWindowFocused(bool)` ile **tüm** terminallerin state machine'lerine yayılır. Tab focus'u ise renderer'dan `terminal:focus` (id veya null) ile gelir; `setFocused(id)` eşleşen terminale `onFocus()`, diğer hepsine `onBlur()` uygular.

## Veri akışı ve bağımlılıklar

```
renderer (xterm onData) ──invoke──▶ TERMINAL_WRITE ──▶ TerminalManager.write ──▶ pty
pty.onData ──▶ [provider infer, OSC parse → StatusStateMachine, OutputBuffer.append]
           ├─send─▶ TERMINAL_OUTPUT ──▶ renderer store appendOutput ──▶ xterm (delta patch)
           └─emit('output')─▶ ActionEngine (wait_for regex step)
StatusStateMachine.onChange ─send─▶ TERMINAL_STATUS ──▶ renderer rozet
                            └────▶ ITerminalNotifier.notifyStatusChange ──▶ NotificationManager
                                       └─send─▶ TERMINAL_BELL (toast/native bildirim)
```

**IPC kanalları:**
- Invoke (renderer→main): `terminal:spawn(repoPath, task?)`, `terminal:write(id, data)`, `terminal:kill(id)`, `terminal:resize(id, cols, rows)`, `terminal:snapshot()`, `terminal:get-status(id)`, `terminal:focus(id|null)`
- Push (main→renderer): `terminal:output(id, chunk)`, `terminal:exit(id, exitCode)`, `terminal:status(id, status)`, `terminal:title(id, title)`, `terminal:sync()` (resume sonrası re-sync isteği), `terminal:bell(id, repoName)` (NotificationManager'dan)
- İlişkili: `app:confirm-quit(count)` / `app:quit-confirmed` (kapatma onayı)

**Bağımlılıklar:**
- **node-pty** (tek native modül; Electron ABI'sine derlenir)
- **NotificationManager** — `ITerminalNotifier` interface'i ile soyutlanmış (notifyStatusChange, removeTerminal)
- **ConfigManager** — `maxTerminals` değeri + `ICodenameTracker` (şu an bağlanmamış)
- **ActionEngine / persona IPC handler'ları** — spawn+write tüketicileri; `buildAgentCommand` ile komut üretimi
- **platform/** — shell seçimi, `fixProcessPath`, `getTempDir`
- **Dış process'ler:** login shell (zsh/bash/...), onun içinde `claude` / `codex` CLI'leri

## Persistence / config

- **Terminal oturumları persist edilmez.** Uygulama kapanışında tüm PTY'ler öldürülür; restart sonrası terminaller geri gelmez. Snapshot/restore yalnızca uygulama açıkken renderer reload/sleep-resume senaryoları içindir.
- `maxTerminals`: ConfigManager üzerinden (Lumi config dosyası, `~/.lumi`), runtime'da değiştirilebilir.
- Sistem prompt'ları: `os.tmpdir()/lumi/system-prompt-<ts>.txt` ve `append-system-prompt-<ts>.txt`; `will-quit`'te dizin komple silinir.
- Pencere durumu (bounds/maximized) terminal alt sisteminin değil config'in işi; close handler'da kaydedilir.

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **node-pty → native PTY:** Swift'te `openpty()/forkpty()` veya SwiftTerm'in `LocalProcess`/`PseudoTerminalHelpers`'ı. ConPTY/winpty ayrımı (`useConpty:false`) macOS-only rewrite'ta tamamen düşer.
2. **IPC katmanı tamamen kalkar:** main↔renderer ayrımı yoktur; `safeSend` guard'ları, snapshot reconciliation (`totalLength/epoch` delta protokolü), `terminal:sync`, preload bridge ve renderer-side ikinci 500KB buffer'ın tamamı tek process içinde basit delegate/Combine akışına iner. Yine de UI thread'i bloklamamak için PTY okuma background thread/queue'da yapılıp UI'ya aktarılmalı.
3. **`fixProcessPath` problemi macOS native'de de AYNEN var:** Dock/Finder'dan başlatılan GUI app'ler minimal PATH alır (`/usr/bin:/bin:/usr/sbin:/sbin`). Mevcut çözüm: `$SHELL -ilc 'echo -n "$PATH"'` (5 sn timeout) + bilinen dizinlerin (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `~/.nvm/current/bin`, `~/.volta/bin`) varsa eklenmesi. Native'de de `claude` binary'sinin bulunabilmesi için startup'ta uygulanmalı (PTY zaten login shell olduğu için PTY içinde sorun yok; sorun `which claude` tarzı system check'lerde ve doğrudan exec'lerde).
4. **xterm.js → SwiftTerm (veya eşdeğeri):** renderer'daki FitAddon/ResizeObserver/IntersectionObserver/WebGL fallback/writeChunked/rAF mekanizmalarının hepsi terminal view'ın kendi resize/draw yönetimine devrolur. Scrollback 5000 satır eşdeğeri korunmalı.
5. **powerMonitor resume → `NSWorkspace.didWakeNotification`**; BrowserWindow focus/blur → `NSWindow didBecome/didResignKey` (window-level focus state machine girdisi olarak korunmalı).
6. **Quit interception:** Electron `close` + `preventDefault` + renderer onay diyaloğu akışı, native'de `applicationShouldTerminate` → `.terminateLater` + onay alert'i ile birebir karşılanır. `uncaughtException`'daki zombie-PTY temizliği için native'de child process'lerin process group/SIGHUP semantiği veya `atexit`/signal handler düşünülmeli.

## Native rewrite notları (riskler, dikkat edilecekler)

- **Byte vs string sınırı (en kritik fark):** node-pty chunk'ları JS string olarak verir; UTF-8 multi-byte karakter bölünmesi node tarafında çözülmüş gelir. Native'de PTY'den **ham byte** okunur — UTF-8 decode'u chunk sınırlarında bölünen karakterleri buffer'layarak yapmak gerekir; aksi halde OSC parser ve `✳` (U+2733, 3 byte) tespiti bozulur. SwiftTerm feed'i byte alır ama Lumi'nin kendi OSC/status parser'ı decode edilmiş stream üzerinde çalışmalı (ya da byte-level yeniden yazılmalı).
- **OSC parser'ı terminal emülatöründen bağımsız tut:** SwiftTerm title callback'i verse bile OSC 9 notification ve ✳-prefix semantiği Lumi'ye özgüdür; mevcut parser davranışı (partial buffer 4096 cap, BEL/ST önceliği, OSC 0/2/9 dışını yutma) birebir port edilmeli. StatusStateMachine zaten pure logic — birebir port edilebilir ve unit testleri taşınabilir.
- **Flow control yok:** Mevcut sistemde backpressure bulunmuyor; `yes` gibi flood üreten komutlarda Electron'da IPC + çift buffer dayanıyordu. Native'de PTY okuma hızı UI yazma hızını aşarsa SwiftTerm'in kendi buffer'ı şişebilir — okuma döngüsüne basit bir backpressure (feed tamamlanana dek read'i duraklatma) eklemek mevcut davranıştan İYİLEŞTİRME olur; en azından 500KB tail-trim semantiği (newline-aware, 2048 pencere) korunmalı.
- **Kill semantiği:** node-pty `kill()` Unix'te SIGHUP gönderir; login shell ve altındaki `claude` process ağacının tamamının öldüğünden emin olun (process group'a sinyal / `killpg`). Aksi halde app kapanınca zombie claude process'leri kalır.
- **Focus reporting filtresi unutulmamalı:** `\x1b[I`/`\x1b[O` strip edilmezse Claude Code arka plandaki terminallerde spinner title basmayı keser ve status detection körleşir. Native terminal view'ın kendi focus reporting'i de (mode 1004) bilinçli olarak bastırılmalı.
- **Codex 3 sn silence heuristiği** timer-per-terminal gerektirir; terminal kapanışında timer iptal sırası (stale "waiting" bildirimi yarışı) Electron'daki cleanup sırası kadar dikkatle korunmalı: önce kayıttan düş, sonra exit status'u işle.
- **Title temizleme regex'i `/^.\s*/`** ilk karakteri körlemesine atar — ✳/spinner ikonunu söker ama ikonsuz title'ların ilk harfini de yer; bilinen bir trade-off, davranış değiştirilecekse status inference ile birlikte test edilmeli.
- **isNew/ICodenameTracker ölü bağlantısı:** spawn `isNew=false` hardcoded; codename keşif mekanizması yarım kalmış. Rewrite'ta karar verin: ya tamamlayın ya da API'den çıkarın.
- **Spawn limiti hata iletişimi zayıf:** limit aşımında sessizce `null` dönüyor; native'de kullanıcıya açık hata göstermek değerlendirilebilir.
- Status değişikliklerinin NotificationManager'a tek interface (`ITerminalNotifier`) üzerinden gitmesi test edilebilirlik için korunmaya değer bir sınır.
