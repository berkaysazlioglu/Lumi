# Lumi Native — Mimari Tasarım

> Tasarım fazının bağlayıcı ana dokümanı. Davranışın kaynağı artık implementasyonun kendisidir (`LumiPackages/` + testler); bu doküman ve kardeşleri ([01](./01-terminal-subsystem.md), [02](./02-services.md), [03](./03-ui-shell.md), [04](./04-prototype-plan.md)) o davranışın **nasıl** implemente edileceğini tanımlar. Kapsam kararları için [decisions.md](../decisions.md) geçerlidir; teknoloji kararları 2026-06-11'de kullanıcı ile birlikte verildi ve aşağıda kayıtlıdır.

---

## 1. Teknoloji kararları

| # | Konu | Karar | Gerekçe |
|---|---|---|---|
| T1 | Terminal emülasyonu | **SwiftTerm** (SPM bağımlılığı, MIT; **revision-pin `24a68bc`**, v1.13.0 sonrası release'lenmemiş CSI T / DEC 2026 / Shift+mouse düzeltmeleri için — gerekçe `Package.swift` yorumunda ve [karar 16](../decisions.md)) + oturum başına **kalıcı view-attached emülatör** | Aktif bakımda, headless `Terminal` motoru + AppKit `TerminalView` ayrımı var, `feed()` tabanlı API okuma döngüsünü bize bırakır (backpressure önkoşulu). Özel emülatör (~3-6 ay) için engelleyici neden bulunamadı. Fork/vendor şimdilik gereksiz; API drift olursa sonradan fork'lanır. Düzeltmeleri kapsayan release çıkınca pin sürüm aralığına döndürülür. Topoloji gerekçesi: [01-terminal-subsystem.md §1](./01-terminal-subsystem.md) |
| T2 | PTY katmanı | **Kendi `PTYProcess` wrapper'ımız** — SwiftTerm `LocalProcess` kullanılmaz | `LocalProcess` fd okumasına suspend/resume kancası sunmaz; watermark backpressure ([00-architecture.md Ek A](#ek-a--buglardan-türetilen-zorunlu-gereksinimler-bağlayıcı)) ancak okuma döngüsü bizdeyse kurulabilir. Process-group kill, env enjeksiyonu ve exit-sıralaması da bizim kontrolümüzde olmalı |
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
    │                    JSON codec'ler (bağımlılıksız)
    ├── LumiTerminal   — PTYProcess, okuma/yazma pipeline'ı, StatusStateMachine,
    │                    OSC parser, TerminalViewRegistry (SwiftTerm: internal detay)
    ├── LumiServices   — Config/Repo/Git/Notification/System servisleri
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
| **LumiKit** | Domain modelleri (`TerminalID`, `TerminalMeta`, `TerminalStatus`, `Repo`, `FileNode`, `GitCommit`, `AppConfig`, `UIState`, `AgentProvider`), tüm servis protokolleri ([02](./02-services.md)), event enum'ları, `LumiError`, `LumiPaths`, ortak yardımcılar | Hepsi |
| **LumiTerminal** | Terminal alt sistemi ([01](./01-terminal-subsystem.md)) | `TerminalService: TerminalServicing` + `TerminalViewRegistry: TerminalViewProviding` — başka hiçbir şey public değil |
| **LumiServices** | Diğer tüm servis implementasyonları | Protokol başına bir somut tip |
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
    let notifications: NotificationServicing
    let system: SystemServicing
    // store'lar
    let workspace: WorkspaceStore
    let terminals: TerminalListStore
    let repoStore: RepoStore
    let gitStore: GitStore
    let toasts: ToastStore
    let settings: SettingsStore
    // bağlantı
    let configCoordinator: ConfigSideEffectCoordinator
}
```

- **View'lar servisleri asla görmez:** bağımlılıklar SwiftUI Environment ile yalnız store olarak girer (`NSHostingView(rootView: RootView().environment(workspace)...)`). Her yan etki bir store intent metodudur. Tek yapısal istisna: `TerminalViewProviding` environment value'su ([03 §3](./03-ui-shell.md)).
- **Test ikamesi:** her LumiKit protokolünün el yazımı fake'i `LumiKitTestSupport` target'ında durur (örn. `FakeTerminalService`: broadcaster'ına senaryo event'leri itilir). Store testi = `Store(service: fake)` + event sür + `@Observable` state assert et. Servis testleri `~/.lumi`'yi taklit eden temp dizinlere karşı, **format-parite golden file'larıyla** koşar (karar 9). SwiftUI preview'ları aynı fake'leri kullanır.

### Bootstrap sırası (sıra-bağımlı)

1. `AppContainer` kur (tüm servis + store'lar; henüz iş yapılmaz).
2. `system.fixProcessPath()` — **her PTY spawn'dan ve SystemChecker'dan önce** ([02 §8](./02-services.md)).
3. Store'lar `start()` — servis stream'lerini tüketmeye başlar.
4. Pencere + menü kur (`MainWindowController`, `MainMenuBuilder`).
5. `config.isFirstRun()` → onboarding sihirbazı **veya** ana UI.

---

## 4. Zorunlu gereksinimlerin karşılanma haritası (üst düzey)

[Ek A](#ek-a--buglardan-türetilen-zorunlu-gereksinimler-bağlayıcı)'teki gereksinimlerin mekanizma haritasının tamamı [01-terminal-subsystem.md §5](./01-terminal-subsystem.md)'tedir. Üst düzeyde:

- **PTY→UI backpressure (A.1):** `FlowController` watermark'ları + `DispatchSourceRead` suspend/resume + `OutputCoalescer` (~16ms) — [01 §3](./01-terminal-subsystem.md).
- **Render-crash izolasyonu ve replay güvenliği (A.2):** kalıcı emülatör topolojisi replay'i yapısal olarak ortadan kaldırır; `PTYInputFilter` protokol-bilinçli girdi filtresi; registry-korumalı teslimat (native `safeSend`) — [01 §1, §4](./01-terminal-subsystem.md).
- **Korunan korumalar (A.3):** scrollback 5000, login-shell + komut enjeksiyonu, process-group SIGHUP temizliği — [01 §2, §6](./01-terminal-subsystem.md).

---

## 5. Karar 1-14 ile tutarlılık

[decisions.md](../decisions.md)'deki kararların tasarımdaki karşılıkları:

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
3. **Frame hızında batching:** Chunk'lar ~16ms'de bir veya boyut eşiğinde coalesce edilmeli. Chunk başına mesaj + render turu **yasak**; chunk işleme maliyeti O(chunk) kalmalı (asla tüm buffer taranmamalı — OOM'un kök nedeni buydu).
4. **Sabit kapasiteli byte ring buffer:** Snapshot/replay tamponu string concat değil `Uint8Array`-eşdeğeri ring buffer olmalı; GC churn sıfır.
5. **Sequence-güvenli kesim:** Her buffer kesimi ANSI escape sequence, OSC gövdesi ve UTF-8/çok-byte'lı karakter sınırlarına saygılı olmalı. Newline-sezgisel 2048-pencere yaklaşımı yetersiz; alt-screen (newline'sız) çıktı için "rastgele indeksten kes" fallback'i yasak. Tercihen replay ham byte yerine **emülatör durum serileştirmesi** (headless terminal state machine: grid + scrollback + modlar) ile yapılmalı.
6. **Detached/görünmeyen terminal politikası:** Görünmeyen view'a tam hız stream gönderilmemeli; cap'li buffer'da biriktirip attach anında tek snapshot ile resync edilmeli. Mevcut fix'in `totalLength` (monoton offset) + `epoch` (full-redraw sinyali) resync protokolü korunmaya değer.
7. **Sıralama garantisi:** Terminal başına tüm yazımlar tek seri kuyruktan akmalı; replace uygulanırken araya append giremez.
8. **Emülatörün iç write buffer'ı da sınırlı olmalı** veya backpressure döngüsüne dahil edilmeli (xterm.js'te bugün sınırsız — ikinci OOM vektörü).

### A.2 Render-crash izolasyonu ve replay güvenliği

9. **Replay ile canlı girdi ayrılmalı:** Backlog replay'i sırasında emülatörün ürettiği otomatik yanıtlar (CPR/DSR, DA, DECRQM, mouse raporları) PTY'ye **asla** yazılmamalı; replay "girdi kapalı" modda yapılmalı. "Random karakterler" bug'ının birebir mekanizması budur — mevcut regex tabanlı focus-event ayıklama (`\x1b[I/O`) yetersizdir; PTY'ye giden yolda **protokol-bilinçli girdi filtresi** gerekir.
10. **Donma/crash gözetimi:** UI için unresponsive-watchdog ve GPU/compositor kaybı kurtarma yolu olmalı; kurtarma sırasında siyah ekran yerine "yeniden bağlanıyor" durumu gösterilmeli.
11. **Tek paylaşımlı GPU context:** Terminal başına ayrı GPU context açılmamalı; N terminal tek renderer/atlas ile çizilmeli (context evict kaynaklı kararma riski sıfırlanır).
12. **Crash dayanıklılığı:** Hedef view yok/çökmüşse gönderim sessizce atlanmalı (safeSend eşdeğeri), PTY pause edilmeli, recovery sonrası snapshot'tan devam edilmeli. "UI ölür → PTY'ler yaşar → UI yeniden bağlanır" akışı için **entegrasyon testi** yazılmalı: yeniden bağlanma sonrası PTY'ye hiçbir istenmeyen byte yazılmadığı doğrulanmalı.

### A.3 Korunması gereken mevcut korumalar

- 500KB tail cap paritesi (PTY başına) + 5000 satır scrollback.
- `safeSend` dersinin native karşılığı: UI lifecycle'ına dayanıklı event dağıtımı.
- Uygulama crash'inde zombi PTY bırakmamak: process group + SIGHUP/killpg ile login shell altındaki tüm claude process ağacının temizlenmesi.
