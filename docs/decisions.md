# Lumi Native Rewrite — Karar Kaydı

> `00-overview.md` §6'daki 14 açık soru 2026-06-11 tarihinde kullanıcı ile birlikte karara bağlandı. Tasarım ve implementasyon fazları bu kararları bağlayıcı kabul eder.

> **Not (2026-09-04):** Electron davranış envanteri spec'leri (`docs/spec/10`–`41`) rewrite tamamlandığı için kaldırıldı; aşağıda `NN-xxx.md` biçiminde anılan dosyalar git history'dedir. Bağlayıcı zorunlu mimari gereksinimler [design/00-architecture.md Ek A](./design/00-architecture.md)'ya taşındı.

| # | Konu | Karar |
|---|---|---|
| 1 | Codename/Collection gamification | **Tamamen at** |
| 2 | Work-log API'si | **At** |
| 3 | Settings modeli | **macOS anlık uygulama** |
| 4 | FileViewer diff | **Unified diff ile başla** |
| 5 | Hata UX'i | **Tek tip sözleşme + görünür hatalar** |
| 6 | Commit diff yükleme | **Lazy-load** |
| 7 | gitignore semantiği | **`git check-ignore`** |
| 8 | Auto-update | **Yok (planlanmıyor)** |
| 9 | Config migration | **Aynı formatı oku/yaz** |
| 10 | Terminal içi arama | **İlk sürümde yok** |
| 11 | Bug düzeltme listesi | **Düzeltmeler onaylandı, parite yok** |
| 12 | `create-project` templates | **Action default set'ten çıkarılır** |
| 13 | Görsel kimlik | **Mevcut kimlik korunur (semantic uyarlama)** |
| 14 | `docs/plans/` action-auto-discovery | **İptal** |

## Karar detayları ve etkileri

### 1. Gamification tamamen atılıyor
Codename üretimi, collection persistence, CollectionProgress bileşeni ve SessionList "NEW" rozeti native spec'e girmez. `collection:get` ile birlikte `00-overview.md` §2'deki ölü kapsam listesinin tamamı taşınmaz. Veri modelinde codename alanı için yer ayrılmaz (YAGNI).

### 2. Work-log API'si atılıyor
ConfigManager'daki work-log persistence native servis katmanına taşınmaz. İleride gerçek bir ihtiyaç doğarsa sıfırdan tasarlanır.

### 3. Settings macOS konvansiyonuna geçiyor
"Draft + Save, Escape=discard" modeli terk edilir; System Settings gibi her değişiklik anında uygulanır ve persist edilir. `22-renderer-ui.md`'deki Settings draft-state davranışları parite hedefi değildir. `config:set` yan etki propagasyonunun (`11-ipc-surface.md`) native karşılığı alan-bazına iner: her ayar değişikliği kendi yan etkisini anında tetikler.

### 4. Diff görünümü side-by-side (revize 2026-06-12)
~~İlk sürümde tek kolonlu unified diff.~~ **Revize:** Diff iki kolonlu **side-by-side** render edilir (sol = eski, sağ = yeni; ekleme yeşil, silme kırmızı, context nötr, karşılıksız satır filler). Monaco DiffEditor portu DEĞİL — kendi saf `SideBySideDiffBuilder` (UnifiedDiff → hizalı sol/sağ hücre satırları) + `SideBySideDiffView` (LazyVStack, satır sarmalı) ile. `UnifiedDiffParser` aynen korunur (parse değişmez; yalnız sunum side-by-side). Eski tek-kolon `DiffAttributedTextBuilder` kaldırıldı. Gerekçe: kullanıcı v1 paritesi istedi; karar 11 (görsel kimlik) ile tutarlı.

### 5. Tek tip hata sözleşmesi + görünür hatalar
Tüm servisler tek hata modeli kullanır (Swift'te typed `Result`/`Error`). Mevcut tutarsızlıklar (çoğu throw, `git:commit` envelope, spawn-limit sessiz `null`, `openExternal` sessiz yutma) taşınmaz; spawn-limit aşımı dahil kullanıcıyı etkileyen her hata görünür bildirimle sunulur.

**Uygulama notu (2026-09-04, refactor Faz 1):** Denetimde bulunan sessiz hata yolları kapatıldı — bu karar artık kodda uçtan uca geçerlidir:
- PTY yazımı EPIPE/hata verirse `TerminalEvent.writeFailed(id, errno:)` akar → toast (`TerminalListStore`). Önceden ölü terminale yazım sessizdi.
- Terminal exit'inde çıkış kodu ≠ 0 ve ≠ SIGHUP ise toast ("Terminal exited with code N"); `statusMachine.onExit(code:)` artık gerçekten çağrılır.
- `PromptQueueStore` enjeksiyon hatasını yutmaz: aynı terminal için **3.** ardışık başarısızlıkta bir kez toast (`injectFailureToastThreshold`) — her denemede basmak kullanıcıyı boğardı.
- `ConfigService` parse/yazım hatası `ConfigEvent.loadFailed` / `.writeFailed` yayar (yalnız console değil).
- `FileSystemOperations` (trash/reveal) `RepoPathGuard` ile izinli kök listesine (projectsRoot + additionalPaths, symlink çözülerek) kapatıldı; dışarısı reddedilir ve görünür hata döner.

### 6. Commit diff lazy-load
Commit seçilince yalnızca dosya listesi yüklenir; diff içeriği dosyaya tıklanınca alınır. `getCommitDiff`'in N+1 `git show` problemi (`12-git-vcs.md`) tasarımla çözülür; UX değişikliği kabul edildi.

### 7. Gerçek gitignore semantiği
File tree ignored-flag'leri `git check-ignore` (veya eşdeğer libgit2 API'si) ile hesaplanır: nested `.gitignore`, global excludes ve `.git/info/exclude` hesaba katılır. Yalnız-kök-`.gitignore` davranışından bilinçli sapma onaylandı.

### 8. Auto-update planlanmıyor
Sparkle entegrasyonu hiçbir faza alınmaz. Dağıtım manuel (DMG/zip). İleride fikir değişirse bu karar güncellenir.

### 9. Persistence formatları korunuyor
Native sürüm `~/.lumi` altındaki mevcut JSON/YAML formatlarını okur ve yazar; geçiş döneminde Electron ve native sürümler arasında gidip-gelme mümkün kalır. `NSWindow` frame autosave gibi native-idiomatik mekanizmalara geçilmez; pencere bounds'u dahil mevcut dosya tabanlı persistence sürer (`30-app-shell.md`).

**Ek (2026-09-04, refactor Faz 1 + 5.7) — persistence'ın tek kapısı `ConfigCodec`:** Config ailesindeki tipler (`AppConfig`, `UIState`, `NotificationSettings`, `SessionTrigger`, `UsageIndicators`, `UsageAutoRefresh`…) **`Codable` DEĞİLDİR**. `Codable` conformance'ı, bilinmeyen/legacy anahtarları sessizce düşüren bir yazım yolu açacağı için bu kararın tuzağıdır. Okuma/yazma yalnız `LumiServices/Config/` altındaki bölüm codec'lerinden (`AppConfigCodec`, `UIStateCodec`, `NotificationSettingsCodec`, `SessionTriggerCodec`, `UsageCodec`, `AdditionalPathCodec`) ve ham-dict overlay merge'inden geçer; skalar okuma tek yerden (`JSONValue`) yapılır — bool asla sayı sayılmaz, string toleransı yalnız kullanım API'lerinde açıktır.

Dosya hiç parse edilemiyorsa (bilinmeyen anahtar koruması artık mümkün değil) defaults'a düşülmeden önce `<ad>.bak-<timestamp>` olarak yedeklenir ve `ConfigEvent.loadFailed` yayılır (karar 5) — önceden ilk yazımda kullanıcının bilinmeyen anahtarları kaybolurdu.

### 10. Terminal içi arama ilk sürümde yok
SwiftTerm search desteğine rağmen kapsam disiplini için parite hedeflenir; arama sonraki sürüme aday feature olarak not edilir.

### 11. Bug düzeltmeleri onaylandı
`00-overview.md` §5 sonundaki "native'de düzeltilmesi önerilen bug listesi" (drop edilen path'in quote'lanmaması, `maxTerminals`'ın üç renderer call-site'ta config'i yok sayması, tanımsız CSS token'ları, ChangesSection/CommitDiffView palet tutarsızlığı vb.) düzeltilmiş davranışla yazılır. Bug paritesi taşınmaz; liste "bilinçli sapma" kaydı olarak spec'te kalır.

### 12. `create-project` action'ı default set'ten çıkıyor
Seed kaynağı bulunamayan `~/.lumi/templates/` bağımlılığı nedeniyle action default set'e konmaz. Action sistemi custom action'ları desteklemeye devam ettiği için kullanıcı isterse kendisi tanımlar.

### 13. Görsel kimlik korunuyor (semantic uyarlama)
Mevcut mor/violet dark tema, JetBrains Mono tipografi ve component görünümleri (`23-design-system.md`) native'de yeniden üretilir. Hedef piksel paritesi değil **semantic uyarlama**: token'lar native renk/spacing sistemine (Asset Catalog / SwiftUI theme katmanı) eşlenir, macOS system look benimsenmez. 23'teki tanımsız-token bug'ları düzeltilerek eşlenir (karar 11 ile tutarlı).

### 14. Action auto-discovery iptal
`docs/plans/2026-02-06-action-auto-discovery.md` (CommandCapture/SessionRecorder/DiscoveryEngine) tamamen iptal edildi; hiçbir sürümde hedeflenmez, doküman arşiv niteliğindedir.

### 15. Grid: iki eksenli model (rows emekli) + maximize/solo
v1'in `auto/columns/rows` tek-eksenli grid'i, dizilim ve yükseklik politikasını iç içe geçirip ("rows" = viewport'a sığar/scroll yok; auto/columns = sabit satır + scroll) zayıf bir UX üretiyordu. Native'de iki eksen ayrılır:
- **Kolon ekseni:** `auto` (genişliğe göre) veya sabit `columns N`.
- **Yükseklik ekseni:** `fit` (hepsi pencereye sığar, scroll yok) veya `scroll` (satır yüksekliği = **kolon genişliği × `heightRatio`** {%100/%50/%33, default %50}; terminal sayısından bağımsız sabit oran, içerik viewport'u aşınca dikey scroll — oran büyüdükçe terminaller uzar, daha çok kaydırma).

`rows` modu **emekli**: yeni yazımda üretilmez, eski/v1 dosyalarında karşılaşılırsa `auto`+`fit`'e migrate edilir. Persistence karar 9 uyumlu kalır — `mode`/`count` alanları korunur, `heightMode` **eklenir** (additive; format değişmez). Ayarlar header'daki butondan açılan sade bir popover'da (Kolon + Yükseklik segmented). Ek olarak tek terminalle rahat çalışmak için **maximize/solo**: bir terminal tam içerik alanını kaplar, diğer görünürler alt şeride iner (oturumluk, persist edilmez). Bu değişiklik `20-renderer-terminal.md` §13'ün yerine geçer.

### 16. Terminal mouse/scroll köprüsü (alt-screen) + SwiftTerm revision pin'i
Alt-screen TUI'lerde (Claude Code, less, vim) scrollback olmadığından SwiftTerm'in buffer-scroll'u tek başına yetmez. Native davranış (v1/xterm.js paritesi):
- **Wheel → uygulamaya:** alt-buffer'da fare tekerleği, TUI mouse mode açtıysa (DECSET 1000/1002/1003; Claude Code hepsini + 1006 SGR'ı açar) pazarlıklı protokole göre kodlanmış wheel event'i olarak (SwiftTerm `encodeButton`+`sendEvent`), mouse mode kapalıysa yön-tuşu dizisi olarak uygulamaya gönderilir. Trackpad'in piksel-hassas delta + momentum seli, hücre-yüksekliği birimli birikimli çeviriyle (`WheelStepAccumulator`) adıma dönüştürülür. Normal buffer'da SwiftTerm'in kendi scrollback kaydırması geçerlidir.
- **Hover bastırma:** SwiftTerm `mouseMoved` upstream bug'ı hover'ı "sol buton release" raporu olarak yollar (TUI caret'i taşır); `anyEvent` (1003) modunda hover event'leri local monitor'da yutulur. Bilinçli trade-off: bu modda Cmd+hover link önizlemesi çalışmaz. Tıklama/sürükleme raporlaması açık kalır (input box'ta caret konumlandırma); TUI çalışırken yerel text seçimi **Shift+sürükle** ile yapılır (SwiftTerm Shift-baypası).
- **Bağımlılık:** SwiftTerm release olmayan revision'a pin'lidir (`24a68bc` — CSI T alt-screen scroll, DEC 2026 render, Shift+mouse düzeltmeleri; gerekçe `LumiPackages/Package.swift` yorumunda). Bu düzeltmeleri kapsayan bir release çıktığında pin sürüm aralığına geri döndürülür; `SwiftTermScrollDiagnosticTests` regresyon bekçisidir.

### 17. Bildirim toggle'ı in-app bell toast'unu da kapsar
v1/spec-13 §4.3'te bell toast sinyali ayardan bağımsız her durumda gönderilirdi; bu "notifications off" beklentisini bozuyordu. Native'de `unseenEnabled` kapalıyken **waiting bell toast'u da gönderilmez**; `error` bell'i ve OS bildirimi (tek seferlik hata sinyali) ayardan bağımsız kalır.

### 18. Terminal customization (v1 spec'ine ek)
v1'de terminal yalnız tek sabit tema + font boyutu sunuyordu. Native'de Settings → Terminal sekmesine dört yeni ayar eklenir; **dördü de hem yeni spawn'lara hem TÜM açık terminallere anında uygulanır** (canlı-uygulama deseniyle; font smoothing toggle'ı karar 29 ile kaldırıldı, stem-darkening sabit kapalı):
- ~~**Renk teması preset'i:** 7 built-in tema~~ — **kaldırıldı (karar 26)**; palet sabit Lumi.. SwiftTerm `installColors` + native bg/fg/cursor/selection.
- **Font ailesi:** sistemdeki monospace aileler; boş = bundle'daki JetBrains Mono. Aile + boyut tek `NSFont`'a birlikte çözülür, çözülemezse JetBrains Mono fallback.
- **Canlı font size:** v1'de yalnız yeni terminaller alıyordu; native'de açık terminallere de anında uygulanır (`terminalView.font` setter zinciri resize + SIGWINCH üretir).
- **Cursor stili + blink:** Block/Underline/Bar × blink → SwiftTerm `CursorStyle` (TUI DECSCUSR ile ezebilir — son-kazanır).

Persistence karar 9 uyumlu: `config.json`'a 3 **additive** key eklenir (`terminalFontFamily`, `terminalCursorStyle`, `terminalCursorBlink`; `terminalTheme` karar 26 ile okunmaz/yazılmaz, diskte kalırsa yok sayılır); eski sürümler bu key'leri görmezse default'a düşer (boş / block / true) ve native bilinmeyen-key korumasıyla diskteki diğer alanlar bozulmaz.

### 19. Zamanlanmış oturum tetikleyici (v1 spec'ine ek)
v1'de yoktu. Kullanıcının 5 saatlik Claude kullanım penceresini her gün belirli bir saatte (örn. iş başı) **öngörülebilir biçimde başlatması** için Settings → **Session** sekmesine eklenir: aktivasyon toggle'ı + saat seçici (yerel HH:MM) + prompt alanı (default `"hello"`) + "Start session now" test butonu. Uygulama açıkken, aktifse, seçilen saatte tetiklenir.

**Mekanizma — UsageService deseninin aynası (kullanıcı kararı):** Tetikleme, çalışan terminallere **dokunmaz**. Usage göstergesinin `claude -p "/usage"` yaklaşımının ([05-usage-indicator.md](./design/05-usage-indicator.md) §1) birebir aynası olarak, arka planda headless bir `claude -p "<prompt>"` süreci spawn edilir (`BinaryLocator` + `ProcessRunner`). Bu istek pencereyi başlatır; **subagent/token maliyeti yoktur, yalnız abonelik kotasından düşer**. Hedef oturum seçimi, "bekleyen oturum" gating'i veya PTY enjeksiyonu **yoktur** — bağımsız tek seferlik bir istektir; açık oturum gerekmez, açık oturuma müdahale edilmez. (Önceki tasarım taslağındaki "bekleyen Claude oturumuna `PromptQueueStore` ile enjekte et" yaklaşımı, "hiçbir şeye dokunma" kullanıcı kararıyla terk edildi.)

Mimari: `SessionStarterServicing` (LumiKit sınırı) → `SessionStarterService` (LumiServices, `UsageService` ile aynı iskelet) → `SessionScheduleStore` (LumiState; config'i izler, `Calendar.nextDate` ile HH:MM'e uyur, `claude -p` çağırır; `isStarting`/`lastRun` durumunu UI'a açar). Config değişimi `ConfigSideEffectCoordinator` köprüsünden akar (karar 3). Başarısızlık `LumiError.sessionStartFailed` ile görünür (karar 5). Önkoşul: CLI'ın authenticated olması (usage ile aynı).

Persistence karar 9 uyumlu: `config.json`'a **additive** `sessionTrigger` nested key'i eklenir (`enabled`/`hour`/`minute`/`prompt`); yoksa kapalı default'a düşer (disabled / 09:00 / "hello") ve bilinmeyen-key korumasıyla diğer alanlar bozulmaz.

**Not (2026-09-04):** Bu kararın terk ettiği "bekleyen oturuma enjekte et" yaklaşımı, **Prompt Queue**'nun kendisini kapsamaz. Prompt Queue ayrı ve canlı bir özelliktir (`PromptQueueStore`, `QueuedPrompt` — eleman başına stabil `UUID`); zamanlanmış tetikleyiciyle ilişkisi yoktur ve tasarım kaydında ayrıca anlatılır.

### 20. Kullanım göstergesi opt-in auto-refresh (2026-06-12 kararının revizyonu)
[05-usage-indicator.md](./design/05-usage-indicator.md) §6.1'de "auto-refresh YOK" diye kayıtlıydı (2026-06-12). Kullanıcı talebiyle (2026-06-15) bu duruş **opt-in** ile revize edildi: default davranış değişmez (bootstrap'te bir kez yükleme + manuel refresh), ama kullanıcı isterse açabileceği periyodik tazeleme eklenir. Settings → **Usage** sekmesi: aktivasyon toggle'ı + aralık seçimi (yalnız {**5, 15, 30**} dk) + son kontrol durumu.

**Aktiflik kapısı (kullanıcı kararı — "uyurken çalışmasın, sadece aktifken"):** Açıkken her `intervalMinutes`'te bir, **yalnızca kullanıcı aktifse** tazelenir. Aktiflik ölçütü idle-gate: sistem-geneli son HID girdisinden bu yana geçen süre (`CGEventSource.secondsSinceLastEventType`) aralıktan **az** ise tazele, değilse atla. **Uyku:** Mac uykudayken process askıya alındığından döngü ateşlenmez; `Task.sleep` `ContinuousClock` kullandığından uyanışta bir kez dönülür ama idle-gate orada da geçerlidir (kullanıcı uyandırmak için girdi verdiyse bir kez tazeler, arka plan uyanışında atlar). Bu sayede ayrı `NSWorkspace` sleep/wake bildirimine gerek yoktur → LumiState AppKit'ten bağımsız kalır. Her tazeleme abonelik kotasından düşer (manuel refresh ile aynı; subagent/token maliyeti yok).

Mimari: `ActivityMonitoring` (LumiKit sınırı) → `SystemActivityMonitor` (LumiServices, CGEventSource; idle sorgusu Accessibility/Input-Monitoring izni GEREKTİRMEZ) → `UsageAutoRefreshStore` (LumiState; `SessionScheduleStore` iskeleti — config'i `update(_:)` ile izler, döngüde uyur/tetikler, `UsageStore.refresh()` çağırır). Config değişimi `ConfigSideEffectCoordinator` köprüsünden akar (karar 3). Persistence karar 9 uyumlu: `config.json`'a **additive** `usageAutoRefresh` nested key'i (`enabled`/`intervalMinutes`); yoksa kapalı default'a düşer (disabled / 15 dk) ve geçersiz aralık izinli set'e clamp'lenir.

### 21. FileViewer'da içerik-tipine göre sunum: render'lı markdown + görsel önizleme (v1 spec'ine ek)
Kullanıcı talebiyle (2026-07-30) FileViewer artık dosya tipine göre sunum seçer (`FilePreviewKind`, uzantı-tabanlı — içerik sniffing yok):

- **Markdown (`.md/.markdown/.mdown/.mkd/.mdx`):** diff ve view modunda **render'lı tek kolon (unified)** akış: başlık ölçekleri, liste işaretleri/girinti, alıntı çubuğu, fence'li kod blokları, tablo satırları, yatay ayraç; satır-içi markdown (kalın/italik/kod/link/üstü-çizili) çözülür. Ekleme/silme kaybolmaz: gutter'da satır no + `+`/`−` işareti ve satır zemininde yeşil/kırmızı. Header'daki **Rendered ⇄ Raw** rozeti ham `SideBySideDiffView`'a döner (oturumluk, persist edilmez). Tek kolon bilinçli: iki kolonda render'lı markdown okunmuyor (satır sarmalı + başlık ölçekleri hizayı bozuyor). Prose fontu proportional, kod monospace — karar 13 tokenları (renkler/zeminler) korunur.
- **Görseller (`png/jpg/jpeg/gif/bmp/tif/tiff/webp/heic/heif/ico`):** metin diff'i yerine **before/after önizleme** (commit-diff'te `sha^:file` ↔ `sha:file`, working-tree diff'inde `HEAD:file` ↔ disk, view modunda tek görsel) + piksel boyutu · dosya boyutu başlığı. Böylece görsel commit'lerde "(binary file)" placeholder'ı yerine gerçek karşılaştırma görünür. Eksik taraf normaldir (eklenen/silinen dosya, root commit) → "(added)"/"(deleted)". **SVG bilinçli olarak metindir** (XML olarak anlamlı diff'lenir).

Mimari: `FilePreviewKind` (LumiKit, saf) + `ImagePreview` modeli; `GitServicing.imagePreview(repoPath:file:sha:)` — liste operasyonları gibi **sessiz** (eksik taraf nil, throw yok; karar 5'in içerik-op kuralından bilinçli sapma çünkü "yok" burada rutin durum), path-traversal guard'ı aynen geçerli (karar 11). Blob'lar `git show <rev>:<path>` ile **ham `Data`** olarak okunur (`ProcessRunner.runRaw` — UTF8 decode kaybı olmadan); taraf başına 20MB sınırı, üstü yüklenmez ve "(too large)" gösterilir. Render tarafı: saf `MarkdownDiffBuilder` (blok ayrıştırma + diff/doküman satır modeli) + `MarkdownInlineStyler` (tema attribute'ları) → `MarkdownDiffView`; görseller `ImagePreviewView`. `UnifiedDiffParser` ve `SideBySideDiffBuilder` değişmedi.

### 22. PTY env: `COLORTERM=truecolor` her zaman set edilir (bug fix, 2026-08-04)
v1 spec'i PTY env'ini `process.env` + `TERM=xterm-256color` olarak tanımlar; `COLORTERM` set edilmez. Bu, launch bağlamına göre değişen davranış üretiyordu: `swift run` (dev) dış terminalin `COLORTERM=truecolor`'ını miras alıp PTY child'a sızdırırken, Finder'dan açılan paketli .app'te değişken hiç yoktu → Claude Code CLI (supports-color tespiti) 256-renk paletine düşüyor ve terminal renkleri **yalnız paketli build'de soluk** görünüyordu (pencere color-space pinlemesi — a8dff8a — bu farkı çözmez; window.colorSpace her iki bağlamda da aynı doğrulandı).

Karar: PTY child'ın gördüğü terminal emülatörü **Lumi'dir** (SwiftTerm, 24-bit destekli); `TERM` gibi `COLORTERM` da miras değerden bağımsız olarak Lumi'nin kendi yeteneğini deklare eder → `TerminalEnvironment.childEnvironment()` her zaman `COLORTERM=truecolor` yazar. Böylece dev ve paketli build aynı (truecolor) çıktıyı alır.

### 23. Claude oturumları Lumi restart'ında devam eder (v1 spec'ine ek, 2026-08-04)
Kullanıcı talebi: Lumi kapatılırken açık Claude chat'leri kaybolmasın; uygulama yeniden açıldığında aynı konuşmalardan devam edilsin. v1'de yoktu (terminaller quit'te ölür, restore yok).

Ampirik bulgular (claude CLI v2.1.221, PTY testleriyle doğrulandı):
- claude çıkışta `Resume this session with: claude --resume <uuid>` basar; uuid, `~/.claude/projects/<cwd-slug>/<uuid>.jsonl` transcript dosya adıyla aynıdır.
- `--session-id <uuid>` ile oturum ID'si **spawn anında dışarıdan atanabilir**.
- `--resume` aynı ID'yi korur (fork yalnız `--fork-session` ile) → ID restart döngüleri boyunca stabildir.
- SIGKILL sonrası bile transcript sağlam ve resume çalışır → quit'te graceful `/exit` **gerekmez**.
- Mesajsız oturumda `claude -r <id>` "No conversation found" ile exit 1 verir.

Mekanizma — çıktı scraping YOK (terminal içeriğinde geçen herhangi bir `claude --resume ...` metni yanlış pozitif üretirdi; ayrıca kill-güvenli ve çoklu-terminal-güvenli olan yol ID'yi baştan bilmektir):
1. **Spawn:** Launch komutunun ilk token'ı `claude` ise ve komut oturum belirleyici flag taşımıyorsa `--session-id <lumi-üretimi-uuid>` enjekte edilir (`ClaudeSessionCommand.prepare`, TerminalSessionManager.spawn içinde — tüm çağrı noktalarını kapsar); ID `TerminalMeta.claudeSessionID`'de taşınır. Komutta `--session-id <uuid>` / `--resume <uuid>` / `-r <uuid>` zaten varsa komut değiştirilmez, ID oradan okunur.
   **Yazım zamanlaması (`LaunchCommandGate`, saha düzeltmesi 2026-08-04):** Launch komutu spawn'dan hemen sonra DEĞİL, shell hazır olunca yazılır — erken PTY yazımı login-shell init'inin girdi flush'una (tcsetattr TCSAFLUSH) denk gelip kaybolabiliyor; sahada `--session-id` claude'a hiç ulaşmadı ve resume boş oturuma düştü. Kapı: shell'in ilk çıktısından sonra 150ms sessizlik (prompt çizimi bitti), hiç çıktı gelmezse 2s üst sınırda yine de yazım. Tüm launch komutlarına uygulanır (codex dahil).
2. **Quit (graceful her yol):** `shutdown()` killAll'dan ÖNCE claudeSessionID'li terminalleri `ui-state.json`'a yazar — additive `resumeSessions` key'i (`[{repoPath, sessionID}]`).
3. **Açılış:** Bootstrap `resumeSessions`'ı okur ve hemen temizler (tek seferlik tüketim); openTabs'ta duran repo'larda `claude --resume <id> || claude` komutuyla terminal spawn eder. `|| claude`: mesajsız/silinmiş oturumda taze claude'a düşer (exit 1 ampirik). Resume komutu da prepare()'dan geçtiğinden meta AYNI ID'yi taşır → sonraki quit'te zincir kesintisiz sürer.

Bilinçli sınırlar: (a) kullanıcının shell'e elle yazdığı `claude` çağrıları izlenmez — terminalin son Lumi-spawn'lı oturumu neyse o devam eder; (b) crash'te persist yoktur, özellik graceful quit kapsamındadır; (c) codex kapsam dışı (eşdeğer session-id/resume CLI yüzeyi doğrulanmadı).

Persistence karar 9 uyumlu: `ui-state.json`'a **additive** `resumeSessions` key'i; eski sürüm görmezse yok sayar, bilinmeyen-anahtar korumasıyla diğer alanlar bozulmaz.

### 24. Gönderimde otomatik minimize (opt-in toggle, v1 spec'ine ek, 2026-08-19)
Kullanıcı talebi: mesaj gönderilen chat, asistan çalışırken grid'de yer kaplamasın; işi bitince ya da girdi bekleyince kendiliğinden geri gelsin.

Davranış (Settings → Terminal → "Auto-Minimize on Send", varsayılan KAPALI):
- Terminal `working`'e geçince (mesaj gönderildi sinyali — Claude'da OSC title, Codex'te input/aktivite; spec/10 §5'in mevcut geçişleri, yeni algılama yok) otomatik minimize edilir ve `autoMinimizedIDs`'te izlenir. Aktif terminal minimize olursa odak mevcut kuralla görünür komşuya kayar (spec/21 §6).
- `working` dışına her geçiş (`waiting-*` / `idle` / `error`) VE "karar bekliyor" sinyali (`awaitingDecisionChanged(true)` — izin promptu da girdi beklemektir) otomatik minimize edileni restore eder. Restore odak VERMEZ — spec/21 §6 değişmezi korunur (odaklı restore yalnız bildirim tıklaması).
- Yalnız bu özelliğin minimize ettikleri otomatik restore edilir: elle minimize edilen chat'e dokunulmaz; elle restore izlemeyi düşürür (kullanıcı niyeti kazanır). Restore branch'i toggle'a bakmaz — özellik kapatılsa bile önceden gizlenen terminal minimize'da mahsur kalmaz.

Mimari: mantık `TerminalListStore.applyAutoMinimize`'da (statusChanged event'i üzerinden, ayrı servis yok); toggle değeri config aynasıdır — bootstrap'te ve `ConfigSideEffectCoordinator` diff'iyle store'a itilir. Persistence karar 9 uyumlu: `config.json`'a **additive** `autoMinimizeOnSend` bool key'i; yoksa/yanlış tipliyse kapalı default.

### 25. Personas ve Quick Actions kaldırıldı (2026-09-04)
Kullanıcı kararı: uygulama sadeleştirilirken sol sidebar'daki **Personas** ve **Quick Actions** bölümleri ve tüm alt yapısı (spec/13 §2–§3: `Persona`/`Action` modelleri, `PersonaServicing`/`ActionServicing`, YAML codec + Yams bağımlılığı, seed/`.history/`, `ActionEngine`, `AgentCommandBuilder`, `PersonasStore`/`ActionsStore`, header dropdown'daki persona girdileri, `default-personas/`/`default-actions/` bundle resource'ları) projeden çıkarıldı.

- `~/.lumi/personas/` ve `~/.lumi/actions/` dizinleri artık okunmaz/yazılmaz; diskte varsa dokunulmaz (karar 9 — silme yok).
- "New <Provider>" dropdown'u yalnız **New Bash** içerir.
- `TerminalServicing.outputStream(id:)` fan-out'u kalır (ileride başka tüketiciler için); `LumiError.actionStepTimedOut` kaldırıldı.
- Orca'dan taşınacak özellikler için yer açar; ileride benzer bir "preset" ihtiyacı doğarsa yeniden tasarlanır, eski YAML şeması bağlayıcı değildir.

### 26. Terminal renk teması seçimi kaldırıldı (2026-09-04)
Sadeleştirme: Settings → Terminal'deki "Color Theme" picker'ı ve altyapısı (`TerminalThemeCatalog`/`TerminalThemeOption`, 7 preset, `AppConfig.terminalTheme`, `TerminalSessionManager.theme`, `ConfigSideEffectCoordinator.onTerminalThemeChanged`) kaldırıldı. `TerminalTheme` tek sabit palete (Lumi) indirildi; spawn'da `DropAwareTerminalView` uygular. `config.json`'daki eski `terminalTheme` key'i okunmaz, yeniden yazımda taşınmaz (bilinmeyen-key koruması diğer alanları korur).

### 27. Header düzeltmeleri: traffic light hit-test, tab overflow (2026-09-04)
- **Traffic light tıklama alanı:** butonlar 28px titlebar container'ının dışına taşındığı için superview bounds'u hit-test'i kırpıyordu (yalnız üst şerit tıklanabiliyordu). Electron `RedrawTrafficLights` paritesi: `TrafficLightLayout` container'ı `TopBarMetrics.height`'a büyütür, butonları içinde ortalar; resize/fullscreen/focus-mode dönüşünde yeniden uygulanır.
- **Tab reorder — YAPILMADI (bilinçli):** sürükle-bırak yeniden sıralama denendi ve geri alındı. Ölçüm: pencerenin üst 28px titlebar bölgesinde SwiftUI hosting içindeki her sürükleme (jest, Button, hatta hosting-dışı kardeş AppKit view) pencereyi de taşıyor; `mouseDownCanMoveWindow`, `isMovable`, `performDrag` override'ı, responder-zinciri kesme ve tracking loop hiçbiri güvenilir biçimde engellemedi. Tab'lar tıklamayla seçilir; sıra açılış sırasıdır.
- **Tab overflow:** şerit artık sabit 600px + ScrollView değil, header'da kalan genişliğin tamamını alır; sığmayan tab'ların metni kısalır (ikon + kapatma her zaman görünür).
- **Modülerlik:** `HeaderBarView` yalnız kompozisyon; `RepoTabStrip`, `NewTerminalButton`, `HeaderControls` ayrı dosyalar.

### 28. File-tree tarama güvenliği: autoreleasepool, symlink takibi yok, tavan, FSEvents filtresi (2026-09-04)
Bug fix: `~` gibi devasa bir dizin `type: repo` olarak eklenip aktif tab olunca uygulama dakikada ~300 MB büyüyüp takılıyordu (2.9M girdi, 1 thread %100). Üç kök neden, dört düzeltme:

- **Autorelease sızıntısı (asıl neden):** `FileTreeBuilder.scan` cooperative pool'da koşar; runloop olmadığı için `contentsOfDirectory`'nin autoreleased NSString/NSURL çöpü tarama bitene kadar drain olmazdı. Artık her dizin kendi `autoreleasepool { }` bloğunda taranır; tür tespiti `lstat` ile yapılır (Foundation çöpü yok).
- **Symlink takip edilmez:** `fileExists(atPath:)` symlink'i çözüyordu → döngülerde sonsuz tarama. `lstat` ile symlink'ler dosya olarak listelenir, içine girilmez (spec/12 §1 "dirent paritesi" notunun bilinçli kararı).
- **Girdi/derinlik tavanı:** `FileTreeBuilder.Limits` (default 100.000 düğüm, 32 derinlik). Tavan aşılınca o seviyenin girdileri listelenir ama alt dizinlere inilmez; sessiz kırpma. Spec/12 §9'daki "sınır YOK" cümlesi bu kararla geçersizdir.
- **Backpressure:** FSEvents üreticisi tam-rescan tüketicisinden hızlıysa unbounded `AsyncStream` şişerdi. `KeyedRefreshCoalescer` (LumiState) tarama uçuştayken gelen event'leri tek follow-up'a çöker; `RepoStore` yalnız `.reposChanged` dinler; tarama `Task.detached` ile actor dışında koşar.
- **Gürültü filtresi:** hardcoded exclude listesine Unity/Xcode/SwiftPM/CocoaPods çıktıları eklendi (`Library`, `Temp`, `Logs`, `obj`, `DerivedData`, `.build`, `Pods`); `RecursiveDirectoryWatcher` bu dizinlere düşen event batch'lerini yutar (`.git` hariç — git panel canlılığı).

Kullanıcıya görünen etki: `Library` adlı gerçek kaynak klasörleri ağaçta soluk görünür ve expand edilemez (kabul edilen bedel). "Repo olarak ekle" akışına ayrı bir uyarı eklenmedi; tavan tek başına güvenliği sağlar.

### 29. Max terminal limiti ve Font Smoothing ayarı kaldırıldı (2026-09-04)
- **Max Terminals:** v1'deki `maxTerminals` config alanı, Settings kontrolü, `TerminalServicing.setMaxTerminals`, spawn guard'ı ve `LumiError.terminalLimitReached` tamamen kaldırıldı; terminal sayısında üst sınır yok. Karar 11'deki "limit yalnız serviste uygulanır" maddesi geçersiz.
- **Font Smoothing:** `terminalFontSmoothing` config alanı ve toggle kaldırıldı; macOS stem-darkening her zaman kapalı (v1 `-webkit-font-smoothing: antialiased` paritesi, `DropAwareTerminalView` + `CGFontRenderingFontSmoothingDisabled`).
- Persistence (karar 9): iki key artık okunmaz/yazılmaz; diskteki mevcut değerler bilinmeyen-key korumasıyla olduğu gibi korunur.

### 30. İnce top bar (Orca paritesi, 2026-09-04)
- v1'in 52px header'ı yerine **36px** ince bar (`TopBarMetrics.height`); bar içi tüm kontroller 26px (`TopBarMetrics.controlHeight`): ikon butonlar, repo chip'leri, New <Provider>, usage ve grid kontrolleri; logo 18px, yazılar 12px.
- Traffic light'lar sola yapışık değil, diğer macOS uygulamalarındaki doğal konumda: ilk buton x=16, barın dikey ortası, 20pt adım (Orca `hiddenInset` + `trafficLightPosition` paritesi). İçerik 80px'ten başlar.
- Karar 27'deki titlebar container büyütme (hit-test) mekanizması aynen korunur; yalnız ölçüler değişti.

### 31. Terminal kart header'ı inceltildi, grid default'u 1 kolon + Fit (2026-09-04)
- Kart header'ı: 20px butonlar, 11px başlık, 3px dikey padding (v1 24px/6px yerine) — top bar (karar 30) ile aynı yoğunluk.
- Kayıtlı yerleşimi olmayan repo için grid default'u `auto/2/scroll` yerine **`columns/1/fit`**: tek terminal pencereyi doldurur, scroll yok. `ui-state.json`'daki mevcut repo yerleşimleri aynen korunur (karar 9).

### 32. Claude + Codex kullanım göstergeleri, Orca'nın eriştiği yollardan (2026-09-04)
- Topbar'da sağlayıcı başına **opt-in** kullanım butonu: Settings → Usage'daki iki toggle (`config.usageIndicators`). Default claude açık (mevcut davranış), codex kapalı. **Kapalı sağlayıcı için hiçbir istek atılmaz** — manuel refresh dahil; kapı `UsageStore.isEnabled`'dadır.
- Butonlarda sağlayıcı marka ikonları (Orca'nın status-bar glyph'leri, SVG olarak taşındı: Claude sunburst, OpenAI knot).
- **Veri kaynağı Orca ile aynı hâle getirildi** (design/05 §1.1):
  - **Claude:** `GET api.anthropic.com/api/oauth/usage`, token macOS Keychain'den (`Claude Code-credentials`) ya da `~/.claude/.credentials.json`'dan. Eski `claude -p "/usage"` yolu **yedek** olarak korundu. Kazanç: anlık, process spawn'ı yok ve **abonelik kotasından düşmüyor**.
  - **Codex:** `codex -c approval_policy=never -s read-only -a never app-server` üzerinden JSON-RPC `account/rateLimits/read`. `~/.codex/auth.json` yoksa `codex` hiç spawn edilmez.
- design/05 §1'in "OAuth ToS gri alanı" gerekçesiyle ertelenen kararı bu kararla değişti: token kullanıcının kendi hesabınındır ve yalnız kendi kullanım verisini okumak için kullanılır.

### 33. Generic shell kompozisyonu: slot / route / toolbar / overlay registry'leri (2026-09-05)
Kabuk (left/right/top/center) artık elle yazılmış bir ağaç değil, **descriptor kaydıyla** kurulan bir kompozisyon (refactor planı Faz 6). Gerekçe: "Tasks" gibi tek bir yeni görünüm eklemek 11 dosya / ~20 dokunuş ve `RootView`/`AppContainer`/`AppDelegate`/`WorkspaceStore`/`SettingsView` merge darboğazı demekti.

- **`ShellContext` (LumiUI) Environment enjeksiyonu:** tüm store'lar + `TerminalViewProviding` + `ShellActions` (reveal/trash/chooseFolder/runChecks/openFile/presentDiff) tek `@Observable @MainActor` bağlamda. `RootView` 14 parametre yerine `.environment(shellContext)` alır; registry'den dinamik kurulan öğelerin `init()`'i boştur, bağlamı Environment'tan okur.
- **Panel yuvaları:** `PanelSlot` (`left`/`right`/`bottom`) + `PanelItemID` + `PanelLayout` (LumiKit, persist edilebilir) ve `PanelItemDescriptor` + `PanelItemRegistry` (LumiUI, saf/test edilir). `PanelHostView(slot:)` listeyi çizer; sol↔sağ taşıma tek `PanelLayout` mutasyonudur. `LeftSidebarView`/`GitSidebar` monolitleri `.sessions`/`.fileTree`/`.gitCommits`/`.gitChanges` öğelerine bölündü.
- **Orta alan route'ları:** `ContentRouteID` + `ContentRouteDescriptor` + `ContentRouteRegistry`; `ContentRouterView` çözer, terminaller `TerminalsRouteView` adında sıradan bir route'tur (maximize/minimized-strip/boş-repo durumu route'un iç meselesi).
- **Toolbar:** `ToolbarRegion` üç bölge (`leading`/`center`/`trailing`) + `ToolbarItemDescriptor` (`order`, `isVisible(ShellContext)`) + `ToolbarRegistry`; `HeaderBarView` üç `ForEach`'e indi.
- **Overlay:** `OverlayDescriptor` + `OverlayRegistry`/`OverlayHost`, `DialogRouter` ile birleşik; elle `||` ile yazılan "input bloklayan overlay açık mı" listesi kalktı.
- **Kayıt yeri:** descriptor **tipleri** LumiUI'da, **kümesi** `LumiAppCore/Composition/ShellComposition.swift`'te. Bir feature kabuğa katkı veriyorsa `ShellContributing`'i uygular (`FeatureAssembly` LumiState'te yaşar ve LumiUI'ı göremez — bu yüzden ayrı protokol).
- **`AnyView` yalnız descriptor düzeyinde** (`makeView`) kullanılır; terminal kartı gibi sıcak yollar asla sarılmaz.

Bağlayıcı sonuç: **yeni bir görünüm/panel öğesi/toolbar öğesi eklemek = 1 assembly dosyası + register satırları.** `RootView`, `PanelHostView`, `HeaderBarView`, `ContentRouterView` düzenlenmez.

### 34. `ui-state.json`'a additive kabuk anahtarları (2026-09-05)
Karar 9 korunarak `~/.lumi/ui-state.json`'a üç **additive** anahtar eklendi:

- **`activeRoute`** (string|null): repo-dışı route kimliği (`WorkspaceRoute.content` rawValue'su). Route bir repo tab'ıysa **null** yazılır; o durumda `activeTab` otoritedir.
- **`panelLayout`** (`{ slots, widths }`) ve **`visibleSlots`** (string dizisi): panel yerleşimi. İkiye ayrılmalarının nedeni, görünürlüğün eski bool'larla aynı bilgi olması ve tek başına okunabilmesi.
- **`leftSidebarOpen` / `rightSidebarOpen`** yazılmaya **devam eder** — artık `visibleSlots`'un projeksiyonudur. Electron'la (ve eski Lumi sürümleriyle) gidip-gelme bozulmaz.
- **Migration kuralı:** dosyada `panelLayout` yoksa yerleşim eski iki bool'dan türetilir (tek seferlik); `PanelLayout` tipi `Codable` değildir, `PanelLayoutCodec`'ten geçer.
- Legacy `activeView` (ve `gridColumns`) tipli modele girmez; bilinmeyen-anahtar korumasıyla diskte aynen kalır.

### 35. `WorkspaceStore` üçe bölündü; route ve viewer sunumu sum type oldu (2026-09-05)
- **`WorkspaceStore` facade'ı kaldırıldı** (Faz 5.2 + 6.1) — geçici bir uyum katmanı olarak bile bırakılmadı, çünkü tek "kabuk store'u" alışkanlığı yeniden god-object üretiyordu. Yerine üç store: **`NavigationStore`** (openTabs, activeRoute), **`LayoutStore`** (visibleSlots, panelLayout, grid, maximize, focus mode; tek `LayoutSnapshot` persist'i), **`DialogRouter`** (5 ayrı bayrak yerine `ActiveDialog` sum type'ı; "input bloklayan overlay açık" otomatik türer). Cross-store davranış `ShellContext` üzerinden kurulur.
- **`WorkspaceRoute`** sum type: `.repo(String)` / `.content(ContentRouteID)` / `.none`. `case tasks` gibi kapalı bir case listesi **bilinçli olarak seçilmedi** — route kümesi registry ile açıktır (karar 33), yeni bir route eklemek enum'a dokunmayı gerektirmemeli. `repoPath` adaptörü `.repo` projeksiyonudur; `onActiveRepoChanged` ve `activeTab` persist'i bunun üzerinden akar.
- **`FileViewerStore.presentation`: `ViewerPresentation`** sum type (`hidden` / `file(...)` / `commit(...)`). Önceki "mode + 4 opsiyonel alan" modeli 48 kombinasyondan ~5'i geçerli olan bir durum uzayıydı ve her sunum yolu diğer alanları elle `nil`liyordu. **Tek hata kuralı (karar 5):** herhangi bir yükleme başarısız olursa içerik `.failed(mesaj)` olur ve toast düşer; modal yeni dosyanın adıyla açık kalır, önceki dosyanın içeriği asla ekranda kalmaz.
- **`OnboardingStore`:** sihirbazın adım/kural/check yürütmesi view `@State`'inden store'a taşındı ("fail bloklar, warn bloklamaz" artık test edilir).

### 36. Composition root: `ServiceRegistry` + `FeatureAssembly` (2026-09-04)
`AppContainer.init` gövdesi tek bir dev fonksiyondu ve her yeni özellik onu büyütüyordu. Yerine:

- **`ServiceRegistry`** (LumiKit) protokolü + `LiveServiceRegistry` / `FakeServiceRegistry`. `LumiPaths.Mode` `#if DEBUG`'dan çıkıp parametre oldu. Tüm process I/O `ProcessRunning` + `BinaryLocating` üzerinden enjekte edilir (statik `ProcessRunner` çağrıları kalktı).
- **`FeatureAssembly` + `BootstrapPhase`** (`system` → `config` → `repo` → `ui`) **LumiState'te** yaşar. LumiKit'te olamaz: assembly store kurar, LumiKit ise store'ları görmez (modül grafiği `LumiKit ← LumiState`). LumiUI'ı da göremediği için kabuk katkısı ayrı bir protokoldür (`ShellContributing`, karar 33). `AppContainer` feature tanımayan ince bir koşucuya indi.
- **`StoreLifecycle`** (`start()`/`stop()` simetrisi) ve **`EventConsumer`**: store'ların `for await` döngüleri tek kalıpta toplandı; `shutdown()` artık hepsini durdurur (önceden yarısı sızıyordu).
- **`AppCommand`/`AppCommands`** (LumiKit) kısayolların **tek kaynağıdır**: `MainMenuBuilder` menüyü, `ShortcutReference` tabloyu, `MenuActionDispatcher` `id → closure` eşlemesini buradan üretir. Yeni komut = 1 satır + 1 handler.
- **`AppDelegate` bölündü:** `MainWindowController` (pencere, bounds persistence, traffic light, fullscreen), `MenuActionDispatcher`, `AppLifecycleBridges` (NotificationCenter token'ları saklanıp kaldırılır).
- **`LumiApp` → `LumiAppCore` (library) + ince `LumiApp` executable** (`main.swift`), böylece composition root test edilebilir (`LumiAppTests`). Paylaşılan fake'ler `LumiTestSupport` target'ında.

### 37. Terminal alt sistemi sınırları: yüzey durumu, watchdog, OSC semantiği (2026-09-05)
- **`TerminalSurfaceState`** (`foreground`/`background`/`minimized`) görünürlük ve odağı **tek kanala** indirdi: `setSurfaceState` atomik olarak coalescer aralığını (16 ms ↔ 100 ms), `statusMachine.onFocus/onBlur`'u ve `activeTerminalID` tutarlılığını birlikte günceller. **Davranış değişikliği:** repo tab'ı/route değiştiğinde arka plana düşen terminaller artık `onBlur` alır — yani odaklıyken bastırılan bildirim, sekme değiştikten sonra gelen "sıra sende"de düşer (önceden görünürlük ve odak bağımsız iki kanaldı; `waitingFocused` yanlış yükselip bildirim ve auto-minimize'i (karar 24) bozuyordu).
- **`TerminalViewProviding`** genişledi: `isAttached(_:)`, `detachAll()`, `refreshAttachedViews()`. Route geçişinde SwiftUI'nin dismantle sırasına güvenmek yerine açık, senkron çağrı yapılır; view'lar yok edilmez.
- **`TerminalServicing` ISP ile bölündü:** `TerminalSessionControlling` + `TerminalAppearanceControlling` + `TerminalViewProviding`. Font/cursor callback dansı silindi.
- **`FeedWatchdog`** eklendi — [design/00-architecture.md Ek A](./design/00-architecture.md) §A.2-10 nihayet implemente edildi: feed süresi ölçülür, 2 sn'lik stall'da `TerminalEvent.stalled(id, Bool)` yayılır ve bütçe aşılınca coalescer eşiği yarıya iner. Terminaller arka planda yaşadığından donmayı başka kimse fark etmezdi.
- **OSC semantiği OCP'ye açıldı:** `OSCStreamParser` yalnız `(code, payload)` üretir; anlamlandırma `OSCSemantics` protokolünü uygulayan enjekte edilmiş zincirdedir (`ClaudeSemantics`, `CodexSemantics`) ve çıktısı açık bir `AgentHint` struct'ıdır. Yeni ajan/OSC dizisi = yeni dosya.
- **`TerminalEventMonitor`:** dağınık global `NSEvent` monitörleri (keyDown/leftMouseDown + N adet wheel/hover) tek `@MainActor` tipte toplandı, enjekte edilir ve `shutdown`'da kaldırılır. **`TerminalInputGate.shared` kaldırıldı**: global bayrak yerine `window.contentView?.hitTest(...)` sorulur — overlay üstteyse olay doğal yoluna gider, yeni bir overlay eklerken "tek satır eklemeyi unutma" riski kalmadı.
- **`TerminalServicing.outputStream(id:)` / `onOutputText` seam'i kaldırıldı** (YAGNI): karar 25'te "ileride başka tüketiciler için kalır" denmişti, tüketici çıkmadı ve `EventBroadcaster`'ı sınırsız büyütüyordu.

### 38. Kullanım göstergesi: aralık seti, TTL cache ve Claude OAuth hata politikası (2026-09-05)
Refactor planındaki K38 sorusu ("kod {1,5} dk vs tasarım {5,15,30} + ≥5 dk TTL — hangisi geçerli?") **tasarım lehine** karara bağlandı (seçenek A):

- **Auto-refresh aralıkları `{5, 15, 30}` dakika, default 5.** Eski dosyalardaki `1` değeri **default'a (5) clamp'lenir** — karar 9 ihlali değildir, tip zaten baştan doğrulayan bir init'e sahipti, yalnız izinli set daraldı.
- **`CachingUsageService`** dekoratörü: `LiveServiceRegistry` her sağlayıcının servisini **300 sn TTL** ile sarar. Yalnız başarı cache'lenir (geçici bir 5xx'i TTL boyunca dondurmak göstergeyi ölü tutardı); hata anında hâlâ taze bir cache varsa o döner. Manuel tazeleme cache'i **`UsageCacheInvalidating`** ile geçersiz kılar. `UsageStore`'un 60 sn'lik `minRefreshInterval` anti-spam kapısı ayrıca durur — biri tıklama sıklığını, diğeri ağ trafiğini sınırlar. En küçük aralığın (5 dk) TTL'den küçük olmaması bu yüzden şarttır.
- **Claude OAuth hata politikası (karar 32'nin gerekçesinin doğal sonucu):** transport hatası, **429** ve **5xx** geçicidir → bir kez jitter'lı yeniden deneme, hâlâ hata varsa `LumiError.usageUnavailable` + stderr log. Bu yollarda `claude -p "/usage"` **yedeğine düşülmez**, çünkü CLI yedeği abonelik kotasından düşer ve geçici bir sunucu hatası yüzünden kotadan yemek karar 32'ye aykırıdır. CLI yedeği yalnız **kalıcı** hâllerde devrededir: token okunamadı, token reddedildi (401/403) veya endpoint tanınmayan bir yanıt/4xx verdi.

### Refactor 2026-09 davranış notları

Faz 1–7 sırasında bilinçli olarak değişen, karar düzeyine çıkmayan kullanıcıya görünür davranışlar:

- **Onboarding:** sistem check'leri artık ekranda **seçili sağlayıcıya** göre koşar (`runChecks(selectedProvider:)`); Codex seçiliyken `claude` yokluğu hata saymaz.
- **Kullanım parser'ları:** `JSONSerialization`'ın bool'u `NSNumber` üretmesi nedeniyle `true` değerleri `1` olarak okunabiliyordu; `JSONValue` sayı okuyucuları bool'u **reddeder**.
- **Git paneli:** kullanıcı bir dosyanın seçimini kaldırdıysa, FSEvents tazelemesi bunu **geri almaz** (`reposWithUserSelection`); önceden istenmeyen dosyalar commit ekranında yeniden seçili hâle geliyordu.
- **Toast ve focus bar** opak zemine geçti (terminal içeriği arkalarından okunmuyor); **modal karartması** tek değere (%60, `ModalOverlay.scrimOpacity`) indi — önceden üç farklı opaklık vardı.
- **Punto ve köşe yuvarlamaları** `Theme.Typography`/`Theme.Radius` token'larına indirgendi; 17 farklı font boyutu ve 9 farklı radius bir sete oturdu (küçük görsel kaymalar bilinçlidir).
- **İkon butonlarına tooltip** (`.help`) ve zorunlu `accessibilityLabel` eklendi (`IconButton`).

## Kapsam özeti

Bu kararlarla native rewrite kapsamı: **mevcut davranış paritesi** (ölü/dormant kod hariç) **+ onaylı bug düzeltmeleri + 5 bilinçli davranış değişikliği** (Settings anlık uygulama, commit-diff lazy-load, gerçek gitignore semantiği, iki-eksenli grid + maximize, side-by-side diff) **− atılan kapsam** (gamification, work-log, create-project action, auto-update, terminal arama, personas + quick actions — karar 25).

Buna ek olarak [design/00-architecture.md Ek A](./design/00-architecture.md)'daki bug-türevli zorunlu gereksinimler (PTY→UI backpressure, render-crash izolasyonu, replay güvenliği) tasarımın başından bağlayıcıdır — Ek A §A.2-10 (feed watchdog) karar 37 ile tamamlandı.

Kararlar 33–38 (2026-09-04/05) kapsamı **büyütmez**; nasıl inşa edildiğini bağlar: kabuk artık registry tabanlı bir kompozisyondur (33), yerleşim additive anahtarlarla persist edilir (34), state ve composition root ayrışmıştır (35–36), terminal sınırları ile kullanım göstergesi politikası nettir (37–38). Uygulama planı ve faz izleri: [refactor-plan-2026-09.md](./refactor-plan-2026-09.md).


### 39. Sekmeli proje paneli (2026-09-05)
Kullanıcının isteğiyle sol Project Context ve sağ Commits/Changes görünümleri kaldırıldı. Yerlerine `RepoFeatureAssembly` tek `projectTools` öğesini sağ yuvaya kaydeder: üstte Explorer, Agent History, Source Control. Sol Sessions kalır; her iki panel toggle'ı yönüne uygun sidebar ikonu kullanır. RootView/PanelHostView değişmez. Eski panel kimlikleri kayıtlı olmadıkları için eski ui-state dosyalarında güvenle atlanır; `projectTools` sağ yuvaya varsayılan kayıt kuralıyla eklenir.

Explorer, Orca'nın kompakt proje araç çubuğu, Names/Contents ad ve içerik araması, Git renkleri/rozetleri, collapse-all, refresh ve görünüm seçeneklerini native SwiftUI'da uygular. Git durumu klasörlere de yansır; silinen alt dosyalar klasöre silinmiş rengi vermez. Unity algısı proje kökünde Assets dizini + ProjectSettings/ProjectVersion.txt gerektirir. Proje başına oturum içi Unity modu yalnız Assets altını gösterir, `.meta` dosyalarını gizler; dosya yolları repo köküne göre kalır. Dotfile/ignored filtreleri bağımsızdır; dosya yaratma ve yeniden adlandırma repo-içi yol doğrulamasından geçer. Yeni yazma yolları symlink bileşenlerini reddeder. İçerik araması binary dosyaları atlar, dosya/byte/sonuç sınırına ulaştığını görünür bildirir. Git durum yolları Unicode ve satır sonlarını koruyan NUL ayracıyla okunur; Explorer ve Source Control, Orca’nın Git renklerini aynı tema fonksiyonundan kullanır.

Agent History, Claude/Codex yerel JSONL kayıtlarının metadata ve sınırlı baş/son örneklerini okuyarak seçili projenin oturumlarını listeler. I/O LumiServices'te, cache/yükleme LumiState'te, sunum LumiUI'dadır. Resume komutu yalnız doğrulanmış session ID ile oluşturulur. Source Control seçili dizinin `git rev-parse --is-inside-work-tree` sonucuna göre görünür (ilk commit'i olmayan repo dahil); mevcut dosya seçimi/commit ve diff altyapısını kullanır. Bu karar eski panel sunumu kapsamını değiştirir; mevcut config dosyası biçimini değiştirmez.

### 40. Source Control > History: commit graph + Create PR (2026-09-05)
History sekmesi Orca modeline geçti: veri kaynağı **tek** `git log HEAD --topo-order --decorate=full -z` çağrısıdır (`GitReading.history`, limit 200). Parent'lar (`%P`) ve ref dekorasyonları (`%D`) commit modeline girer; lane/renk hesabı saf `LumiKit/CommitGraph` içinde yapılır (Orca `buildGitHistoryViewModels` portu), çizim `CommitGraphLaneCanvas` (SwiftUI `Canvas`) ile olur. Palet 5 basamaklıdır ve indeks 0 checkout edilmiş branch'e ayrılmıştır; round-robin bu basamağı atlar. Orca'dan tek bilinçli sapma: parent'sız (root) commit yalnız kendi lane'ini kapatır, yandaki bağımsız tepeyi düşürmez.

Branch başına ayrı `git log` (`commits(repoPath:branch:)`) **kaldırılmadı** — Commits görünümü ve `commitsByBranch` cache'i onu kullanmaya devam eder; History artık ona bağlı değildir. Ref rozetleri satır başına en fazla 2 + "+N" gösterir; sıralama checkout edilmiş ref → yerel branch → uzak branch → tag'dir ve `refs/remotes/*/HEAD` rozet üretmez. Commit satırının sağ tık menüsü: Open Commit, Copy Commit Hash / Short Hash / Commit Message ve — remote GitHub ise — Open on GitHub. Remote normalizasyonu (`ssh`/`scp`/`https` → `owner/repo`) saf `GitRemote` fonksiyonundadır; GitHub dışı host'ta eylem görünmez.

**Create PR** yalnız GitHub remote'lu repoda ve current branch default branch (`main`/`master`) DEĞİLKEN Source Control başlığında görünür; `gh pr create --web --head <branch>` komutunu yeni bir Lumi terminal oturumunda çalıştırır, böylece `gh auth` istemi kullanıcıya görünür. Başlık/gövde düzenlemesi ve PR şablonu Lumi'ye taşınmaz (tarayıcıdaki form kullanılır). `gh` PATH'te yoksa buton görünür ama kapalıdır ("GitHub CLI (gh) not found"); yoklama `BinaryLocating` üzerinden süreç ömrü boyunca bir kez yapılır. **Push/pull/publish-branch kapsam dışıdır** (karar 9'daki "worktree/checkout/pull/push/stash kapsam DIŞI" kuralı sürer): PR akışı yalnızca zaten push edilmiş bir branch için anlamlıdır.


### 41. Proje paneli Orca paritesi düzeltmeleri (2026-09-05)
Kullanıcının Orca ile yan yana karşılaştırmasından çıkan düzeltmeler; kapsam büyümez, sunum ve arama yetenekleri Orca'ya yaklaşır.

- **Commit graph geometrisi:** dal açılış/kapanış köşeleri artık sabit yarıçaplı çeyrek yaydır (yarıçap = bir lane adımı, Orca `A 11 11`); önceki çizim yayı satırın yarı yüksekliğine yayıyor ve 40pt satırda basık elips üretiyordu.
- **Source Control başlığı:** `GitReading.branchSummary` üç hafif komutla upstream adı, ileri/geri commit sayısı ve çalışma ağacı satır istatistiğini (`diff --shortstat HEAD`) getirir; başlık `main  +4,612 -691` / `→ origin/main  ↑2` düzenindedir. Commit butonu bölünmüş buton oldu (sağ ok: Select/Deselect All, Clear Message). Push/pull hâlâ kapsam dışıdır; upstream yoksa "Not published" yazar, eylem sunulmaz.
- **İçerik araması:** sorgu artık `ExplorerContentQuery` (metin + `Aa` büyük/küçük harf + `ab` tam kelime + `.*` regex + include/exclude glob'ları). Arayıcı tüm dosya metninde tek regex koşar, eşleşme konumunu (`column`/`length`) bildirir; vurgu bu konumdan çizilir. Glob eşleyici `*`, `**`, `?` destekler; `/` içermeyen desen dosya adına uygulanır. Geçersiz regex hata mesajı olarak görünür.
- **Custom popover menüler:** panel içindeki `Menu`/`NSMenu` kullanımları `PopoverMenu` (tema uyumlu, hover'lı satırlar, onay işaretli toggle'lar) ile değiştirildi: Explorer görünüm seçenekleri, Source Control `⋯`, Agent History filtre ve satır menüsü. Sağ tık `contextMenu`ları (native) yerinde kalır.
- **Unity otomatik algı:** Unity projesi ilk açılışta `ExplorerOptions.unityDefault` (yalnız Assets) ile açılır; kullanıcı seçeneği bir kez değiştirdiyse yeniden yüklemeler dokunmaz.
- **Agent History detayı:** Claude alt ajanları `<session>/subagents/agent-*.jsonl` + `.meta.json`'dan okunur (`AgentSubagentScanner`: ad/tür/model + mesaj sayısı; meta yoksa ad ilk istemden). Kart düzeni Orca `SessionInlineDetails`: tonlu aksiyon şeridi, FIRST PROMPT (Copy'li "YOU" kartı), LATEST TURNS, SUBAGENTS (N) satırları, WORKTREE (branch + kompakt yol). Satır başlığında `⌃`/`⋯` düğmeleri ve `Claude · N msgs · N subagents · süre · model` metadata'sı vardır. Codex'te alt ajan listesi boştur.
- **Ortak bileşenler:** `SegmentedModeSwitch` (Names/Contents ve Changes/History aynı anahtar) ve `PopoverMenu` LumiUI/Components'a girdi.

### 42. Sağ proje paneli 340px + sabit yükseklikli Commit butonu (2026-09-05)
- **Genişlik:** sağ yuva (`projectTools`) varsayılanı 280 → 340px (`PanelLayout.projectPanelWidth`); sol Sessions ve alt yuva 280'de kalır. Gerekçe: içerik arama şeridi (Aa/ab/.* + include/exclude), commit graph lane'leri ve Agent History alt ajan satırları 280'de sıkışıyordu; Orca'nın yan yana karşılaştırmasında panel belirgin dardı.
- **Migration:** kabuk hiç panel resize sunmadığı için `ui-state.json`'daki `widths.right = 280` daima eski default'tur; codec bu değeri okurken yeni default'a taşır, 280 dışındaki değerler aynen korunur. Format değişmez (karar 9), anahtar aynen yazılır.
- **Commit butonu:** bölünmüş buton `Theme.Row.control` (28pt) sabit yüksekliktedir. Önceki `maxHeight: .infinity` ok yarısı tüm HStack'i esnek yapıp Changes gövdesinin boş alanını yutuyor, buton panel boyunca uzuyordu.

### 43. Alt durum barı: Settings + Keep computer awake + Resource Manager (2026-09-05)
Orca'nın 24px alt barı Lumi'ye taşındı; top bar'daki Settings dişlisi alt barın soluna indi, sağda iki segment var.

- **Kabuk:** alt bar `ToolbarRegistry`'nin iki yeni bölgesidir (`statusLeading` / `statusTrailing`); `StatusBarView` yalnız bu iki bölgeyi dizer, `HeaderBarView` ilk üçünü. Yeni bölge = yeni registry değil; feature'lar alt bara aynı `ToolbarItemDescriptor` ile katkı verir. Focus mode'da header gibi gizlenir.
- **Keep computer awake:** `config.json`'a additive `computerAwakeMode` (`on` / `auto` / `off`, default `off`; bilinmeyen → `off`). `auto` ("Agent") = en az bir terminal `working` iken. Engel IOKit power assertion'ıdır (`PreventUserIdleSystemSleep` + `PreventSystemSleep`; Orca `caffeinate -i -s`'in çocuk süreçsiz karşılığı). `ComputerAwakeStore` mod × çalışan ajan sayısı türevini `withObservationTracking` ile izler, yalnız değişimde sistem çağrısı yapar. Segment: kahve ikonu + mod etiketi + nokta; menü: başlık + "Agent · Active" + üç açıklamalı radyo satırı.
- **Resource Manager:** Orca `collector.ts` yaklaşımı — tek `ps -eo pid=,ppid=,pcpu=,rss=` (5 sn; popover açıkken 2 sn), terminal başına PTY çocuk sürecinin alt ağacı toplanır (`TerminalSessionControlling.processID(for:)` yeni). Gruplama repo bazlı (Lumi'de worktree yok); tek repo varsa düz oturum listesi. LUMI bölümü: ana süreç + terminal ağaçları hariç yardımcı torunlar, RSS sparkline'ı. Kill / Kill all satır içi onay kartıyla (native dialog yok), `TerminalListStore.close` üzerinden. Orca'ya özgü "Restart daemon", worktree silme ve "Clean up workspaces" kapsam dışı.
- **Bilinçli fark:** Orca'daki Ports/SSH/Update/Pet segmentleri ve usage roster pill'i alt bara taşınmadı; kullanım göstergeleri top bar'da kalır (karar 32).
