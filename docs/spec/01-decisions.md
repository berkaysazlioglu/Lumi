# Lumi Native Rewrite — Karar Kaydı

> [00-overview.md](./00-overview.md) §6'daki 14 açık soru 2026-06-11 tarihinde kullanıcı ile birlikte karara bağlandı. Tasarım ve implementasyon fazları bu kararları bağlayıcı kabul eder.

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
Codename üretimi, collection persistence, CollectionProgress bileşeni ve SessionList "NEW" rozeti native spec'e girmez. `collection:get` ile birlikte [00-overview.md](./00-overview.md) §2'deki ölü kapsam listesinin tamamı taşınmaz. Veri modelinde codename alanı için yer ayrılmaz (YAGNI).

### 2. Work-log API'si atılıyor
ConfigManager'daki work-log persistence native servis katmanına taşınmaz. İleride gerçek bir ihtiyaç doğarsa sıfırdan tasarlanır.

### 3. Settings macOS konvansiyonuna geçiyor
"Draft + Save, Escape=discard" modeli terk edilir; System Settings gibi her değişiklik anında uygulanır ve persist edilir. [22-renderer-ui.md](./22-renderer-ui.md)'deki Settings draft-state davranışları parite hedefi değildir. `config:set` yan etki propagasyonunun ([11-ipc-surface.md](./11-ipc-surface.md)) native karşılığı alan-bazına iner: her ayar değişikliği kendi yan etkisini anında tetikler.

### 4. Diff görünümü side-by-side (revize 2026-06-12)
~~İlk sürümde tek kolonlu unified diff.~~ **Revize:** Diff iki kolonlu **side-by-side** render edilir (sol = eski, sağ = yeni; ekleme yeşil, silme kırmızı, context nötr, karşılıksız satır filler). Monaco DiffEditor portu DEĞİL — kendi saf `SideBySideDiffBuilder` (UnifiedDiff → hizalı sol/sağ hücre satırları) + `SideBySideDiffView` (LazyVStack, satır sarmalı) ile. `UnifiedDiffParser` aynen korunur (parse değişmez; yalnız sunum side-by-side). Eski tek-kolon `DiffAttributedTextBuilder` kaldırıldı. Gerekçe: kullanıcı v1 paritesi istedi; karar 11 (görsel kimlik) ile tutarlı.

### 5. Tek tip hata sözleşmesi + görünür hatalar
Tüm servisler tek hata modeli kullanır (Swift'te typed `Result`/`Error`). Mevcut tutarsızlıklar (çoğu throw, `git:commit` envelope, spawn-limit sessiz `null`, `openExternal` sessiz yutma) taşınmaz; spawn-limit aşımı dahil kullanıcıyı etkileyen her hata görünür bildirimle sunulur.

### 6. Commit diff lazy-load
Commit seçilince yalnızca dosya listesi yüklenir; diff içeriği dosyaya tıklanınca alınır. `getCommitDiff`'in N+1 `git show` problemi ([12-git-vcs.md](./12-git-vcs.md)) tasarımla çözülür; UX değişikliği kabul edildi.

### 7. Gerçek gitignore semantiği
File tree ignored-flag'leri `git check-ignore` (veya eşdeğer libgit2 API'si) ile hesaplanır: nested `.gitignore`, global excludes ve `.git/info/exclude` hesaba katılır. Yalnız-kök-`.gitignore` davranışından bilinçli sapma onaylandı.

### 8. Auto-update planlanmıyor
Sparkle entegrasyonu hiçbir faza alınmaz. Dağıtım manuel (DMG/zip). İleride fikir değişirse bu karar güncellenir.

### 9. Persistence formatları korunuyor
Native sürüm `~/.lumi` altındaki mevcut JSON/YAML formatlarını okur ve yazar; geçiş döneminde Electron ve native sürümler arasında gidip-gelme mümkün kalır. `NSWindow` frame autosave gibi native-idiomatik mekanizmalara geçilmez; pencere bounds'u dahil mevcut dosya tabanlı persistence sürer ([30-app-shell.md](./30-app-shell.md)).

### 10. Terminal içi arama ilk sürümde yok
SwiftTerm search desteğine rağmen kapsam disiplini için parite hedeflenir; arama sonraki sürüme aday feature olarak not edilir.

### 11. Bug düzeltmeleri onaylandı
[00-overview.md](./00-overview.md) §5 sonundaki "native'de düzeltilmesi önerilen bug listesi" (drop edilen path'in quote'lanmaması, `maxTerminals`'ın üç renderer call-site'ta config'i yok sayması, tanımsız CSS token'ları, ChangesSection/CommitDiffView palet tutarsızlığı vb.) düzeltilmiş davranışla yazılır. Bug paritesi taşınmaz; liste "bilinçli sapma" kaydı olarak spec'te kalır.

### 12. `create-project` action'ı default set'ten çıkıyor
Seed kaynağı bulunamayan `~/.lumi/templates/` bağımlılığı nedeniyle action default set'e konmaz. Action sistemi custom action'ları desteklemeye devam ettiği için kullanıcı isterse kendisi tanımlar.

### 13. Görsel kimlik korunuyor (semantic uyarlama)
Mevcut mor/violet dark tema, JetBrains Mono tipografi ve component görünümleri ([23-design-system.md](./23-design-system.md)) native'de yeniden üretilir. Hedef piksel paritesi değil **semantic uyarlama**: token'lar native renk/spacing sistemine (Asset Catalog / SwiftUI theme katmanı) eşlenir, macOS system look benimsenmez. 23'teki tanımsız-token bug'ları düzeltilerek eşlenir (karar 11 ile tutarlı).

### 14. Action auto-discovery iptal
`docs/plans/2026-02-06-action-auto-discovery.md` (CommandCapture/SessionRecorder/DiscoveryEngine) tamamen iptal edildi; hiçbir sürümde hedeflenmez, doküman arşiv niteliğindedir.

### 15. Grid: iki eksenli model (rows emekli) + maximize/solo
v1'in `auto/columns/rows` tek-eksenli grid'i, dizilim ve yükseklik politikasını iç içe geçirip ("rows" = viewport'a sığar/scroll yok; auto/columns = sabit satır + scroll) zayıf bir UX üretiyordu. Native'de iki eksen ayrılır:
- **Kolon ekseni:** `auto` (genişliğe göre) veya sabit `columns N`.
- **Yükseklik ekseni:** `fit` (hepsi pencereye sığar, scroll yok) veya `scroll` (satır yüksekliği = **kolon genişliği × `heightRatio`** {%100/%50/%33, default %50}; terminal sayısından bağımsız sabit oran, içerik viewport'u aşınca dikey scroll — oran büyüdükçe terminaller uzar, daha çok kaydırma).

`rows` modu **emekli**: yeni yazımda üretilmez, eski/v1 dosyalarında karşılaşılırsa `auto`+`fit`'e migrate edilir. Persistence karar 9 uyumlu kalır — `mode`/`count` alanları korunur, `heightMode` **eklenir** (additive; format değişmez). Ayarlar header'daki butondan açılan sade bir popover'da (Kolon + Yükseklik segmented). Ek olarak tek terminalle rahat çalışmak için **maximize/solo**: bir terminal tam içerik alanını kaplar, diğer görünürler alt şeride iner (oturumluk, persist edilmez). Bu değişiklik [20-renderer-terminal.md](./20-renderer-terminal.md) §13'ün yerine geçer.

### 16. Terminal mouse/scroll köprüsü (alt-screen) + SwiftTerm revision pin'i
Alt-screen TUI'lerde (Claude Code, less, vim) scrollback olmadığından SwiftTerm'in buffer-scroll'u tek başına yetmez. Native davranış (v1/xterm.js paritesi):
- **Wheel → uygulamaya:** alt-buffer'da fare tekerleği, TUI mouse mode açtıysa (DECSET 1000/1002/1003; Claude Code hepsini + 1006 SGR'ı açar) pazarlıklı protokole göre kodlanmış wheel event'i olarak (SwiftTerm `encodeButton`+`sendEvent`), mouse mode kapalıysa yön-tuşu dizisi olarak uygulamaya gönderilir. Trackpad'in piksel-hassas delta + momentum seli, hücre-yüksekliği birimli birikimli çeviriyle (`WheelStepAccumulator`) adıma dönüştürülür. Normal buffer'da SwiftTerm'in kendi scrollback kaydırması geçerlidir.
- **Hover bastırma:** SwiftTerm `mouseMoved` upstream bug'ı hover'ı "sol buton release" raporu olarak yollar (TUI caret'i taşır); `anyEvent` (1003) modunda hover event'leri local monitor'da yutulur. Bilinçli trade-off: bu modda Cmd+hover link önizlemesi çalışmaz. Tıklama/sürükleme raporlaması açık kalır (input box'ta caret konumlandırma); TUI çalışırken yerel text seçimi **Shift+sürükle** ile yapılır (SwiftTerm Shift-baypası).
- **Bağımlılık:** SwiftTerm release olmayan revision'a pin'lidir (`24a68bc` — CSI T alt-screen scroll, DEC 2026 render, Shift+mouse düzeltmeleri; gerekçe `LumiPackages/Package.swift` yorumunda). Bu düzeltmeleri kapsayan bir release çıktığında pin sürüm aralığına geri döndürülür; `SwiftTermScrollDiagnosticTests` regresyon bekçisidir.

### 17. Bildirim toggle'ı in-app bell toast'unu da kapsar
v1/spec-13 §4.3'te bell toast sinyali ayardan bağımsız her durumda gönderilirdi; bu "notifications off" beklentisini bozuyordu. Native'de `unseenEnabled` kapalıyken **waiting bell toast'u da gönderilmez**; `error` bell'i ve OS bildirimi (tek seferlik hata sinyali) ayardan bağımsız kalır.

### 18. Terminal customization (v1 spec'ine ek)
v1'de terminal yalnız tek sabit tema + font boyutu sunuyordu. Native'de Settings → Terminal sekmesine dört yeni ayar eklenir; **dördü de hem yeni spawn'lara hem TÜM açık terminallere anında uygulanır** (font smoothing canlı-uygulama deseniyle):
- **Renk teması preset'i:** 7 built-in tema (Lumi default + Dracula, One Dark, Nord, Solarized Dark/Light, GitHub Light). SwiftTerm `installColors` + native bg/fg/cursor/selection.
- **Font ailesi:** sistemdeki monospace aileler; boş = bundle'daki JetBrains Mono. Aile + boyut tek `NSFont`'a birlikte çözülür, çözülemezse JetBrains Mono fallback.
- **Canlı font size:** v1'de yalnız yeni terminaller alıyordu; native'de açık terminallere de anında uygulanır (`terminalView.font` setter zinciri resize + SIGWINCH üretir).
- **Cursor stili + blink:** Block/Underline/Bar × blink → SwiftTerm `CursorStyle` (TUI DECSCUSR ile ezebilir — son-kazanır).

Persistence karar 9 uyumlu: `config.json`'a 4 **additive** key eklenir (`terminalTheme`, `terminalFontFamily`, `terminalCursorStyle`, `terminalCursorBlink`); eski sürümler bu key'leri görmezse default'a düşer (lumi / boş / block / true) ve native bilinmeyen-key korumasıyla diskteki diğer alanlar bozulmaz.

### 19. Zamanlanmış oturum tetikleyici (v1 spec'ine ek)
v1'de yoktu. Kullanıcının 5 saatlik Claude kullanım penceresini her gün belirli bir saatte (örn. iş başı) **öngörülebilir biçimde başlatması** için Settings → **Session** sekmesine eklenir: aktivasyon toggle'ı + saat seçici (yerel HH:MM) + prompt alanı (default `"hello"`) + "Start session now" test butonu. Uygulama açıkken, aktifse, seçilen saatte tetiklenir.

**Mekanizma — UsageService deseninin aynası (kullanıcı kararı):** Tetikleme, çalışan terminallere **dokunmaz**. Usage göstergesinin `claude -p "/usage"` yaklaşımının ([05-usage-indicator.md](../design/05-usage-indicator.md) §1) birebir aynası olarak, arka planda headless bir `claude -p "<prompt>"` süreci spawn edilir (`BinaryLocator` + `ProcessRunner`). Bu istek pencereyi başlatır; **subagent/token maliyeti yoktur, yalnız abonelik kotasından düşer**. Hedef oturum seçimi, "bekleyen oturum" gating'i veya PTY enjeksiyonu **yoktur** — bağımsız tek seferlik bir istektir; açık oturum gerekmez, açık oturuma müdahale edilmez. (Önceki tasarım taslağındaki "bekleyen Claude oturumuna `PromptQueueStore` ile enjekte et" yaklaşımı, "hiçbir şeye dokunma" kullanıcı kararıyla terk edildi.)

Mimari: `SessionStarterServicing` (LumiKit sınırı) → `SessionStarterService` (LumiServices, `UsageService` ile aynı iskelet) → `SessionScheduleStore` (LumiState; config'i izler, `Calendar.nextDate` ile HH:MM'e uyur, `claude -p` çağırır; `isStarting`/`lastRun` durumunu UI'a açar). Config değişimi `ConfigSideEffectCoordinator` köprüsünden akar (karar 3). Başarısızlık `LumiError.sessionStartFailed` ile görünür (karar 5). Önkoşul: CLI'ın authenticated olması (usage ile aynı).

Persistence karar 9 uyumlu: `config.json`'a **additive** `sessionTrigger` nested key'i eklenir (`enabled`/`hour`/`minute`/`prompt`); yoksa kapalı default'a düşer (disabled / 09:00 / "hello") ve bilinmeyen-key korumasıyla diğer alanlar bozulmaz.

## Kapsam özeti

Bu kararlarla native rewrite kapsamı: **mevcut davranış paritesi** (ölü/dormant kod hariç) **+ onaylı bug düzeltmeleri + 5 bilinçli davranış değişikliği** (Settings anlık uygulama, commit-diff lazy-load, gerçek gitignore semantiği, iki-eksenli grid + maximize, side-by-side diff) **− atılan kapsam** (gamification, work-log, create-project action, auto-update, terminal arama).

Buna ek olarak [00-overview.md](./00-overview.md) §4'teki bug-türevli zorunlu gereksinimler (PTY→UI backpressure, render-crash izolasyonu, replay güvenliği) tasarımın başından bağlayıcıdır.
