# Renderer State Katmanı (Zustand Store'lar, Hook'lar, Tipler)

Kapsam: `src/renderer/stores` (4 store + testler), `src/renderer/hooks` (2 hook), `src/renderer/types`.

## Amaç ve sorumluluk

Renderer process'in tüm UI state'ini tutar ve main process ile senkronize eder. Dört bağımsız ama birbirine referans veren Zustand store'u vardır:

| Store | Sorumluluk |
|---|---|
| `useTerminalStore` | Terminal listesi, output buffer'ları, aktif terminal seçimi, repo başına son aktif terminal, main ile snapshot senkronizasyonu, terminal event bridge |
| `useAppStore` | UI layout (tab'lar, sidebar'lar, grid layout), modal/dialog state'leri, AI provider seçimi, focus mode, file viewer, UI state persistence |
| `useRepoStore` | Repository listesi, ek path'ler, branch/commit/status cache'leri, commit için dosya seçimi |
| `useNotificationStore` | Toast (bildirim) kuyruğu |

**Temel mimari ilke:** Terminaller için **main process source of truth'tur**. Renderer'daki terminal state'i bir cache/projection'dır; her IPC mutasyonundan (spawn/kill) sonra `syncFromMain()` ile reconcile edilir. UI layout state'i ise renderer'da yaşar, main'e sadece persistence için yazılır.

## Kavramsal model

- **Repository (repo):** Diskteki bir proje klasörü. `name` (klasör adı), `path` (mutlak yol), `isGitRepo`, `source` (hangi kaynaktan keşfedildi: `'projectsRoot'` ya da bir additional path'in yolu) alanlarına sahip. Repo'lar `name` ile referanslanır (tab'larda), terminal eşleştirmesi `path` ile yapılır.
- **Tab:** Açık bir repo sekmesi. `openTabs: string[]` repo **adlarını** tutar (path değil!). Tek bir `activeTab` vardır. Tab kapatınca o repo'nun tüm terminalleri öldürülür.
- **Terminal (session):** Main'de yaşayan bir PTY oturumu. Renderer'da `Terminal` objesi olarak yansıtılır: `id`, `name`, `repoPath`, `status` (`idle | working | waiting-unseen | waiting-focused | waiting-seen | error`), `task?`, `oscTitle?` (OSC escape ile gelen başlık), `isNew?`, `minimized?`, `createdAt`. `minimized` ve `isNew` **yalnızca renderer'da** yaşar — snapshot reconcile'da main'den gelmez, mevcut renderer değerinden korunur.
- **Workspace kavramı yoktur** — en üst birim repo/tab'dır. Repo'lar sidebar'da "source" bazında gruplanır (Projects Root, ek root path'ler, Standalone Repos).
- **Aktif terminal:** Global tek bir `activeTerminalId`. Ek olarak repo başına `lastActiveByRepo: Map<repoPath, terminalId>` tutulur; tab değişince o repo'da en son aktif olan terminale geri dönülür.

## Feature envanteri

### useTerminalStore

**State:** `terminals: Map<id, Terminal>`, `outputs: Map<id, TerminalOutput>`, `activeTerminalId: string | null`, `lastActiveByRepo: Map<repoPath, id>`, `syncing: boolean`, `pendingSync: boolean`.

#### 1. TerminalOutput modeli (capped buffer + delta rendering desteği)
- Output buffer üç alanlı immutable bir obje: `{ text, totalLength, epoch }`.
  - `text`: stream'in **son 500KB'lık kuyruğu** (`RENDERER_OUTPUT_MAX_SIZE = 500_000` karakter). Sebep: sınırsız birikim renderer'da V8 OOM crash'lerine yol açıyordu.
  - `totalLength`: stream'e şimdiye kadar eklenen **toplam** karakter sayısı (monoton artan, mutlak offset). Terminal görünümünün (xterm) "sadece yeni gelen delta'yı yaz" optimizasyonunu sürer — render eden taraf kendi yazdığı offset'i hatırlar, `totalLength - kendiOffset` kadar yeni veri olduğunu bilir.
  - `epoch`: non-incremental bir rewrite (buffer içeriği baştan değiştiğinde) olduğunda artar; render tarafına "tam redraw yap" sinyalidir.
- **Trim davranışı (`trimOutputTail`):** 500KB aşılınca baştan kesilir; kesim noktasından itibaren 2048 karakterlik pencerede ilk `\n` aranır ve oradan kesilir (ANSI escape sequence'ları ortadan bölmemek için). Newline bulunamazsa ham offset'ten kesilir.
- `appendOutput(id, chunk)`: text'e ekler + trim, `totalLength += chunk.length`, epoch sabit kalır.

#### 2. Snapshot merge (`mergeSnapshotOutput`) — canlı output ile snapshot reconciliation
Main'den gelen snapshot output'u ile renderer'daki canlı buffer şu kurallarla birleşir:
- Renderer'da hiç output yoksa → snapshot'ı al, `epoch+1` (tam redraw).
- Snapshot boş ya da text ile birebir aynı → mevcut korunur (referans bile aynı kalır).
- Snapshot, mevcut text ile **başlıyorsa** (snapshot ileride; renderer event kaçırmış) → incremental uzat, `totalLength` farkı kadar artar, **epoch sabit** (redraw yok).
- Mevcut text snapshot ile başlıyorsa (renderer ileride; sync canlı output ile yarıştı) → mevcut korunur (rollback flicker engellenir).
- İki stream diverge etmişse → **uzun olan** tercih edilir; snapshot kazanırsa `epoch+1`.

#### 3. `syncFromMain()` — ana reconciliation döngüsü
- `getTerminalSnapshots()` IPC çağrısı ile main'deki tüm terminallerin `{id, name, repoPath, status, task, oscTitle, createdAt, output}` snapshot'larını alır.
- `reconcileTerminals`: yeni `terminals` map'ini **sadece snapshot'taki id'lerden** kurar (main'de olmayan terminal renderer'dan düşer). Renderer-only alanlar (`isNew`, `minimized`) ve snapshot'ta boş gelen `status`/`oscTitle` mevcut renderer değerinden korunur.
- Aktif terminal çözümü (`resolveActiveTerminal`): mevcut aktif hâlâ **görünür** (minimize edilmemiş) terminaller içindeyse korunur; değilse görünürlerin ilki seçilir; hiç yoksa `null`.
- `rebuildLastActiveByRepo`: her repo için varsayılan olarak ilk terminal, ama hâlâ geçerli olan önceki seçimler korunur. Sadece görünür terminaller üzerinden hesaplanır.
- **Re-entrancy koruması:** Sync sürerken yeni sync istenirse `pendingSync = true` set edilir, istek **asla sessizce düşmez** — mevcut sync bitince (finally bloğunda) otomatik yeniden çalışır.
- **Race koruması:** Final commit `preserveNewerLiveOutputs` üzerinden yapılır: IPC await sırasında gelen canlı `appendOutput`'lar, reconcile edilmiş output'tan **aynı epoch'ta ve daha yüksek `totalLength`'te** ise canlı olan korunur. Aksi hâlde `totalLength` geri sarar ve destructive redraw tetiklenirdi. Epoch'lar farklıysa reconcile edilen kazanır. Reconcile'da olmayan (öldürülmüş) terminallerin canlı output'u atılır.
- **Çağrılma sözleşmesi:** Spawn/kill yapan her UX path'i IPC mutasyonundan sonra `syncFromMain()` çağırmak zorunda. Yeni terminal spawn edildiğinde, sync mevcut aktifi koruduğu için, çağıran **açıkça** `setActiveTerminal(yeniId)` çağırmalı.

#### 4. Terminal event bridge (`connectTerminalEventBridge` / `disconnectTerminalEventBridge`)
- App-level (terminal panel-level **değil**) yaşayan, tekil global IPC dinleyici seti. İkinci kez connect çağrısı no-op (idempotent).
- Dinlenen olaylar: `onTerminalOutput` → `appendOutput`; `onTerminalStatus` → `updateTerminal({status})`; `onTerminalTitle` → `updateTerminal({oscTitle})`; `onTerminalExit` → `removeTerminal`.
- Cleanup fonksiyonu modül-scope değişkende tutulur (store state'inde değil).

#### 5. `removeTerminal(id)` — kapanışta komşu odaklama
- Silmeden **önce**, kapanan terminal aktifse komşu hesaplanır: `findNeighborTerminalId(closedId, görünürTerminaller, aynıRepoPath)`.
- Komşu kuralı: **önceki** terminal; ilk terminal kapanıyorsa **sonraki**; id bulunamazsa listenin ilki; liste boşsa `null`.
- `repoPath` verildiğinde sadece **aynı repo'nun** terminalleri aday olur — Cmd+W odağı asla başka repo'nun terminaline atlamaz. Aynı repo'da görünür terminal kalmadıysa `activeTerminalId = null` (kullanıcı aynı tab'da, aktif terminalsiz kalır).
- `lastActiveByRepo` güncellenir: silinen, repo'nun last-active'iyse → repo'da kalan ilk görünür terminale, hiç yoksa entry silinir.
- Kapanan aktif değilse aktif terminal değişmez.

#### 6. Minimize / restore
- `minimizeTerminal(id)`: `minimized: true` set eder; minimize edilen aktif terminal ise **proaktif olarak** görünür bir komşuya (aynı repo) odak kaydırır.
- `restoreTerminal(id)`: `minimized: false`.
- `getVisibleTerminals(map)`: minimize edilmemişleri filtreleyen, store'lar ve hook'larca paylaşılan utility. Değişmez kural: **minimize edilmiş bir terminal asla odak alamaz** — `syncFromMain`, `setActiveTab`, klavye navigasyonu hep görünür kümede çalışır. İstisna: bildirim tıklaması (kullanıcı niyeti açık) önce restore eder, sonra odaklar.

#### 7. `setActiveTerminal(id | null)`
- `null` → sadece `activeTerminalId = null`.
- Terminal map'te varsa → aktif yap + o repo'nun `lastActiveByRepo` girdisini güncelle.
- Map'te yoksa bile id set edilir (yeni spawn edilen terminal henüz sync'lenmemiş olabilir).

#### 8. Yardımcı selector'lar
- `getTerminalsByRepo(repoPath)`: o repo'nun terminalleri (insertion order).
- `getTerminalCount()`: toplam (minimize dahil) sayı — `maxTerminals` (varsayılan 12) limitine karşı kullanılır.

### useAppStore

**State:** `UIState` alanları (`openTabs`, `activeTab`, `leftSidebarOpen` [varsayılan true], `rightSidebarOpen` [varsayılan false], `projectGridLayouts`, `windowBounds?`, `windowMaximized?`) + `settingsOpen`, `quitDialogOpen`/`quitTerminalCount`, `closeTabDialogOpen`/`closeTabRepoName`/`closeTabMinimizedCount`, `aiProvider` (`'claude' | 'codex'`, varsayılan `'claude'`), `focusModeActive`, `collapsedGroups: Set<string>`, `fileViewer: FileViewerState | null`.

#### 9. Tab yönetimi
- `openTab(repoName)`: tab listede yoksa ekle + aktif yap + persist; varsa sadece aktif yap (persist edilmez — mevcut davranış).
- `setActiveTab(tab)`: tab'ı aktif yapar, sonra **cross-store yan etki**: o repo'nun `lastActiveByRepo` girdisi geçerli ve görünürse o terminale, değilse repo'nun ilk **görünür** terminaline odaklanır (hiç yoksa `null`). Sonra persist.
- `closeTab(repoName)`:
  1. **Guard:** repo'nun minimize edilmiş terminali varsa kapanmaz — `CloseTabDialog` açılır (`showCloseTabDialog(repoName, minimizedCount)`).
  2. Guard geçilirse: tab listeden çıkar; kapanan aktif tab ise **listenin son** tab'ı aktif olur (yoksa `null`).
  3. Repo'nun **tüm** terminalleri için `killTerminal` IPC'leri paralel atılır; hata loglanır; her durumda (finally) `syncFromMain()` çağrılır.
  4. `unwatchFileTree(repo.path)` çağrılır (file tree watcher bırakılır).
  5. Persist.
- `confirmCloseTab()`: dialog onayı — guard'ı atlayıp aynı kapanış mantığını çalıştırır ve dialog state'ini sıfırlar.

#### 10. Grid layout (proje başına)
- `GridLayout = { mode: 'auto' | 'columns' | 'rows', count: number }`. Varsayılan `{ mode: 'auto', count: 2 }` (stabil tekil referans — `useSyncExternalStore`'un yeni obje referansı görüp sonsuz re-render'a girmemesi için).
- `projectGridLayouts: Record<repoPath, GridLayout>` — anahtar repo **path'i** (tab'ların aksine).
- `setProjectGridLayout(repoPath, layout)`: boş `repoPath` guard'ı var; state hemen güncellenir ama persist **500ms debounce'lu** (hızlı tıklamalarda eşzamanlı IPC/dosya yazımlarını engeller).
- `getActiveGridLayout()`: aktif tab'ın repo'suna ait layout, yoksa default.

#### 11. Dialog/modal state'leri
- Settings modal: `openSettings`/`closeSettings`.
- Quit dialog: uygulamadan çıkarken açık terminal sayısı ile (`showQuitDialog(count)`/`hideQuitDialog`) — sayı main'den gelir.
- Close-tab dialog: yukarıda anlatıldı.
- File viewer: `FileViewerState` (`mode: 'view' | 'diff' | 'commit-diff'`, dosya/repo path, content/original/modified content, commit hash + dosyaları). `openFileViewer` `isOpen: true` ile set eder, `closeFileViewer` `null`'lar. **Persist edilmez.**

#### 12. Focus mode ve sidebar'lar
- `enterFocusMode`/`exitFocusMode`/`toggleFocusMode` — persist edilmez (oturumluk).
- `toggleLeftSidebar`/`toggleRightSidebar` — her toggle'da persist.
- `toggleGroupCollapse(groupKey)`: sidebar'daki repo gruplarının açık/kapalı durumu (`Set<string>`). **Persist edilmez.**

#### 13. UI state persistence ve migration
- `saveUIState()`: sadece `{openTabs, activeTab, leftSidebarOpen, rightSidebarOpen, projectGridLayouts}` IPC ile main'e yazılır (window bounds'u main kendisi yönetir). Hata loglanır, kullanıcıya yansıtılmaz.
- `loadUIState()`: main'den okur. **Legacy migration:** eski formatta global `gridColumns: number | 'auto'` alanı varsa ve `projectGridLayouts` yoksa, her açık tab'ın repo path'ine aynı layout kopyalanarak `projectGridLayouts`'a çevrilir. Bu migration `useRepoStore.repos`'u okuduğu için **`loadRepos()` tamamlanmadan `loadUIState()` çağrılmamalı** (init sırası sözleşmesi).

### useRepoStore

**State:** `repos: Repository[]`, `additionalPaths: AdditionalPath[]`, `commits: Map<repoPath, Map<branchName, Commit[]>>`, `branches: Map<repoPath, Branch[]>`, `changes: Map<repoPath, FileChange[]>`, `selectedFiles: Map<repoPath, Set<filePath>>`.

#### 14. Repo ve ek path yükleme
- `loadRepos()`: `getRepos()` IPC — main diskte keşfettiği repo listesini döner.
- `loadAdditionalPaths()`: `getConfig()` IPC'den `config.additionalPaths` alınır. `AdditionalPath = { id, path, type: 'root' | 'repo', label? }` — `root` tipi altındaki tüm repo'lar taranır, `repo` tipi tek başına bir repo'dur.

#### 15. Repo gruplama (`groupReposBySource` — pure fonksiyon)
- Repo'lar `source` alanına göre gruplanır. Sıra: (1) `projectsRoot` ("Projects Root" etiketi, boşsa hiç görünmez), (2) additional path'ler **config'teki sırayla** — `root` tipindekiler **boş olsa bile** grup olarak gösterilir (label: verilen label ya da path'in son segmenti), (3) `repo` tipindekilerin hepsi tek "Standalone Repos" grubunda (`key: '__standalone__'`, boşsa görünmez).

#### 16. Git veri cache'leri
- `loadBranches(repoPath)`: branch listesi (`{name, isCurrent}`).
- `loadCommits(repoPath, branch)`: branch başına commit listesi; iç içe Map'te cache'lenir. `loadAllBranchCommits(repoPath)`: bilinen tüm branch'ler için paralel yükler.
- `loadChanges(repoPath)`: working tree status (`FileChange = {path, status: modified|added|deleted|renamed|untracked}`). **Yan etki:** her yüklemede o repo'nun `selectedFiles`'ı **tüm değişen dosyalar seçili** olacak şekilde sıfırlanır.
- `getCommitsForBranch`, `getRepoByName` selector'ları. Tüm load'larda hata yutulmaz, console'a loglanır; state değişmez.

#### 17. Commit akışı ve dosya seçimi
- `toggleFile` / `selectAll` / `deselectAll`: repo başına seçili dosya kümesi.
- `commitChanges(repoPath, message)`: seçili dosya yoksa `{success: false, error: 'No files selected'}` döner (IPC'ye gitmeden). Başarılıysa `loadChanges` + `loadAllBranchCommits` ile cache tazelenir. Sonuç `{success, error?}` envelope'u çağırana döner (UI hata mesajını gösterir).

### useNotificationStore

#### 18. Toast kuyruğu
- `NotificationToast = { id, type: 'bell'|'error'|'success'|'info', title, message, terminalId?, timestamp }`. Id'ler modül-scope sayaçtan (`toast-N`).
- `addToast(terminalId, repoName)`: bell tipi toast — başlık repo adı, mesaj "Assistant is waiting for input". **Dedupe:** aynı terminal için aktif bir bell toast'u varsa yenisi eklenmez.
- `notify(type, title, message)`: genel amaçlı toast.
- Kurallar: en fazla **5** toast (eskiler düşer, `slice(-5)`), her toast **5 saniyede** otomatik kapanır (`setTimeout`), `removeToast(id)` / `clearAll()`.
- Bell toast'una tıklama UI tarafında terminali (minimize ise restore edip) odaklar.

### Hooks

#### 19. useKeyboardShortcuts
İki kaynak dinler: (a) main process'in native menüsünden gelen `onShortcut(action)` IPC olayları, (b) renderer'da global `keydown`.

**Menü aksiyonları:** `new-terminal`, `close-terminal`, `toggle-left-sidebar`, `toggle-right-sidebar`, `open-repo-selector` (renderer'da CustomEvent `'open-repo-selector'` dispatch eder), `open-settings`, `toggle-focus-mode`.

- **Yeni terminal:** aktif tab'ın repo'su yoksa no-op; `getTerminalCount() >= maxTerminals` (12) ise no-op. Akış: `spawnTerminal(repoPath)` → dönen id'ye `writeTerminal(id, providerKomutu)` (provider launch komutu: `'claude\r'` ya da `'codex\r'`) → `syncFromMain()` → `setActiveTerminal(yeniId)`.
- **Kapat (Cmd+W semantiği):** aktif terminal varsa onu öldürür (`killTerminal` → `removeTerminal` → `syncFromMain`); aktif terminal **yoksa** aktif **tab'ı** kapatır.
- **Renderer keydown kısayolları** (macOS / Win-Linux):
  - Focus mode: Cmd+Shift+F / Ctrl+Shift+F.
  - Tab N'e geç: Cmd+1..9 / Ctrl+Shift+1..9 (`openTabs[N-1]` varsa).
  - Önceki/sonraki terminal: Cmd+Shift+←/→ / Ctrl+Shift+←/→.
- **Terminal navigasyonu (`navigateTerminal`):** sadece **görünür** terminaller arasında, **tüm repo'lar genelinde** dairesel (wrap-around) gezinir. Hedef terminal başka repo'daysa o repo'nun tab'ı da aktif edilir (`setActiveTab`). Aktif terminal yokken `next` ilk terminale, `prev` son terminale gider.

#### 20. useNotificationListener
- `onTerminalBell(terminalId, repoName)`: terminal bell'i geldiğinde, o terminal **şu an aktif değilse** toast eklenir (aktifse kullanıcı zaten görüyor — gürültü yapılmaz).
- `onNotificationClick(terminalId)`: OS bildirimi tıklanınca — terminal varsa: minimize ise restore et; repo adı (`repoPath`'in son segmenti) açık tab'lardaysa o tab'a geç; terminali odakla. Not: burada repo adı path'ten türetilir, `getRepoByName` kullanılmaz — repo adı klasör adından farklıysa tab geçişi atlanır (bilinen davranış).

### Types

#### 21. `global.d.ts`
- `window.api: ApiType` (preload'dan türetilir) global tanımı + `*.png` modül tanımı. Renderer'ın main ile **tek** temas noktası `window.api`'dir.

## Veri akışı ve bağımlılıklar

### Store'lar arası bağımlılık grafı
- `useAppStore` → `useRepoStore` (`getRepoByName` ile tab adı→repo çözümü) ve → `useTerminalStore` (tab değişimi/kapanışında terminal odak ve kill yan etkileri).
- `useKeyboardShortcuts` → üç store'a birden.
- `useNotificationListener` → notification + terminal + app store.
- `useTerminalStore` ve `useRepoStore` ve `useNotificationStore` başka store'a bağımlı değildir.
- Cross-store erişim `useXStore.getState()` ile imperatif yapılır (subscribe edilmez).

### Kullanılan IPC yüzeyi (`window.api`)
- **Terminal:** `spawnTerminal(repoPath) → {id,name,isNew}`, `killTerminal(id)`, `writeTerminal(id, data)`, `getTerminalSnapshots() → TerminalSnapshot[]`.
- **Terminal event'leri (main→renderer push):** `onTerminalOutput(id, data)`, `onTerminalStatus(id, status)`, `onTerminalTitle(id, oscTitle)`, `onTerminalExit(id)`, `onTerminalBell(id, repoName)`, `onNotificationClick(id)`. Hepsi cleanup fonksiyonu döner.
- **Config/UI:** `getUIState()`, `setUIState(partial)`, `getConfig()`.
- **Git:** `getRepos()`, `getBranches(path)`, `getCommits(path, branch)`, `getStatus(path)`, `commitFiles(path, files[], message)`.
- **Diğer:** `unwatchFileTree(path)`, `onShortcut(action)`, `platform` (klavye modifier seçimi için).

### Başlatma sırası (Layout component'inden gelen sözleşme)
1. Event bridge bağlanır (`connectTerminalEventBridge`) — uygulama ömrü boyunca tek sefer.
2. `loadRepos()` + `loadAdditionalPaths()` paralel.
3. **Sonra** `loadUIState()` (migration repos'a bakar).
4. **Sonra** `syncFromMain()` (mevcut terminaller — ör. dev'de hot reload sonrası — geri yüklenir).
Ayrıca config değişimi/refresh olaylarında aynı sıra tekrarlanır; çeşitli main olayları `syncFromMain()` tetikler.

## Persistence / config

Renderer **hiçbir şeyi kendisi persist etmez** (localStorage kullanılmaz). Tüm kalıcılık IPC üzerinden main'in ConfigManager'ına gider:

- **`<configDir>/ui-state.json`** — `{openTabs (repo adları), activeTab, leftSidebarOpen, rightSidebarOpen, projectGridLayouts (repoPath→GridLayout)}` + main'in kendi yazdığı `windowBounds`/`windowMaximized`. `setUIState` partial merge yapar. configDir: macOS'ta uygulama config klasörü (`lumi`, dev'de `lumi-dev` son eki).
- **`<configDir>/config.json`** — renderer buradan sadece **okur** (`additionalPaths`, `aiProvider` vb.); yazma Settings UI'ın ayrı IPC'leriyle olur.
- **Persist edilmeyenler:** terminal output'ları (main'de in-memory buffer; uygulama kapanınca gider), `focusModeActive`, `collapsedGroups`, modal/dialog state'leri, `fileViewer`, toast'lar, `aiProvider`'ın renderer kopyası (config'ten yüklenir), `minimized`/`isNew` bayrakları (yalnız oturumluk).
- **Persist tetikleyicileri:** tab aç/kapa/değiştir, sidebar toggle (anında); grid layout değişimi (500ms debounce).

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **İki-process mimarisi ve snapshot reconciliation:** `syncFromMain`, `mergeSnapshotOutput`, `preserveNewerLiveOutputs`, `syncing/pendingSync`, event bridge — bunların tamamı renderer ile main arasındaki **asenkron IPC yarışlarını** telafi etmek için var. Native (tek process, Swift) uygulamada PTY yöneticisi ile UI aynı process'te olacağından bu reconciliation katmanı **tamamen gereksizleşir**: tek bir `TerminalManager` (actor / MainActor sınıfı) hem PTY'leri hem state'i tutar, "source of truth senkronizasyonu" diye bir kavram kalmaz.
2. **`totalLength`/`epoch` delta-rendering mekanizması:** xterm.js'in React üzerinden beslenmesine özgü. SwiftTerm gibi bir native terminal view PTY stream'ini doğrudan tüketir; bu üçlü modelin yerini "view'a byte'ları feed et" alır. Ancak **500KB tail cap fikri** (scrollback sınırı) native'de de gerekir — SwiftTerm'de scrollback satır limiti olarak çözülür.
3. **`window.api` / preload köprüsü:** Native'de yok; doğrudan fonksiyon çağrısı/Combine/observation.
4. **Tab geçişinde menü kısayolları IPC'si (`onShortcut`):** Native'de NSMenu + standart key equivalents; renderer keydown listener'a gerek yok.
5. **Hot-reload sonrası state geri yükleme:** `syncFromMain`'in bir sebebi dev'de renderer reload olunca terminallerin yaşamaya devam etmesi. Native'de bu senaryo yok.
6. **Zustand + `getState()` imperatif cross-store erişim:** Swift'te `@Observable` store'lar ya da tek bir `AppState` aggregate; Map insertion-order semantiğine dikkat (aşağıda).

## Native rewrite notları (riskler, dikkat edilecekler)

- **Map insertion order'a gizli bağımlılık:** "İlk terminal", "önceki/sonraki komşu", "repo'nun ilk terminali" gibi tüm kurallar JS `Map`'in **ekleme sırasını koruması** varsayımına dayanır (pratikte spawn sırası = snapshot sırası). Swift `Dictionary` sırasızdır — native modelde terminaller **sıralı bir koleksiyon** (Array + id index'i, ya da OrderedDictionary) olarak tutulmalı, yoksa komşu-odak ve fallback davranışları belirsizleşir.
- **Tab kimliği repo ADI, layout kimliği repo PATH'i:** `openTabs` repo adı tutar; aynı ada sahip iki repo (farklı path) çakışır. `useNotificationListener` repo adını path'ten türetir (klasör adı ≠ repo adı ise tab geçişi sessizce atlanır). Native modelde tab kimliğini baştan **path (ya da stable id)** üzerine kurmak bu sınıf hatayı yok eder; ui-state migration'da ad→path çevirisi gerekir.
- **Odak kuralları davranışsal sözleşmedir, birebir taşınmalı:**
  - Minimize edilmiş terminal asla otomatik odak almaz; tek istisna açık kullanıcı niyeti (bildirim tıklaması → restore + focus).
  - Kapanışta komşu **aynı repo içinde** ve "önceki, ilkse sonraki" kuralıyla seçilir; aynı repo'da kimse kalmazsa odak `null` (tab değişmez).
  - Tab geçişinde repo'nun son aktif görünür terminali, yoksa ilk görünür terminali odaklanır.
  - Terminal navigasyonu (Cmd+Shift+ok) repo'lar arası dairesel gezinir ve tab'ı da değiştirir.
- **Close-tab guard'ı:** Minimize terminal varken tab kapatma onay diyaloğu ister; onay tüm terminalleri öldürür. Native'de aynı UX korunmalı (veri kaybı koruması).
- **Toast kuralları:** max 5, 5sn auto-dismiss, terminal başına bell dedupe, aktif terminal için bell toast'u gösterilmez. Bunlar ürün davranışı; native bildirim merkezi tasarlanırken aynen uygulanmalı.
- **Persistence formatı:** `ui-state.json` ve `config.json` formatları korunursa Electron→native geçişte kullanıcı state'i taşınabilir; en azından legacy `gridColumns` migration'ı gibi tek seferlik bir okuma-dönüştürme yazılmalı.
- **maxTerminals limiti (12)** spawn öncesi UI tarafında kontrol edilir; native'de tek yerde (TerminalManager) merkezi guard olarak konmalı.
- **Hata politikası:** Tüm load/save hataları loglanıp yutulur, UI çökmez; commit gibi kullanıcı-başlatan işlemler `{success, error}` envelope'u ile UI'a hata döner. Native'de aynı ayrım (arka plan sessiz + kullanıcı aksiyonu görünür hata) korunmalı.
- **Debounce'lar:** UI state yazımı 500ms debounce (grid layout); native'de dosya yazımı için aynı throttling (ya da atomic write + coalescing) gerekir.
- **Test edilebilirlik:** Mevcut kodda odak/merge mantığı pure fonksiyonlara ayrılmış ve testli (`findNeighborTerminalId`, `mergeSnapshotOutput`, `resolveActiveTerminal`, `rebuildLastActiveByRepo`, `preserveNewerLiveOutputs`, `appendTerminalOutput`, `trimOutputTail`). Merge/snapshot fonksiyonları native'de gereksizleşse de **komşu-odak, last-active ve görünürlük kuralları** pure Swift fonksiyonları olarak yazılıp aynı test senaryolarıyla (testler bu spec'teki kuralların en net dökümüdür) doğrulanmalı.
