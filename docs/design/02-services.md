# Lumi Native — Servis Katmanı Tasarımı

> `LumiKit` protokolleri + `LumiServices`/`LumiTerminal` implementasyon sözleşmeleri. Davranış kaynağı: [spec/11](../spec/11-ipc-surface.md), [spec/12](../spec/12-git-vcs.md), [spec/13](../spec/13-main-services.md). IPC kanal haritası iç API sözleşmesi olarak kullanılır ([spec/00 §5](../spec/00-overview.md)).

Genel kurallar:
- Tüm protokoller `LumiKit`'te; metodlar yalnız `LumiError` fırlatır; tüm event payload'ları `Sendable`.
- **İzolasyon:** UI-yüzlü ve store'larla senkron konuşan `TerminalServicing` (+ `TerminalViewProviding`) `@MainActor` protokoldür — PTY I/O implementasyonun içindeki io queue'lardadır, protokol bu detayı sızdırmaz (Faz 1'de netleşti). Dosya/process-I/O ağırlıklı diğer servisler `Actor` + `async throws` kalır.
- **Servis→store event'leri `AsyncStream<Event>`** — `EventBroadcaster<Event>` yardımıyla (continuation registry; her `events()` çağrısı taze stream döner). Her domain'in tek tüketicisi kendi store'udur; UI servislere asla doğrudan abone olmaz.
- Push'ların çoğu **pull-after-push** kalır: payload'sız "changed" sinyali → store tüm listeyi yeniden çeker (Electron paritesi, basitlik).

---

## 1. 62 IPC kanalının eşlemesi

| Electron kanalı | Native karşılığı |
|---|---|
| `terminal:spawn / write / kill / resize / focus` | `TerminalServicing.spawn / write / kill / resize / setFocused` |
| `terminal:snapshot` | Silindi — tek process'te reconciliation yok; `TerminalServicing.list()` yalnız metadata döner |
| `terminal:get-status` | Ölü kanal — taşınmaz |
| `terminal:output` (push) | **Event değil** — ham çıktı PTY→emülatör hattında `LumiTerminal` içinde akar ([01 §3](./01-terminal-subsystem.md)); state katmanına asla çıkmaz |
| `terminal:exit / status / title / bell` (push) | `TerminalEvent.exited / statusChanged / titleChanged / bell` |
| `terminal:sync` (push) | Silindi — uyanmada resync gereksiz (state hiç kopmaz); `NSWorkspace.didWakeNotification` yalnız watcher tazelemesi tetikler |
| `repos:list` | `RepoServicing.repos()` |
| `repos:files` | Ölü legacy — taşınmaz |
| `repos:file-tree / watch-file-tree / unwatch-file-tree` | `RepoServicing.fileTree / watch / unwatch` |
| `repos:changed`, `file-tree:changed` (push) | `RepoEvent.reposChanged / fileTreeChanged(repoPath)` |
| `git:commits / branches / status / commit / read-file / file-diff` | `GitServicing` aynı adlı metodlar |
| `git:commit-diff` | **İkiye bölündü** (karar 6): `commitFiles(sha)` (yalnız liste) + `commitFileDiff(sha, file)` (lazy) |
| `context:delete-file / reveal-in-file-manager` | `SystemServicing.trash / revealInFinder` |
| `config:is-first-run / get / set` | `ConfigServicing.isFirstRun / config / update` |
| `ui-state:get / set` | `ConfigServicing.uiState / updateUIState` |
| `window:toggle-maximize / minimize / close / set-traffic-light-visibility` | IPC'siz — `MainWindowController` iç metodları (custom titlebar butonları native'de yok; traffic-light gizleme focus-mode akışında, [03 §2](./03-ui-shell.md)) |
| `dialog:open-folder` | `SystemServicing.chooseFolder()` |
| `actions:list / execute / delete / history / restore / create-new / edit` | `ActionServicing` aynı adlı metodlar |
| `actions:load-project / default-ids` | `actions(projectPath:)` parametresiyle ve `Action.isDefault` alanıyla emilir |
| `actions:changed` (push) | `ActionServicing.events()` (Void) |
| `personas:list / load-project / spawn` | `PersonaServicing.personas(projectPath:) / spawn` |
| `personas:changed` (push) | `PersonaServicing.events()` (Void) |
| `system:check-run / check-fix` | `SystemServicing.runChecks / fix` |
| `shell:open-external` | `SystemServicing.openExternal` (http/https whitelist **korunur**; ihlal → görünür hata) |
| `app:confirm-quit` / `app:quit-confirmed` | IPC'siz — `applicationShouldTerminate` → `.terminateLater` akışı ([03 §2](./03-ui-shell.md)) |
| `notification:click` (push) | `NotificationEvent.clicked(TerminalID)` |
| `collection:get` | Ölü — taşınmaz (karar 1) |

---

## 2. ConfigServicing

```swift
public protocol ConfigServicing: Actor, Sendable {
    func config() async -> AppConfig
    func update(_ mutate: @Sendable (inout AppConfig) -> Void) async throws
    func uiState() async -> UIState
    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async
    func isFirstRun() async -> Bool
    func events() -> AsyncStream<ConfigEvent>   // .configChanged(old: AppConfig, new: AppConfig)
}
```

- **Persistence paritesi (karar 9, bağlayıcı):** `~/.lumi/config.json` ve `ui-state.json` mevcut şemayla, 2-space-indent pretty JSON olarak okunur/yazılır. Dev modda `~/.lumi-dev`; production'da yeni dizin yoksa legacy `~/.pulpo` → `~/.ai-orchestrator` fallback'i (migration değil, yerinde kullanım). Tümü `LumiPaths`'te. **Format-parite golden testleri zorunlu**: gerçek Electron çıktısı fixture'larına karşı byte-uyumlu round-trip.
- Defaults infill, `additionalPaths` array coercion'ı, `aiProvider` doğrulaması (`claude|codex`, default claude) birebir. Dosya yok/parse hatası → log + defaults; yazma hatası → throw.
- `updateUIState` in-memory state'e anında uygular, **500ms debounce'lu atomik yazım** planlar.
- `isFirstRun()` = config.json yok VEYA `projectsRoot` boş.

**Yan etki propagasyonu — `ConfigSideEffectCoordinator` (app target):** `ConfigEvent.configChanged(old:new:)` tüketir, alanları **eşitlikle** karşılaştırır (Electron'un truthiness bug'ı yapısal olarak imkânsız — `0`/boş string de propagate olur, karar 11):
- `maxTerminals` değişti → `terminal.setMaxTerminals(n)`
- `projectsRoot`/`additionalPaths` değişti → `repo.setRoots(...)` (→ `reposChanged` yayını)
- `notifications` değişti → `notifications.updateSettings(s)`

Settings anlık-uygulama modeli (karar 3) bu koordinatörle çalışır: her kontrol değişikliği `config.update {}` → diff → anında yan etki.

---

## 3. RepoServicing

```swift
public protocol RepoServicing: Actor, Sendable {
    func repos() async throws -> [Repo]
    func fileTree(repoPath: String) async throws -> FileNode
    func watch(repoPath: String) async
    func unwatch(repoPath: String) async
    func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) async
    func events() -> AsyncStream<RepoEvent>   // .reposChanged, .fileTreeChanged(repoPath)
}
```

- **Keşif paritesi ([spec/12](../spec/12-git-vcs.md)):** `projectsRoot` + `additionalPaths(root|repo)`; root'lar non-recursive ilk seviye taraması; `.`-prefix ve dizin-olmayan atlanır; `<dir>/.git` (dosya veya dizin) → `isGitRepo`; git-olmayan dizinler de listelenir; mutlak-path dedup, ilk kazanır; var olmayan path sessiz atlanır.
- **File tree:** Hardcoded exclude listesi (git-olmayan dizinler için **korunur**); ignored bayrakları **`git check-ignore`** ile (karar 7 — nested/global/`info/exclude` dahil, bilinçli sapma); `.git` daima gizli; ignored klasöre inilmez; sıralama: klasör→dosya, ignored sona, `localeCompare`. Path'ler repo-köküne göre `/` ayraçlı.
- **Watcher:** Root'lar non-recursive **300ms** debounce; aktif repo recursive **500ms** debounce; FSEvents/DispatchSource; `.git` event fırtınalarına coalescing zorunlu. "Olay → tam reload" stratejisi korunur. Polling yok (parite).

---

## 4. GitServicing

```swift
public protocol GitServicing: Sendable {          // stateless; git CLI + porcelain parse
    func commits(repoPath: String, branch: String?) async throws -> [GitCommit]
    func branches(repoPath: String) async throws -> GitBranches
    func status(repoPath: String) async throws -> [GitStatusEntry]
    func commit(repoPath: String, message: String, files: [String]) async throws
    func readFile(repoPath: String, file: String) async throws -> String
    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff
    func commitFiles(repoPath: String, sha: String) async throws -> [CommitFile]      // karar 6: yalnız liste
    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff  // lazy
}
```

- simple-git yerine **`git` CLI + porcelain parse** ([spec/00 §5](../spec/00-overview.md) önerisi). Async `Process`, timeout'lu.
- **Commit log semantiği birebir:** default branch `main → master → nil`; `--max-count=50`; branch verilmişse ve default'tan farklıysa **`defaultBranch..branch`** aralığı; hata → boş array + log (görünür hataya çevrilmez — panel-boş davranış paritesi).
- **Status sadeleşmesi korunur:** staged/unstaged ayrımı yok; `modified|added|deleted|renamed|untracked`; rename'de `to` path.
- **Path-traversal guard'ı TÜM path alan metodlarda** (karar 11 — Electron'da yalnız `readFile` korumalıydı): repo köküne canonical-path kontrolü; ihlal → `LumiError.pathOutsideRepo`.
- `fileDiff`/`commitFileDiff` çıktısı tiplenmiş `UnifiedDiff` modelidir (hunk'lar; FileViewer doğrudan render eder — [03 §6](./03-ui-shell.md)).

---

## 5. PersonaServicing

```swift
public protocol PersonaServicing: Actor, Sendable {
    func personas(projectPath: String?) async throws -> [Persona]   // project, user'ı id ile EZER (gizler)
    func spawn(personaID: String, repoPath: String) async throws -> TerminalMeta
    func events() -> AsyncStream<Void>                              // personasChanged
}
```

- **Seed: her startup'ta default'lar EZİLİR** (`Bundle.module/default-personas/` → `~/.lumi/personas/`) — asimetrinin persona tarafı, birebir parite.
- YAML şema paritesi: `id`, `label` zorunlu; `provider`, `claude{systemPrompt, appendSystemPrompt, model, allowedTools[], disallowedTools[], tools, permissionMode, maxTurns}`, `codex{model?}`.
- User + project (`<repo>/.lumi/personas/`) dizinleri izlenir; değişiklik → tam reload → changed yayını.
- `spawn`: yeni terminal + `task = persona.label`; provider = `persona.provider ?? config.aiProvider`; komut `AgentCommandBuilder` üzerinden enjekte edilir.

---

## 6. ActionServicing (store + engine)

```swift
public protocol ActionServicing: Actor, Sendable {
    func actions(projectPath: String?) async throws -> [Action]     // Action.isDefault dahil
    func execute(actionID: String, repoPath: String) async throws -> TerminalMeta
    func delete(actionID: String, scope: ActionScope, projectPath: String?) async throws
    func history(actionID: String) async throws -> [ActionVersion]
    func restore(actionID: String, version: String) async throws
    func createNew(repoPath: String) async throws -> TerminalMeta   // AI destekli
    func edit(actionID: String, scope: ActionScope, projectPath: String?) async throws -> TerminalMeta
    func events() -> AsyncStream<Void>                              // actionsChanged
}
```

**Store paritesi:**
- **Seed asimetrisi birebir:** hedef dosyada `modified_at` varsa default ezilmez (kullanıcı düzenlemesi korunur, id default işaretli kalır); parse-bozuk dosya ezilir; deprecated default'lar user dizininden silinir. **`create-project` default sete konmaz** (karar 12).
- Versiyonlama: değişiklikte `.history/<id>/<iso-ts>.yaml` backup (`:` → `-`, ms kırpılır), **max 20**, en eski silinir; default dosya silinirse anında yeniden seed. Silme, dosya adına değil **id alanına** dizin taramasıyla.
- User + project dizin watcher'ları; her durumda tam reload + changed.

**Engine paritesi + onaylı düzeltmeler:**
- `execute` daima **yeni** terminal açar; limit doluysa `LumiError.terminalLimitReached` **fırlatır** (sessiz `null` taşınmaz — karar 5/11).
- Step'ler sıralı: `write{content}` (\r-sonlu; `AgentCommandBuilder` dönüşümünden geçer) / `wait_for{pattern, timeout=10sn}` / `delay{ms}`.
- **`wait_for` rolling buffer:** terminalin output stream'inden ([01 §3](./01-terminal-subsystem.md)) beslenen **4 KB rolling ring** üzerinde regex — tek-chunk eşleşme zorunluluğu bug'ı düzeltilir, 10 sn timeout semantiği korunur (karar 11). Timeout → `LumiError.actionStepTimedOut`.

**`AgentCommandBuilder` (`buildAgentCommand` portu):**
- Claude: içerik `claude ` ile başlıyorsa flag enjeksiyonu (`--system-prompt-file` / `--append-system-prompt-file` temp dosyaları, `--model`, `--allowedTools "A" "B"`, `--disallowedTools`, `--tools`, `--permission-mode`, `--max-turns`) + ` -- ` ayracı. **Temp system-prompt dosyaları izlenir ve uygulama çıkışında + oturum kapanışında silinir** (hiç-temizlenmeme bug'ı taşınmaz — karar 11); adlandırma çakışmasız (UUID).
- Codex: `codex` ile başlıyorsa ve config'de model varsa ve `--model` yoksa enjekte.
- Eşleşmeyen içerik (örn. `git pull\r`) değişmeden geçer.
- AI create/edit akışları: ephemeral `__create-action`/`__edit-action`; claude'da prompt `appendSystemPrompt` flag'iyle, codex'te **çağrı başına rastgele UUID delimiter'lı heredoc** (prompt-injection guard'ı birebir). Edit prompt'u AI'ya `modified_at` güncelletir.

---

## 7. NotificationServicing

```swift
public protocol NotificationServicing: Actor, Sendable {
    func requestPermissionIfNeeded() async        // YENİ gereksinim: UNUserNotificationCenter izin akışı
    func notifyStatusChange(id: TerminalID, repoName: String,
                            old: TerminalStatus, new: TerminalStatus) async
    func updateSettings(_ s: NotificationSettings) async
    func terminalRemoved(_ id: TerminalID) async  // cleanup sözleşmesi: interval timer'ları iptal
    func events() -> AsyncStream<NotificationEvent>   // .clicked(TerminalID), .bell(TerminalID, repoName)
}
```

- Status-makinesi-güdümlü tablo birebir: `waiting-unseen` → anında bildirim + `unseenIntervalMinutes` (default 1 dk) tekrar; `waiting-seen` → yalnız `seenIntervalMinutes` (default 5 dk) tekrar; `error` → tek seferlik; `working/idle/waiting-focused` → temizle. Terminal başına en fazla bir interval.
- **Focus guard:** native OS bildirimi yalnız pencere odaklı değilken; `bell` toast event'i her durumda.
- Bildirim tıklaması → `.clicked(id)` → store terminale odaklanır (**minimize istisnası**: minimize edilmiş terminalin otomatik odak alabildiği tek yol).
- `terminalRemoved` exit-cleanup sırasının 3. adımıdır ([01 §6](./01-terminal-subsystem.md)); interval sızıntısı testi zorunlu.

---

## 8. SystemServicing

```swift
public protocol SystemServicing: Sendable {
    func runChecks() async -> [SystemCheckResult]
    func fix(checkID: String) async -> SystemCheckResult
    func fixProcessPath() async
    func openExternal(_ url: URL) throws          // http/https whitelist; ihlal → .externalURLBlocked
    func trash(path: String) async throws         // FileManager.trashItem; path-guard'lı
    func revealInFinder(path: String)             // NSWorkspace.activateFileViewerSelecting; path-guard'lı
    func chooseFolder() async -> String?          // NSOpenPanel (içeride MainActor sıçraması)
}
```

- **Check'ler async koşar** (senkron SystemChecker taşınmaz — karar 11): shell zinciri, PTY smoke testi (`PTYProcess` spawn+kill), `claude-cli`/`codex-cli` varlığı (`which` 5 sn timeout + `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin` fallback; seçili provider fail+fixable, diğeri warn). Electron'a özgü `spawn-helper`/`conpty` check'leri düşer.
- **`fixProcessPath` birebir + async:** `$SHELL -ilc 'echo -n "$PATH"'` (5 sn timeout, sessiz fail) + bilinen dizinler (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/{bin,sbin}`, `~/.nvm/current/bin`, `~/.volta/bin`); Set dedup; startup'ta bir kez, **her spawn'dan önce** ([00 §3 bootstrap](./00-architecture.md)).

---

## 9. Hata sözleşmesi: `LumiError` (karar 5)

Tek app-geneli enum, `LumiKit`'te; her servis iç hatayı (Process, FileManager, parse) kendi sınırında map'ler — servis dışına başka hata çıkmaz:

```swift
public enum LumiError: Error, LocalizedError, Sendable, Equatable {
    case terminalLimitReached(max: Int)        // sessiz null'dı — artık görünür
    case spawnFailed(reason: String)
    case terminalNotFound(TerminalID)
    case gitFailed(operation: String, detail: String)
    case pathOutsideRepo(path: String)         // traversal guard, TÜM path'lerde
    case fileOperationFailed(path: String, detail: String)
    case configIOFailed(file: String, detail: String)
    case yamlInvalid(file: String, detail: String)
    case actionStepTimedOut(actionID: String, step: Int)
    case externalURLBlocked(URL)               // sessiz yutuluyordu — artık görünür
    case systemCheckFailed(check: String, detail: String)
    case notificationPermissionDenied
    case underlying(domain: String, message: String)   // kaçış kapısı; yine tipli ve sunulabilir
}
```

Tek enum tercihinin gerekçesi: karar 5 *tek* sözleşme ister; toast sunucusunda exhaustive switch, dedupe için bedava `Equatable`, protokol-existential törensizliği. Domain sayısı sabit ve küçük.

**Tek tip yüzeye çıkış:** store'lar her intent'i `ToastStore.reporting {}` yardımcısıyla sarar ([03 §4](./03-ui-shell.md)) — kullanıcıyı etkileyen her hata tek koridordan toast kuyruğuna düşer; hiçbir hata yalnız console'a gitmez.
