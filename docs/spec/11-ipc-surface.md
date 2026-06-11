# IPC Yüzeyi (src/main/ipc, src/preload, src/shared)

> Bu doküman Lumi'nin Electron IPC katmanının eksiksiz davranış envanteridir. Native (Swift) rewrite'ta bu harita, UI katmanı ile servis katmanı arasındaki **iç API sözleşmesine** dönüşecektir. Electron'da "kanal" olan her şey, native tarafta bir servis metodu (invoke), bir delegate/Combine publisher (push) veya bir notification (send) olur.

## Amaç ve sorumluluk

- **`src/shared/ipc-channels.ts`**: Tüm kanal adlarının tek kaynağı (`domain:operation` adlandırması). Hardcoded string yasak; her yeni kanal önce buraya eklenir.
- **`src/main/ipc/handlers.ts`**: Main process'te tüm servislerin (manager/store/engine) kurulduğu composition root. Servisleri yaratır, change callback'lerini renderer push'larına bağlar, typed `IpcHandlerContext` oluşturur ve domain bazlı 5 registration modülüne dağıtır.
- **`src/main/ipc/handlers/*`**: Domain bazlı ince handler modülleri. Kural: handler'lar yalnızca validation + orchestration yapar; iş mantığı domain servislerindedir (TerminalManager, RepoManager, ConfigManager, ActionStore/Engine, PersonaStore, SystemChecker, NotificationManager).
- **`src/preload/`**: `contextBridge` ile renderer'a `window.api` objesini açan güvenli köprü. `nodeIntegration: false`, `contextIsolation: true`. Her kanalın preload'da explicit bir mapping'i vardır.
- **`src/shared/`**: Main ve renderer'ın ortak kullandığı tipler, sabitler ve saf yardımcı fonksiyonlar (test edilebilir, Electron bağımsız).

## Composition root davranışı (`setupIpcHandlers`)

Sıralı kurulum:
1. `ConfigManager` yaratılır, config okunur.
2. `NotificationManager` yaratılır, `config.notifications` ile beslenir.
3. `TerminalManager(config.maxTerminals, notificationManager, configManager)` yaratılır.
4. `RepoManager(config.projectsRoot, config.additionalPaths || [])` yaratılır.
5. `ActionStore`, `ActionEngine(terminalManager)`, `PersonaStore` yaratılır.
6. `SystemChecker`, aktif provider'ı lazily okuyan bir closure alır (`getActiveProvider`).
7. Change callback'leri bağlanır (hepsi `safeSend` üzerinden renderer'a push):
   - ActionStore değişti → `actions:changed`
   - PersonaStore değişti → `personas:changed`
   - RepoManager repo listesi değişti → `repos:changed`
   - RepoManager file tree değişti → `file-tree:changed` (payload: `repoPath`)
8. `repoManager.watchProjectsRoot()` başlatılır (fs watcher).
9. 5 registration modülü çağrılır.

`getActiveProvider`: `config.aiProvider === 'codex'` ise `'codex'`, aksi halde her durumda `'claude'` (bilinmeyen değerler claude'a düşer).

Modül seviyesinde mutable referanslar: `mainWindow`, `terminalManager`, `repoManager`, `actionEngine`. `setMainWindow(window)` çağrısı pencereyi set eder ve `actionEngine.setWindow(window)`'u günceller. `getTerminalManager()` / `getRepoManager()` accessor'ları `index.ts`'in quit akışında kullanılır.

## EKSİKSİZ IPC KANAL HARİTASI

Toplam 62 kanal: 46 invoke (renderer→main, request/response), 1 send (renderer→main, fire-and-forget), 14 push (main→renderer) ve 1 ölü kanal. (46 invoke'tan ikisi — `terminal:get-status` ve `repos:files` — kayıtlı ama çağıransızdır; bkz. K.)

### A) Terminal — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `terminal:spawn` | `(repoPath: string, task?: string)` | `SpawnResult \| null` | Main window yoksa `Error('No main window')` fırlatır. `terminalManager.spawn(repoPath, window)` çağırır; sonuç varsa ve `task` verilmişse `setTask(id, task)`. Max terminal limitine ulaşıldıysa `null` döner. |
| `terminal:write` | `(terminalId: string, data: string)` | `boolean` | PTY stdin'e yazar; terminal yoksa `false`. |
| `terminal:kill` | `(terminalId: string)` | `boolean` | PTY'yi öldürür; terminal yoksa `false`. |
| `terminal:resize` | `(terminalId: string, cols: number, rows: number)` | `boolean` | PTY resize. |
| `terminal:snapshot` | `()` | `TerminalSnapshot[]` | **Tek pull/reconciliation API'si.** Tüm terminallerin meta + birikmiş output buffer'ını döner. Renderer state'ini main ile senkronlamanın tek yolu. |
| `terminal:get-status` | `(terminalId: string)` | `string \| null` | Tek terminalin `TerminalStatus` değeri. **Ölü API:** handler'ı ve preload mapping'i (`getTerminalStatus`) mevcut ama renderer'da hiçbir çağıranı yok — status zaten `terminal:status` push + `terminal:snapshot` ile akıyor. `repos:files` / `collection:get` gibi taşınmayacak ölü kapsam (bkz. K). |
| `terminal:focus` | `(terminalId: string \| null)` | `void` | Hangi terminalin UI'da odakta olduğunu main'e bildirir (`null` = hiçbiri). Notification ve `waiting-*` status geçişleri için kritik. |

### B) Repository — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `repos:list` | `()` | `Repository[]` | `projectsRoot` + `additionalPaths` altındaki repoları keşfeder. |
| `repos:files` | `(repoPath: string)` | `string[]` | Repo içindeki dosya yolları (düz liste). **Ölü API:** çağıranı yok (bkz. K). |
| `repos:file-tree` | `(repoPath: string)` | `FileTreeNode[]` | Hiyerarşik ağaç; gitignored öğeler `ignored: true` flag'i ile dahil. |
| `repos:watch-file-tree` | `(repoPath: string)` | `void` | Repo için fs watcher başlatır; değişiklikte `file-tree:changed` push edilir. |
| `repos:unwatch-file-tree` | `(repoPath: string)` | `void` | Watcher'ı kapatır. |

### C) Git — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `git:commits` | `(repoPath: string, branch?: string)` | `Commit[]` | Branch verilmezse current branch log'u. |
| `git:branches` | `(repoPath: string)` | `Branch[]` | `{ name, isCurrent }` listesi. |
| `git:status` | `(repoPath: string)` | `FileChange[]` | `{ path, status: 'modified'\|'added'\|'deleted'\|'renamed'\|'untracked' }`. |
| `git:commit` | `(repoPath: string, files: string[], message: string)` | `{ success: boolean; error?: string }` | Seçili dosyaları stage'leyip commit eder. Hata fırlatmak yerine result envelope döner. |
| `git:read-file` | `(repoPath: string, filePath: string)` | `string` | Working tree'den dosya içeriği (file viewer için). |
| `git:file-diff` | `(repoPath: string, filePath: string)` | `{ original: string; modified: string }` | HEAD vs working tree içerik çifti (diff UI iki tam içerikten render edilir, patch formatı değil). |
| `git:commit-diff` | `(repoPath: string, commitHash: string)` | `CommitDiffFile[]` | Commit'in dosya bazlı diff'i; her dosya için `{ path, status, original, modified }`. |

### D) Dosya context menu — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `context:delete-file` | `(repoPath: string, relativePath: string)` | `void` | `path.join(repoPath, relativePath)` → **çöpe taşır** (`shell.trashItem`), kalıcı silmez. |
| `context:reveal-in-file-manager` | `(repoPath, relativePath)` | `void` | Finder/Explorer'da gösterir (`shell.showItemInFolder`). |

### E) Config / UI State / Window / Dialog — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `config:is-first-run` | `()` | `boolean` | Config dosyası hiç yazılmamışsa `true` (onboarding tetikler). |
| `config:get` | `()` | `Config` | Tam config objesi. |
| `config:set` | `(partial: Partial<Config>)` | `true` | Config'i merge edip kaydeder + **yan etkileri propagate eder** (aşağıya bak). |
| `ui-state:get` | `()` | `UIState` | Persist edilmiş UI durumu. |
| `ui-state:set` | `(partial: Partial<UIState>)` | `true` | Merge + kaydet. |
| `window:toggle-maximize` | `()` | `void` | Maximized ise unmaximize, değilse maximize. |
| `window:minimize` | `()` | `void` | Pencereyi minimize eder. |
| `window:close` | `()` | `void` | `close` event'ini tetikler (quit-confirm akışına girer). |
| `window:set-traffic-light-visibility` | `(visible: boolean)` | `void` | **Sadece macOS**: traffic light butonlarını gizler/gösterir (focus mode için). Diğer platformlarda no-op. |
| `dialog:open-folder` | `()` | `string \| null` | Native klasör seçim dialogu. İptal veya boş seçimde `null`, aksi halde seçilen mutlak yol. |

**`config:set` yan etki kuralları** (native rewrite'ta birebir korunmalı):
- `maxTerminals` truthy ise → `terminalManager.setMaxTerminals(n)`
- `projectsRoot` truthy ise → `repoManager.setProjectsRoot(root)` + repos etkilendi
- `additionalPaths !== undefined` ise → `repoManager.setAdditionalPaths(paths)` + repos etkilendi (boş array geçerli güncelleme)
- `notifications` truthy ise → `notificationManager.updateSettings(s)`
- Repos etkilendiyse → renderer'a `repos:changed` push edilir.
- **Dikkat (mevcut davranış/bug):** kontroller truthiness ile yapılır; `maxTerminals: 0` veya `projectsRoot: ''` gönderilirse yan etki çalışmaz ama config dosyasına yazılır. Native'de explicit `!= nil` kontrolüne çevrilmeli.

### F) Action — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `actions:list` | `(repoPath?: string)` | `Action[]` | User-scope + (repoPath verilirse) project-scope action'lar. |
| `actions:execute` | `(actionId: string, repoPath: string)` | `SpawnResult \| null` | Action'ı store'dan bulur (yoksa `Error('Action not found: <id>')`), `provider` alanı boşsa aktif provider ile doldurur, `actionEngine.execute(action, repoPath)` çağırır. Başarılıysa terminal task'ı `action.label` yapılır. |
| `actions:delete` | `(actionId, scope: 'user'\|'project', repoPath?)` | `boolean` | Action dosyasını siler. |
| `actions:load-project` | `(repoPath: string)` | `void` | Projenin action'larını store'a yükler (proje sekmesi açılınca çağrılır). |
| `actions:history` | `(actionId: string)` | `string[]` | Action'ın versiyon timestamp'leri. |
| `actions:restore` | `(actionId, timestamp: string)` | `boolean` | Belirli versiyonu geri yükler. |
| `actions:default-ids` | `()` | `string[]` | Built-in (silinmemesi gereken) action id'leri. |
| `actions:create-new` | `(repoPath: string)` | `SpawnResult \| null` | **AI destekli action yaratma.** Ephemeral `__create-action` action'ı sentezler (aşağıda detay) ve execute eder. Task: `'Create Action'`. |
| `actions:edit` | `(actionId, scope: string, repoPath?)` | `SpawnResult \| null` | **Terminal-first action editleme.** Store'dan YAML içeriği ve dosya yolu okunur (bulunamazsa `Error` fırlatır), mevcut YAML'ı içeren edit prompt'u kurulur, ephemeral `__edit-action` execute edilir. `repoPath` yoksa cwd olarak `actionStore.getUserDir()` kullanılır. Task: `'Edit: <actionId>'`. |

**`actions:create-new` / `actions:edit` provider ayrımı:**
- **claude**: action'a `claude.appendSystemPrompt = <prompt>` konur; tek step `write` ile `claude "."\r` yazılır (sistem prompt'u CLI flag'iyle enjekte edilir, `buildAgentCommand` üzerinden).
- **codex**: prompt heredoc ile stdin'den verilir: `codex exec - <<'__AI_ORCH_<uuid_altçizgili>__'\n<prompt>\n<marker>\r`. **Marker her çağrıda random UUID'den üretilir** (prompt injection / delimiter çakışmasına karşı güvenlik önlemi — `buildDelimitedInputCommand` util'i). Prompt sonuna `The user request is ".". Create/Edit the action now.` eklenir.

### G) Persona — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `personas:list` | `(repoPath?: string)` | `Persona[]` | User + project scope personalar. |
| `personas:load-project` | `(repoPath: string)` | `void` | Proje personalarını yükler. |
| `personas:spawn` | `(personaId: string, repoPath: string)` | `SpawnResult \| null` | Window yoksa / persona bulunamazsa `Error`. Terminal spawn edilir (spawn `null` dönerse `null` döner), task = `persona.label`. Provider: `persona.provider ?? aktifProvider`. Base komut: codex → `codex\r`, claude → `claude ""\r`. `buildAgentCommand(base, { provider, claude, codex })` ile persona config'i (systemPrompt, model, allowedTools vb.) CLI flag'lerine çevrilir ve PTY'ye yazılır. |

### H) System / Shell — invoke kanalları

| Kanal | Payload | Dönüş | Handler davranışı |
|---|---|---|---|
| `system:check-run` | `()` | `SystemCheckResult[]` | Tüm ortam kontrollerini koşar (shell bulunabilirliği, provider binary'si, node-pty vb.). `SystemCheckResult = { id, label, status: 'pending'\|'running'\|'pass'\|'fail'\|'warn', message, fixable? }`. Binary aramada `which` başarısızsa fallback yollar denenir: `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin` (Electron'un kısıtlı PATH'i nedeniyle). |
| `system:check-fix` | `(checkId: string)` | `SystemCheckResult` | İlgili check'in fix fonksiyonunu koşar, güncel sonucu döner. |
| `shell:open-external` | `(url: string)` | `void` | **Validation:** sadece `http://` veya `https://` ile başlayan string'ler açılır; aksi halde sessizce yok sayılır. Default browser'da açar. |

### I) App lifecycle

| Kanal | Yön | Payload | Davranış |
|---|---|---|---|
| `app:confirm-quit` | main → renderer (push) | `(terminalCount: number)` | Pencere kapatılırken aktif terminal varsa (`terminalCount > 0` ve `isQuitting` false) `close` event'i `preventDefault` edilir ve renderer'a onay diyaloğu göstermesi için push edilir. Kapatmadan önce window bounds/maximized state UI state'e kaydedilir. |
| `app:quit-confirmed` | renderer → main (**send**, `ipcMain.on`) | `()` | Tek fire-and-forget kanal. `isQuitting = true`, tüm terminaller `killAll()`, `repoManager.dispose()`, `app.quit()`. Terminal yoksa close akışı doğrudan killAll + dispose yapar, onay sorulmaz. |

### J) Main → renderer push kanalları (event stream)

Hepsi `safeSend` üzerinden gönderilir (bkz. Electron'a özgü kısımlar).

| Kanal | Payload | Kaynak ve tetik |
|---|---|---|
| `terminal:output` | `(terminalId: string, data: string)` | TerminalManager — PTY'den gelen her ham data chunk'ı (ANSI escape dahil). Yüksek frekanslı stream. |
| `terminal:exit` | `(terminalId: string, exitCode: number)` | PTY process exit ettiğinde. |
| `terminal:status` | `(terminalId: string, status: string)` | Status state machine geçişlerinde (`TerminalStatus` değerleri). |
| `terminal:title` | `(terminalId: string, title: string)` | OSC title sequence parse edildiğinde (temizlenmiş başlık). |
| `terminal:bell` | `(terminalId: string, repoName: string)` | NotificationManager — bildirim koşulları oluştuğunda (in-app bell UI'ı için). |
| `notification:click` | `(terminalId: string)` | OS bildirimine tıklanınca; renderer ilgili terminale odaklanır. |
| `terminal:sync` | `()` | `powerMonitor.on('resume')` — macOS uyku/uyanma sonrası. Renderer bunu alınca `terminal:snapshot` ile tam reconciliation yapmalıdır. |
| `repos:changed` | `()` | Repo listesi değişti (projectsRoot fs watcher veya `config:set` yan etkisi). Renderer `repos:list`'i yeniden çağırır. |
| `file-tree:changed` | `(repoPath: string)` | Watch edilen reponun ağacı değişti; renderer o repo için `repos:file-tree`'yi yeniler. |
| `actions:changed` | `()` | ActionStore değişti (dosya yaratıldı/silindi/düzenlendi — AI editleme dahil). |
| `personas:changed` | `()` | PersonaStore değişti. |
| `window:fullscreen-changed` | `(isFullscreen: boolean)` | `enter-full-screen` / `leave-full-screen` window event'leri. Renderer body class toggle'ı yapar. |
| `app:confirm-quit` | `(terminalCount: number)` | (Yukarıda I bölümünde.) |
| `shortcut` | `(action: string)` | **`IPC_CHANNELS`'da YOK, hardcoded string** (bilinçli istisna). App menüsü accelerator'larından gelir. Değerler: `new-terminal`, `close-terminal`, `open-repo-selector`, `toggle-left-sidebar`, `toggle-right-sidebar`, `open-settings`, `toggle-focus-mode`. |

### K) Ölü / çağıransız kanallar

- `collection:get` (`COLLECTION_GET`): `ipc-channels.ts`'de tanımlı ama **hiçbir handler'ı ve preload mapping'i yok**. Native rewrite'a taşınmamalı.
- `terminal:get-status` (`TERMINAL_GET_STATUS`): tersi durum — handler'ı (`register-terminal-handlers.ts`) ve preload mapping'i (`getTerminalStatus`) mevcut ama **renderer'da hiçbir çağıranı yok**; status bilgisi fiilen `terminal:status` push'u ve `terminal:snapshot` üzerinden akar. Çağıransız ölü kapsam; native rewrite'a taşınmamalı.
- `repos:files` (`REPOS_FILES`): aynı şekilde handler + preload mapping (`getRepoFiles`) mevcut ama **çağıranı yok** — `repos:file-tree` tarafından geride bırakılmış legacy API. Taşınmamalı.

## Preload köprüsü davranışı

- `contextBridge.exposeInMainWorld('api', api)` ile renderer'a tek bir `window.api` objesi açılır; `ApiType = typeof api` export edilir (renderer tarafında tip güvenliği).
- `api.platform = process.platform` — renderer'ın platform'a göre UI kararı vermesi için (örn. traffic light boşluğu).
- **`invokeIpc<T>(channel, ...args)`**: `ipcRenderer.invoke` etrafında generic wrapper. Dönüş tipi caller'ın bildirdiği `T`'dir; runtime validation yoktur (native'de typed servis metodları bu sorunu kökten çözer).
- **`createIpcListener<T extends unknown[]>(channel, callback)`**: `ipcRenderer.on` ile listener ekler, `IpcRendererEvent`'i callback'ten gizler ve **cleanup fonksiyonu döner** (`removeListener`). Tüm `on*` API'leri bu pattern'i izler — React effect'lerinde unsubscribe için kritik. Native karşılığı: Combine `AnyCancellable` veya `removeObserver` token'ı.
- Renderer→main `send` sadece `confirmQuit()` için kullanılır.

## Veri akışı ve bağımlılıklar

```
renderer (window.api)
   │ invoke / send                    ▲ push (safeSend)
   ▼                                  │
preload (ipc-utils) ── ipcMain.handle/on ── handler modülleri
                                      │
        ┌──────────┬──────────┬───────┴────┬───────────┬────────────┐
  TerminalManager RepoManager ConfigManager ActionStore  PersonaStore
   (node-pty)     (simple-git, (config.json, ActionEngine SystemChecker
                   fs watcher)  ui-state.json)            NotificationManager
```

- **Dış process'ler:** node-pty üzerinden shell + `claude` / `codex` CLI'ları; `git` (simple-git aracılığıyla); `which` (SystemChecker).
- **Çapraz bağımlılıklar:** ActionEngine → TerminalManager (terminal spawn + step yazma). NotificationManager → OS bildirimleri + `notification:click`/`terminal:bell` push. TerminalManager → NotificationManager (status değişiminde) ve ConfigManager.
- **Tarih serileştirme kuralı:** Renderer-side `Terminal.createdAt: Date`; IPC payload'ları (`TerminalInfo`/`TerminalSnapshot`) ISO string kullanır. `Commit.date: Date` structured clone ile geçer. `Terminal.minimized` ve `isNew` **renderer-only** state'tir, IPC payload'larında yoktur; snapshot reconciliation sırasında renderer tarafında korunmalıdır.

## Shared tipler (servis katmanı modelleri)

- **`SpawnResult`**: `{ id: string; name: string; isNew: boolean }` — spawn/execute dönüşlerinin ortak tipi (`isNew`: terminal yeni mi yaratıldı, mevcut mu reuse edildi).
- **`TerminalStatus`**: `'idle' | 'working' | 'waiting-unseen' | 'waiting-focused' | 'waiting-seen' | 'error'` — provider-agnostic tek doğruluk kaynağı.
- **`TerminalInfo`**: `{ id, name, repoPath, createdAt: string(ISO), task?, oscTitle?, status }`; **`TerminalSnapshot`** = `TerminalInfo + { output: string }`.
- **`Repository`**: `{ name, path, isGitRepo, source }`. **`AdditionalPath`**: `{ id, path, type: 'root'|'repo', label? }`.
- **`Commit`**: `{ hash, shortHash, message, author, date: Date }`. **`Branch`**: `{ name, isCurrent }`.
- **`FileTreeNode`**: `{ name, path, type: 'file'|'folder', children?, ignored? }`. **`FileChange`**, **`CommitDiffFile`** (yukarıda).
- **`Config`**: `{ projectsRoot, additionalPaths, aiProvider, maxTerminals, theme: 'dark'|'light', terminalFontSize, notifications }`.
- **`NotificationSettings`**: `{ unseenEnabled, unseenIntervalMinutes, seenEnabled, seenIntervalMinutes }`.
- **`UIState`**: `{ openTabs: string[], activeTab, leftSidebarOpen, rightSidebarOpen, projectGridLayouts: Record<string, GridLayout>, windowBounds?, windowMaximized? }`; `GridLayout = { mode: 'auto'|'columns'|'rows', count }`.
- **`Action`** (`action-types.ts`): `{ id, label, description?, icon, scope: 'user'|'project', provider?, claude?: ClaudeConfig, codex?: CodexConfig, steps: ActionStep[], modified_at? }`.
  - `ActionStep`: `{ type: 'write', content }` | `{ type: 'wait_for', pattern, timeout? }` | `{ type: 'delay', ms }`.
  - `ClaudeConfig`: `appendSystemPrompt?, systemPrompt?, model?, allowedTools?: string[], disallowedTools?: string[], tools?: string, permissionMode?, maxTurns?`. `CodexConfig`: `{ model? }`.
- **`Persona`** (`persona-types.ts`): `{ id, label, scope, provider?, claude?, codex? }` — step'siz Action gibi; interaktif oturum başlatır.
- **`AIProvider`** (`ai-provider.ts`): `'claude' | 'codex'`. Yardımcılar: `getProviderLabel`, `getProviderLaunchCommand` (`codex\r` / `claude\r`), `getProviderBinary`, `isAIProvider` type guard. Default: `'claude'`.
- **`constants.ts` default'ları**: `DEFAULT_CONFIG = { projectsRoot: '', additionalPaths: [], aiProvider: 'claude', maxTerminals: 12, theme: 'dark', terminalFontSize: 13, notifications: { unseenEnabled: true, unseenIntervalMinutes: 1, seenEnabled: true, seenIntervalMinutes: 5 } }`; `DEFAULT_UI_STATE = { openTabs: [], activeTab: null, leftSidebarOpen: true, rightSidebarOpen: false, projectGridLayouts: {}, windowBounds: undefined, windowMaximized: false }`.

### `output-trim.ts` (paylaşılan saf util + test)

`trimOutputTail(text, maxSize = 500_000, searchWindow = 2048)`:
- `text.length <= maxSize` ise dokunmadan döner.
- Aksi halde **baş tarafı keser**, en fazla `maxSize` karakter kalır. Cut noktasından ileriye `searchWindow` içinde en yakın `\n` aranır; bulunursa kesim newline'dan **sonra** yapılır (ANSI escape sequence'larının ortadan bölünmesini önler); bulunamazsa hard cut.
- Boş string → boş string.
- İki tüketicisi var: main'de `OutputBuffer` (terminal başına 500K buffer) ve renderer terminal store'u. Vitest testleri (`__tests__/output-trim.test.ts`) tam bu 5 davranışı doğrular: değişmeden dönme, maxSize sınırı, pencere içinde newline'a kesme, pencere dışında hard cut, boş string. Native rewrite'ta aynı semantikle (UTF-8/grapheme sınırlarına dikkat ederek) port edilmeli ve testleri taşınmalıdır.

## Persistence / config

IPC katmanı kendisi persist etmez; ConfigManager üzerinden dolaylıdır:
- **`config.json`** — `Config` objesi. Konum: `getConfigDir()` → macOS'ta `~/Library/Application Support/lumi` benzeri app-data dizini; dev modda `-dev` suffix'i (`lumi-dev`) ile prod config'ten izole. Windows'ta `%APPDATA%/lumi`; eski kurulumlar için `pulpo` dizininden migration fallback'i var.
- **`ui-state.json`** — `UIState`; pencere bounds/maximized dahil (resize/move/maximize/close event'lerinde main process tarafından otomatik kaydedilir, renderer'dan da `ui-state:set` ile partial merge).
- Action/Persona YAML dosyaları (user dir + proje dizini) ve action history bu kanalların arkasındaki store'larda — detayları ilgili alt sistem spec'lerinde.
- Set işlemleri **partial merge** semantiğine sahiptir (gönderilmeyen alanlar korunur).

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **IPC'nin kendisi tamamen ortadan kalkar.** Üç kanal türü üç native pattern'e maplenir:
   - invoke → doğrudan async servis metodu (`async throws` Swift fonksiyonu),
   - push → Combine publisher / `AsyncStream` / delegate,
   - send (`app:quit-confirmed`) → basit metod çağrısı.
2. **`safeSend` guard zinciri**: window null / destroyed / webContents destroyed / crashed kontrolleri + try-catch. Gerekçe: renderer crash/reload sırasında PTY output akmaya devam eder ve disposed frame'e send konsolu flood eder. Native'de "renderer process crash" diye bir şey yok; ancak **UI henüz hazır değilken veya kapanırken servislerden gelen event'lerin drop edilmesi/buffer'lanması** kararı yine verilmeli (özellikle yüksek frekanslı `terminal:output`).
3. **`contextBridge` / `contextIsolation` güvenlik modeli**: native'de gereksiz; tip güvenliği derleyiciden gelir. Preload'daki `invokeIpc<T>`'nin doğrulanmayan generic dönüşü gibi zayıflıklar kendiliğinden kapanır.
4. **`powerMonitor.resume` → `terminal:sync` → `terminal:snapshot` pull**: macOS native'de `NSWorkspace.didWakeNotification`. Uyku sonrası tam state reconciliation davranışı korunmalı (PTY'ler uykuda output üretmiş olabilir).
5. **Window kontrol kanalları** (`window:*`): SwiftUI/AppKit'te doğrudan `NSWindow` API'leri. `setWindowButtonVisibility` → `standardWindowButton(.closeButton)?.isHidden` vb. `window:fullscreen-changed` → `NSWindow.willEnterFullScreenNotification`.
6. **`dialog:open-folder`** → `NSOpenPanel` (`canChooseDirectories`). **`shell.trashItem`** → `FileManager.trashItem(at:resultingItemURL:)`. **`shell.showItemInFolder`** → `NSWorkspace.activateFileViewerSelecting`. **`shell.openExternal`** → `NSWorkspace.open(url)` — **http(s) prefix validation'ı native'de de korunmalı**.
7. **Menü accelerator'ları → `shortcut` kanalı**: native'de `NSMenu` + responder chain veya `keyboardShortcut` modifier; ayrı bir event kanalına gerek kalmaz ama 7 aksiyon birebir taşınmalı.
8. **Electron'un kısıtlı PATH problemi** (`fixProcessPath`, SystemChecker fallback yolları): GUI'den başlatılan macOS app'lerinde de aynı problem var (login shell PATH'i gelmez). Fallback dizin listesi (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`) ve/veya login shell'den PATH çekme stratejisi native'de de gerekli.
9. **Quit interception**: Electron `close` event + `preventDefault` → native'de `NSWindowDelegate.windowShouldClose` / `applicationShouldTerminate` (`.terminateLater` ile async onay). Sıra önemli: önce window state kaydı, sonra terminal sayısı kontrolü, onay, killAll + dispose.

## Native rewrite notları (riskler, dikkat edilecekler)

- **`terminal:snapshot` tek pull API'sidir** — list/buffer gibi legacy endpoint'ler bilinçli kaldırılmış. Native servis API'sinde de tek `getSnapshots()` metodu tutun; reconciliation mantığını çoğaltmayın.
- **`terminal:output` chunk'ları ham VT/ANSI byte stream'idir.** Native'de SwiftTerm gibi bir terminal emülatörüne beslenecek; string'e çevirip işlemeyin, UTF-8 sınır bölünmelerine dikkat edin. Electron tarafında trim'in newline'a hizalanması tam bu yüzden var.
- **Status modeli provider-agnostic kalmalı** (`TerminalStatus` adlandırması bilinçli; claude/codex'e özgü isim sızdırmayın).
- **Heredoc random delimiter güvenliği** (`__AI_ORCH_<uuid>__`): codex'e prompt enjeksiyonunda delimiter'ın prompt içinde geçme/manipüle edilme riskine karşı her seferinde rastgele üretilir. Native'de stdin'e doğrudan yazma imkânı varsa heredoc'a hiç gerek kalmayabilir, ama PTY üzerinden komut yazılıyorsa aynı önlem şart.
- **`config:set` truthiness bug'ı** (0 / boş string yan etkileri atlar) native'de düzeltilmeli ama davranış değişikliği olarak not edilmeli.
- **Hata sözleşmesi tutarsız**: çoğu handler exception fırlatır (renderer'da promise reject), `git:commit` ise `{ success, error? }` envelope döner, `shell:open-external` geçersiz girdiyi sessizce yutar. Native API'de tek tip hata stratejisi (Swift `throws` + tipli error) seçilip bu üç davranış bilinçli olarak normalize edilmeli.
- **Runtime payload validation yok**: invoke argümanları cast ile alınır (`scope as 'user' | 'project'` gibi). Native'de enum'larla derleme zamanında çözülür; dosya tabanlı girdiler (YAML action/persona) için yine de runtime validation gerekir.
- **Change-callback → push zinciri** (store değişti → UI'a "changed" sinyali → UI yeniden fetch eder) **pull-after-push** pattern'idir; payload taşımaz. Native'de `@Observable`/Combine ile store'u doğrudan observe etmek bu çift turu ortadan kaldırabilir, ama "değişiklik granülaritesi" (tüm liste yeniden yüklenir) davranışı basitliğiyle korunmaya değer.
- **`collection:get` (handler'sız) ve `terminal:get-status` (çağıransız) ölü kanallarını taşımayın** (bkz. K).
- **Ephemeral action id'leri** `__create-action` / `__edit-action` ve task etiketleri (`Create Action`, `Edit: <id>`) UI'da görünür davranıştır; birebir korunmalı.
- Spawn limiti aşıldığında sözleşme **exception değil `null` dönüşüdür**; renderer bunu sessiz başarısızlık olarak ele alır. Native API'de `nil` dönüş veya tipli `limitReached` sonucu olarak modellenmeli.
