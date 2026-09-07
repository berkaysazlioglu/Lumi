# Lumi Native — Servis Katmanı Tasarımı

> **2026-09-05 refactor (Faz 1–7) ile güncellendi** (`docs/refactor-plan-2026-09.md`): protokol imzaları, ISP bölünmeleri, servis parçaları ve `LumiError` bloğu kodun gerçek hâline eşitlendi; §10 ve §11 eklendi.
>
> `LumiKit` protokolleri + `LumiServices`/`LumiTerminal` implementasyon sözleşmeleri. Electron IPC kanal haritası iç API sözleşmesine dönüştürülmüştür (§1).

Genel kurallar:
- Tüm protokoller `LumiKit`'te (`Protocols/`, composition sözleşmeleri `Composition/`); metodlar yalnız `LumiError` fırlatır; tüm event payload'ları `Sendable`.
- **İzolasyon** (§11): UI-yüzlü ve store'larla senkron konuşan protokoller (`TerminalSessionControlling`, `TerminalAppearanceControlling`, `TerminalViewProviding`, `NotificationServicing`) `@MainActor`'dır — PTY I/O implementasyonun içindeki io queue'lardadır, protokol bu detayı sızdırmaz. Dosya/process-I/O ağırlıklı ve durum tutan servisler `Actor` (`ConfigService`, `RepoService`, kullanım servisleri); durumsuz olanlar `Sendable` struct'tır (`GitService`, `SystemService` bileşenleri, `SystemProcessRunner`).
- **Servis→store event'leri `AsyncStream<Event>`** — `EventBroadcaster<Event>` yardımıyla (continuation registry; her `events()` çağrısı taze stream döner; `bufferingPolicy` varsayılanı `.unbounded`, yaşam döngüsü event'leri kayıpsız olmalı). Her domain'in tek tüketicisi kendi store'udur; UI servislere asla doğrudan abone olmaz.
- **`events()` actor'lı servislerde `nonisolated`** (refactor 5.6): tüketici Task'ı KURULMADAN ÖNCE senkron alınabilmeli, yoksa actor hop'u boyunca gönderilen boot event'leri kaybolur. Tüketici tarafındaki karşılığı `EventConsumer`dır ([00 §3](./00-architecture.md)).
- Push'ların çoğu **pull-after-push** kalır: payload'sız "changed" sinyali → store tüm listeyi yeniden çeker (Electron paritesi, basitlik).

**Protokol envanteri** (LumiKit; hepsi bir `ServiceRegistry` üyesiyle ya da bir dikiş noktasıyla eşleşir):

| Protokol | Somut tip(ler) | Bölüm |
|---|---|---|
| `ConfigServicing` | `ConfigService` (actor) | [§2](#2-configservicing) |
| `RepoServicing` | `RepoService` (actor) | [§3](#3-reposervicing) |
| `GitReading` / `GitContentReading` / `GitWriting` (`GitServicing` typealias) | `GitService` (+ `GitCommandRunner`, `GitPorcelainParser`, `RepoPathGuard`) | [§4](#4-gitservicing) |
| `NotificationServicing` + `NotificationPresenting` | `NotificationService` + `UNNotificationPresenter` / `LogNotificationPresenter` (LumiAppCore) | [§7](#7-notificationservicing) |
| `SystemServicing` + `SystemCheck` + `TerminalSmokeTesting` | `SystemService` (+ `ShellCheck`, `PTYSmokeCheck`, `AgentCLICheck`, `PathEnvironmentFixer`, `ExternalURLOpener`, `FileSystemOperations`, `FolderChooser`); smoke tester `PTYSmokeTester` (LumiTerminal) | [§8](#8-systemservicing) |
| `ProcessRunning` / `BinaryLocating` | `SystemProcessRunner` / `SystemBinaryLocator` | [§8](#8-systemservicing) |
| `UsageServicing` + `UsageCacheInvalidating` | `ClaudeUsageService`, `CodexUsageService`, `CachingUsageService` dekoratörü | [05](./05-usage-indicator.md) |
| `SyntaxHighlighting` | `HighlightrEngine` (+ `HighlightrStyle`) | [§8](#8-systemservicing) |
| `SessionStarterServicing` | `SessionStarterService` (actor) | [§7](#7-notificationservicing) |
| `ActivityMonitoring` | `SystemActivityMonitor` | [05 §6.1](./05-usage-indicator.md) |
| `TerminalSessionControlling` / `TerminalAppearanceControlling` / `TerminalViewProviding` | `TerminalSessionManager` / `TerminalViewRegistry` | [01](./01-terminal-subsystem.md) |
| `ServiceRegistry` / `ConfigChangeObserving` | `LiveServiceRegistry` / feature assembly'leri | [00 §3](./00-architecture.md) |

---

## 1. 62 IPC kanalının eşlemesi

| Electron kanalı | Native karşılığı |
|---|---|
| `terminal:spawn / write / kill / resize / focus` | `TerminalSessionControlling.spawn / write / kill / resize / setFocused` |
| `terminal:snapshot` | Silindi — tek process'te reconciliation yok; `TerminalSessionControlling.terminals` yalnız metadata döner (sıralı koleksiyon, karar 11) |
| `terminal:get-status` | Ölü kanal — taşınmaz |
| `terminal:output` (push) | **Event değil** — ham çıktı PTY→emülatör hattında `LumiTerminal` içinde akar ([01 §3](./01-terminal-subsystem.md)); state katmanına asla çıkmaz |
| `terminal:exit / status / title / bell` (push) | `TerminalEvent.exited / statusChanged / titleChanged / bell` |
| `terminal:sync` (push) | Silindi — uyanmada resync gereksiz (state hiç kopmaz); `NSWorkspace.didWakeNotification` yalnız watcher tazelemesi tetikler |
| `repos:list` | `RepoServicing.repos()` (fırlatmaz — var olmayan kök sessizce atlanır) |
| `repos:files` | Ölü legacy — taşınmaz |
| `repos:file-tree / watch-file-tree / unwatch-file-tree` | `RepoServicing.fileTree / watchFileTree / unwatchFileTree` |
| `repos:changed`, `file-tree:changed` (push) | `RepoEvent.reposChanged / fileTreeChanged(repoPath)` |
| `git:commits / branches / status / commit / read-file / file-diff` | Aynı adlı metodlar, üç protokole dağılmış: `GitReading` (commits/branches/status) · `GitContentReading` (readFile/fileDiff) · `GitWriting` (commit) |
| `git:commit-diff` | **İkiye bölündü** (karar 6): `commitFiles(sha)` (yalnız liste) + `commitFileDiff(sha, file)` (lazy) |
| `context:delete-file / reveal-in-file-manager` | `SystemServicing.trash / revealInFinder` |
| `config:is-first-run / get / set` | `ConfigServicing.isFirstRun / config / updateConfig` |
| `ui-state:get / set` | `ConfigServicing.uiState / updateUIState` |
| `window:toggle-maximize / minimize / close / set-traffic-light-visibility` | IPC'siz — `MainWindowController` iç metodları (custom titlebar butonları native'de yok; traffic-light gizleme focus-mode akışında, [03 §2](./03-ui-shell.md)) |
| `dialog:open-folder` | `SystemServicing.chooseFolder()` |
| `actions:*` / `personas:*` | **Kaldırıldı** (karar 25) — karşılığı yok |
| `system:check-run / check-fix` | `SystemServicing.runChecks(selectedProvider:)`. **`check-fix` karşılığı yok:** düzeltme bir sayfa açmaktır ve URL'i kontrolün kendisi üretir (`SystemCheckResult.fixURL`) — `fix(checkID:)` metodu ve checkID→URL `switch`'i kaldırıldı (refactor 3.6) |
| `shell:open-external` | `SystemServicing.openExternal` (http/https whitelist **korunur**; ihlal → görünür hata) |
| `app:confirm-quit` / `app:quit-confirmed` | IPC'siz — `applicationShouldTerminate` → `.terminateLater` akışı ([03 §2](./03-ui-shell.md)) |
| `notification:click` (push) | `NotificationEvent.clicked(TerminalID)` |
| `collection:get` | Ölü — taşınmaz (karar 1) |

---

## 2. ConfigServicing

```swift
public protocol ConfigServicing: Actor {
    func config() async -> AppConfig
    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) async throws
    func uiState() async -> UIState
    /// In-memory'ye anında uygulanır; disk yazımı 500 ms debounce'lanır.
    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async
    func isFirstRun() async -> Bool
    /// Quit yolunda bekleyen debounce'lu yazımları hemen diske indirir.
    func flushPendingWrites() async
    nonisolated func events() -> AsyncStream<ConfigEvent>
}

public enum ConfigEvent: Sendable, Equatable {
    case configChanged(old: AppConfig, new: AppConfig)
    case loadFailed(file: String, detail: String)    // bozuk JSON → .bak yedeği alındı
    case writeFailed(file: String, detail: String)   // debounce'lu ui-state yazımı diske inemedi
}
```

- **Persistence paritesi (karar 9, bağlayıcı):** `~/.lumi/config.json` ve `ui-state.json` mevcut şemayla, 2-space-indent pretty JSON olarak okunur/yazılır (`.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`; atomik yazım). Dev modda `~/.lumi-dev`; production'da yeni dizin yoksa legacy `~/.pulpo` → `~/.ai-orchestrator` fallback'i (migration değil, yerinde kullanım). Tümü `LumiPaths`'te (`Mode` artık `#if DEBUG` değil, parametre — [00 §3](./00-architecture.md)). **Format-parite golden testleri zorunlu**: `ConfigGoldenBytesTests` byte-uyumlu round-trip'i, `ConfigCodecIntegrityTests` `Mirror` ile alan bütünlüğünü kilitler.
- **Codec yapısı (refactor 5.7):** çeviri tek giriş kapısı `ConfigCodec`'tir; gövde bölüm başına codec'lere ayrılmıştır — `AppConfigCodec`, `UIStateCodec`, `NotificationSettingsCodec`, `SessionTriggerCodec`, `UsageCodec`, `AdditionalPathCodec`. Her codec'te `decode(_:)` ve `overlay(_:)` yan yana durur; modele eklenen her alan ikisine birden girmek zorundadır (`ConfigCodecIntegrityTests` alt tip bazında zorlar). Lenient skalar okuma `JSONValue`'dadır (tek tanım; `int` keser, `roundedInt` yuvarlar, bool asla sayı sayılmaz, string kabulü yalnız kullanım API'lerinde açık seçimle).
- **Config ailesindeki hiçbir model `Codable` DEĞİLDİR** (karar 9'un teknik eki): yazım, diskten okunan **ham sözlüğün** üzerine tipli overlay merge'idir; böylece spec dışı/legacy anahtarlar (`gridColumns`, `activeView`, Electron'dan kalanlar) aynen korunur. `Codable` eklemek bu garantiyi sessizce bozar.
- Defaults infill, `additionalPaths` array coercion'ı, `aiProvider` doğrulaması (`claude|codex`, default claude) birebir.
- **Bozuk dosya (Faz 1.13):** parse edilemeyen dosya defaults'la EZİLMEDEN önce `<ad>.bak-<yyyyMMdd-HHmmss>` olarak yanına kopyalanır (aynı dosya için tek yedek), stderr'e iz düşer ve `ConfigEvent.loadFailed` yayınlanır — merge yalnız parse edilebilen ham sözlük üzerinden çalıştığı için, yedek alınmasa bilinmeyen anahtarlar ilk yazımda kaybolurdu. Debounce'lu ui-state yazımı diske inemezse `ConfigEvent.writeFailed`. `updateConfig` yazma hatasında `LumiError.configIOFailed` fırlatır. `SettingsStore` iki event'i de tüketir ve `ToastStore` üzerinden hata toast'ı gösterir (karar 5).
- `updateUIState` in-memory state'e anında uygular, **500 ms debounce'lu atomik yazım** planlar; `flushPendingWrites()` quit yolunda bunu hemen indirir.
- `isFirstRun()` = config.json yok VEYA `projectsRoot` boş.

**Yan etki propagasyonu — `ConfigSideEffectCoordinator` (LumiAppCore):** `ConfigEvent.configChanged(old:new:)` tüketir ve `(old, new)` çiftini kayıtlı `ConfigChangeObserving` gözlemcilerine kayıt sırasında dağıtır. Refactor 3.3'ten sonra koordinatör **hangi alanın ne yaptığını bilmez**; diff'i her gözlemci (yani her `FeatureAssembly`) kendi alanları için yapar ve karşılaştırma **eşitlikle** olur (Electron'un truthiness bug'ı yapısal olarak imkânsız — `0`/boş string de propagate olur, karar 11):

- `projectsRoot`/`additionalPaths` değişti → `RepoFeatureAssembly` → `repo.setRoots(...)` (→ `reposChanged` yayını)
- `notifications` değişti → `NotificationAssembly` → `notifications.updateSettings(s)`
- `usageIndicators`/`usageAutoRefresh` değişti → `UsageFeatureAssembly` ([05 §6.1](./05-usage-indicator.md))
- `sessionTrigger` değişti → `SessionScheduleAssembly`
- terminal font/cursor değişti → `TerminalFeatureAssembly` → `TerminalAppearanceControlling`

Settings anlık-uygulama modeli (karar 3) bu koordinatörle çalışır: her kontrol değişikliği `config.updateConfig {}` → diff → anında yan etki. `SettingsStore` ayrıca aynı `configChanged` akışını dinleyip aynasını tazeler.

---

## 3. RepoServicing

```swift
public protocol RepoServicing: Actor {
    func repos() async -> [Repo]
    func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) async
    func fileTree(repoPath: String) async -> [FileTreeNode]   // kök seviyesi; alt düğümler `children`da
    func watchFileTree(repoPath: String) async
    func unwatchFileTree(repoPath: String) async
    nonisolated func events() -> AsyncStream<RepoEvent>       // .reposChanged, .fileTreeChanged(repoPath)
}
```

- **Sessiz-boş sözleşme:** ne `repos()` ne `fileTree(repoPath:)` fırlatır; var olmayan kök/dizin sessizce atlanır (git olmayan ya da silinmiş dizin rutin bir durumdur).
- **Keşif paritesi:** `projectsRoot` + `additionalPaths(root|repo)`; root'lar non-recursive ilk seviye taraması; `.`-prefix ve dizin-olmayan atlanır; `<dir>/.git` (dosya veya dizin — submodule sayılır) → `isGitRepo`; git-olmayan dizinler de listelenir; mutlak-path dedup, ilk kazanır; yalnız baştaki `~` açılır (`~user` desteklenmez, Electron paritesi).
- **File tree:** Hardcoded exclude listesi (`FileTreeBuilder.isHardcodedExcluded`, git-olmayan dizinler için **korunur**); ignored bayrakları **tek** git çağrısıyla (`git ls-files --others --ignored --exclude-standard --directory -z`) — nested/global/`info/exclude` dahil (karar 7'nin bilinçli sapması), tamamen ignored dizinler trailing-slash'li tek girdiye çöker ve o dizine inilmez; `.git` daima gizli; sıralama klasör→dosya, ignored sona. Path'ler repo-köküne göre `/` ayraçlı, `FileTreeNode.id`'dir.
- **Tarama güvenliği (karar 28):** `FileTreeBuilder.build` actor DIŞINDA, `Task.detached(priority: .utility)` içinde koşar — devasa bir kökte dakikalar süren senkron iş `RepoService`'i (repo listesi, watcher yönetimi) kilitlemez. Ayrıca `Limits(maxEntries: 100_000, maxDepth: 32)` bütçesi vardır: bellek sızıntısına dönüşen sınırsız tarama yapısal olarak imkânsızdır (`FileTreeBuilderSafetyTests`).
- **Watcher:** Kökler non-recursive **300 ms** debounce (`DirectoryWatcher`); aktif repo recursive **500 ms** latency (`RecursiveDirectoryWatcher`, FSEvents, `FileTreeBuilder.watchNoiseNames` hariç tutulur). "Olay → tam reload" stratejisi korunur; polling yok (parite). `unwatchFileTree` watcher'ı iptal edip düşürür — tab kapanışında çağrılmazsa FSEvents akışı sızar.

---

## 4. GitServicing

ISP (refactor 3.8): tek büyük protokol yerine **hata sözleşmesine göre** üçe ayrılmış yüzeyler. Tüketici store'lar yalnız kullandıkları yüze bağlanır, fake'ler küçülür; `GitServicing` bu üçünün bileşimidir ve yalnız composition root ile `GitService` kullanır.

```swift
/// SESSİZ-BOŞ sözleşme: hata → boş koleksiyon + log (git olmayan dizinler rutin
/// olarak açılır; panel boş kalır, Electron paritesi). UI'ya hata sızmaz.
public protocol GitReading: Sendable {
    func branches(repoPath: String) async -> [GitBranch]
    func commits(repoPath: String, branch: String?) async -> [GitCommit]
    func status(repoPath: String) async -> [GitFileChange]
    func commitFiles(repoPath: String, sha: String) async -> [CommitFile]          // karar 6: yalnız liste
    func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview  // karar 21
}

/// FIRLATAN sözleşme: kullanıcı bir dosya açtı/diff istedi; başarısızlık görünür hatadır.
public protocol GitContentReading: Sendable {
    func readFile(repoPath: String, file: String) async throws -> String
    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff
    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff  // lazy
}

/// YAZMA sözleşmesi: repoyu değiştiren tek operasyon.
public protocol GitWriting: Sendable {
    func commit(repoPath: String, message: String, files: [String]) async throws
}

public typealias GitServicing = GitReading & GitContentReading & GitWriting
```

**Implementasyon üçe bölünmüştür (refactor 3.10)** — `GitService` yalnız kompozisyondur:

| Parça | Sorumluluk |
|---|---|
| `GitCommandRunner` | argv + cwd + timeout (`/usr/bin/git`, 20 sn) + sessiz-hata loglaması (`logQuietFailure`); `ProcessRunning` üstünde durur, parse/iş mantığı içermez |
| `GitPorcelainParser` | Saf parse (`enum`, I/O yok) — `parseBranches` / `defaultBranch(fromRefOutput:)` / `parseCommits` / `parseStatus(Line)` / `parseDiffTree`; birim testi `GitPorcelainParserTests` |
| `RepoPathGuard` | Path-traversal doğrulaması; `GitService` **ve** `FileSystemOperations` (trash/reveal) ortak kullanır |

- simple-git yerine **`git` CLI + porcelain parse**; tüm process I/O `ProcessRunning` üzerinden (refactor 3.1) — git binary'si olmayan ortamda da birim testi yazılabilir.
- **Commit log semantiği birebir:** default branch `main → master → nil`; `--max-count=50`; branch verilmişse ve default'tan farklıysa **`defaultBranch..branch`** aralığı; hata → boş array + log. Default branch tek `for-each-ref refs/heads/main refs/heads/master` çağrısıyla ve **yalnız gerektiğinde** hesaplanır (eskiden her `commits` çağrısı ayrıca tam bir `branch --list` koşturuyordu: N branch → 2N process, Faz 1.9).
- **Status sadeleşmesi korunur:** staged/unstaged ayrımı yok; `modified|added|deleted|renamed|untracked`; rename'de `to` path.
- **Path-traversal guard'ı TÜM path alan metodlarda** (karar 11 — Electron'da yalnız `readFile` korumalıydı): `RepoPathGuard.resolve(repoPath:relativePath:)`; ihlal → `LumiError.pathOutsideRepo`. **İki taraf da `resolvingSymlinksInPath()` ile canonicalize edilir** (Faz 1.12): aksi hâlde repo içindeki bir symlink repo DIŞINA işaret ettiğinde guard geçiliyordu; ayrıca `/var` ↔ `/private/var` uyumsuzluğu çözülür.
- **Commit hata yolu (Faz 1.6):** `commit` önce her dosyayı guard'dan geçirir, sonra `git add -- <files>` koşar. `add` başarısızsa detay **ilk koşunun** `stderr`'inden alınır (`?? "timeout"`) — hata yolunda `add`'i ikinci kez çalıştırmak yan etkiyi tekrarlar ve gereksiz bir process daha açardı. `LumiError.gitFailed(operation:detail:)`, detay 500 karaktere kırpılır.
- `fileDiff`/`commitFileDiff` çıktısı tiplenmiş `UnifiedDiff` modelidir (`UnifiedDiffParser`; FileViewer doğrudan render eder — [03 §6](./03-ui-shell.md)).
- **`imagePreview` (karar 21):** görsel dosyalarda metin diff'i yerine ham blob çifti. `sha` verilirse `git show sha^:file` ↔ `git show sha:file`, verilmezse `HEAD:file` ↔ disk. Çıktı `GitCommandRunner.runRaw` ile **`Data`** olarak alınır (UTF8 decode görselleri bozar). Liste operasyonları gibi **sessiz**: eksik taraf nil'dir (root commit'in parent'ı, eklenen/silinen dosya, untracked dosya — hepsi rutin), yalnız path-traversal ihlali loglanır. Taraf başına `maxImagePreviewBytes` (20 MB) sınırı; disk tarafında boyut önce file attribute'undan okunur, sınır üstü dosya belleğe hiç alınmaz.

---

## 5. PersonaServicing — **kaldırıldı (karar 25, 2026-09-04)**

Persona ön ayarları projeden çıkarıldı; protokol, servis, YAML codec ve seed yok. Eski tasarım için git geçmişine bakılabilir.

---

## 6. ActionServicing — **kaldırıldı (karar 25, 2026-09-04)**

Quick Action otomasyonları (`ActionEngine`, `AgentCommandBuilder`, `.history/`) projeden çıkarıldı. Onlar için tutulan `TerminalServicing.outputStream(id:)` / `onOutputText` fan-out dikişi de Faz 1.19'da **silindi** (YAGNI: tek tüketicisi kalmamıştı). Ham çıktıya ihtiyaç duyan yeni bir özellik çıkarsa dikiş yeniden açılır.

---

## 7. NotificationServicing

```swift
@MainActor
public protocol NotificationServicing: AnyObject {
    func requestPermissionIfNeeded() async
    func updateSettings(_ settings: NotificationSettings)
    /// Pencere odaklıyken native OS bildirimi gönderilmez (focus guard).
    func setWindowFocused(_ focused: Bool)
    func handleStatusChange(id: TerminalID, repoName: String, status: TerminalStatus)
    /// Exit-cleanup sözleşmesi: interval timer'ını iptal eder — çağrılmazsa timer sızar.
    func terminalRemoved(_ id: TerminalID)
    func events() -> AsyncStream<NotificationEvent>   // .clicked(TerminalID), .bell(TerminalID, repoName)
}

/// OS sunumunun dikiş yeri: UNUserNotificationCenter bundle'lı app ister
/// (`swift run` altında çöker) — bu yüzden sunum ayrı protokoldür.
public protocol NotificationPresenting: Sendable {
    func requestAuthorization() async -> Bool
    @MainActor func present(id: String, title: String, body: String)
    @MainActor func removeDelivered(id: String)
}
```

- Servis **`@MainActor`**'dır (UI-yüzlü, store'la senkron konuşur), `Actor` değil. Yeni durum tek bir `status` parametresiyle gelir (`handleStatusChange`); eski/yeni çifti servise taşınmaz — geçiş kararını status makinesi zaten vermiştir.
- Sunum enjekte edilir: bundle'lı çalışmada `UNNotificationPresenter`, `swift run`'da `LogNotificationPresenter` (ikisi de LumiAppCore), testte `FakeNotificationPresenter`. Tekrarlı bildirimler `RepeatingScheduling` dikişi (üretimde `TimerRepeatingScheduler`) ile kurulur — testte sahte zamanlayıcıyla interval sızıntısı doğrulanır.
- Status-makinesi-güdümlü tablo birebir: `waiting-unseen` → anında bildirim + `unseenIntervalMinutes` (default 1 dk) tekrar; `waiting-seen` → yalnız `seenIntervalMinutes` (default 5 dk) tekrar; `error` → tek seferlik; `working/idle/waiting-focused` → temizle. Terminal başına en fazla bir interval.
- **Focus guard:** native OS bildirimi yalnız pencere odaklı değilken; `bell` toast event'i her durumda.
- Bildirim tıklaması → `.clicked(id)` → store terminale odaklanır (**minimize istisnası**: minimize edilmiş terminalin otomatik odak alabildiği tek yol).
- `terminalRemoved` exit-cleanup sırasının 3. adımıdır ([01 §6](./01-terminal-subsystem.md)); interval sızıntısı testi zorunlu (`NotificationServiceTests`).

### 7.1 SessionStarterServicing (zamanlanmış oturum)

```swift
public protocol SessionStarterServicing: Sendable {
    func start(prompt: String) async throws
}
```

`SessionStarterService` (actor): `BinaryLocating` ile `claude` çözülür → `runner.run(binary, arguments: ["-p", prompt], timeout: 120)`. Argümanlar dizi olarak geçer (shell yok — prompt tek argv, quoting sorunu doğmaz). Çalışan terminallere DOKUNMAZ; amacı 5 saatlik kullanım penceresini planlanan saatte başlatmaktır. Hata → `LumiError.cliNotFound` / `.sessionStartFailed`. Tetikleyen taraf `SessionScheduleStore` + `SessionScheduleAssembly`'dir; ayar `config.sessionTrigger`.

---

### 7.2 AgentHookServing / AgentHookInstalling (karar 45)

```swift
public protocol AgentHookServing: Sendable {
    func start() async throws -> AgentHookEndpoint   // 127.0.0.1:<port> + rastgele token; idempotent
    func stop() async
    func events() -> AsyncStream<AgentHookEvent>
}
public protocol AgentHookInstalling: Sendable {
    func install() async -> [AgentHookInstallResult]   // sağlayıcı başına installed/unchanged/skipped/failed
    func uninstall() async -> [AgentHookInstallResult]
}
```

- **`AgentHookServer`** (`LumiServices/AgentHooks/`): Network.framework `NWListener`, tek isteklik bağlantılar. `HTTPRequestParser` (saf; istek satırı + başlıklar + `Content-Length`, 16 KB başlık / 1 MiB gövde bütçesi) → `AgentHookRequestRouter` (saf; `POST /hook/<provider>`, `X-Lumi-Agent-Hook-Token`, `X-Lumi-Terminal-ID`) → `AgentHookEvent.parse` (LumiKit; ham JSON'dan yalnız durum için gereken alanlar). Hata sözleşmesi: yanlış istek HTTP koduyla reddedilir ve yayılmaz; sunucu hatası `LumiError.underlying` fırlatır, assembly toast basar ve hook'suz devam eder.
- **`AgentHookInstaller`**: script'ler (`AgentHookScript`, `~/.lumi/hooks/lumi-*-hook.sh`, 0755) + `ClaudeHookSettings` (`~/.claude/settings.json` `hooks` bölümü) + `CodexHookSettings` (`~/.codex/hooks.json`) + `CodexHookTrust`/`CodexConfigTomlEditor` (`config.toml` `[hooks.state."…"] trusted_hash`, satır tabanlı ve geri kalanı byte-byte koruyan). Dosya I/O doğrudan `FileManager`'dır (process yok); JSON yazımı `.prettyPrinted + .sortedKeys + .withoutEscapingSlashes`, atomik.
- **Assembly:** `AgentHooksAssembly` (`.system`, terminal assembly'sinden önce) sunucuyu açar → `TerminalSessionControlling.setAgentHookEndpoint` → olayları `applyAgentHookEvent`'e akıtır → kurulumu ayrı Task'ta koşar. `agentHooksEnabled` kapanınca sunucu durur, uç nokta `nil`e çekilir ve `uninstall()` çağrılır; kapanışta yalnız sunucu durur.

## 8. SystemServicing

```swift
public protocol SystemServicing: Sendable {
    /// Check'ler async koşar (senkron SystemChecker taşınmaz — karar 11).
    func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult]
    func fixProcessPath() async
    func openExternal(_ url: URL) throws          // http/https whitelist; ihlal → .externalURLBlocked
    func trash(path: String) async throws         // FileManager.trashItem; path-guard'lı
    func revealInFinder(path: String)             // NSWorkspace.activateFileViewerSelecting; path-guard'lı
    @MainActor func chooseFolder() async -> String?   // NSOpenPanel
}

/// Tek bir sağlık kontrolünün sınırı (OCP): yeni kontrol = yeni dosya + bir satır.
public protocol SystemCheck: Sendable {
    var id: String { get }                        // ürettiği SystemCheckResult.id ile aynı
    func run(context: SystemCheckContext) async -> SystemCheckResult
}

public struct SystemCheckContext: Sendable, Equatable {
    public let selectedProvider: AgentProvider
}
```

**`SystemService` artık yalnız KOMPOZİSYONDUR (refactor 3.9)** — yüzey değişmedi, gövde beş parçaya dağıldı:

| Parça | Sorumluluk |
|---|---|
| `[any SystemCheck]` | Sağlık kontrolleri. `SystemService.defaultChecks(smokeTester:locator:)` sırayı sabitler: `ShellCheck` → `PTYSmokeCheck` (yalnız smoke tester verilmişse) → her `AgentProvider` için `AgentCLICheck` |
| `PathEnvironmentFixer` | `fixProcessPath()` |
| `ExternalURLOpener` | http/https whitelist'i + açma closure'ı (test edilebilir) |
| `FileSystemOperations` | `trash` / `revealInFinder` — **path guard'lı** (`RepoPathGuard.isInside(anyOf:path:)`, izinli kökler async okunur; 02'nin eski sapması kapandı) |
| `FolderChooser` | `NSOpenPanel` (MainActor) |

- **`SystemCheckResult.fixURL`:** "Fix" aksiyonunun açacağı kurulum sayfasını **kontrolün kendisi** üretir (`AgentCLICheck.setupURL`). `fix(checkID:)` metodu ve `AppDelegate`'teki checkID→URL `switch`'i kaldırıldı (refactor 3.6). `isFixable == true` olduğu hâlde `fixURL == nil` olabilir (düzeltme yolu bir bağlantı değilse).
- Check içerikleri: shell zinciri, PTY smoke testi (`PTYSmokeTester`, `TerminalSmokeTesting` dikişiyle enjekte edilir — `SystemService` LumiTerminal'i import edemez), `claude`/`codex` varlığı (`which` 5 sn timeout + `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin` fallback'leri `SystemBinaryLocator`'da; seçili provider fail+fixable, diğeri warn). Electron'a özgü `spawn-helper`/`conpty` check'leri düşer.
- **`fixProcessPath` birebir + async:** `$SHELL -ilc 'echo -n "$PATH"'` (5 sn timeout, sessiz fail) + bilinen dizinler (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/{bin,sbin}`, `~/.nvm/current/bin`, `~/.volta/bin`); Set dedup; startup'ta bir kez, **her spawn'dan önce** ([00 §3 bootstrap](./00-architecture.md)).

### 8.1 ProcessRunning / BinaryLocating (tüm process I/O'nun sınırı)

```swift
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String], currentDirectory: String?,
             standardInput: Data?, timeout: TimeInterval) async -> ProcessOutput?
    /// Binary-güvenli varyant: stdout UTF8'e çevrilmeden `Data` döner (görsel blob'ları, karar 21).
    func runRaw(...) async -> RawProcessOutput?
}

public protocol BinaryLocating: Sendable {
    func locate(_ name: String, timeout: TimeInterval) async -> String?   // default timeout 5 sn
}
```

- **Sessiz-fail sözleşmesi:** timeout, başlatma hatası veya iptal `nil` döndürür — fırlatmaz; çağıran servis bunu kendi hata sözleşmesine map'ler.
- Refactor 3.1: eskiden static bir `ProcessRunner` enum'una (artık yok) giden 7 çağıran vardı; artık her servis `init(runner:locator:)` ile ikame alabilir (`FakeProcessRunner`, `FakeBinaryLocator`) — git/claude/codex binary'si olmayan ortamda da birim testi yazılır.
- `SystemProcessRunner` düzeltmeleri (Faz 1.11): timeout/launch-failure yolunda `DispatchGroup` `leave`'leri tamamlandı (process + fd sızıntısı), `withTaskCancellationHandler` ile iptalde `terminate()`. Stdout/stderr `readabilityHandler` ile paralel okunur (klasik `NSTask` deadlock'una karşı).

### 8.2 SyntaxHighlighting (FileViewer dikişi)

```swift
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString
}
```

Refactor 7.5'te tek implementasyon `HighlightrEngine` LumiUI'dan **LumiServices**'e taşındı: view modülü artık ne Highlightr paketini (JSCore) ne de arka plan kuyruğunu tanır. Görsel parametreler `HighlightrStyle` ile composition root'tan enjekte edilir (tema adı, düz metin rengi, punto→font closure'ı) — motor `Theme`/`LumiFonts`'u göremez (katman kuralı). `plainTextCutoffBytes` (1 MB) üstünde düz metne düşülür. Highlightr yetersiz kalırsa view'a dokunmadan başka bir motora geçilebilir.

---

## 9. Hata sözleşmesi: `LumiError` (karar 5)

Tek app-geneli enum, `LumiKit/Errors/`'da; her servis iç hatayı (Process, FileManager, parse, HTTP) kendi sınırında map'ler — servis dışına başka hata çıkmaz:

```swift
public enum LumiError: Error, LocalizedError, Sendable, Equatable {
    case spawnFailed(reason: String)
    case terminalNotFound(TerminalID)
    case gitFailed(operation: String, detail: String)
    case pathOutsideRepo(path: String)         // traversal guard, TÜM path'lerde (symlink-canonical)
    case fileOperationFailed(path: String, detail: String)
    case configIOFailed(file: String, detail: String)
    case externalURLBlocked(URL)               // sessiz yutuluyordu — artık görünür
    case systemCheckFailed(check: String, detail: String)
    case cliNotFound(binary: String)           // claude/codex PATH'te yok
    case usageUnavailable(detail: String)      // kullanım verisi alınamadı (05)
    case sessionStartFailed(detail: String)    // zamanlanmış oturum başlatılamadı
    case underlying(domain: String, message: String)   // kaçış kapısı; yine tipli ve sunulabilir
}
```

Tek enum tercihinin gerekçesi: karar 5 *tek* sözleşme ister; toast sunucusunda exhaustive switch, dedupe için bedava `Equatable`, protokol-existential törensizliği. Domain sayısı sabit ve küçük. Her case'in `errorDescription`'ı kullanıcıya dönük İngilizce tek cümledir.

**Silinen case'ler (Faz 1.22, ölü kod):** `yamlInvalid` (persona/YAML karar 25'te düştü), `actionStepTimedOut` (Quick Action'lar karar 25'te düştü), `notificationPermissionDenied` (izin reddi bir hata değil, sessiz bir durumdur — bildirim gönderilmez).

**Tek tip yüzeye çıkış:** store'lar her intent'i `ToastStore.reporting {}` yardımcısıyla sarar ([03 §4](./03-ui-shell.md)) — kullanıcıyı etkileyen her hata tek koridordan toast kuyruğuna düşer; hiçbir hata yalnız console'a gitmez. İstisnalar bilinçlidir ve burada yazılıdır: `GitReading`'in sessiz-boş sözleşmesi, `RepoServicing`'in var-olmayan-kök toleransı, kullanım göstergesinin popover içi hata satırı ([05 §6.1](./05-usage-indicator.md)).

---

## 10. Yeni servis ekleme kontrol listesi

Bir özelliğe servis eklerken sırayla:

1. **Protokolü `LumiKit/Protocols/` altına yaz.** Modeller `LumiKit/Models/` altına; hiçbir şey `LumiServices`'te public olmaz ki store/UI somut tipi göremesin.
2. **İzolasyonu §11'e göre seç** ve protokole yaz (`@MainActor` / `Actor` / `Sendable`).
3. **Hata sözleşmesini seç ve protokol yorumunda belirt:** *sessiz-boş* (liste/keşif operasyonları, rutin başarısızlık) veya *fırlatan* (`LumiError`, kullanıcının açık isteği). İkisini aynı protokolde karıştırma — `GitReading`/`GitContentReading` ayrımı tam olarak bu yüzden var.
4. **ISP uygula:** farklı tüketiciler farklı yüzler kullanacaksa protokolü baştan böl ve gerekiyorsa `typealias` ile birleştir (`GitServicing`, `TerminalServicing`). Fake'lerin boyutu ölçüdür: fake'te boş bırakılan metod varsa yüzey çok geniştir.
5. **Tüm process I/O `ProcessRunning`, binary çözümü `BinaryLocating` üzerinden geçsin**; `init(runner:locator:)` ile enjekte edilebilir olsun. Doğrudan `Process()` kurmak yalnız `SystemProcessRunner` ve `CodexAppServerProbe` gibi pipe yaşam döngüsünü kendi yöneten özel durumlarda kabul edilir ve gerekçesi dosyada yazılır.
6. **Repo/dosya path'i alan her metod `RepoPathGuard`'dan geçsin** (karar 11) — istisnasız.
7. **Push varsa `EventBroadcaster<Event>` + `nonisolated func events()`**; payload'sız "changed" sinyali + store'un pull'u tercih edilir. Tüketici tarafta `EventConsumer` kullan (stream Task'tan ÖNCE alınır).
8. **Yaşam döngüsü varsa `StoreLifecycle`** (`start()` idempotent, `stop()` eşzamanlı) ve kapanışta `shutdown()` simetrisi.
9. **Fake'i `Tests/LumiTestSupport`'a yaz** (ürün target'ına değil); en az bir "hata yolu" senaryosu taşısın.
10. **`ServiceRegistry`'ye bir üye + `LiveServiceRegistry`'ye bir satır ekle.** Cache/retry/log gibi çapraz kesen davranışlar servise gömülmez, **dekoratörle** sarılır (`CachingUsageService(wrapping:ttl:)` deseni) ve dekoratörün yeteneği ayrı bir protokolle duyurulur (`UsageCacheInvalidating`).
11. **Feature assembly'sini yaz** (`build → start → configDidChange → shutdown`) ve `AppComposition.live` listesine ekle; config alanı varsa diff'i assembly'nin içinde, eşitlikle yap ([00 §3](./00-architecture.md)).

## 11. İzolasyon seçim kuralı

| Servis şekli | İzolasyon | Örnek |
|---|---|---|
| UI-yüzlü; store'la senkron konuşuyor, `NSView`/`NSEvent` gibi AppKit tiplerine dokunuyor | **`@MainActor` protokol** | `TerminalSessionControlling`, `TerminalAppearanceControlling`, `TerminalViewProviding`, `NotificationServicing`, `SyntaxHighlighting` |
| Dosya/process/ağ I/O ağırlıklı **ve** çağrılar arası durum tutuyor (cache, watcher tablosu, debounce task'ı) | **`actor`** | `ConfigService`, `RepoService`, `ClaudeUsageService`, `CodexUsageService`, `CachingUsageService`, `SessionStarterService` |
| Durumsuz; her çağrı bağımsız | **`Sendable` struct/final class** | `GitService`, `SystemService`, `SystemProcessRunner`, `SystemBinaryLocator`, `RepoPathGuard`, `GitCommandRunner` |
| Saf hesap/parse (I/O yok) | **`enum` + `static` fonksiyonlar** | `GitPorcelainParser`, `UsageOutputParser`, `ClaudeUsageAPIParser`, `CodexUsageParser`, `JSONValue`, `TerminalGridFit` |

Kurallar:

- **İzolasyon protokolde ilan edilir, implementasyonda keşfedilmez.** `@MainActor` bir protokol gereksinimi değilse çağıran taraf onu varsayamaz.
- **Actor içindeki uzun senkron iş actor'ı kilitler.** Devasa dizin taraması gibi işler `Task.detached(priority:)` ile actor'ın dışına çıkarılır (`RepoService.fileTree`, karar 28).
- **`events()` her zaman `nonisolated`** — actor hop'u boot penceresinde event kaybettirir (refactor 5.6).
- **`@MainActor` bir servis PTY/dosya I/O yapmaz;** implementasyonun içindeki io queue'ları protokol sızdırmaz (`TerminalSessionManager` MainActor'dır, `PTYProcess` kendi `DispatchSource`'unda koşar).
- **Kilit (`NSLock`) yalnız iki farklı yürütme bağlamının (io queue + MainActor) aynı alanı gördüğü yerlerde** kullanılır ve `@unchecked Sendable` gerekçesi dosyada yazılır (`EventBroadcaster`, `FeedWatchdog`, `AdaptiveBatchBudget`, `PTYProcess`).
