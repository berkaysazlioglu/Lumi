# Lumi Native Rewrite — Keşif Özeti

> Bu doküman, Electron tabanlı Lumi'nin macOS-native (Swift/AppKit-SwiftUI) rewrite'ı için yapılan keşif fazının üst düzey özetidir. Detaylar numaralı alt sistem raporlarındadır; bu dosya envanter, mimari özet, zorunlu gereksinimler ve açık soruları tek yerde toplar.

---

## 1. Uygulamanın amacı ve ana kavramlar

**Lumi**, birden çok Claude Code / Codex CLI oturumunu tek bir masaüstü dashboard'unda yöneten bir geliştirici aracıdır. Kullanıcı repolarını sekmeler halinde açar, her repo içinde çok sayıda terminal (PTY) çalıştırır, AI agent'larının "çalışıyor / input bekliyor" durumunu canlı izler ve bildirim alır.

Temel kavramlar (raporlardan derlenmiş sözlük):

| Kavram | Tanım | Kaynak |
|---|---|---|
| **Repository (repo)** | Diskteki bir proje klasörü; `projectsRoot` taraması veya `additionalPaths` (root/repo tipli) ile keşfedilir. Git reposu olmayan dizinler de açılabilir (`isGitRepo: false`). | [12](./12-git-vcs.md) |
| **Tab** | Açık bir repo sekmesi. `openTabs` repo **adı** tutar (path değil — bilinen kimlik tutarsızlığı). Tab kapatınca reponun tüm terminalleri öldürülür. **Workspace kavramı yoktur**; en üst birim repo/tab'dır. | [21](./21-renderer-state.md) |
| **Terminal (session)** | Main process'te yaşayan bir PTY oturumu. Login shell (`zsh -l`) başlatılır; `claude`/`codex` CLI'ları PTY argümanı olarak değil, **shell'e komut yazılarak** başlatılır. Her terminale UUID + rastgele codename (`brave-falcon`) atanır. Oturumlar persist edilmez. | [10](./10-main-terminal-pty.md) |
| **TerminalStatus** | 6 durumlu, provider-agnostic state machine: `idle / working / waiting-unseen / waiting-focused / waiting-seen / error`. OSC 0/2 title parse (✳ prefix = Claude idle), OSC 9 notification (Codex turn-complete) ve Codex için 3 sn output-silence heuristiği ile beslenir. Bildirim sistemi tamamen bu makineden sürülür. | [10](./10-main-terminal-pty.md) |
| **Persona** | YAML tabanlı ön ayar (system prompt, model, tool izinleri); tıklanınca o rolde hazır interaktif AI oturumu açar. İki scope: user (`~/.lumi/personas/`) ve project (`<repo>/.lumi/personas/`); project, user'ı id ile override eder. Default'lar (architect, expert, fixer, reviewer) her startup'ta **ezilerek** seed edilir. | [13](./13-main-services.md) |
| **Action (Quick Action)** | YAML tabanlı otomasyon: yeni terminal açıp sıralı step'ler çalıştırır (`write` / `wait_for` regex / `delay`). Otomatik versiyonlama (`.history/`, max 20 backup); default'lar `modified_at` varsa **korunur** (persona'nın tersine). AI destekli create/edit akışları vardır. | [13](./13-main-services.md) |
| **AI Provider** | `claude \| codex` (default claude). `buildAgentCommand` tek giriş noktasıdır: satır başındaki `claude` komutunu provider binary'sine çevirir ve config'i CLI flag'lerine enjekte eder. | [11](./11-ipc-surface.md), [13](./13-main-services.md) |
| **Codename koleksiyonu** | Yarım kalmış gamification: `discovered-codenames.json` + CollectionProgress component'i mevcut ama spawn `isNew=false` hardcoded, component hiçbir yere mount edilmemiş. Kapsam kararı gerekiyor (bkz. Açık sorular). | [10](./10-main-terminal-pty.md), [22](./22-renderer-ui.md) |
| **Focus mode** | Header/sidebar'ları gizleyen, traffic light'ları saklayan, hover-reveal kontrol çubuklu dikkatsiz-çalışma modu. | [22](./22-renderer-ui.md) |
| **Minimize** | Renderer-only terminal bayrağı: kart gizlenir, PTY yaşar. Minimize terminal **asla** otomatik odak almaz (tek istisna: bildirim tıklaması). Tab kapatma guard'ı (CloseTabDialog) bu bayrağa bağlıdır. | [21](./21-renderer-state.md) |

---

## 2. Feature haritası

Alt sistem raporlarının üst düzey envanteri (toplam ~213 davranış maddesi). Kapsam kararları için bkz. [01-decisions.md](./01-decisions.md).

| # | Alt sistem | Feature sayısı | Öne çıkanlar |
|---|---|---|---|
| 10 | [Terminal / PTY yönetimi (main)](./10-main-terminal-pty.md) | 12 | PTY spawn (login shell + komut enjeksiyonu), OSC parser, 6 durumlu StatusStateMachine, provider inference, focus-reporting filtresi, 500KB OutputBuffer, snapshot/sync |
| 11 | [IPC yüzeyi (62 kanal)](./11-ipc-surface.md) | 62 | 46 invoke + 1 send + 14 push + 1 ölü kanal (`collection:get`); `terminal:snapshot` tek reconciliation API'si; `config:set` yan etki propagasyonu; randomized heredoc delimiter güvenliği |
| 12 | [Git/VCS ve repo yönetimi](./12-git-vcs.md) | 13 | Repo keşfi, `defaultBranch..branch` commit log semantiği, sadeleştirilmiş status (staged/unstaged ayrımı yok), ignored-flag'li file tree (f4467ac), fs.watch tabanlı canlılık (300/500ms debounce). Worktree/checkout/pull/push/stash YOK |
| 13 | [Main servisleri (config/persona/action/notification/system/platform)](./13-main-services.md) | 28 | 4 dosyalı ConfigManager, asimetrik seed (persona ezilir / action korunur), ActionEngine step çalıştırıcı, status-driven NotificationManager, SystemChecker, `fixProcessPath` |
| 20 | [Renderer terminal (xterm.js + grid)](./20-renderer-terminal.md) | 18 | xterm 6 + addon'lar, totalLength/epoch delta-render (OOM fix), `display:none` mount stratejisi, piksel-hassas grid matematiği, spawn akışları, drag-drop path yazma |
| 21 | [Renderer state (Zustand store'lar)](./21-renderer-state.md) | 21 | 4 store, syncFromMain reconciliation, ayrıntılı odak/komşu/minimize kuralları, ui-state persistence (500ms debounce), toast kuralları (max 5, 5sn, dedupe) |
| 22 | [Renderer UI (kabuk: Layout/Header/Sidebar/Settings/Setup/FileViewer)](./22-renderer-ui.md) | 42 | Sıra-bağımlı bootstrap, 3-tetikleyicili sleep/wake re-sync, Monaco tabanlı FileViewer (view/diff/commit-diff), 4 adımlı onboarding, tüm animasyon parametreleri spec'lenmiş |
| 23 | [Görsel tasarım sistemi (globals.css)](./23-design-system.md) | — | `globals.css` (~2987 satır) envanteri: renk/spacing/radius token'ları (değerleriyle), JetBrains Mono tipografi ölçeği, status-dot renk sistemi, BEM component görünümleri, CSS animasyon kalıpları, tanımsız-token bug'ları |
| 30 | [App shell (pencere/lifecycle/menü/quit/paketleme)](./30-app-shell.md) | 17 | Quit-onay akışı (Cmd+Q dahil), pencere bounds persist + çoklu monitör doğrulaması, mikrofon izni (voice mode), entitlements, auto-update YOK |
| 40 | [Bug: siyah ekran + random karakterler](./40-bug-black-screen.md) | — | Dört halkalı zincir: GC fırtınası → siyah ekran → backlog replay → xterm otomatik yanıtlarının PTY'ye yazılması |
| 41 | [Bug: terminal stream OOM](./41-bug-stream-oom.md) | — | Sınırsız renderer buffer × O(n) tarama = O(n²); mevcut fix (04009f6) belleği düzeltir ama flow control'ü düzeltmez |

**Taşınmayacak ölü/dormant kapsam:** `collection:get` IPC kanalı (handler'sız), `repos:files` legacy API (çağıranı yok), `terminal:get-status` invoke kanalı (handler + preload mapping var, renderer'da çağıranı yok), boş `src/main/vcs/`, boş `src/main/browser/`, boş `BrowserSlot/`, mount edilmemiş CollectionProgress, hiç render olmayan SessionList "NEW" rozeti (`isNew` daima false), work-log API'sinin main tarafında aktif çağıranı görünmüyor.

---

## 3. Mevcut mimarinin özeti

### Katmanlar

```
┌─ Renderer (React 19 + Zustand) ──────────────────────────────┐
│  Layout / Header / Sidebars / Settings / Setup / FileViewer  │
│  Terminal kartları (xterm.js)  ← 4 Zustand store             │
└──────────────▲──────────────────────────────│────────────────┘
               │ push (14 kanal, safeSend)    │ invoke (46) + send (1)
┌─ Preload ────┴──────────────────────────────▼────────────────┐
│  contextBridge → window.api (her kanalın explicit mapping'i) │
└──────────────▲──────────────────────────────│────────────────┘
┌─ Main ───────┴──────────────────────────────▼────────────────┐
│  setupIpcHandlers (composition root)                         │
│  TerminalManager(node-pty) ── StatusStateMachine ── OSC parse│
│  RepoManager(simple-git, fs.watch)   ConfigManager(~/.lumi)  │
│  ActionStore/Engine  PersonaStore  NotificationManager       │
│  SystemChecker  platform/ (shell, fixProcessPath, paths)     │
└──────────────────────────────────────────────────────────────┘
Dış process'ler: login shell → claude/codex CLI, git, which
```

### Ana veri akışları

- **Terminal çıktısı:** `pty.onData` → provider inference + OSC parse + OutputBuffer(500KB) → `safeSend('terminal:output')` chunk başına 1 IPC (batching/backpressure YOK) → renderer store'da ikinci 500KB cap'li buffer (`{text, totalLength, epoch}`) → xterm'e O(delta) append. Status geçişleri `terminal:status` push'u + NotificationManager'ı besler.
- **Source of truth:** Terminaller için main process tek doğruluk kaynağıdır; renderer optimistic ekleme yapmaz, her spawn/kill sonrası `terminal:snapshot` ile `syncFromMain()` reconciliation'ı yapar (merge kuralları + `preserveNewerLiveOutputs` + `pendingSync` kuyruğu). Sleep/wake'te `powerMonitor.resume → terminal:sync → snapshot pull` zinciri çalışır.
- **Pull-after-push:** Store değişiklikleri (actions/personas/repos/file-tree) renderer'a payload'sız "changed" sinyali olarak gider; UI tüm listeyi yeniden çeker.
- **Persistence:** Tamamı main'in ConfigManager'ında: `~/.lumi/config.json`, `ui-state.json` (pencere bounds dahil), `actions/` + `.history/`, `personas/`, `discovered-codenames.json`, `work-logs/`. Renderer localStorage kullanmaz. Dev modda `~/.lumi-dev` izolasyonu; production'da legacy `~/.pulpo` / `~/.ai-orchestrator` dizinleri yerinde kullanılır.
- **Quit akışı:** `close` event yakalanır → aktif PTY varsa `app:confirm-quit` → onayda `killAll` + dispose + quit. Menüdeki Cmd+Q bile `window.close()` çağırarak aynı akıştan geçer.

> **Raporlar arası çelişki notu:** [11-ipc-surface.md](./11-ipc-surface.md) config konumunu "`~/Library/Application Support/lumi` benzeri app-data dizini" olarak tarif ederken [12](./12-git-vcs.md), [13](./13-main-services.md) ve [30](./30-app-shell.md) tutarlı şekilde `~/.lumi` (dev: `~/.lumi-dev`) der. Platform katmanı raporu (13) kaynak koddan doğrulanmış göründüğü için **`~/.lumi` doğru kabul edilmelidir**; 11'deki ifade düzeltilmeli. Ayrıca [13](./13-main-services.md) codename keşif boolean'ının UI animasyonu tetiklediğini söyler, ancak [10](./10-main-terminal-pty.md) `addDiscoveredCodename`'in hiç çağrılmadığını ve [22](./22-renderer-ui.md) CollectionProgress'in mount edilmediğini netleştirir — özellik fiilen **dormant**'tır.

---

## 4. Bug'lardan türetilen zorunlu gereksinimler

[40-bug-black-screen.md](./40-bug-black-screen.md) ve [41-bug-stream-oom.md](./41-bug-stream-oom.md) raporları, native tasarımın **birinci günden** sağlaması gereken gereksinimleri tanımlar. Bunlar "sonradan eklenecek iyileştirme" değil, mimari ön koşuldur:

### 4.1 PTY → UI backpressure (en kritik)

1. **Ham çıktı UI state store'unda tutulmamalı.** Ekran modeli (grid + scrollback) yalnızca terminal emülatöründe yaşamalı; state katmanı sadece metadata (id, status, title) taşımalı.
2. **Ack tabanlı uçtan uca flow control:** View tükettiği byte'ları ack'lemeli; in-flight byte sayacı tutulmalı; high watermark'ta PTY fd okuması durdurulmalı (kernel PTY buffer'ı yazan süreci doğal olarak bloklar — veri kaybı olmaz), low watermark'ta devam edilmeli. Mevcut sistemde `pty.pause()/resume()` hiç kullanılmıyor.
3. **Frame hızında batching:** Chunk'lar ~16ms'de bir veya boyut eşiğinde coalesce edilmeli. Chunk başına mesaj + render turu **yasak**; chunk işleme maliyeti O(chunk) kalmalı (asla tüm buffer taranmamalı — OOM'un kök nedeni buydu).
4. **Sabit kapasiteli byte ring buffer:** Snapshot/replay tamponu string concat değil `Uint8Array`-eşdeğeri ring buffer olmalı; GC churn sıfır.
5. **Sequence-güvenli kesim:** Her buffer kesimi ANSI escape sequence, OSC gövdesi ve UTF-8/çok-byte'lı karakter sınırlarına saygılı olmalı. Newline-sezgisel 2048-pencere yaklaşımı yetersiz; alt-screen (newline'sız) çıktı için "rastgele indeksten kes" fallback'i yasak. Tercihen replay ham byte yerine **emülatör durum serileştirmesi** (headless terminal state machine: grid + scrollback + modlar) ile yapılmalı.
6. **Detached/görünmeyen terminal politikası:** Görünmeyen view'a tam hız stream gönderilmemeli; cap'li buffer'da biriktirip attach anında tek snapshot ile resync edilmeli. Mevcut fix'in `totalLength` (monoton offset) + `epoch` (full-redraw sinyali) resync protokolü korunmaya değer.
7. **Sıralama garantisi:** Terminal başına tüm yazımlar tek seri kuyruktan akmalı; replace uygulanırken araya append giremez.
8. **Emülatörün iç write buffer'ı da sınırlı olmalı** veya backpressure döngüsüne dahil edilmeli (xterm.js'te bugün sınırsız — ikinci OOM vektörü).

### 4.2 Render-crash izolasyonu ve replay güvenliği

9. **Replay ile canlı girdi ayrılmalı:** Backlog replay'i sırasında emülatörün ürettiği otomatik yanıtlar (CPR/DSR, DA, DECRQM, mouse raporları) PTY'ye **asla** yazılmamalı; replay "girdi kapalı" modda yapılmalı. "Random karakterler" bug'ının birebir mekanizması budur — mevcut regex tabanlı focus-event ayıklama (`\x1b[I/O`) yetersizdir; PTY'ye giden yolda **protokol-bilinçli girdi filtresi** gerekir.
10. **Donma/crash gözetimi:** UI için unresponsive-watchdog ve GPU/compositor kaybı kurtarma yolu olmalı; kurtarma sırasında siyah ekran yerine "yeniden bağlanıyor" durumu gösterilmeli.
11. **Tek paylaşımlı GPU context:** Terminal başına ayrı GPU context açılmamalı; N terminal tek renderer/atlas ile çizilmeli (context evict kaynaklı kararma riski sıfırlanır).
12. **Crash dayanıklılığı:** Hedef view yok/çökmüşse gönderim sessizce atlanmalı (safeSend eşdeğeri), PTY pause edilmeli, recovery sonrası snapshot'tan devam edilmeli. "UI ölür → PTY'ler yaşar → UI yeniden bağlanır" akışı için **entegrasyon testi** yazılmalı: yeniden bağlanma sonrası PTY'ye hiçbir istenmeyen byte yazılmadığı doğrulanmalı.

### 4.3 Korunması gereken mevcut korumalar

- 500KB tail cap paritesi (PTY başına) + 5000 satır scrollback.
- `safeSend` dersinin native karşılığı: UI lifecycle'ına dayanıklı event dağıtımı.
- Uygulama crash'inde zombi PTY bırakmamak: process group + SIGHUP/killpg ile login shell altındaki tüm claude process ağacının temizlenmesi.

---

## 5. Electron'a bağımlı olup native'de yeniden tasarlanacak alanlar

| Alan | Electron'daki hali | Native karşılığı / karar |
|---|---|---|
| **IPC katmanının tamamı (62 kanal)** | invoke/push/send + preload bridge | Tamamen kalkar: invoke → `async throws` servis metodu, push → Combine/AsyncStream, send → metod çağrısı. Kanal haritası iç API sözleşmesi olarak kullanılmalı ([11](./11-ipc-surface.md)) |
| **Snapshot reconciliation makinesi** | syncFromMain, mergeSnapshotOutput, preserveNewerLiveOutputs, event bridge, ikinci 500KB buffer | İki-process yarışlarını telafi için vardı; tek process'te gereksizleşir. Tek bir `TerminalManager` (actor) hem PTY hem state tutar — ama PTY okuma background queue'da kalmalı ([21](./21-renderer-state.md)) |
| **node-pty** | Electron ABI'sine derlenen native modül | `forkpty()`/SwiftTerm LocalProcess. **Kritik fark:** native PTY ham byte verir; UTF-8 decode chunk sınırında buffer'lanmalı, yoksa OSC parser ve ✳ (3 byte) tespiti bozulur ([10](./10-main-terminal-pty.md)) |
| **xterm.js + addon'lar** | FitAddon, WebGL, Unicode11, WebLinks, rAF chunked write | SwiftTerm (veya eşdeğeri); fit/render/unicode built-in. SwiftTerm'in mode 1004 focus reporting'i **bilinçli bastırılmalı**; OSC 9 + ✳ semantiği Lumi'ye özgü olduğundan kendi parser'ı korunmalı ([20](./20-renderer-terminal.md)) |
| **`display:none` mount + IntersectionObserver** | Sekme değişiminde kartlar gizlenir, görünür olunca fit | View hidden tutma veya state-view ayrımı + reattach-replay; "görünür olunca fit/resize" davranışı şart, yoksa TUI'lar yanlış genişlikte reflow olur |
| **Monaco Editor (FileViewer)** | view/diff/commit-diff modları, side-by-side DiffEditor | **En büyük UI teknik riski.** tree-sitter/Highlightr/Runestone + custom diff renderer erken prototiplenmeli; gerekirse ilk sürümde unified diff ([22](./22-renderer-ui.md)) |
| **simple-git + ignore paketi** | child-process sarmalayıcı + kök-`.gitignore`-only eşleştirme | `git` CLI + porcelain parse önerilir; ignore tespiti `git check-ignore`'a devredilirse nested/global ignore bedavaya gelir (davranış farkı olarak notlanmalı). Hardcoded exclude listesi git olmayan dizinler için korunmalı ([12](./12-git-vcs.md)) |
| **fs.watch** | root'lar non-recursive (300ms), aktif repo recursive (500ms) | FSEvents/DispatchSource; debounce süreleri korunmalı, `.git` event fırtınalarına karşı coalescing şart. "Olay → tam reload" stratejisi korunmalı |
| **fixProcessPath** | `$SHELL -ilc 'echo $PATH'` + bilinen dizin fallback'leri | **Problem native'de aynen var** (Dock'tan başlatılan GUI app minimal PATH alır). Birebir taşınmalı; execSync yerine async Process + timeout ([13](./13-main-services.md), [30](./30-app-shell.md)) |
| **Quit interception** | close preventDefault + confirm-quit IPC çifti | `applicationShouldTerminate` → `.terminateLater` + onay alert'i. Cmd+Q dahil **her** çıkış yolu bu akıştan geçmeli; Cmd+W pencereyi değil terminali kapatır (performClose override) |
| **Electron Notification** | isFocused guard'lı, silent, click-to-focus | `UNUserNotificationCenter`; **bildirim izni isteme akışı yeni gereksinim**. `removeTerminal` cleanup sözleşmesi (interval sızıntısı) test edilmeli |
| **Custom titlebar / traffic light** | `-webkit-app-region: drag`, hiddenInset, 80px padding, `setTrafficLightVisibility` IPC | `NSWindow` fullSizeContentView + `standardWindowButton(...).isHidden`; Linux/Windows dalları tamamen düşer |
| **Entitlements** | JIT, unsigned-memory, dyld, disable-library-validation, audio-input | İlk dördü V8'e özgü, **kaldırılmalı**. `audio-input` + child inheritance (PTY'deki claude voice mode için) korunmalı, TCC zinciri test edilmeli. App Sandbox kullanılamaz; Developer ID + notarization ([30](./30-app-shell.md)) |
| **shell/dialog API'leri** | trashItem, showItemInFolder, openExternal, open-folder | `FileManager.trashItem`, `NSWorkspace.activateFileViewerSelecting`, `NSWorkspace.open` (http/https whitelist **korunmalı**), `NSOpenPanel` |
| **powerMonitor / focus event'leri** | resume → terminal:sync; window focus/blur → status machine | `NSWorkspace.didWakeNotification`, `NSWindow didBecome/ResignKey` — focus bilgisi status motoruna **aynı semantikle** akmalı, yoksa bildirimler bozulur |
| **Kısayollar (çift kaynak)** | Menü accelerator IPC + renderer keydown + CustomEvent köprüsü | Tamamı NSMenu key equivalents'a toplanmalı (tek kaynak) |
| **Renderer crash recovery** | render-process-gone → 1sn reload | Karşılığı yok; kök neden (buffer/backpressure) bölüm 4 ile adreslenir |
| **default-actions/ ve default-personas/** | `app.getAppPath()` ile okunur | `Bundle.main.resourceURL` resource'ları. **Seed asimetrisi (persona ezilir / action `modified_at` ile korunur) birebir korunmalı** |
| **Veri formatı uyumluluğu** | `~/.lumi` altındaki tüm JSON/YAML'lar | **Birebir aynı kalmalı** — kullanıcı iki sürüm arasında geçiş yapabilmeli; legacy `~/.pulpo` / `~/.ai-orchestrator` migration'ı da gerekli |

### Native'de düzeltilmesi önerilen mevcut bug'lar (parite olarak TAŞINMAMALI)

- `config:set` truthiness bug'ı: `0` / boş string değerler yan etki propagasyonunu atlar ([11](./11-ipc-surface.md)).
- Renderer'daki **tüm** max-terminal limit kontrollerinin `DEFAULT_CONFIG.maxTerminals` sabitini kullanması (kullanıcı config'i yerine): FocusExitControl ve useKeyboardShortcuts ([22](./22-renderer-ui.md)) + TerminalPanel'in üç call-site'ı — spawn öncesi limit alert'i, "N / 12" sayacı, dropdown disabled durumu ([20](./20-renderer-terminal.md) §15). Gerçek config limitini yalnızca main'deki TerminalManager uygular.
- Path-traversal tutarsızlığı: `readFile` korumalı ama `getFileDiff`, `context:delete-file`, `reveal` korumasız ([12](./12-git-vcs.md)).
- Tab kimliğinin repo adı, layout kimliğinin repo path'i olması — native'de baştan path/stable-id ([21](./21-renderer-state.md)).
- Drop edilen dosya path'inin quote'lanmaması (boşluklu path bozulur); spawn/kill hatalarının yalnızca console'a gitmesi; spawn limitinin sessiz `null` dönüşü ([20](./20-renderer-terminal.md), [10](./10-main-terminal-pty.md)).
- `wait_for` regex'inin tek chunk içinde eşleşme zorunluluğu — rolling buffer (örn. son 4KB) önerilir, 10sn timeout semantiği korunarak ([13](./13-main-services.md)).
- Temp system-prompt dosyalarının hiç temizlenmemesi; SystemChecker'ın senkron koşması ([13](./13-main-services.md)).
- JS `Map` insertion-order'a gizli bağımlılık: terminaller native'de **sıralı koleksiyon** olarak modellenmeli ([21](./21-renderer-state.md)).

---

## 6. Açık sorular — KARARA BAĞLANDI

> Aşağıdaki 14 soru 2026-06-11'de kullanıcı ile karara bağlandı. Bağlayıcı kararlar ve etkileri için bkz. **[01-decisions.md](./01-decisions.md)**. Sorular tarihsel bağlam için korunmuştur.

1. **Codename/Collection gamification'ı:** `isNew` hardcoded, `addDiscoveredCodename` çağrılmıyor, CollectionProgress mount edilmemiş; SessionList'teki "NEW" rozeti de aynı `isNew` bayrağına bağlı olduğu için hiç görünmüyor ([22](./22-renderer-ui.md) §3.1 — dormant/ölü UI). Native'de tamamlanacak mı, tamamen atılacak mı? (Karar rozeti de kapsar.)
2. **Work-log API'si:** ConfigManager'da var ama main tarafında aktif çağıran görünmüyor. Kapsama alınacak mı?
3. **Settings "draft + Save" modeli:** macOS konvansiyonu anlık uygulamadır; mevcut "değişiklikler Save'e kadar uygulanmaz, Escape=discard" davranışı korunacak mı, macOS'a uyarlanacak mı?
4. **FileViewer diff stratejisi:** Monaco'nun side-by-side DiffEditor'ına native karşılık maliyetli. İlk sürümde unified diff'e düşmek kabul edilebilir mi? (Erken prototip önerilir.)
5. **Hata UX'i normalizasyonu:** Mevcut sözleşme tutarsız (çoğu throw, `git:commit` envelope, spawn limiti sessiz `null`, openExternal sessiz yutma). Native'de tek tip strateji seçilirken spawn-limit aşımı kullanıcıya görünür hata olacak mı?
6. **getCommitDiff lazy-load:** N+1 `git show` problemi için dosya-seçilince-yükle modeline geçilirse FileViewer commit-diff UX'i değişir. Kabul mü?
7. **gitignore semantiği iyileşmesi:** `git check-ignore` kullanımı nested/global ignore'u da hesaba katar — mevcut davranıştan (yalnız kök `.gitignore`) bilinçli sapma onaylanıyor mu?
8. **Auto-update (Sparkle):** Mevcut üründe yok. Rewrite scope'una eklenecek mi, ayrı faz mı?
9. **ui-state/config migration stratejisi:** Aynı dosya formatı okunmaya devam mı edilecek (iki sürüm arasında gidip-gelme mümkün kalır), yoksa tek seferlik migration mı (örn. tab kimliği ad→path çevirisi, `NSWindow` frame autosave'e geçiş)?
10. **Terminal içi arama:** Mevcut üründe yok (SearchAddon yüklü değil). SwiftTerm search desteğiyle eklenirse bu yeni feature kararıdır — kapsama girecek mi?
11. **Drop edilen path'in quote'lanması ve diğer "bilinçli davranış değişiklikleri":** Bölüm 5'in sonundaki bug düzeltme listesi onaylanıyor mu, yoksa birebir parite mi isteniyor?
12. **`create-project` action'ının `~/.lumi/templates/` bağımlılığı:** Bu şablonların seed kaynağı incelenen alt sistemlerde bulunamadı — nereden geldiği doğrulanmalı; native'de bundle'a eklenecek mi?
13. **Görsel kimlik: native look mı, görsel parite mi?** Mevcut UI tamamen custom bir dark temadır (mor/violet accent paleti, JetBrains Mono monospace tipografi, BEM component stilleri — envanteri [23](./23-design-system.md)'te). Native rewrite macOS görünümünü mü benimseyecek (system font, semantic NSColor, vibrancy), yoksa mevcut görsel kimlik birebir mi korunacak? Bu karar 23'teki tüm token'ların taşınma şeklini (piksel paritesi vs semantic mapping) belirler.
14. **Bekleyen plan dokümanları (`docs/plans/`) native scope'a alınacak mı?** Repo'da in-flight tasarım dokümanları var; özellikle **`2026-02-06-action-auto-discovery.md`** implemente edilmemiş planlı bir özelliktir (CommandCapture/SessionRecorder/DiscoveryEngine kodda yok) — native scope'a girecek mi, Electron'da mı tamamlanacak, yoksa iptal mi? Diğerleri durum tespitiyle: `2026-02-09-terminal-state-source-of-truth.md`, `2026-02-12-enhanced-focus-mode-design.md` ve `2026-02-25-project-grid-layout-{design,plan}.md` implemente edilmiş görünüyor (davranışları ilgili spec'lerde zaten belgeli); `2025-02-11-distributed-claude-md-design.md` ise koda değil dokümantasyon organizasyonuna dairdir.
