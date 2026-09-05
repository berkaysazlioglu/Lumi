# Lumi Native — Mimari Tasarım

> **2026-09-05 refactor (Faz 1–7) ile güncellendi** (`docs/refactor-plan-2026-09.md`, K33–K38): §2 modül ağacı, §3 composition root ve Ek A'nın karşılanma durumu kodun gerçek hâline eşitlendi.
>
> Tasarım fazının bağlayıcı ana dokümanı. Davranışın kaynağı artık implementasyonun kendisidir (`LumiPackages/` + testler); bu doküman ve kardeşleri ([01](./01-terminal-subsystem.md), [02](./02-services.md), [03](./03-ui-shell.md), [04](./04-prototype-plan.md)) o davranışın **nasıl** implemente edileceğini tanımlar. Kapsam kararları için [decisions.md](../decisions.md) geçerlidir; teknoloji kararları 2026-06-11'de kullanıcı ile birlikte verildi ve aşağıda kayıtlıdır.

---

## 1. Teknoloji kararları

| # | Konu | Karar | Gerekçe |
|---|---|---|---|
| T1 | Terminal emülasyonu | **SwiftTerm** (SPM bağımlılığı, MIT; **revision-pin `24a68bc`**, v1.13.0 sonrası release'lenmemiş CSI T / DEC 2026 / Shift+mouse düzeltmeleri için — gerekçe `Package.swift` yorumunda ve [karar 16](../decisions.md)) + oturum başına **kalıcı view-attached emülatör** | Aktif bakımda, headless `Terminal` motoru + AppKit `TerminalView` ayrımı var, `feed()` tabanlı API okuma döngüsünü bize bırakır (backpressure önkoşulu). Özel emülatör (~3-6 ay) için engelleyici neden bulunamadı. Fork/vendor şimdilik gereksiz; API drift olursa sonradan fork'lanır. Düzeltmeleri kapsayan release çıkınca pin sürüm aralığına döndürülür. Topoloji gerekçesi: [01-terminal-subsystem.md §1](./01-terminal-subsystem.md) |
| T2 | PTY katmanı | **Kendi `PTYProcess` wrapper'ımız** — SwiftTerm `LocalProcess` kullanılmaz | `LocalProcess` fd okumasına suspend/resume kancası sunmaz; watermark backpressure ([00-architecture.md Ek A](#ek-a--buglardan-türetilen-zorunlu-gereksinimler-bağlayıcı)) ancak okuma döngüsü bizdeyse kurulabilir. Process-group kill, env enjeksiyonu ve exit-sıralaması da bizim kontrolümüzde olmalı |
| T3 | UI çatısı | **AppKit kabuk + SwiftUI içerik** | `.terminateLater` quit akışı, traffic-light konumlandırma, dosya-tabanlı bounds persistence (karar 9 frameAutosave'i dışlar) ve NSMenu'nun tek kısayol kaynağı olması AppKit gerektirir. Pencere içi UI'ın tamamı (spec'teki animasyonlar dahil) güncel SwiftUI kapasitesinde |
| T4 | DI | **Manuel constructor injection + composition root**; DI kütüphanesi yok. Faz 3 (K36) composition root'u üçe ayırdı: `ServiceRegistry` (servis grafiği) + `SharedStores` (paylaşılan store'lar) + `FeatureAssembly` listesi; `AppContainer` yalnız faz-sıralı koşucudur (§3) | Graf küçük (~12 servis + ~15 store), tek sefer kurulur, scope ihtiyacı yok. Manuel DI compile-time doğrulanır; sıra-bağımlı bootstrap kodda açıkça okunur. Factory/Swinject runtime çözümleme hatası ve Swift 6 Sendable sürtünmesi getirir |
| T5 | Deployment target | **macOS 14.0+, Swift 6 language mode, strict concurrency** | `@Observable` (Observation) 14+ ister; ObservableObject/Combine fallback yolu hiç yazılmaz. Hedef kitle (Claude Code CLI kullanan geliştiriciler) ağırlıkla güncel macOS'ta |
| T6 | Event akışı | Servis→store **`AsyncStream`**, store→UI **`@Observable`**; **Combine kullanılmaz** | AsyncStream Sendable'dır, her domain'in tek tüketicisi (kendi store'u) vardır — tek-tüketici doğası özellik olur. Debounce ihtiyaçları noktasaldır ve birbirinden farklıdır (`ConfigService`'in 500 ms ui-state yazım debounce'u, `DirectoryWatcher` 300 ms / `RecursiveDirectoryWatcher` 500 ms FSEvents coalescing'i, `FileTreeSearchModel`'in arama debounce'u, `KeyedRefreshCoalescer`) — ortak bir `Debouncer` tipi bile gerekmedi, ikinci bir reactive runtime hiç |
| T7 | Modül yapısı | **Lokal SPM paketleri** + ince app target; Xcode projesi YOK (app katmanı da SPM'de: `LumiAppCore` library + `LumiApp` executable) | View↔iş mantığı ayrımı (rewrite ana hedefi) Xcode group'larıyla değil, modül sınırlarıyla **derleyici tarafından** zorlanır. App kabuğunun library olması `LumiAppTests`'in `@testable import` edebilmesi içindir (SPM executable target'ları test'ten import edilemez) |

---

## 2. Modül yapısı ve bağımlılık kuralları

**Xcode projesi yoktur — her şey `LumiPackages/Package.swift` altındadır** (uygulama katmanı dahil). `.app` paketleme ve `Lumi.entitlements` (yalnız `audio-input`; App Sandbox / JIT entitlement'ları bilinçli olarak YOK) `Scripts/make-app.sh` tarafından üretilir.

```
LumiPackages/Package.swift
├── LumiKit        — domain modelleri, TÜM servis protokolleri (Protocols/),
│                    Errors/LumiError, Composition/ (ServiceRegistry,
│                    ConfigChangeObserving), Commands/ (AppCommand, AppCommands),
│                    Models/ (+ Models/Config/: AppConfig, UIState,
│                    NotificationSettings, SessionTrigger, UsageIndicators,
│                    UsageAutoRefresh, AdditionalPath; PanelModels, ShellModels),
│                    Diff/ (MarkdownDiffBuilder, SideBySideDiffBuilder),
│                    Support/ (LumiPaths, EventBroadcaster, JSONValue, Loadable,
│                    UsageLevel, UsageStatusFormatter, RelativeTimeFormatter,
│                    TerminalGridFit, usage parser'ları)          — BAĞIMLILIKSIZ
├── LumiTerminal   — PTY/ (PTYProcess, PTYChildRegistry), Flow/ (FlowController,
│                    OutputCoalescer, AdaptiveBatchBudget, FeedWatchdog),
│                    Parsing/ (OSCStreamParser + OSCSemantics), Status/
│                    (StatusStateMachine), Input/ (PTYInputFilter), Session/
│                    (TerminalSession/Pipeline/Manager, TerminalViewRegistry,
│                    TerminalEventMonitor)          → SwiftTerm (internal detay)
├── LumiServices   — Config/ (ConfigService + bölüm codec'leri), Repo/, Git/,
│                    System/ (+ Checks/), Notification/, Usage/, Session/,
│                    Highlighting/                  → Highlightr (internal detay)
├── LumiState      — @Observable @MainActor store'lar; Composition/
│                    (FeatureAssembly + BootstrapPhase, SharedStores,
│                    StoreLifecycle, EventConsumer), Workspace/ (NavigationStore,
│                    LayoutStore, DialogRouter, TerminalFocusCoordinating)
├── LumiUI         — SwiftUI: Shell/ (RootView, ShellContext, ShellRegistries,
│                    panel/route/toolbar/overlay registry'leri), Theme/,
│                    Components/, Form/, Settings/, FileViewer/, Terminal/,
│                    Sidebar/, Usage/, PromptQueue/, Presentation/
├── LumiAppCore    — AppKit kabuğu (LIBRARY, test edilebilir): AppBootstrap,
│                    AppDelegate, Composition/ (AppComposition, AppContainer,
│                    LiveServiceRegistry, ShellComposition), Features/
│                    (6 FeatureAssembly), Window/ (MainWindowController,
│                    RootViewFactory, TrafficLightLayout), MainMenuBuilder,
│                    MenuActionDispatcher, ConfigSideEffectCoordinator
├── LumiApp        — executable (ürün adı `Lumi`); main.swift → AppBootstrap.run()
└── Tests/
    ├── LumiTestSupport  — paylaşılan el yazımı fake'ler (ayrı TARGET, Sources'ta
    │                      değil; hiçbir ürün ona bağlı değil)
    └── LumiKitTests / LumiTerminalTests / LumiServicesTests / LumiStateTests /
        LumiUITests / LumiAppTests
```

**Bağımlılık yönü (derleyici-zorlamalı):**

```
LumiApp (exe) ──► LumiAppCore ──► LumiUI ──► LumiState ──► LumiKit
                       ├────────► LumiServices ─────────► LumiKit  (+ Highlightr)
                       └────────► LumiTerminal ─────────► LumiKit  (+ SwiftTerm)
LumiKit ──► (dış bağımlılık yok)
```

- `LumiUI` ve `LumiState`, `LumiServices`/`LumiTerminal`'i **import edemez** — yalnız `LumiKit` protokollerini görürler. Somut implementasyonları yalnız `LumiAppCore` (composition root) tanır.
- SwiftTerm yalnız `LumiTerminal`, Highlightr yalnız `LumiServices` içinde import edilir; ikisi de public yüzeye sızmaz. (Highlightr refactor 7.5'te LumiUI'dan LumiServices'e taşındı: view modülü artık ne JSCore'u ne de bir arka plan kuyruğunu tanır; dikiş `SyntaxHighlighting` protokolüdür — [02 §8](./02-services.md).)
- Sınır hilesi: `TerminalViewProviding` protokolü (NSView tipli `attachView`/`detachView`/`isAttached`/`detachAll`/`refreshAttachedViews`) **LumiKit'te** yaşar; böylece `LumiUI`, `LumiTerminal`'i import etmeden canlı terminal view'larını host eder ([03 §3](./03-ui-shell.md)).
- `FeatureAssembly`/`SharedStores` neden LumiKit'te değil LumiState'te? İkisi de `SharedStores`'a (yani somut store tiplerine) bağlıdır; LumiKit store katmanını göremez. `ServiceRegistry` ise yalnız protokollere bağlı olduğu için LumiKit'tedir.

| Modül | Sorumluluk | Public yüzey |
|---|---|---|
| **LumiKit** | Domain modelleri (`TerminalID`, `TerminalMeta`, `TerminalStatus`, `TerminalSurfaceState`, `Repo`, `FileTreeNode`, `GitCommit`, `AppConfig`, `UIState`, `AgentProvider`, `PanelLayout`/`PanelItemID`, `WorkspaceRoute`/`ContentRouteID`, `UsageSnapshot`), tüm servis protokolleri ([02](./02-services.md)), event enum'ları, `LumiError`, `LumiPaths`, `AppCommand(s)`, saf yardımcılar | Hepsi |
| **LumiTerminal** | Terminal alt sistemi ([01](./01-terminal-subsystem.md)) | `TerminalSessionManager: TerminalServicing` + `TerminalViewRegistry: TerminalViewProviding` + `PTYSmokeTester: TerminalSmokeTesting` — composition root'un gördüğü tek yüz bunlar. (`PTYProcess`, `FlowController`, `TerminalEventMonitor`, `TerminalTheme` de `public`'tir ama yalnız test/araç erişimi içindir; SwiftTerm tipleri hiçbirinin imzasında geçmez.) |
| **LumiServices** | Diğer tüm servis implementasyonları + parçaları (`GitCommandRunner`/`GitPorcelainParser`/`RepoPathGuard`, `SystemCheck`'ler, `CachingUsageService` dekoratörü) | Protokol başına bir somut tip (+ bileşenleri) |
| **LumiState** | View-state store'ları ([03 §4](./03-ui-shell.md)) + composition sözleşmeleri | Store'lar, `FeatureAssembly`, `SharedStores`, `StoreLifecycle`, `EventConsumer` |
| **LumiUI** | Tüm SwiftUI view'ları + tasarım sistemi + kabuk kayıt defteri | `RootView`, `Theme`, `ShellContext`/`ShellActions`, `ShellRegistries` ve descriptor tipleri (`PanelItemDescriptor`, `ContentRouteDescriptor`, `ToolbarItemDescriptor`, `OverlayDescriptor`) |
| **LumiAppCore** | AppKit lifecycle, pencere, menü, quit akışı, composition root (`AppComposition`/`AppContainer`/`LiveServiceRegistry`/`ShellComposition`), config yan etki koordinasyonu, sleep/wake + focus bildirimlerinin servislere bağlanması | `AppBootstrap` (executable'ın tek giriş noktası) |
| **LumiApp** | Executable kabuğu | `main.swift` → `AppBootstrap.run()` |

---

## 3. DI tasarımı

**Composition root:** `AppDelegate.applicationDidFinishLaunching` içinde kurulan `AppComposition.live(mode:notificationPresenter:)`. Faz 3 (K36) tek parçalı `AppContainer`'ı üçe böldü — her parçanın tek bir sorumluluğu var:

| Parça | Yer | Sorumluluk |
|---|---|---|
| `ServiceRegistry` (protokol) | LumiKit `Composition/` | Servis grafiğinin tek erişim yüzü. Üretim: `LiveServiceRegistry` (LumiAppCore), test: `FakeServiceRegistry` (LumiTestSupport). Somut servis tipleri YALNIZ `LiveServiceRegistry`'de görünür |
| `SharedStores` | LumiState `Composition/` | Birden çok feature'ın veya AppKit kabuğunun paylaştığı 6 store: `toasts`, `navigation`, `layout`, `dialogs`, `terminals`, `settings`. Üyelik ölçütü tek soru: "birden fazla feature/kabuk erişiyor mu?" |
| `FeatureAssembly` (protokol) + `BootstrapPhase` | LumiState `Composition/` | Bir özelliğin servisi + store'ları + config yan etkisi + yaşam döngüsü TEK dosyada: `build(services:shared:)` → `start()` → `configDidChange(old:new:)` → `shutdown()` |
| `StoreLifecycle` / `EventConsumer` | LumiState `Composition/` | Store'ların `start()`/`stop()` simetrisi; tek-tüketicili `AsyncStream` döngüsünün nesil (generation) sayaçlı, eşzamanlı durdurulabilen kabı |
| `AppContainer` | LumiAppCore `Composition/` | **Hiçbir feature'ı tanımayan** koşucu: prelude, paylaşılan store yaşam döngüsü, faz sıralı `start()`, config koordinatörü, simetrik `shutdown()` |
| `ShellComposition` + `ShellContributing` | LumiAppCore `Composition/` | Kabuk katkılarının **kümesi**: `ShellRegistries` (panels / routes / overlays / toolbar) + `ShellContext`. Descriptor **tipleri** LumiUI'da |
| `RootViewFactory` | LumiAppCore `Window/` | `RootView(registries:)` + `.environment(\.shell, ShellContext)` → `NSHostingView` |

```swift
@MainActor
public protocol ServiceRegistry: AnyObject {
    var paths: LumiPaths { get }                       // ~/.lumi çözümlemesi (karar 9)
    var config: any ConfigServicing { get }
    var system: any SystemServicing { get }
    var repo: any RepoServicing { get }
    var git: any GitServicing { get }                  // GitReading & GitContentReading & GitWriting
    var terminal: any TerminalServicing { get }        // TerminalSessionControlling & TerminalAppearanceControlling
    var viewProvider: any TerminalViewProviding { get } // canlı NSView köprüsü AYRI yüzdür
    var highlighter: any SyntaxHighlighting { get }
    var notifications: any NotificationServicing { get }
    var sessionStarter: any SessionStarterServicing { get }
    var activityMonitor: any ActivityMonitoring { get }
    func usage(for provider: AgentProvider) -> any UsageServicing   // sağlayıcı başına (karar 32)
}
```

- **ISP:** `terminal` tek bir "her şeyi yapan" tip değildir; oturum kontrolü (`TerminalSessionControlling`) ile görünüm ayarı (`TerminalAppearanceControlling`) ayrı yüzlerdir ve store'lar yalnız birincisini alır. Canlı view köprüsü (`viewProvider`) terminal servisinin bir alanı olarak sızdırılmaz. Aynı gerekçeyle git yüzeyi üçe ayrılmıştır ([02 §4](./02-services.md)).
- **`LumiPaths.Mode` artık parametredir:** `#if DEBUG` yalnız executable'ın girişinde (`AppBootstrap.defaultPathsMode`) durur; `AppDelegate(pathsMode:)` → `LiveServiceRegistry(mode:)`. Böylece composition root testte prod/dev moduyla kurulabilir.
- **Feature assembly listesi** (`AppComposition.live`; kayıt sırası aynı faz içindeki dağıtım sırasıdır): `TerminalFeatureAssembly` (`.system`), `NotificationAssembly` / `SessionScheduleAssembly` / `UsageFeatureAssembly` (`.config`), `RepoFeatureAssembly` (`.repo`), `WorkspaceBootAssembly` (`.ui`). Yeni özellik = yeni assembly dosyası + bu listeye **bir satır**; kabuk katkısı varsa aynı tip ayrıca `ShellContributing`'i uygular ve `registerShellItems(into:)` içinde route/panel/toolbar/overlay kaydeder.
- **View'lar servisleri asla görmez:** enjeksiyon SwiftUI Environment'tan **tek** bir `ShellContext` ile yapılır (`RootView(registries:).environment(\.shell, context)`; view tarafında `@Shell` property wrapper'ı). `ShellContext` yalnız store'ları, iki köprüyü (`TerminalViewProviding`, `SyntaxHighlighting`) ve `ShellActions` closure'larını (`chooseFolder` / `reveal` / `trash`) taşır — servis referansı taşımaz. Faz 6.1 öncesindeki 15 parametreli `RootView.init` ve prop drilling kalktı.
- **Test ikamesi:** her protokolün el yazımı fake'i `LumiTestSupport` target'ındadır (`Tests/LumiTestSupport`): `FakeConfigService`, `FakeRepoService`, `FakeGitService`, `FakeSystemService`, `FakeNotificationService`, `FakeNotificationPresenter`, `FakeTerminalService`, `FakeTerminalViewProvider`, `FakeUsageService`, `FakeSessionStarterService`, `FakeActivityMonitor`, `FakeProcessRunner`, `FakeBinaryLocator`, `FakeSyntaxHighlighter`, `FakeServiceRegistry` + `ManualClock` / `SubscriptionCounter`. Store testi = `Store(service: fake)` + event sür + `@Observable` state assert et; bootstrap sözleşmesi tamamen fake bir grafikle test edilir (`AppContainerBootstrapTests`). Servis testleri `~/.lumi`'yi taklit eden temp dizinlere karşı, **format-parite golden file'larıyla** koşar (karar 9). SwiftUI preview'ları aynı fake'leri kullanır (`LumiUI/Preview/PreviewFixtures.swift` → `ShellContext.preview(repoPath:)`).

### Bootstrap sırası (sıra-bağımlı)

`AppComposition.live(...)` önce grafiği kurar — her assembly'nin `build(services:shared:)`'i çağrılır ve koordinatöre `register` edilir, **hiçbir iş yapılmaz**. Ardından `AppContainer.start()` (idempotent; uçuştaki `startTask` saklanır):

1. **Prelude:** `paths.ensureDirectoriesExist()` (hata → toast) → `system.fixProcessPath()` — **her PTY spawn'dan ve her SystemCheck'ten önce** ([02 §8](./02-services.md)).
2. `SharedStores.start()` — paylaşılan tüketiciler (`terminals`, `settings`) servis stream'lerini tüketmeye başlar.
3. Assembly'ler `BootstrapPhase` artan sırada `start()`: `.system` (terminal) → `.config` (bildirim, oturum zamanlaması, kullanım) → `.repo` (repo keşfi, git + dosya ağacı) → `.ui` (workspace yükleme, onboarding).
4. `ConfigSideEffectCoordinator.start()` — `ConfigEvent.configChanged(old:new:)` akışını kayıtlı `ConfigChangeObserving` gözlemcilerine (yani assembly'lere) dağıtır; diff'i her gözlemci kendi alanları için **eşitlikle** yapar (karar 11).

AppKit tarafı: menü **bootstrap'ten önce** senkron kurulur (`AppMenuCommands.register(in:shared:)` + `MainMenuBuilder.install(dispatcher:)`; menü ve kısayollar `AppCommands` tek kaynağından), pencere ise `container.start()` bittikten **sonra** açılır (`MainWindowController.install(contentView:uiState:)` + `RootViewFactory`) — böylece ilk kare hazır state ile çizilir. Focus/wake köprüleri `AppLifecycleBridges`'te kurulur ve token'ları saklanır. İlk çalıştırma (`config.isFirstRun()`) → onboarding akışı `OnboardingStore` / `WorkspaceBootAssembly` üzerinden.

`shutdown()` **tam simetriktir** (refactor 3.13): uçuştaki `startTask` iptal edilip beklenir → `configCoordinator.stop()` → `SharedStores.stop()` (önce paylaşılan tüketiciler susar ki kapanışta üreyen `.exited` event'leri toast doğurmasın) → assembly'ler **ters** sırada `shutdown()` → `config.flushPendingWrites()` → temp dizini silinir (karar 11).

---

## 4. Zorunlu gereksinimlerin karşılanma haritası (üst düzey)

[Ek A](#ek-a--buglardan-türetilen-zorunlu-gereksinimler-bağlayıcı)'teki gereksinimlerin mekanizma haritasının tamamı [01-terminal-subsystem.md §5](./01-terminal-subsystem.md)'tedir. Üst düzeyde:

- **PTY→UI backpressure (A.1):** `FlowController` watermark'ları (512 KB high / 128 KB low) + `DispatchSourceRead` suspend/resume (`PTYProcess`, `resumeRequested` kayıp-uyanma korumasıyla) + `OutputCoalescer` (görünür 16 ms / gizli 100 ms) — [01 §3](./01-terminal-subsystem.md).
- **Render-crash izolasyonu ve replay güvenliği (A.2):** kalıcı emülatör topolojisi replay'i yapısal olarak ortadan kaldırır; `PTYInputFilter` protokol-bilinçli girdi filtresi; registry-korumalı teslimat (native `safeSend`) — [01 §1, §4](./01-terminal-subsystem.md).
- **Donma gözetimi (A.2-10):** `FeedWatchdog` (2 sn stall heartbeat → `TerminalEvent.stalled`, UI'da "stalled" rozeti) + `AdaptiveBatchBudget` (4 ms feed bütçesi aşılırsa coalescer boyut eşiği yarıya, alt sınır 8 KB) — Faz 4.2'de implemente edildi, [01 §3, §8](./01-terminal-subsystem.md).
- **Korunan korumalar (A.3):** scrollback 5000, login-shell + komut enjeksiyonu, process-group SIGHUP temizliği — [01 §2, §6](./01-terminal-subsystem.md).

---

## 5. Karar 1-14 ile tutarlılık

[decisions.md](../decisions.md)'deki kararların tasarımdaki karşılıkları:

| Karar | Tasarımdaki yeri |
|---|---|
| 1, 2 (gamification, work-log at) | Hiçbir modülde karşılık yok; `TerminalMeta`'da codename alanı yok |
| 3 (Settings anlık) | `SettingsStore` + `ConfigSideEffectCoordinator` → `ConfigChangeObserving` gözlemcileri (feature assembly'leri) — [03 §4](./03-ui-shell.md) |
| 4 (unified diff) | FileViewer stack — [03 §6](./03-ui-shell.md) |
| 5 (tek hata sözleşmesi) | `LumiError` + `ToastStore.reporting` — [02 §9](./02-services.md) |
| 6 (commit-diff lazy) | `GitServicing.commitFiles` / `commitFileDiff` ayrımı — [02 §4](./02-services.md) |
| 7 (git check-ignore) | `RepoServicing.fileTree` (`git ls-files --others --ignored --exclude-standard --directory`) — [02 §3](./02-services.md) |
| 8 (auto-update yok) | Paketleme fazında Sparkle yok — [04 faz 6](./04-prototype-plan.md) |
| 9 (persistence formatları aynen) | `LumiPaths` + ConfigService format-parite golden testleri — [02 §2](./02-services.md) |
| 10 (terminal arama yok) | SwiftTerm search API'si kullanılmaz |
| 11 (bug düzeltmeleri) | Tasarıma gömülü: equality-diff side-effect, path-traversal guard'ı her path'te, tab kimliği=path, sıralı terminal koleksiyonu, drop-path quote, görünür spawn-limit hatası, `wait_for` rolling buffer, temp dosya temizliği |
| 12 (create-project çıkar) | Default action seti `Bundle.module`'da bu action'sız |
| 13 (görsel kimlik semantic) | `Theme` token katmanı — [03 §5](./03-ui-shell.md) |
| 14 (auto-discovery iptal) | Karşılık yok |

**Faz 8 kararları (K33–K38, 2026-09-04/05)** — bu dokümandaki karşılıkları:

| Karar | Tasarımdaki yeri |
|---|---|
| K33 (generic shell kompozisyonu) | §2 LumiUI public yüzeyi (descriptor tipleri) + §3 `ShellComposition`/`ShellContext`/`ShellRegistries`; ayrıntı [03 §7](./03-ui-shell.md) |
| K34 (`UIState`'e additive alanlar) | §2 `PanelLayout`/`PanelItemID` LumiKit'te; persist paritesi [02 §2](./02-services.md) |
| K35 (`WorkspaceStore` → 3 store) | §2 LumiState `Workspace/`; `SharedStores`'un `navigation`/`layout`/`dialogs` üyeleri |
| K36 (`FeatureAssembly` + `ServiceRegistry`) | §3'ün tamamı |
| K37 (`TerminalSurfaceState` + `TerminalViewProviding` genişlemesi) | §2 sınır hilesi maddesi; ayrıntı [01](./01-terminal-subsystem.md) |
| K38 (usage aralık seti + TTL) | [05 §6.1](./05-usage-indicator.md) |

---

## Ek A — Bug'lardan türetilen zorunlu gereksinimler (bağlayıcı)

Electron sürümünün iki kök-neden analizinden (siyah ekran + terminal stream OOM) türetilmiştir; native tasarımın **birinci günden** sağlaması gereken gereksinimlerdir. Bunlar "sonradan eklenecek iyileştirme" değil, mimari ön koşuldur.

**Kök nedenler (özet):**
- *Stream OOM:* PTY chunk'ı başına O(500KB) string yeniden inşası + `Map` kopyası + React render turu → V8 major GC fırtınası, ardından heap OOM ve `render-process-gone`. Chunk başına 1 IPC mesajı, batching yok, `pty.pause()` hiç kullanılmıyordu.
- *Siyah ekran + "random karakter":* dört halkalı zincir — (1) bellek baskısı renderer'ı dondurur/öldürür → (2) siyah ekran penceresi → (3) reload sonrası backlog replay'i → (4) replay sırasında xterm.js'in ürettiği otomatik yanıtlar (CPR/DSR, DA, mouse) PTY'ye yazılır.

Gereksinimler:

### A.1 PTY → UI backpressure (en kritik)

1. **Ham çıktı UI state store'unda tutulmamalı.** Ekran modeli (grid + scrollback) yalnızca terminal emülatöründe yaşamalı; state katmanı sadece metadata (id, status, title) taşımalı.
2. **Ack tabanlı uçtan uca flow control:** View tükettiği byte'ları ack'lemeli; in-flight byte sayacı tutulmalı; high watermark'ta PTY fd okuması durdurulmalı (kernel PTY buffer'ı yazan süreci doğal olarak bloklar — veri kaybı olmaz), low watermark'ta devam edilmeli. Mevcut sistemde `pty.pause()/resume()` hiç kullanılmıyor.
   > **Kayıp-uyanma yarışı (Faz 1.1'de kapatıldı):** suspend/resume iki farklı bağlamdan sürülür — okuma yönergesi io queue'da (`handleReadable` `.suspend` döndürür), ack ise MainActor'da (`resumeReading()`). `.suspend` dönüşü ile fiilî `source.suspend()` arasındaki pencerede gelen resume, `readSuspended == false` gördüğü için no-op oluyor, hemen ardından suspend uygulanıyor ve **terminal kalıcı donuyordu**. Bu yüzden `PTYProcess` bir `resumeRequested` bayrağı tutar: pencere içindeki resume isteği kaydedilir ve `suspendReading()` bayrağı görünce suspend'i hiç uygulamaz. Yarış YOKTUR diye varsaymak yeterli değildir; regresyon `PTYProcessTests.testResumeRequestedDuringSuspendWindowCancelsSuspend` (+ `testSuspendStillWorksAfterResume`, `testConcurrentResumeDuringTerminateIsSafe`) ile kilitlidir.
3. **Frame hızında batching:** Chunk'lar ~16ms'de bir veya boyut eşiğinde coalesce edilmeli. Chunk başına mesaj + render turu **yasak**; chunk işleme maliyeti O(chunk) kalmalı (asla tüm buffer taranmamalı — OOM'un kök nedeni buydu).
4. **Sabit kapasiteli byte ring buffer:** Snapshot/replay tamponu string concat değil `Uint8Array`-eşdeğeri ring buffer olmalı; GC churn sıfır.
5. **Sequence-güvenli kesim:** Her buffer kesimi ANSI escape sequence, OSC gövdesi ve UTF-8/çok-byte'lı karakter sınırlarına saygılı olmalı. Newline-sezgisel 2048-pencere yaklaşımı yetersiz; alt-screen (newline'sız) çıktı için "rastgele indeksten kes" fallback'i yasak. Tercihen replay ham byte yerine **emülatör durum serileştirmesi** (headless terminal state machine: grid + scrollback + modlar) ile yapılmalı.
6. **Detached/görünmeyen terminal politikası:** Görünmeyen view'a tam hız stream gönderilmemeli; cap'li buffer'da biriktirip attach anında tek snapshot ile resync edilmeli. Mevcut fix'in `totalLength` (monoton offset) + `epoch` (full-redraw sinyali) resync protokolü korunmaya değer.
7. **Sıralama garantisi:** Terminal başına tüm yazımlar tek seri kuyruktan akmalı; replace uygulanırken araya append giremez.
8. **Emülatörün iç write buffer'ı da sınırlı olmalı** veya backpressure döngüsüne dahil edilmeli (xterm.js'te bugün sınırsız — ikinci OOM vektörü).

### A.2 Render-crash izolasyonu ve replay güvenliği

9. **Replay ile canlı girdi ayrılmalı:** Backlog replay'i sırasında emülatörün ürettiği otomatik yanıtlar (CPR/DSR, DA, DECRQM, mouse raporları) PTY'ye **asla** yazılmamalı; replay "girdi kapalı" modda yapılmalı. "Random karakterler" bug'ının birebir mekanizması budur — mevcut regex tabanlı focus-event ayıklama (`\x1b[I/O`) yetersizdir; PTY'ye giden yolda **protokol-bilinçli girdi filtresi** gerekir.
10. **Donma/crash gözetimi:** UI için unresponsive-watchdog ve GPU/compositor kaybı kurtarma yolu olmalı; kurtarma sırasında siyah ekran yerine "yeniden bağlanıyor" durumu gösterilmeli.
    > **Durum: implemente edildi (Faz 4.2).** `FeedWatchdog` in-flight byte varken son başarılı feed'in üzerinden 2 sn geçtiyse terminali stall sayar (heartbeat io queue'da koşar), `TerminalEvent.stalled(id, Bool)` yayınlanır ve kart header'ında "stalled" rozeti çıkar — boş/siyah kart yerine görünür durum. Aynı watchdog feed süresini 4 ms bütçeye karşı ölçer ve `AdaptiveBatchBudget` üzerinden coalescer'ın boyut eşiğini yarıya indirir (alt sınır 8 KB; bütçe içinde kalan her feed'de kademeli geri açılır). Testler: `FeedWatchdogTests`.
11. **Tek paylaşımlı GPU context:** Terminal başına ayrı GPU context açılmamalı; N terminal tek renderer/atlas ile çizilmeli (context evict kaynaklı kararma riski sıfırlanır).
12. **Crash dayanıklılığı:** Hedef view yok/çökmüşse gönderim sessizce atlanmalı (safeSend eşdeğeri), PTY pause edilmeli, recovery sonrası snapshot'tan devam edilmeli. "UI ölür → PTY'ler yaşar → UI yeniden bağlanır" akışı için **entegrasyon testi** yazılmalı: yeniden bağlanma sonrası PTY'ye hiçbir istenmeyen byte yazılmadığı doğrulanmalı.
    > **Durum: entegrasyon testi yazıldı (Faz 2.3).** `TerminalSessionReattachTests` gerçek bir `/bin/cat` PTY'si ile `TerminalSession`'ı kurar, attach → detach → attach → `refreshAttachedViews()` turunu koşturur ve PTY'ye yazılan byte sayısının 0 olduğunu doğrular. Ön koşulu olan `PTYSpawning`/`TerminalViewMaking` factory enjeksiyonu Faz 4.1'de yapıldı (`TerminalSessionInjectionTests`).

### A.3 Korunması gereken mevcut korumalar

- 500KB tail cap paritesi (PTY başına) + 5000 satır scrollback. *Native karşılığı:* `FlowController` 512 KB high / 128 KB low watermark'ı (in-flight byte sınırı) + `TerminalSession.scrollbackLines = 5000`. Kalıcı emülatör topolojisinde ayrı bir tail buffer'ı yoktur — sınır, biriken ham byte'ın kendisine konur.
- `safeSend` dersinin native karşılığı: UI lifecycle'ına dayanıklı event dağıtımı.
- Uygulama crash'inde zombi PTY bırakmamak: process group + SIGHUP/killpg ile login shell altındaki tüm claude process ağacının temizlenmesi.
