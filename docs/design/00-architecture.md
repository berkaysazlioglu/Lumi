# Lumi Native — Mimari Tasarım

> Tasarım fazının bağlayıcı ana dokümanı. Davranışın kaynağı `docs/spec/`; bu doküman ve kardeşleri ([01](./01-terminal-subsystem.md), [02](./02-services.md), [03](./03-ui-shell.md), [04](./04-prototype-plan.md)) o davranışın **nasıl** implemente edileceğini tanımlar. Kapsam kararları için [spec/01-decisions.md](../spec/01-decisions.md) geçerlidir; teknoloji kararları 2026-06-11'de kullanıcı ile birlikte verildi ve aşağıda kayıtlıdır.

---

## 1. Teknoloji kararları

| # | Konu | Karar | Gerekçe |
|---|---|---|---|
| T1 | Terminal emülasyonu | **SwiftTerm** (SPM bağımlılığı, MIT, v1.13.0+) + oturum başına **kalıcı view-attached emülatör** | Aktif bakımda, headless `Terminal` motoru + AppKit `TerminalView` ayrımı var, `feed()` tabanlı API okuma döngüsünü bize bırakır (backpressure önkoşulu). Özel emülatör (~3-6 ay) için engelleyici neden bulunamadı. Fork/vendor şimdilik gereksiz; API drift olursa sonradan fork'lanır. Topoloji gerekçesi: [01-terminal-subsystem.md §1](./01-terminal-subsystem.md) |
| T2 | PTY katmanı | **Kendi `PTYProcess` wrapper'ımız** — SwiftTerm `LocalProcess` kullanılmaz | `LocalProcess` fd okumasına suspend/resume kancası sunmaz; watermark backpressure ([spec/00 §4.1-2](../spec/00-overview.md)) ancak okuma döngüsü bizdeyse kurulabilir. Process-group kill, env enjeksiyonu ve exit-sıralaması da bizim kontrolümüzde olmalı |
| T3 | UI çatısı | **AppKit kabuk + SwiftUI içerik** | `.terminateLater` quit akışı, traffic-light konumlandırma, dosya-tabanlı bounds persistence (karar 9 frameAutosave'i dışlar) ve NSMenu'nun tek kısayol kaynağı olması AppKit gerektirir. Pencere içi UI'ın tamamı (spec'teki animasyonlar dahil) güncel SwiftUI kapasitesinde |
| T4 | DI | **Manuel constructor injection + `AppContainer` composition root**; DI kütüphanesi yok | Graf küçük (~10 servis + ~8 store), tek sefer kurulur, scope ihtiyacı yok. Manuel DI compile-time doğrulanır; sıra-bağımlı bootstrap kodda açıkça okunur. Factory/Swinject runtime çözümleme hatası ve Swift 6 Sendable sürtünmesi getirir |
| T5 | Deployment target | **macOS 14.0+, Swift 6 language mode, strict concurrency** | `@Observable` (Observation) 14+ ister; ObservableObject/Combine fallback yolu hiç yazılmaz. Hedef kitle (Claude Code CLI kullanan geliştiriciler) ağırlıkla güncel macOS'ta |
| T6 | Event akışı | Servis→store **`AsyncStream`**, store→UI **`@Observable`**; **Combine kullanılmaz** | AsyncStream Sendable'dır, her domain'in tek tüketicisi (kendi store'u) vardır — tek-tüketici doğası özellik olur. Debounce ihtiyaçları (~20 satırlık `Debouncer`) ikinci bir reactive runtime'ı haklı çıkarmaz |
| T7 | Modül yapısı | **Lokal SPM paketleri** + ince app target | View↔iş mantığı ayrımı (rewrite ana hedefi) Xcode group'larıyla değil, modül sınırlarıyla **derleyici tarafından** zorlanır |

---

## 2. Modül yapısı ve bağımlılık kuralları

```
Lumi.xcodeproj
├── Lumi/                      (app target — ince)
│   ├── main/AppDelegate.swift (pure AppKit @main; composition root host)
│   ├── AppContainer.swift
│   ├── MainWindowController.swift
│   ├── MainMenuBuilder.swift + MenuActionDispatcher.swift
│   ├── ConfigSideEffectCoordinator.swift
│   └── Lumi.entitlements      (audio-input + inherit; sandbox/JIT entitlement'ları YOK)
└── LumiPackages/Package.swift
    ├── LumiKit        — domain modelleri, TÜM servis protokolleri, LumiError,
    │                    LumiPaths (~/.lumi çözümlemesi), Debouncer, EventBroadcaster,
    │                    JSON/YAML codec'ler (yalnız Yams'a bağımlı)
    ├── LumiTerminal   — PTYProcess, okuma/yazma pipeline'ı, StatusStateMachine,
    │                    OSC parser, TerminalViewRegistry (SwiftTerm: internal detay)
    ├── LumiServices   — Config/Repo/Git/Persona/Action/Notification/System servisleri;
    │                    default-actions/ ve default-personas/ Bundle.module resource
    ├── LumiState      — @Observable @MainActor store'lar; servislerin tek tüketicisi
    └── LumiUI         — SwiftUI view'lar + Theme; yalnız LumiState + LumiKit görür
```

**Bağımlılık yönü (derleyici-zorlamalı):**

```
Lumi (app) ──► LumiUI ──► LumiState ──► LumiKit
   │              │            │
   ├──► LumiServices ──────────┴──► LumiKit
   └──► LumiTerminal ──────────────► LumiKit
LumiKit ──► (yalnız Yams)
```

- `LumiUI` ve `LumiState`, `LumiServices`/`LumiTerminal`'i **import edemez** — yalnız `LumiKit` protokollerini görürler. Somut implementasyonları yalnız app target (composition root) tanır.
- SwiftTerm yalnız `LumiTerminal` içinde import edilir; public yüzeyine sızmaz.
- Sınır hilesi: `TerminalViewProviding` protokolü (NSView tipli `attachView`/`detachView`) **LumiKit'te** yaşar; böylece `LumiUI`, `LumiTerminal`'i import etmeden canlı terminal view'larını host eder ([03 §3](./03-ui-shell.md)).

| Modül | Sorumluluk | Public yüzey |
|---|---|---|
| **LumiKit** | Domain modelleri (`TerminalID`, `TerminalMeta`, `TerminalStatus`, `Repo`, `FileNode`, `GitCommit`, `Persona`, `Action`, `AppConfig`, `UIState`, `AgentProvider`), tüm servis protokolleri ([02](./02-services.md)), event enum'ları, `LumiError`, `LumiPaths`, ortak yardımcılar | Hepsi |
| **LumiTerminal** | Terminal alt sistemi ([01](./01-terminal-subsystem.md)) | `TerminalService: TerminalServicing` + `TerminalViewRegistry: TerminalViewProviding` — başka hiçbir şey public değil |
| **LumiServices** | Diğer tüm servis implementasyonları + bundle resource seed'leri | Protokol başına bir somut tip |
| **LumiState** | View-state store'ları ([03 §4](./03-ui-shell.md)) | Store'lar |
| **LumiUI** | Tüm SwiftUI view'ları + tasarım sistemi | `RootView`, `Theme` |
| **Lumi (app)** | AppKit lifecycle, pencere, menü, quit akışı, composition root, config yan etki koordinasyonu, sleep/wake + focus bildirimlerinin servislere bağlanması | — |

---

## 3. DI tasarımı

**Composition root:** `AppDelegate.applicationDidFinishLaunching` içinde kurulan `@MainActor final class AppContainer`. Tüm servisler ve store'lar burada, protokol tipleriyle, **bir kez** inşa edilir; constructor injection ile birbirine bağlanır.

```swift
@MainActor final class AppContainer {
    // servisler (somut tipler yalnız burada görünür)
    let config: ConfigServicing
    let terminal: TerminalServicing
    let viewRegistry: TerminalViewProviding
    let repo: RepoServicing
    let git: GitServicing
    let personas: PersonaServicing
    let actions: ActionServicing
    let notifications: NotificationServicing
    let system: SystemServicing
    // store'lar
    let workspace: WorkspaceStore
    let terminals: TerminalListStore
    let repoStore: RepoStore
    let gitStore: GitStore
    let actionsStore: ActionsStore
    let personasStore: PersonasStore
    let toasts: ToastStore
    let settings: SettingsStore
    // bağlantı
    let configCoordinator: ConfigSideEffectCoordinator
}
```

- **View'lar servisleri asla görmez:** bağımlılıklar SwiftUI Environment ile yalnız store olarak girer (`NSHostingView(rootView: RootView().environment(workspace)...)`). Her yan etki bir store intent metodudur. Tek yapısal istisna: `TerminalViewProviding` environment value'su ([03 §3](./03-ui-shell.md)).
- **Test ikamesi:** her LumiKit protokolünün el yazımı fake'i `LumiKitTestSupport` target'ında durur (örn. `FakeTerminalService`: broadcaster'ına senaryo event'leri itilir). Store testi = `Store(service: fake)` + event sür + `@Observable` state assert et. Servis testleri `~/.lumi`'yi taklit eden temp dizinlere karşı, **format-parite golden file'larıyla** koşar (karar 9). SwiftUI preview'ları aynı fake'leri kullanır.

### Bootstrap sırası (sıra-bağımlı — spec/22 §bootstrap'ın native karşılığı)

1. `AppContainer` kur (tüm servis + store'lar; henüz iş yapılmaz).
2. `system.fixProcessPath()` — **her PTY spawn'dan ve SystemChecker'dan önce** ([02 §8](./02-services.md)).
3. Seed: persona'lar ezilir, action'lar `modified_at` varsa korunur ([02 §6](./02-services.md)).
4. Store'lar `start()` — servis stream'lerini tüketmeye başlar.
5. Pencere + menü kur (`MainWindowController`, `MainMenuBuilder`).
6. `config.isFirstRun()` → onboarding sihirbazı **veya** ana UI.

---

## 4. Zorunlu gereksinimlerin karşılanma haritası (üst düzey)

[spec/00-overview.md §4](../spec/00-overview.md)'teki gereksinimlerin mekanizma haritasının tamamı [01-terminal-subsystem.md §5](./01-terminal-subsystem.md)'tedir. Üst düzeyde:

- **PTY→UI backpressure (4.1):** `FlowController` watermark'ları + `DispatchSourceRead` suspend/resume + `OutputCoalescer` (~16ms) — [01 §3](./01-terminal-subsystem.md).
- **Render-crash izolasyonu ve replay güvenliği (4.2):** kalıcı emülatör topolojisi replay'i yapısal olarak ortadan kaldırır; `PTYInputFilter` protokol-bilinçli girdi filtresi; registry-korumalı teslimat (native `safeSend`) — [01 §1, §4](./01-terminal-subsystem.md).
- **Korunan korumalar (4.3):** scrollback 5000, login-shell + komut enjeksiyonu, process-group SIGHUP temizliği — [01 §2, §6](./01-terminal-subsystem.md).

---

## 5. Karar 1-14 ile tutarlılık

[spec/01-decisions.md](../spec/01-decisions.md)'deki kararların tasarımdaki karşılıkları:

| Karar | Tasarımdaki yeri |
|---|---|
| 1, 2 (gamification, work-log at) | Hiçbir modülde karşılık yok; `TerminalMeta`'da codename alanı yok |
| 3 (Settings anlık) | `SettingsStore` + `ConfigSideEffectCoordinator` — [03 §4](./03-ui-shell.md) |
| 4 (unified diff) | FileViewer stack — [03 §6](./03-ui-shell.md) |
| 5 (tek hata sözleşmesi) | `LumiError` + `ToastStore.reporting` — [02 §9](./02-services.md) |
| 6 (commit-diff lazy) | `GitServicing.commitFiles` / `commitFileDiff` ayrımı — [02 §4](./02-services.md) |
| 7 (git check-ignore) | `RepoServicing.fileTree` — [02 §3](./02-services.md) |
| 8 (auto-update yok) | Paketleme fazında Sparkle yok — [04 faz 6](./04-prototype-plan.md) |
| 9 (persistence formatları aynen) | `LumiPaths` + ConfigService format-parite golden testleri — [02 §2](./02-services.md) |
| 10 (terminal arama yok) | SwiftTerm search API'si kullanılmaz |
| 11 (bug düzeltmeleri) | Tasarıma gömülü: equality-diff side-effect, path-traversal guard'ı her path'te, tab kimliği=path, sıralı terminal koleksiyonu, drop-path quote, görünür spawn-limit hatası, `wait_for` rolling buffer, temp dosya temizliği |
| 12 (create-project çıkar) | Default action seti `Bundle.module`'da bu action'sız |
| 13 (görsel kimlik semantic) | `Theme` token katmanı — [03 §5](./03-ui-shell.md) |
| 14 (auto-discovery iptal) | Karşılık yok |
