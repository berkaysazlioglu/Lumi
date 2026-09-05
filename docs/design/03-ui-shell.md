# Lumi Native — UI Kabuğu ve State Tasarımı

> App target (AppKit kabuk) + `LumiState` + `LumiUI` modüllerinin bağlayıcı tasarımı.
>
> Durum: 2026-09-05 refactor (Faz 1–7) ile güncellendi.

---

## 1. AppKit / SwiftUI sınırı

| Alan | Sahip |
|---|---|
| App lifecycle, quit akışı | AppKit — `AppDelegate` (~170 satır: yalnız lifecycle + quit) |
| Pencere, traffic light, bounds persistence, key-status → focus, focus-mode yan etkisi | AppKit — `MainWindowController` |
| Menü kurulumu | `MainMenuBuilder` (`LumiKit.AppCommands.all` tablosundan) |
| Menü aksiyonlarının hedefi | `MenuActionDispatcher` (tek `@objc` selector + `CommandID → closure`) |
| NotificationCenter köprüleri (window focus, wake) | `AppLifecycleBridges` (token'ları saklar, `stop()`'ta kaldırır) |
| Kök SwiftUI view'ının kurulumu | `RootViewFactory` (`RootView(registries:)` + `.environment(\.shell, context)`) |
| Pencere içindeki her şey | SwiftUI — tek `NSHostingView` (`RootView`) = `window.contentView` |
| Terminal emülatör view'ları | AppKit; `TerminalViewRegistry` sahipliğinde, SwiftUI'a salt-köprü |
| FileViewer metin render'ı | `NSTextView` (TextKit 2) `NSViewRepresentable` ile (§6) |

App **pure AppKit lifecycle** kullanır (`@main` AppDelegate + `MainWindowController`), SwiftUI `App` protokolü değil. Gerekçe: `.terminateLater` quit akışı, özel traffic-light geometrisi, `fullSizeContentView` ve ui-state.json bounds persistence (karar 9 `frameAutosave`'i dışlar).

Bu beş tip **gerçekten ayrı dosyalardır** (Faz 3.6): tasarımın ilk hâlinde adları geçiyor ama kodda tek bir 436 satırlık `AppDelegate` vardı. Bugün `AppDelegate` yalnız uygulama yaşam döngüsünü ve quit akışını taşır; pencere işleri `Window/MainWindowController.swift`, kök view kurulumu `Window/RootViewFactory.swift`, menü hedefi `MenuActionDispatcher.swift`, bildirim gözlemcileri `AppLifecycleBridges.swift` altındadır.

---

## 2. Pencere, menü, quit

**Pencere:** `NSWindow(styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`; default 1400×900, min 1000×600; traffic light'lar titlebar-layout kancasında (`TrafficLightLayout`) `standardWindowButton(_:)` frame'leriyle doğal macOS konumuna (ilk buton x:16, 36px barın dikey ortası, 20pt adım — karar 30) yerleşir; `acceptFirstMouse` davranış paritesi.

**Bounds persistence (karar 9):** `windowDidMove/windowDidResize` → 500ms debounce → `config.updateUIState { $0.windowBounds = ... }`; maximize anında. Restore'da tüm `NSScreen` workArea'larına karşı overlap doğrulaması; geçersizse default boyut. Maximize state show'dan önce uygulanır (flash önleme).

**Focus köprüsü:** `windowDidBecomeKey/ResignKey` → `terminal.setWindowFocused(_:)` — bildirim semantiği buna bağlıdır (Electron sürümüyle aynı semantikle akmalı, yoksa bildirimler bozulur).

**Menü = TEK kısayol kaynağı, komut tablosu = tek kaynak.** Kısayolların otoritesi `LumiKit/Commands/` altındaki `AppCommands.all` tablosudur (Faz 3.5). `MainMenuBuilder` `NSMenu`'yu **bu tablodan** kurar, `LumiUI.ShortcutReference.all` (Settings → Shortcuts) **aynı tablodan** türer — elle tutulan ikinci bir liste yoktur, iki taraf yapısal olarak ayrışamaz. Bir `AppCommand` `id: CommandID`, `title`, `menu: MenuSection` (`app`/`shell`/`edit`/`terminal`/`view`/`window`), `key`, `modifiers: CommandModifiers` ve `isSystemStandard` taşır.

Tablodaki kısayollar:

| Komut | Kısayol |
|---|---|
| `openSettings` | ⌘, |
| `quit` | ⌘Q |
| `newTerminal` | ⌘T |
| `closeTerminal` | **⌘W — terminali kapatır, pencereyi DEĞİL** (menü interception) |
| `openRepoSelector` | ⌘O |
| `focusTerminalAtIndex` | ⌘1 … ⌘9 (indeks `NSMenuItem.tag`'de) |
| `focusNextTerminal` / `focusPreviousTerminal` | ⌘⇧→ / ⌘⇧← |
| `toggleMaximizeTerminal` | **⌘⌃M** |
| `toggleLeftSidebar` / `toggleRightSidebar` | ⌘B / ⌘⇧B |
| `toggleFocusMode` | ⌘⇧F |
| `minimizeWindow` | ⌘M |
| `cut`/`copy`/`paste`/`selectAll` | ⌘X/⌘C/⌘V/⌘A — platform standardı (`isSystemStandard`), terminal copy-paste için zorunlu; Shortcuts tablosunda **gösterilmez** |

Item'lar `MenuActionDispatcher`'a (@MainActor, app target) hedeflenir: tek `performCommand(_:)` selector'ü, `representedObject`'teki `CommandID`'yi `register(_:_:)` ile kaydedilmiş closure'a çevirir (12 ayrı `@objc` aksiyon yerine). `validateMenuItem` store state okur (örn. aktif terminal yokken ⌘W disabled). **Yeni komut = tabloya bir satır + dispatcher'a bir `register`.** **SwiftUI `.keyboardShortcut` ve `keyDown` handler'ı hiçbir yerde kullanılmaz** — Electron'un çift-kaynak bug sınıfı yapısal olarak silinir.

**Quit akışı (her çıkış yolu):** `applicationShouldTerminate` → canlı terminal varsa `.terminateLater` + `dialogs.presentQuitDialog(terminalCount:)` (custom SwiftUI dialog — görsel kimlik korunur; sonuç `DialogRouter.onQuitResolved` ile geri döner); onay → `await terminal.killAll()` → `NSApp.reply(toApplicationShouldTerminate: true)`; iptal → `false`. Cmd+Q, Dock quit ve logout dahil hepsi bu akıştan geçer. Pencere çarpısı (X) da dahildir: `windowShouldClose` kapatmayı reddedip `NSApp.terminate`'e yönlendirir — dialog pencere içeriğinde yaşadığından pencere önce kapansaydı onay görünmez kalır ve `.terminateLater` cevapsız asılırdı; pencere yalnız uygulama gerçekten çıkarken kapanır. Çıkışta temp dizini (`tmp/lumi*`) silinir.

**Sleep/wake:** `NSWorkspace.didWakeNotification` → watcher tazeleme + repo listesi yenileme. Electron'daki 3-tetikleyicili terminal re-sync zinciri **gerekmez** — terminal state'i tek process'te hiç kopmaz.

**Focus mode:** `LayoutStore.isFocusMode` SwiftUI chrome gizlemeyi + hover-reveal bar'ı sürer (mouse-üstten-50px / `Theme.Motion.hoverRevealDelay` = 500ms / dropdown-açıkken-kal kuralları SwiftUI'da); `MainWindowController` aynı bayrağı `LayoutStore.onFocusModeChanged` ile izleyip traffic-light'ları gizler/gösterir (`TrafficLightLayout.setHidden`). Focus mode panel görünürlüğünü **geçici olarak** ezer: `isSlotVisible(_:)` false döner ama `panelLayout.visibleSlots` (dolayısıyla disk) değişmez — çıkışta eski hâl geri gelir (§7.2). AppKit yan etkileri window controller'da kalır; store AppKit'siz kalır.

---

## 3. Terminal view'larının SwiftUI dışında sahipliği (yük taşıyan desen)

- `TerminalViewRegistry` (@MainActor, `LumiTerminal` içinde; `LumiKit.TerminalViewProviding` implementasyonu) spawn'da SwiftTerm tabanlı NSView'ı yaratır ve **PTY ömrü boyunca retain eder**. SwiftUI asla sahip olmaz.
- **`TerminalViewProviding` yüzeyi (LumiKit, K37):** `attachView(for:into:)`, `detachView(for:from:)`, `isAttached(_:)`, `detachAll()`, `refreshAttachedViews()`. Protokol LumiKit'te yaşar ki LumiUI, LumiTerminal'i import etmeden terminal host edebilsin. `detachAll()` ve `isAttached(_:)` route geçişinin **açık** kapanışıdır: SwiftUI'nin dismantle sırasına güvenmek yerine tek senkron çağrı (§7.3).
- `TerminalHostView: NSViewRepresentable` (`LumiUI`): `makeNSView` boş bir `TerminalHostContainer` döner; `updateNSView` → `registry.attachView(for:into:)`; `dismantleNSView` → yalnız `detachView`. `.id(terminalID)` ile yapısal kimlik sabitlenir.
- **`attachView` = reparent + görünürlük sinyali; frame'e DOKUNMAZ (Faz 4.5).** Görünürlük sinyali (`onVisibilityChange(true)`) yüzeyi `.foreground`'a alır ve `pokeRepaint()` (SIGWINCH) ile TUI'yi yeniden çizdirir — `needsDisplay` tek başına boş kart bırakırdı. Ayrı bir `onRedraw` kancası **yoktur**: her iki tetikleyicisi de attach olayına düştüğü için tam çizim görünürlük kanalına katlandı. `refreshAttachedViews()` de fit yapmaz; superview'a `needsLayout = true` verip yeni bir layout geçişi ister (fullscreen giriş/çıkışı gibi AppKit'in hiyerarşiyi taşıdığı geçişlerin onarımı).
- **Frame otoritesi tek yerdedir — `TerminalHostContainer.pinTerminalView` → `LumiKit.TerminalGridFit.fit`.** `fit` başka hiçbir yerden çağrılmaz. Fonksiyon emülatör satır/sütun sayısını `Int(boyut / hücre)` ile aşağı yuvarlar; view tam host bounds'una oturtulursa artan boşluk (bir satır yüksekliğine kadar, 13pt'de ~16px) tamamen alta ve sağa düşer ve terminal kart çerçevesine asimetrik oturur. Bu yüzden view ızgaranın fiilen kapladığı alana (hücre boyutunun tam katı) oturtulup host içinde **ortalanır**. Hedef frame hücre boyutundan aritmetikle türediği için **idempotenttir** — delta yoksa `false` döner, gereksiz redraw doğmaz; küçültme satır/sütunu değiştirmediği için ek PTY resize da doğmaz. View'lara `autoresizingMask` **verilmez** (ızgara katı olmayan bir boyuta esnetip aradaki karelerde gereksiz cols/rows değişimi doğururdu).
- **`TerminalHostContainer` reassert'i:** container her `setFrameSize`/`layout` geçişinde önce `reassertAttachment()` sonra `pinTerminalView()` çağırır. Reassert **zaten bağlıysa tam no-op**'tur (aksi hâlde her frame'de görünürlük sinyali → tam çizim tetiklenir, resize/animasyon boyunca N terminal × frame maliyeti doğardı); yalnız view başka bir host'a kaçmışsa geri çeker. Simetrik olarak `detachView` kaldırmayı bir sonraki runloop'a erteler ve view o ana dek başka bir container'a taşınmışsa dokunmaz — grid ⇄ maximize round-trip'indeki reparenting yarışına karşı.
- Font değişimi hücre boyutunu değiştirdiğinden `TerminalPresentation.setFont` → `onLayoutInvalidated` → `TerminalViewRegistry.invalidateLayout(for:)` host'a `needsLayout` işaretler; oturum superview'a doğrudan dokunmaz ([01 §2.1](./01-terminal-subsystem.md)).
- **Girdi yönlendirme:** klavye/tıklama/tekerlek olayları tek `TerminalEventMonitor`'dan geçer ve hedef terminal `window.contentView?.hitTest(...)` ile bulunur. Global `TerminalInputGate.shared` bayrağı **kaldırıldı** (Faz 4.6): overlay üstteyse hit-test zaten terminale ulaşmaz, dolayısıyla yeni bir görünüm eklerken "kapıyı güncellemeyi unutma" riski yoktur ([01 §4.1](./01-terminal-subsystem.md)).
- Sonuç: SwiftUI bir container'ı yıksa bile (tab değişimi, grid mod değişimi, minimize, route değişimi) emülatör view'ı ve state'i registry'de yaşar — **re-render hiçbir koşulda terminal state'ini yok edemez**. Detach edilen oturumda coalescing genişler ve çizim durur ([01 §3.4](./01-terminal-subsystem.md)); attach = reparent + görünürlük sinyali + host'un tek fit'i.

---

## 4. Store'lar (`LumiState`)

Hepsi `@Observable @MainActor final class`. **Tek process ⇒ doğrudan gözlem:** `syncFromMain`, snapshot reconciliation, event bridge **yoktur**. **Ham terminal çıktısı hiçbir store'da, asla.**

**`WorkspaceStore` YOKTUR** (K35, Faz 5.2/6.1): kabuk state'i üç ayrı store'a bölündü ve facade kaldırıldı.

| Store | Tuttuğu (yalnız UI/metadata) | Beslendiği | Kritik kurallar |
|---|---|---|---|
| `NavigationStore` | `openTabs: [String]` (**repo path** — ad-çakışması bug fix'i, karar 11), `activeRoute: WorkspaceRoute` | UI intent'leri; açılışta `ui-state.json` (tek seferlik ad→path migration) | `activeRepoPath` `.repo` projeksiyonudur; `onActiveRepoChanged` yalnız `.repo`'da ateşlenir. Route geçişinin terminal yan etkileri `applySurfaceTransition` sözleşmesinde (§7.3). Tab kapatma: minimize guard'ı → repo terminallerini kill → `onTabClosed` (cache eviction) |
| `LayoutStore` | `panelLayout: PanelLayout` (slots/visibleSlots/widths), `projectGridLayouts: [String: GridLayout]`, oturumluk `maximizedByRepo: [String: TerminalID]`, `isFocusMode` | UI intent'leri; açılışta `UIState` | Panel intent'leri: `toggleSlot`/`setSlotVisible`/`move(item:to:index:)`/`setWidth` — hepsi `PanelLayout`'un immutable mutasyonlarına iner ve **değişmediyse yazmaz**. Persist tek `LayoutSnapshot` üzerinden; `isFocusMode` ve `maximizedByRepo` persist **edilmez**. `evict(repoPath)` tab kapanınca çağrılır |
| `DialogRouter` | `active: ActiveDialog` (5 ayrı bool yerine sum type), `collapsedRepoGroups` | UI intent'leri + AppKit quit akışı | `isInputBlockingOverlayOpen` elle `\|\|` listesinden değil `active`'den **türer**. Quit sonucu `onQuitResolved` ile AppDelegate'e döner |
| `TerminalListStore` | **Sıralı** `[TerminalMeta]`, `activeTerminalID`, `minimizedIDs`, `awaitingDecisionIDs`, `stalledIDs`, `lastActiveByRepo`, `surfaceRepoPath` | `TerminalEvent` stream | Kapanışta komşu-odak (silmeden önce hesap: önceki → sonraki → ilk, aynı repo); minimize-asla-otomatik-odak (tek istisna: bildirim tıklaması); yüzey intent'leri `setTerminalSurfaceVisible(_:in:)` / `deactivateSurface()` ([01 §3.4](./01-terminal-subsystem.md)); `isFailureExit(_:)` → exit toast'ı |
| `PromptQueueStore` | `queues: [TerminalID: [QueuedPrompt]]`, `pausedIDs` | `TerminalEvent` stream | §4.1 |
| `RepoStore` | `repos`, kaynak-gruplu görünüm, `fileTrees` cache (stale-while-revalidate, scroll-pozisyon korumalı yenileme) | `RepoEvent` stream | Event → tam yeniden çekme (pull-after-push). Aktif tab'ın reposunu watch eder, tab kapanınca unwatch. `additionalPaths` `private(set)` + intent (iki yazar sorunu, Faz 5.4) |
| `GitStore` | Repo başına commits/branches/status cache'leri; `selectedCommit`, `commitFiles`, `[FilePath: Loadable<UnifiedDiff>]` | `RepoEvent.fileTreeChanged` invalidation + intent'ler | Lazy commit-diff (karar 6). Eşzamanlı `git log` tavanı (TaskGroup sınırı) — N branch × 2 process patlaması kapatıldı |
| `FileViewerStore` | `presentation: ViewerPresentation` (`hidden` / `file(repoPath, filePath, mode, Loadable<ViewerContent>)` / `commit(repoPath, CommitContext, filePath?, Loadable<ViewerContent>)`), `rendersMarkdown` | intent'ler + `GitContentReading` | 4 opsiyonel + mode kombinasyonu (48 durum, 5 geçerli) yerine sum type; elle nil temizliği yapısal olarak kalktı. `content` tek bir `Loadable`'dır ⇒ **tek hata kuralı**: yükleme hatası yalnız burada yaşar, ayrı bir `errorMessage` alanı yok. `isRenderedMarkdown` = `previewKind == .markdown && rendersMarkdown` **türevidir** |
| `SettingsStore` | `AppConfig` alanlarının binding aynası | `ConfigEvent` stream | **Anlık uygulama (karar 3):** her kontrol değişikliği → `config.update {}`; yan etkiler `ConfigSideEffectCoordinator`'dan. Draft/Save/Escape yok. Kısmi güncellemeler (`updateNotifications`/`updateTrigger`/`updateUsageAutoRefresh`) **taze okur** — body-anı snapshot'ı ayar clobber'ına yol açıyordu (Faz 1.2) |
| `SessionScheduleStore` | Günlük tetikleyicinin zamanlayıcısı | `update(_:)` ile config | Belirli saatte headless `claude -p` isteği |
| `UsageStore` (sağlayıcı başına) | Bir sağlayıcının kullanım snapshot'ı | `UsageServicing` | [05](./05-usage-indicator.md) |
| `UsageAutoRefreshStore` | Opt-in otomatik tazeleme zamanlayıcısı (karar 20) | `update(_:)` ile config | Yalnız kullanıcı aktifken tetikler |
| `ToastStore` | `[Toast]` (max 5, 5sn auto-dismiss `Task`'leri, `LumiError` eşitliği/mesajla dedupe) | diğer store'lar `reporting {}` ile | Uygulamanın tek hata lavabosu (karar 5) |
| `OnboardingStore` | Adım durumu + sistem kontrolleri | `SystemServicing` | "fail bloklar, warn bloklamaz" burada test edilir (view `@State`'inde değil) |
| `FileTreeSearchModel<Rows>` | Arama kutusunun debounce/iptal/sonuç-sırası durum makinesi | UI girdisi | View'dan çıkarıldı (dört `@State` + elle Task yerine) |

**Sahiplik:** `SharedStores` yalnız birden fazla feature'ın ya da AppKit kabuğunun dokunduğu store'ları taşır — `toasts`, `navigation`, `layout`, `dialogs`, `terminals`, `settings`. Kalanlar feature assembly'sinin içindedir: `promptQueue` (terminal), `repos`/`git`/`fileViewer` (repo), `usage`/`usageAutoRefresh` (usage), `sessionSchedule` (zamanlanmış oturum), `onboarding` (workspace boot).

**`StoreLifecycle` sözleşmesi** (Faz 3.4) servis stream'i tüketen store'ların tek kalıbıdır — `TerminalListStore`, `SettingsStore`, `RepoStore`, `PromptQueueStore`, `SessionScheduleStore`, `UsageAutoRefreshStore`:

- `start()` **idempotent**'tir: ikinci çağrı ikinci tüketici kurmaz.
- `stop()` **eşzamanlı**dır: döndükten sonra hiçbir event state'i değiştiremez.
- `stop()` sonrası `start()` temiz bir tüketiciyle devam eder.
- `update(_:)` artık yaşam döngüsü değil yalnız **config değişimi** yoludur.

Garantiyi `EventConsumer` taşır: stream Task'tan **önce** senkron alınır (boot penceresinde event kaybı yok) ve bir **nesil sayacı** tutulur — `stop()` nesli ilerletir, `for await`'te askıda kalmış eski tüketici uyandığında neslini doğrulayamaz ve hiçbir mutasyon uygulamadan çıkar (start-stop-start'ta aynı event iki kez uygulanamaz).

**Environment enjeksiyonu:** store'lar view'lara **parametre olarak geçmez**. Kabuğun tek bağlamı `LumiUI.ShellContext`'tir; `RootViewFactory` onu `.environment(\.shell, context)` ile koyar, view'lar `@Shell private var shell` (`@Environment(\.shell)` sarmalayıcısı) ile okur (§7.1).

**Hata koridoru:**

```swift
@MainActor public final class ToastStore {
    /// Senkron ve async iki aşırı yüklemesi vardır; ikisi de "başarılı mı"
    /// bilgisini `Bool` olarak döndürür (çağıran akışı buna göre kesebilsin).
    @discardableResult public func reporting(_ operation: () throws -> Void) -> Bool
    @discardableResult public func reporting(_ operation: @MainActor () async throws -> Void) async -> Bool
    // yakalama: LumiError → show(error:); diğer her hata → .underlying(domain:message:)
}
```

**Bootstrap UI zinciri** (native'e indirgenmiş): loading ekranı → `isFirstRun` → onboarding (4 adım: Welcome/SystemChecks/ProjectsRoot/Ready; fail bloklar, warn bloklamaz) **veya** `repos + additionalPaths` paralel yükle → `uiState` yükle (migration repo listesini okur) → ana UI. `syncFromMain` adımı yoktur.


### 4.1 Prompt kuyruğu (`PromptQueueStore`)

Tasarımın ilk hâlinde hiç yoktu; canlı bir özelliktir (karar 19'un yanında ayrı yaşar). Kullanıcı çalışan bir terminale prompt biriktirir, kuyruk terminal **girdi beklemeye geçtiğinde** kendi kendine akar.

- Model: `LumiKit.QueuedPrompt` (`id: UUID` + `text`). Stabil id şart: liste `id: \.offset` ile çizildiğinde `.onMove` sırasında satır kimlikleri kayıyordu. Kuyruk **persist edilmez** (oturumluk — karar 9 biçimleri değişmez).
- Enjeksiyon koşulu saf bir predikattır (`canInject`): kuyruk boş değil **ve** duraklatılmamış **ve** karar beklenmiyor (`awaitingDecisionIDs` — OSC 9 permission sinyali, [01 §3.1](./01-terminal-subsystem.md)) **ve** durum `isWaiting`. Koşul sağlanınca kısa bir settle gecikmesinden sonra kuyruğun başı yazılır; koşul bozulursa bekleyen görev iptal edilir.
- Yazım `LumiKit.PromptInjection.encode(_:)` ile **bracketed paste** (DECSET 2004) olarak kodlanır: `ESC[200~` + metin + `ESC[201~` + tek `CR`. Çok satırlı prompt'ta aradaki newline'lar erken submit'e yol açmaz; sondaki newline'lar kırpıldığı için çift submit de olmaz.
- Hata yutulmaz (karar 5, Faz 1.14): başarısız yazımda kuyruk **korunur**, `injectFailureToastThreshold` ardışık hatada bir kez toast basılır.
- Terminal `exited` olduğunda o terminale ait kuyruk, duraklatma ve sayaçlar temizlenir.
- View'lar (`LumiUI/PromptQueue/`): `PromptQueueToggleButton` (kart başlığındaki sayaç/rozet), `PromptQueuePanel` (kompozisyon + liste), `PromptQueueRow` (tek eleman, sil/sürükle), `PromptQueueOverlayModifier` (kartın üzerine bindirme).

---

## 5. Tasarım sistemi (karar 13: semantic uyarlama)

`LumiUI` klasörleri: `Theme/`, `Components/`, `Form/`, `Settings/`, `Shell/`, `Terminal/`, `Sidebar/`, `FileViewer/`, `Usage/`, `PromptQueue/`, `Presentation/`, `Preview/`, `Support/`.

**Renk.** `Theme` namespace'i (`Theme/Theme.swift`): zemin `#0a0a12 / #12121f / #1a1a2e`, metin `#e2e2f0 / #8888a8 / #4a4a6a`, accent `#a78bfa / #8b5cf6 / #7c3aed / #22d3ee / #4ade80 / #fbbf24 / #f87171`, border `#2a2a4a` + glow. macOS system look benimsenmez. Git-status renk paleti tek kaynaktadır (karar 11).

**Tipografi (`Theme+Typography.swift`).** JetBrains Mono (Apache 2.0) launch'ta `CTFontManagerRegisterFontsForURL` ile kaydedilir (`LumiFonts`). `Theme.Typography.Size` `Comparable` bir ölçek taşır:

| Ad | pt | Ad | pt |
|---|---|---|---|
| `micro` | 8 | `title` | 15 |
| `tiny` | 9 | `headline` | 18 |
| `caption` | 10 | `heading` | 20 |
| `label` | 11 | `display` | 22 |
| `body` | 12 | `hero` | 34 |
| `base` | 13 (taban) | `splash` | 44 |

`Size.scale` sıralı listedir ve `stepped(_ offset:)` ölçekte kaydırır (markdown başlık kademeleri gibi türev boyutlar için — ara değer uydurulmaz). Font fabrikaları: `mono(_:weight:)`, `ui(_:weight:)`, `rounded(_:weight:)` + hazır semantik sabitler.

**Metrikler (`Theme+Metrics.swift`).** `Theme.Radius`: `sm 4` / `md 6` / `lg 8` / `panel 16`. `Theme.Spacing`: `xxxs 1` / `xxs 2` / `xs 4` / `sm 6` / `md 8` / `lg 12` / `xl 16` / `xxl 24` / `xxxl 32`. `Theme.Stroke.hairline 1`. Her ikisinin de `scale` dizisi vardır (lint testi bunları okur).

**Hareket (`Theme+Motion.swift`).** Süreler `quick 0.12` / `standard 0.2` / `panel 0.3` / `pulse 1` + hazır `Animation` sabitleri (`quickEase`, `standardEase`, `standardOut`, `panelEase`, `statusPulse`). Gecikmeler ayrı `Duration` sabitleridir: `hoverRevealDelay 500ms`, `hoverOpenDelay 350ms`, `hoverCloseDelay 200ms`, `searchDebounce 150ms`. StatusDot durum renk sistemi (working=success+pulse, waiting-unseen=warning+pulse, …) birebir korunur.

**Diff (`Theme+Diff.swift`).** `Theme.Diff.backgroundOpacity = 0.13` ve `diffForeground(for:)` / `diffBackground(for:)` (SwiftUI `Color` ve `NSColor` sürümleri). Diff renk eşlemesinin üç kopyası buraya konsolide edildi.

**`Components/`** (paylaşılan, store bilmeyen bileşenler): `IconButton`, `HoverButtonStyle`, `Badge`, `Keycap`, `Panel`, `ModalOverlay`, `SectionHeader`, `InfoCard`, `EmptyStatePlaceholder`, `ProviderIcon`.
**`Form/`** (eski "yalnız Settings" kısıtı kalktı): `LumiField`, `LumiTextInput`, `LumiToggle`, `LumiSegmented`, `LumiBrowseButton`, `LumiSectionTitle`.

**Lint kilitleri** (Faz 7.1/7.6/7.7 — göç tamamlandı, bütçe **sıfır**):

| Test | Kilitlediği |
|---|---|
| `DesignTokenLintTests` | Modülde literal `.font(.system(size:` ve literal `cornerRadius` sayısı **0**; yeni literal derleme değil test hatası verir |
| `IconButtonAccessibilityTests` | `IconButton` boş/boşluk-only `accessibilityLabel` reddeder; **hiçbir çağrı yeri boş label geçmez**; hiçbir dosya `HoverButtonStyle` yerine kendi `@State isHovering`'ini tutmaz |
| `PreviewGuardLintTests` | Her `#Preview` bir `#if DEBUG` içinde |

**Preview altyapısı.** `Preview/PreviewFixtures.swift` `ShellContext.preview()` fabrikasını verir (LumiTestSupport'a bağımlı olmadan, modül içi hafif fake'lerle); her preview `\.shell` Environment'ını bu bağlamla kurar. `UsageStore.preview(provider:percent:)` ve örnek repo/diff fixture'ları da buradadır.

**Erişilebilirlik.** `IconButton` `accessibilityLabel`'ı **zorunlu** parametredir (yukarıdaki lint testi bunu çağrı yerlerinde de doğrular); dekoratif öğeler `accessibilityHidden`; tıklanabilir göstergeler `onTapGesture` değil `Button`'dır.

**Settings (`Settings/`).** Eski 820 satırlık tek dosya bölündü: `SettingsShell` (kap + kapatma), `SettingsNav` (sol sekme listesi), `SettingsTab` (enum: `general`/`terminal`/`appearance`/`notifications`/`session`/`usage`/`shortcuts` + başlık/ikon/içerik eşlemesi) ve `Tabs/` altında sekme başına bir dosya. Her sekme `SettingsTabContent` protokolüne uyar ve yalnız ihtiyacı olan store'u Environment'tan okur.

---

## 6. FileViewer v1 metin stack'i

- **Görüntüleme modu:** `NSTextView` (TextKit 2, non-editable) + **Highlightr** (highlight.js → `NSAttributedString`); Lumi violet paletinden üretilmiş custom highlight.js teması; JetBrains Mono 13. Highlight main-actor dışında; **~1MB üstü dosyada düz metne düşülür** (Highlightr'ın JSCore maliyeti nötralize edilir). Dil eşleme tablosu uzantı→dil haritasından.
- **Side-by-side diff modu (karar 4 revize):** `GitServicing`'in tiplenmiş `UnifiedDiff` modeli → saf `SideBySideDiffBuilder` (hizalı sol/sağ hücre satırları: del[i]↔add[i], context iki tarafta, fazlalar filler) → `SideBySideDiffView` (SwiftUI `LazyVStack`, satır sarmalı, kolon başına gutter + arka plan renkleri Theme token'larından). Monaco portu değil; `UnifiedDiffParser` korunur (yalnız sunum değişti). Eski tek-kolon `DiffAttributedTextBuilder` kaldırıldı.
- **Render'lı markdown modu (karar 21):** `.md` ailesi dosyalarda hem view hem diff modu **tek kolon (unified)** render'lı akışa düşer: saf `MarkdownDiffBuilder` (`UnifiedDiff` → blok stili çözülmüş satırlar; `buildDocument(_:)` ile tam metin → aynı model) + `MarkdownInlineStyler` (inline-only `AttributedString` parse'ı üzerine tema attribute'ları: kod monospace+cyan, link accent+altçizgi) → `MarkdownDiffView` (LazyVStack; başlık ölçekleri, bullet/ordered girinti kademeleri (2 boşluk = 1 kademe, max 4), alıntı çubuğu, fence'li kod bloğu zemini, tablo/ayraç). Fence durumu **hunk başına** sıfırlanır (hunk'lar süreksiz). Diff işaretleri korunur: gutter'da satır no + `+`/`−`, satır zemininde success/error opacity 0.13. Header'daki **Rendered ⇄ Raw** rozeti (`FileViewerStore.rendersMarkdown`, oturumluk) ham side-by-side görünüme döner.
- **Görsel önizleme modu (karar 21):** görsel uzantılarında diff yerine `ImagePreviewView`: commit-diff/diff'te BEFORE ⇄ AFTER panelleri (`ImagePreview.before/after` → `NSImage(data:)`), view modunda tek görsel; her panelde `pixelsWide×pixelsHigh · ByteCountFormatter` başlığı, `bgDeep` zemin (saydam PNG sınırları görünür). Eksik taraf "(added)"/"(deleted)", 20MB üstü "(too large)", çözülemeyen kodek "(unsupported image format)".
- **Değiştirilebilirlik:** view yalnız `SyntaxHighlighting` protokolüne bağlanır. Protokol **LumiKit**'tedir (`Protocols/SyntaxHighlighting.swift`), imzası `@MainActor func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString`'tir (dil çözümlemesi çağıranın değil implementasyonun işidir). Tek implementasyon `HighlightrEngine` **LumiServices**'tedir (Faz 7.5): JSCore + arka plan kuyruğu view modülünden çıktı, `plainTextCutoffBytes = 1 MB` üstünde düz metne düşülür. View'a `ShellContext.highlighter` ile ulaşır. Highlightr yetersiz kalırsa tree-sitter'a (SwiftTreeSitter/Runestone) view'a dokunmadan geçilir; v1'de grammar-bundle maliyeti salt-okunur viewer için alınmaz.
- **Saf builder'lar LumiKit'tedir** (`Diff/`): `SideBySideDiffBuilder` ve `MarkdownDiffBuilder` view modülünden çıkarıldı; `MarkdownInlineStyler` (AppKit attribute'ları) LumiUI'da kaldı.
- **Render kalıbı:** pahalı dönüşümler `body`'de değil `.task(id:)` içinde koşar (Faz 1.3) — içerik değişince **bir kez**; `GeometryReader` altındaki her `body` çağrısında yeniden parse yoktur. Görsel önizlemede `NSImage(data:)` decode'u ve caption üretimi (`ImagePreviewCaption.make`) de `body`'den `.task(id: data)`'ya taşındı.
- **Rendered ⇄ Raw** rozeti `FileViewerStore.rendersMarkdown` (oturumluk) bayrağını çevirir; view'ın okuduğu değer `isRenderedMarkdown` **türevidir** (`previewKind == .markdown && rendersMarkdown`).
- Görünüm paritesi: 85vw×80vh eşdeğeri oran, commit sidebar 220px, ilk dosya default seçili, satır numaraları açık, minimap yok.

---

## 7. Generic kabuk kompozisyonu (K33–K37)

Refactor öncesi kabuğun kompozisyon esnekliği **sıfırdı**: "Tasks görünümü + servis + store" eklemek ≈ 11 dosya / 19-20 dokunuş ve `RootView`/`AppContainer`/`AppDelegate`/`WorkspaceStore`/`SettingsView` merge darboğazı demekti. Bu bölüm o maliyeti **1 assembly dosyası + birkaç `register` satırına** indiren yapıyı bağlayıcı kılar.

Ortak kalıp: kabuğun her uzatma noktası bir **descriptor tipi** (LumiUI'da) + bir **registry** (saf çözümleme) + composition root'ta bir **kayıt kümesi** üçlüsüdür. Kimlikler kapalı `enum` değil `RawRepresentable` string struct'lardır (`PanelItemID`, `ContentRouteID`, `ToolbarItemID`, `OverlayID`) — yeni öğe LumiKit'teki bir enum'u ve ondan türeyen exhaustive switch'leri değiştirmek zorunda kalmaz (OCP) ve düz string olduğu için persist tarafı additive bir alana sığar.

### 7.1 `ShellContext` — kabuğun tek bağlamı

`@Observable @MainActor final class ShellContext` (LumiUI/Shell) tüm store'ları, köprüleri ve aksiyonları taşır:

- **Store'lar:** `navigation`, `layout`, `dialogs`, `terminals`, `repos`, `git`, `fileViewer`, `settings`, `sessionSchedule`, `promptQueue`, `toasts`, `onboarding`, `usage: [AgentProvider: UsageStore]`.
- **Köprüler (`@ObservationIgnored`):** `viewProvider: any TerminalViewProviding`, `highlighter: any SyntaxHighlighting`, `actions: ShellActions`.
- **`ShellActions`** kabuğun sistem etkileşimleridir — `chooseFolder`, `reveal(repoPath, relativePath)`, `trash(repoPath, relativePath)`. View'lar servisleri asla görmez.
- **Facade değildir:** `WorkspaceStore` kaldırıldı; üç alt store doğrudan sunulur. Burada yalnız **birden fazla store'a dokunan** koordinasyon intent'leri yaşar (`requestCloseTab`/`confirmCloseTab`/`cancelCloseTab`, `presentFile`/`presentDiff`/`presentCommit`, `reveal`/`trash`). Tek store'a giden her şey doğrudan çağrılır.
- **Türevler:** `activeRepoPath` (`.repo` projeksiyonu), `isFocusMode`.

Enjeksiyon tek noktadadır: `EnvironmentValues.shell` (opsiyonel) + `@Shell` property wrapper'ı opsiyonelliği tek yerde açar (`preconditionFailure` ile "kurulmadı" hatası). `RootView.init` tek parametre alır (kayıt defteri); eski 14-15 parametreli prop drilling (RootView → HeaderBar → RepoTabStrip, `usageStores`'un iki yoldan taşınması) tamamen kalktı. Registry'den dinamik inşa edilen her descriptor view'ının `init()`'i bu yüzden **parametresizdir**: bağlamını Environment'tan okur, kayıt tarafı hiçbir store'u closure'a kapatmaz.

### 7.2 Panel yuvaları (K33/K34)

**Yuva sayısı kapalı, öğe kümesi açık.** `LumiKit.PanelSlot` = `left` / `right` / `bottom` (bir pencere kabuğunun coğrafyası); `PanelItemID` string id'dir ve kayıtlı öğeler bugün `sessions` ve `projectTools`'tur (karar 39). Eski `fileTree`, `gitCommits`, `gitChanges` kimlikleri kayıtlı değildir; eski yerleşimlerden sessizce atlanırlar.

`PanelLayout` **değişmezdir** — `slots: [PanelSlot: [PanelItemID]]`, `visibleSlots: Set<PanelSlot>`, `widths: [PanelSlot: Double]`; her mutasyon (`settingVisible`, `togglingVisible`, `settingWidth`, `moving(_:to:index:)`) **yeni bir değer** döndürür. Genişlik `minWidth 180 … maxWidth 640` aralığına kırpılır, `defaultWidth = 280`. Varsayılan yerleşim: sol = `sessions` (açık), sağ = `projectTools` (kapalı). `projectTools` üstte Explorer / Agent History / yalnız Git projesinde Source Control sekmeleri sunar. Unity projelerinde Explorer isteğe bağlı yalnız Assets içeriğini gösterir ve `.meta` dosyalarını gizler.

`LayoutStore` intent'leri bu mutasyonlara iner: `toggleSlot(_:)`, `setSlotVisible(_:_:)`, `move(item:to:index:)`, `setWidth(_:for:)`. **Bir öğeyi soldan sağa taşımak tek `move` çağrısıdır.** Değişmediyse yazılmaz (idempotent). Focus mode kalıcı görünürlüğü ezmez: `visibleSlots` kalıcı hâli, `isSlotVisible(_:)` çizim kararını (`!isFocusMode && …`) verir.

**Persist (K34, additive — karar 9 korunur):** `ui-state.json`'a `panelLayout` (slots + widths) ve `visibleSlots` anahtarları eklenir; `leftSidebarOpen` / `rightSidebarOpen` **okunmaya ve yazılmaya devam eder** (yerleşimin projeksiyonu: `LayoutSnapshot.leftSidebarOpen` = `panelLayout.isVisible(.left)`). `panelLayout` anahtarı yokken görünürlük eski iki bool'dan türetilir (`PanelLayout.migrating(leftOpen:rightOpen:)`).

**Descriptor:**

```swift
struct PanelItemDescriptor: Identifiable {
    let id: PanelItemID
    let title: String
    let icon: String
    let defaultSlot: PanelSlot          // yerleşimde adı geçmeyen yeni öğe buraya düşer
    let sizing: PanelItemSizing         // .fit (içerik kadar) | .fill (kalanı paylaş)
    let isAvailable: @MainActor (ShellContext) -> Bool
    let makeView: @MainActor () -> AnyView   // PARAMETRESİZ
}
```

`PanelItemRegistry.resolved(slot:layout:context:)` **saf**tır ve view render etmeden test edilir (`PanelItemRegistryTests`). Kuralları: (1) sıra `layout`'tan gelir — kullanıcının düzeni otoritedir; (2) yerleşimde adı geçen ama kayıtlı olmayan id sessizce atlanır (eski `ui-state`'te kalmış bir feature kabuğu bozmaz); (3) `isAvailable == false` olan çizilmez; (4) hiç yerleşim bilgisi olmayan kayıtlı öğe `defaultSlot`'una, listenin sonuna düşer (yeni feature migration beklemez).

`PanelHostView(slot:registry:)` listeyi çizer; yuva görünmüyorsa boş döner, genişliği `LayoutStore.width(for:)`'dan alır.

### 7.3 Orta alan router'ı

```swift
struct ContentRouteDescriptor: Identifiable {
    let id: ContentRouteID
    let title: String
    let icon: String
    let makeView: @MainActor (String?) -> AnyView   // yalnız repoPath; nil = repo-bağımsız route
}
```

`ContentRouteRegistry` de saftır: `routes()` kayıt sırasını döndürür, `resolve(_:)` bilinmeyen id'de **`terminals` fallback**'ine düşer (eski bir route id'si kabuğu boş bırakmaz). `ContentRouterView` `NavigationStore.activeRoute`'u eşler: `.repo(path)` → `terminals` descriptor'ı + path, `.content(id)` → o descriptor, `.none` → `WelcomeView`.

`TerminalsRouteView` eski `RootView.repoContent`'in yerine geçer: minimize şeridi, boş-repo durumu ve `maximized ⇄ grid` seçimi artık **route'un iç meselesidir**; kabuk yalnız "hangi route" sorusunu bilir.

**Route geçiş sözleşmesi view'da değil `NavigationStore.applySurfaceTransition(from:to:)`'dadır:**

| Geçiş | Terminal yüzeyi | View köprüsü |
|---|---|---|
| terminals → başka route | `deactivateSurface()` (arka plan + odak yok) | `detachAll()` |
| başka route → terminals | `activateRepo(path)` (foreground + odak) | `refreshAttachedViews()` |
| repo → repo | `activateRepo(path)` (eskiyi arkaya, yeniyi öne) | — (host'lar yerinde) |
| route-dışı → route-dışı | — | — |

PTY hiçbir adımda durmaz, view'lar yok edilmez: detach yalnız reparent eder (§3). Kalkan testler: `RouteTransitionTests`, `TerminalGridFitIntegrationTests`.

### 7.4 Toolbar kompozisyonu

`ToolbarRegion` = `leading` / `center` / `trailing`. **Bölge konum değil Gestalt grubudur:** leading = gezinme (panel toggle, logo, tab'lar), center = üretim (grid ayarı, New \<Provider>), trailing = durum ve global kontroller (usage, focus, panel toggle'ları, settings). Grup içi boşluk bölgeye gömülüdür (`spacing`: 8 / 6 / 4 — karar 30 ince bar). `HeaderBarView` üç bölgeyi `ForEach` ile dizer.

```swift
struct ToolbarItemDescriptor: Identifiable {
    let id: ToolbarItemID
    let region: ToolbarRegion
    let order: Int                                   // küçük önce; eşitlikte kayıt sırası
    let isVisible: @MainActor (ShellContext) -> Bool
    let makeView: @MainActor () -> AnyView           // PARAMETRESİZ
}
```

`ToolbarRegistry.items(in:context:)` saftır: bölge filtresi → `isVisible` filtresi → `order` sıralaması (`sorted` kararsız olduğu için kayıt sırası tie-break olarak **açıkça** yazılır). **Aynı id ikinci kez kaydedilirse öncekini EZER** (panel/overlay registry'leriyle aynı kural): kayıt kümesi birden çok katkıcıdan toplanır ve bir feature kabuğun default öğesini kendi sürümüyle değiştirebilmelidir — yığılma olsaydı bar'da iki kopya çizilirdi; ayrıca çözümleme kompozisyon sırasından bağımsız kalır ve testler tek öğeyi izole edip yerine sahte koyabilir. Ezen kayıt öğenin **kayıt sırasındaki yerini korur**.

**Panel toggle'ları elle yazılmaz:** id `ToolbarItemID.panelToggle(slot)` ile yuvadan türer ve descriptor'lar `PanelSlot.allCases` üzerinden üretilir (`ShellToolbarItems.panelToggles(panels:)`); yeni bir yuva yeni bir sabit gerektirmez. Aynı şekilde kullanım göstergeleri `ToolbarItemID.usageIndicator(provider)` ile sağlayıcıdan türer (eski `ForEach(enabledProviders)` döngüsünün yerine — karar 32).

Mevcut descriptor'lar:

| id | Bölge | order | Görünürlük | Kaydeden |
|---|---|---|---|---|
| `panelToggle(.left)` | leading | 0 | yuvanın sahiplendiği kayıtlı bir panel öğesi varsa (öğenin `isAvailable`'ına bakılmaz) | kabuk |
| `logo` | leading | 10 | daima | kabuk |
| `repoTabs` | leading | 20 | daima | kabuk |
| `gridSettings` | center | 0 | `activeRepoPath != nil` | terminal assembly |
| `newTerminal` | center | 10 | `activeRepoPath != nil` | terminal assembly |
| `usageIndicator(provider)` | trailing | `index * usageStep` | `usageIndicators.isEnabled(provider)` (store yoksa view boş çizer) | usage assembly |
| `focusMode` | trailing | 100 | daima | kabuk |
| `panelToggle(.bottom)` | trailing | 105 | yuvada kayıtlı öğe varsa | kabuk |
| `panelToggle(.right)` | trailing | 110 | yuvada kayıtlı öğe varsa | kabuk |
| `settings` | trailing | 120 | daima | kabuk |

### 7.5 Overlay host

```swift
struct OverlayDescriptor: Identifiable {
    let id: OverlayID
    let alignment: Alignment
    let isPresented: @MainActor (ShellContext) -> Bool
    let makeView: @MainActor () -> AnyView
}
```

`OverlayRegistry.presented(in:)` saftır; `OverlayHost` açık olanları kayıt sırasıyla `ZStack`'te üst üste çizer. `confirmationDialog`'lar da birer descriptor'dır: `makeView` sıfır boyutlu bir **`DialogAnchor`**'a modifier'ı takar. Böylece "şu an bir overlay açık mı?" sorusunun elle `||` listesi kalkar — cevap `DialogRouter.active` (`ActiveDialog.isInputBlockingOverlay`) ile descriptor'ların `isPresented` predikatlarından türer. Kayıtlı overlay'ler: `focusModeBar`, `fileViewer`, `settings`, `toasts`, `closeTabDialog`, `quitDialog`.

### 7.6 Kayıt yeri

**Descriptor tipleri LumiUI'da, kümesi composition root'ta.** `ShellRegistries` (`panels` / `routes` / `overlays` / `toolbar`) LumiUI'dadır; kümeyi `LumiAppCore/Composition/ShellComposition.swift` kurar.

`FeatureAssembly` LumiState'te yaşar ve LumiUI'ı **göremez** (modül grafiği); bu yüzden kabuk katkısı ayrı bir protokoldür:

```swift
@MainActor protocol ShellContributing {          // LumiAppCore
    func registerShellItems(into registries: ShellRegistries)
}
```

Katkı vermeyen assembly protokolü hiç uygulamaz. `ShellComposition.makeRegistries(contributors:)` **servis grafiğinden bağımsızdır** (dolayısıyla tek başına test edilir) ve sırası anlamlıdır: önce feature katkıları, sonra kabuğun kendi overlay'leri, en sonda kabuğun toolbar'ı — çünkü panel toggle'ları o an kayıtlı panel öğelerine bakar.

**`AnyView` yalnız descriptor düzeyindedir** (route / panel item / toolbar item / overlay); terminal kartı içi ya da liste satırları asla sarılmaz.

### 7.7 Yeni bir görünüm / panel öğesi / toolbar item ekleme

1. **Kimlik sabiti** ekle: `extension ContentRouteID { static let tasks = ContentRouteID("tasks") }` (ya da `PanelItemID` / `ToolbarItemID` / `OverlayID`).
2. **View'ı parametresiz yaz:** `init()` boş, bağlamı `@Shell private var shell` ile Environment'tan oku. Parent closure'ı alma.
3. **Assembly'yi yaz:** `struct TasksAssembly: FeatureAssembly, ShellContributing` — servis + store + `StoreLifecycle` + `registerShellItems(into:)` içinde `registries.routes.register(...)` / `panels.register(...)` / `toolbar.register(...)`.
4. **Komut gerekiyorsa** `AppCommands.all`'a bir satır + `MenuActionDispatcher`'a bir `register` (menü ve Shortcuts tablosu otomatik türer, §2).
5. **Assembly'yi listeye ekle:** `AppComposition.live` içinde `assemblies` dizisine (ve kabuğa katkı veriyorsa `contributors` dizisine) adını yaz. Kabuk dosyalarının (`RootView`, `AppShellView`, `HeaderBarView`, `PanelHostView`, `ContentRouterView`, `OverlayHost`, `AppDelegate`) hiçbirine dokunulmaz.
6. **Testi saf tarafta yaz:** registry çözümlemesi (`resolved`/`items(in:)`/`resolve`) view render etmeden test edilir; route terminal yüzeyine dokunuyorsa geçiş sözleşmesini (§7.3) de kilitle.
