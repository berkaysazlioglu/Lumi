# Renderer UI (Terminal/TerminalPanel hariç tüm component'ler)

Kapsam: `src/renderer/components` altındaki **Layout, Header, LeftSidebar, RightSidebar, Settings, Setup, FocusMode, FileViewer, BrowserSlot, Notifications, CloseTabDialog, QuitDialog, common, ui, icons**. Terminal grid'in kendisi (Terminal/TerminalPanel) ayrı spec'tedir; burada sadece bu UI'ların terminale dokunan davranışları anlatılır.

---

## Amaç ve sorumluluk

Bu alt sistem, Lumi dashboard'unun terminal grid'i dışındaki tüm görsel kabuğudur:

- **Layout**: Uygulama iskeleti, başlangıç (bootstrap) sırası, first-run / loading / normal ekran seçimi, global IPC listener'larının yaşam döngüsü, tüm modal/dialog/toast'ların mount noktası.
- **Header**: Repo tab bar'ı, repo açma dropdown'u, sidebar toggle'ları, focus mode / settings butonları, platforma özel pencere kontrolleri.
- **LeftSidebar**: Aktif repo'nun terminal session listesi, dosya ağacı (Project Context), Quick Actions (kullanıcı tanımlı komut kısayolları).
- **RightSidebar**: Git commit ağacı (branch bazlı) ve uncommitted changes + commit UI.
- **Settings**: Sekmeli ayarlar modal'ı (General / Terminal / Appearance / Notifications / Shortcuts).
- **Setup**: İlk çalıştırma onboarding sihirbazı (4 adım).
- **FocusMode**: Dikkat dağıtmayan tam ekran terminal görünümünde hover ile beliren kontrol çubuğu.
- **FileViewer**: Dosya içeriği / diff / commit diff gösteren Monaco tabanlı modal.
- **Notifications**: Uygulama içi toast bildirimleri.
- **CloseTabDialog / QuitDialog**: Yıkıcı işlemler için onay modal'ları.
- **common / ui / icons**: ErrorBoundary, yeniden kullanılabilir küçük bileşenler (Button, IconButton, Badge, EmptyState, SearchInput…), Logo/Mascot/StatusDot.

**Not:** `BrowserSlot/` dizini mevcut ama **boş** (sadece boş bir `hooks/` alt dizini var). Implementasyonu yok; native rewrite'ta yok sayılabilir veya gelecekteki embedded-browser feature placeholder'ı olarak not edilebilir.

---

## Feature envanteri

### 1. Layout (uygulama iskeleti ve bootstrap)

**1.1 Bootstrap sırası (kritik, sıra bağımlı):**
1. `isFirstRun()` IPC → true ise SetupScreen render edilir, başka hiçbir şey yüklenmez.
2. Değilse `getConfig()` → `aiProvider` ('claude' | 'codex', default 'claude') app store'a yazılır.
3. `loadRepos()` + `loadAdditionalPaths()` **paralel**.
4. `loadUIState()` — **mutlaka loadRepos'tan sonra** (legacy `gridColumns` → `projectGridLayouts` migration'ı repo listesine ihtiyaç duyar).
5. `syncFromMain()` — terminal snapshot'ı main process'ten çekilir.
- Bu süre boyunca "loading screen" gösterilir: Mascot (loading varyantı, 80px), "Lumi" başlığı, "Initializing..." metni.
- Setup tamamlanınca (`onComplete`) aynı bootstrap dizisi tekrar koşulur.

**1.2 Global listener yaşam döngüsü (Layout mount/unmount'a bağlı):**
- Terminal event bridge (`connectTerminalEventBridge`/`disconnect…`) — terminal output'unun panel mount durumundan bağımsız akmaya devam etmesi için **app seviyesinde** bağlanır. Edge-case: TerminalPanel unmount olsa bile (focus mode geçişleri, repo değişimi) output kaybolmaz.
- `onConfirmQuit(terminalCount)` → QuitDialog'u açar (main process quit'i intercept edip soruyor).
- `onReposChanged()` → repo listesi + additional paths yeniden yüklenir (fs watcher).
- **Sleep/wake re-sync**: 3 ayrı tetikleyiciyle `syncFromMain()` çağrılır: (a) `document.visibilitychange` → visible, (b) `window focus`, (c) main process `onTerminalSync` sinyali (powerMonitor resume). Native'de NSWorkspace wake notification + app didBecomeActive karşılığı gerekir.

**1.3 Yerleşim ve focus mode animasyonları:**
- Normal düzen: üstte Header, altında `layout-body` = [sol sidebar | main (TerminalPanel) | sağ sidebar].
- Focus mode aktifken: Header `AnimatePresence` ile çıkar — exit animasyonu `opacity 0, y:-20`, 0.25s easeInOut (giriş animasyonu `initial={false}` ile atlanır, sadece çıkış animasyonludur). Her iki sidebar gizlenir, yerine `FocusExitControl` render edilir.
- Sidebar'lar `leftSidebarOpen`/`rightSidebarOpen` flag'lerine göre koşullu render (AnimatePresence `mode="wait"` ile sarılı ama aside'larda motion yok — pratikte anlık aç/kapa).
- Layout her zaman mount eden global overlay'ler: SettingsModal, QuitDialog, CloseTabDialog, ToastContainer, FileViewerModal.

**1.4 Klavye kısayolları (useKeyboardShortcuts, Layout'ta aktive edilir):**
- İki kaynak: (a) main process menü accelerator'larından gelen `onShortcut(action)` IPC eventleri, (b) renderer'da window keydown listener.
- IPC ile gelen aksiyonlar: `new-terminal` (aktif repo'da PTY spawn + AI provider launch komutu yaz + sync + yeni terminale focus; max terminal limiti dolu ise sessizce no-op), `close-terminal` (aktif terminal varsa kill; **yoksa aktif repo tab'ını kapatır**), `toggle-left-sidebar`, `toggle-right-sidebar`, `open-repo-selector` (window'a `open-repo-selector` CustomEvent dispatch eder), `open-settings`, `toggle-focus-mode`.
- Renderer keydown'ları: Focus mode (mac: Cmd+Shift+F, diğer: Ctrl+Shift+F), Tab N'e geç (mac: Cmd+1..9 — Shift'siz; diğer: Ctrl+Shift+1..9), Önceki/Sonraki terminal (Cmd/Ctrl+Shift+←/→). Terminal navigasyonu **sadece görünür (minimize olmayan)** terminaller arasında wrap-around dolaşır; hedef terminal başka repo'daysa o repo'nun tab'ı da aktive edilir.
- Kısayol referans tablosu (ShortcutsSection'daki tam liste): New Terminal ⌘T, Close Terminal ⌘W, Open Repository ⌘O, Toggle Left Sidebar ⌘B, Toggle Right Sidebar ⌘⇧B, Tab N ⌘1–⌘9, Prev/Next Terminal ⌘⇧←/→, Settings ⌘,, Focus Mode ⌘⇧F, Quit ⌘Q. (Windows/Linux'ta hepsi Ctrl+Shift kombinasyonu.)

**1.5 Bildirim dinleyici (useNotificationListener, Layout'ta aktive edilir):**
- `onTerminalBell(terminalId, repoName)`: Terminal bell (assistant input bekliyor) geldiğinde, **o terminal şu an aktif değilse** toast eklenir. Aktifse sessiz.
- `onNotificationClick(terminalId)`: Native OS bildirimine tıklanınca → terminal minimize ise restore edilir, repo tab'ı açıksa aktive edilir, terminal focus alır.

### 2. Header

**2.1 Genel:**
- Üç bölge: sol (hamburger menü toggle, Mascot app-icon 26px, uygulama adı — dev build'de "DEV", prod'da "Lumi"), orta (repo tab'ları + "+" repo selector), sağ (Focus Mode, sağ sidebar toggle, Settings, Linux'ta pencere kontrolleri).
- Header'a **çift tıklama** → pencere maximize/restore toggle (`toggleMaximize` IPC). Native'de zaten standart davranış.
- Header sürüklenebilir pencere alanıdır (`-webkit-app-region: drag`). Platform-conditional padding: macOS'ta traffic light'lar için 80px sol padding (fullscreen'de 12px), Windows'ta titleBarOverlay için 140px sağ padding, Linux'ta 12px.
- Linux'ta native titleBarOverlay yerine custom minimize/maximize/close butonları render edilir (Wayland/tiling WM instabilitesi nedeniyle).
- Focus Mode butonu tooltip'i platforma duyarlı: "Focus Mode (⌘⇧F)" / "(Ctrl+Shift+F)".

**2.2 RepoTab:**
- Folder ikonu + repo adı + X (kapat) butonu. Aktif tab `--active` stiline sahip.
- Tab'a tıklama → aktif tab değişimi; X tıklaması `stopPropagation` ile tab seçimini engeller.
- **Tab kapatma akışı (store davranışı):** Repo'da minimize edilmiş terminal varsa kapatma yerine `CloseTabDialog` açılır. Yoksa: repo'nun tüm terminalleri kill edilir (paralel, hata loglanır, sonunda `syncFromMain`), repo'nun file tree watcher'ı kaldırılır, tab listeden çıkar; kapanan tab aktifse **listede kalan son tab** aktif olur (yoksa null), UI state persist edilir.
- **Tab aktive etme (setActiveTab):** Repo'nun "son aktif terminal"i hatırlanır (`lastActiveByRepo`); o terminal hâlâ mevcut ve minimize değilse focus'u alır, değilse ilk görünür terminal, o da yoksa null. Her tab değişimi UI state'i persist eder.

**2.3 RepoSelector (repo açma dropdown'u):**
- "+" butonuna veya ⌘O'ya basınca açılır (⌘O `open-repo-selector` CustomEvent ile gelir). `createPortal` ile `document.body`'ye render edilir (header DOM'unun dışında).
- İçerik: arama input'u (açılınca auto-focus) + repo listesi.
- Filtre: zaten açık tab'lar listeden gizlenir + isimde case-insensitive substring araması.
- **Gruplama**: birden fazla kaynak grubu varsa repo'lar gruplanır: (1) "Projects Root", (2) her additional root path için ayrı grup (label'ı: custom label → klasör adı → tam path), (3) standalone repo'lar → "Standalone Repos". Tek grup varsa düz liste.
- Grup başlığı tıklanabilir → collapse/expand (chevron döner; içerik Framer Motion `height: 0↔auto, opacity 0↔1`, 0.15s). Collapsed grup durumu app store'da `collapsedGroups` Set'inde tutulur (persist edilmez, session-local). Grup başlığında repo sayısı badge'i.
- **Klavye navigasyonu**: ↑/↓ ile seçim (sadece açık gruplardaki düz listede), Enter ile aç, Escape ile kapat+arama sıfırla. Arama her değiştiğinde seçim index'i 0'a döner.
- Dışarı tıklama dropdown'u kapatır (trigger ve dropdown ref'leri kontrol edilir).
- Her satırda: git repo ise FolderGit2 ikonu + "git" badge'i, değilse düz Folder ikonu.
- Boş durumlar: arama eşleşmezse "No matching repos", tüm repo'lar açıksa "No more repos available", grup boşsa "No repositories found".
- Repo seçilince: `openTab(name)` — tab zaten açıksa sadece aktive edilir, değilse listeye eklenip aktive edilir; dropdown kapanır, arama sıfırlanır.

### 3. LeftSidebar

Üç dikey bölümden oluşur: SessionList, ProjectContext, QuickActions. (CollectionProgress component'i mevcut ama LeftSidebar'a mount edilmemiş — aşağıda ayrı anlatıldı.)

**3.1 SessionList ("Sessions"):**
- **Sadece aktif repo'nun** terminallerini listeler (repoPath eşleşmesi). Başlıkta toplam sayaç badge'i.
- Her satır: StatusDot (terminal durumu: renk CSS ile status'a göre) + isim. İsim önceliği: `oscTitle` (OSC escape ile terminal'in kendi set ettiği başlık) → `task` → `name`.
- Aktif terminal `--active`, minimize edilmiş terminal `--minimized` stilinde.
- Satıra tıklama: minimize ise önce restore edilir, sonra aktif terminal yapılır.
- "NEW" rozeti (Sparkles ikonu, spring animasyon: stiffness 400, damping 15, `opacity/scale 0.5→1`) — **dormant/ölü UI**: render koşulu `terminal.isNew`, ancak bu bayrak hiçbir akışta `true` olmuyor (main'de `TerminalManager.spawn` içinde `const isNew = false` hardcoded; renderer store'u snapshot reconciliation'da yalnızca mevcut değeri korur). Rozet fiilen hiç görünmez; CollectionProgress/codename gamification'ıyla aynı yarım kalmış kapsamdadır (bkz. [00-overview](./00-overview.md) açık soru 1).
- Hiç session yoksa "No active sessions" metni.

**3.2 ProjectContext (dosya ağacı):**
- Aktif repo'nun dosya ağacını gösterir. Başlık satırı: "Project Context" (tıklayınca bölüm collapse/expand), arama (büyüteç) butonu, chevron butonu.
- **Repo başına cache**: ağaç verisi `Map<repoPath, nodes>` içinde tutulur; repo değişince cache varsa anında gösterilir, yoksa fetch edilir ("Loading..." durumu). Expand durumu da repo başına `Map<repoPath, Set<path>>`.
- **İlk yüklemede** kök seviyesindeki tüm klasörler otomatik expand edilir (sadece o repo için ilk kez).
- **Watcher (stale-while-revalidate)**: aktif repo için `watchFileTree` çağrılır, repo değişince/unmount'ta `unwatchFileTree`. `onFileTreeChanged(repoPath)` gelince eski ağaç ekranda kalırken arka planda yeni ağaç çekilir ve değiştirilir; **scroll pozisyonu korunur** (değişiklik öncesi scrollTop kaydedilir, layout-effect'te geri yüklenir).
- **Node davranışları:**
  - Klasör: tıklayınca expand/toggle. `ignored` işaretli klasörler (gitignore'lu — soluk stil) expand edilmez (children boş gelir).
  - Dosya: tıklayınca içerik okunur ve FileViewer 'view' modunda açılır.
  - Her node **drag edilebilir**: `text/plain` olarak mutlak/repo-relative path'i taşır (terminale sürükle-bırak için; effectAllowed: copy).
  - Sağ tık context menüsü: dosyalar için "Delete" (silme + ağaç yenileme, hata sessizce yutulur — dosya zaten silinmiş olabilir), herkes için "Copy Path" (clipboard) ve "Reveal in Finder / File Explorer / File Manager" (platforma göre label).
- **Filtreleme (arama):** Büyüteç → başlık crossfade ile gizlenir, SearchInput belirir (auto-focus). Filtre, isimde case-insensitive eşleşen dosyaları VE eşleşen çocuk içeren klasörleri bırakır (klasör adı eşleşirse tüm çocukları korunur). Filtre aktifken **tüm klasörler otomatik expand** edilir; ilk filtre tuşunda mevcut expand durumu snapshot'lanır, filtre temizlenince geri yüklenir. Input boşken blur → arama kapanır. Escape → temizle+kapat. Repo değişince arama sıfırlanır.
- Boş durumlar: "No repo selected", "Loading...", "No matching files" (filtre varken), "Empty directory".

**3.3 QuickActions:**
- YAML tabanlı, kullanıcı tanımlı hızlı komutlar. İki scope: `user` (global) ve `project` (repo'ya özel) — araya ince divider çizilir.
- Aktif repo değişince `getActions(repoPath)` ile liste yüklenir, `loadProjectActions(repoPath)` proje action'larını tetikler; `onActionsChanged` watcher eventi listeyi canlı yeniler.
- Her action butonu: ikon (isimden map: Terminal, TestTube, Package, GitBranch, FileEdit, Plus, Zap; bilinmeyen → Zap) + label + (description varsa) Info ikonu.
- **Info tooltip'i**: Info ikonuna hover'da 300ms gecikmeyle, ikonun sağında portal'la tooltip belirir (Framer Motion `opacity/x: -4→0`, 0.15s); mouse ayrılınca 150ms sonra kaybolur (hover-intent davranışı).
- Action'a tıklama → `executeAction(id, repoPath)` (main process yeni terminal açıp komutu çalıştırır) → `syncFromMain()`. Aktif repo yoksa butonlar disabled.
- Başlıktaki "+" → `createNewAction(repoPath)` (template YAML'la editör terminali açılır) → sync.
- **Sağ tık context menüsü** (action başına): Edit (action dosyasını editörde açar — terminal spawn eder), Delete, History, ve eğer action default seed'lerden biriyse **ve** üzerinde değişiklik varsa (`modified_at`) "Reset to Default" (dosyayı siler; watcher yeniden seed eder).
- **History**: `getActionHistory(id)` timestamp'li yedek listesi döner; boşsa panel açılmaz. Girdiler relative-time formatlanır ("Just now", "N min ago", "Nh ago", "Nd ago", sonrası "Mar 5" gibi). Dosya adı formatı `2026-02-11T14-30-00.yaml` → ISO'ya çevrilip parse edilir. Girdi seçilince `restoreAction(id, timestamp)`.
- Default action ID'leri `getDefaultActionIds()` ile bir kez yüklenir.

**3.4 CollectionProgress (mount edilmemiş / dormant feature):**
- "Collection" gamification widget'ı: `getCollection()` 3 sn'de bir poll edilir, `discovered/total` (default total 2500) progress bar (Framer Motion width animasyonu 0.5s easeOut).
- Sayı arttığında 2 sn'lik "New codename discovered!" rozeti (Sparkles, fade+slide).
- Tamamlanınca "COMPLETED" badge'i + canvas tabanlı 60 parçacıklı konfeti animasyonu (yerçekimli, requestAnimationFrame; partiküller ölünce kendini kapatır).
- Şu an hiçbir yerden render edilmiyor — native rewrite'ta taşınıp taşınmayacağına ürün kararı verilmeli.

### 4. RightSidebar (Git paneli)

**4.1 Genel:**
- Aktif repo yoksa EmptyState ("No repository / Select a repository to view").
- İki CollapsibleSection: "Commits" (default açık) ve "Changes" (default açık, badge'inde uncommitted dosya sayısı).
- `onFileTreeChanged` eventi aktif repo için gelirse: changes + branches + tüm branch commit'leri yeniden yüklenir (canlı git durumu).
- CollapsibleSection: başlık tıklamasıyla aç/kapa; içerik Framer Motion `height 0↔auto, opacity`, 0.2s easeInOut; chevron yön değiştirir; badge>0 ise warning Badge.

**4.2 CommitTree / BranchSection:**
- Repo'nun tüm branch'leri listelenir; her branch başlığı: chevron + GitBranch ikonu + isim + (current ise) "current" accent badge'i.
- **Default expand**: kullanıcı hiç dokunmadıysa sadece current branch açık gelir. Expand durumu repo başına Map'te (session-local).
- Branch açıkken commit listesi: shortHash + (current branch'in ilk commit'i ise) "HEAD" success badge'i + mesaj + relative tarih ("Nm ago"/"Nh ago"/"Nd ago").
- **Commit'e tıklama** → `getCommitDiff(repoPath, hash)` → FileViewer 'commit-diff' modunda açılır (dosya listesi + diff).
- Branch'ler yüklenmemişse "Loading branches..." metni.

**4.3 ChangesSection:**
- Uncommitted değişiklik yoksa "No uncommitted changes".
- Toolbar: "Select All / Deselect All" checkbox'ı + "seçili/toplam" sayacı. Seçim durumu repo başına store'da.
- **FileChangeItem** (her dosya): checkbox (toggle; satır tıklaması da toggle eder) + durum harfi rozeti (M/A/D/R/U — modified/added/deleted/renamed/untracked, her biri farklı renk sınıfı) + dosya adı (title'da tam path) + göz (Eye) ikonu.
  - Göz ikonu → `getFileDiff(repoPath, path)` → FileViewer 'diff' modunda (original vs modified, side-by-side).
  - Sağ tık → "Reveal in File Manager".
- **Commit UI**: mesaj input'u + Commit butonu. Buton ancak (en az 1 dosya seçili && mesaj boş değil && commit sürmüyorken) aktif. Cmd/Ctrl+Enter input'tan commit tetikler. Commit sırasında buton "Committing..."; başarıda mesaj temizlenir.

### 5. SettingsModal

**5.1 Çerçeve davranışı:**
- Tam ekran overlay + ortada modal. Animasyon: overlay fade 0.15s; modal `opacity+scale 0.95→1` 0.15s. Overlay'e tıklama veya Escape kapatır (modal içine tıklama propagation'ı kesilir).
- Sol nav: 5 sekme (General, Terminal, Appearance, Notifications, Shortcuts), her biri ikonlu. Sekme içeriği `AnimatePresence mode="wait"` ile geçiş yapar (`opacity 0, y:8 → 1,0 → exit y:-8`, 0.15s).
- **Yükleme**: modal her açılışında (mount'ta değil) `getConfig()` + `getUIState()` paralel çekilir; config `DEFAULT_CONFIG` ile merge edilir.
- **Kaydetme modeli**: tüm değişiklikler lokal state'te birikir; `hasChanges` flag'i bir şey değişene kadar Save'i disabled tutar. Save → `setConfig(config)` + `setUIState(uiDefaults)` + `aiProvider` store'a yazılır + modal kapanır. Cancel/Escape → değişiklikler atılır. Save sırasında "Saving..." metni.

**5.2 GeneralSection:**
- **Projects Root**: text input + "Browse" (native klasör seçim dialogu, `openFolderDialog` IPC).
- **Additional Paths** (AdditionalPathsField): iki ekleme butonu — "Add Root Directory" (taranacak ek kök) ve "Add Repository" (tek standalone repo). Her ikisi klasör dialogu açar. Guard'lar: seçilen path projectsRoot'a eşitse veya zaten listedeyse sessizce eklenmez. Her girdi: ROOT/REPO tip rozeti + label veya kısaltılmış path (`.../<son-2-segment>`; ≤3 segmentse tam path; title'da tam path) + kalem (label inline edit: Enter kaydet, Escape iptal, Check butonu) + X (kaldır). ID'ler `crypto.randomUUID()`.
- **AI Provider**: Claude / Codex segmented seçim — terminallerde kullanılacak CLI'ı belirler.
- **Theme**: Dark aktif; Light butonu disabled, "Coming soon" tooltip'li.

**5.3 TerminalSection:**
- Max Terminals: number input, 1–20 sınırı (aralık dışı değerler yazılmaz).
- Font Size: number input, 10–24 px sınırı.

**5.4 AppearanceSection:**
- İki toggle switch: "Left Sidebar" ve "Right Sidebar" — **başlangıçta** sidebar'ların default açık/kapalı durumu (UIState'e yazılır, anlık layout'u değiştirmez).

**5.5 NotificationsSection:**
- Bilgi kartı: bildirimlerin "assistant bitirip input beklerken, pencere odakta değilken native OS bildirimi olarak" gönderildiğini açıklar.
- İki toggle + koşullu frequency input:
  - **Waiting (Unseen)**: yanıt henüz görülmemişken bildirim. Açıkken interval input'u görünür (0.5–10 dk, 0.5 adım).
  - **Waiting (Seen)**: yanıt görülmüş ama cevap verilmemişken periyodik hatırlatma (1–30 dk, 1 adım).
- Frequency input'ları aralık dışı/NaN değerleri reddeder.

**5.6 ShortcutsSection:** Salt-okunur kısayol listesi (bkz. 1.4'teki tablo). Her satır: aksiyon adı + `kbd` görünümlü tuş kombinasyonları; aralıklı kombolar ("⌘1 – ⌘9") tire ile gösterilir. Platform algısına göre mac/diğer set'i seçilir.

### 6. Setup (onboarding sihirbazı)

- `isFirstRun()` true iken Layout yerine tam ekran SetupScreen.
- **Stepper başlığı**: 4 adım noktası (1–4 numaralı), aktif/done durum stilleri, adımlar arası ilerleme çizgisi (geçilen segmentler `--active`). Adım label'ları: Welcome, System Checks, Projects, Ready.
- Adım içerikleri `AnimatePresence mode="wait"` ile geçiş: her adım `opacity 0, y:10 → 1,0`, exit `y:-10`, 0.3s.
- **WelcomeStep**: Mascot (onboarding, 120px) + "Welcome to Lumi" + açıklama + AI Provider seçimi (Claude/Codex segmented) + "Get Started". İlerlemeden önce `setConfig({aiProvider})` kaydedilir (hata loglanır ama ilerleme engellenmez).
- **SystemChecksStep**: mount'ta `runSystemChecks()` otomatik koşar. Koşarken "Running checks…" spinner satırı. Her sonuç: durum ikonu (pending/running: dönen Loader, pass: CheckCircle, fail: XCircle, warn: AlertTriangle) + label + mesaj. `fixable && fail` olan check'lerde "Fix" butonu → `fixSystemCheck(id)` tek check'i günceller. "Re-run All" (checkler bittiyse görünür). **Next butonu herhangi bir 'fail' varken disabled** (tooltip: "Fix all failures before proceeding"); warn engellemez. Back var.
- **ProjectsRootStep**: text input (placeholder `~/Projects`, auto-focus, Enter=Next) + Browse (klasör dialogu). Next: boş/whitespace ise disabled; tıklanınca `setConfig({projectsRoot})` kaydedilir ("Saving…" durumu), hata olursa adımda kalınır.
- **ReadyStep**: spring animasyonlu check ikonu (scale 0→1, stiffness 200, damping 15, 0.1s delay) + "You're All Set" + "Launch Dashboard" (Rocket ikonu) → onComplete → Layout normal bootstrap'ı koşar.
- Setup'ın kendi CSS dosyası vardır (`SetupScreen.css`) — global stillerden ayrı.

### 7. FocusMode (FocusExitControl)

- Focus mode'a girince: Header/sidebar'lar gizlenir (bkz. 1.3) ve mount anında **macOS traffic light'ları gizlenir** (`setTrafficLightVisibility(false)`); çıkışta (unmount) geri gösterilir.
- **Hover-reveal bar**: mouse ekranın üst 50px'ine girerse 500ms gecikme sonrası kontrol çubuğu belirir (Framer Motion `opacity 0, y:-20 → 1,0`, 0.2s; çıkışı aynı ters). Mouse bölgeden çıkınca timer iptal + bar gizlenir — **ancak bar içindeki dropdown açıksa gizlenmez** (dropdown open-state ref ile takip edilir). Bar görünürken traffic light'lar da gösterilir (visible state'e senkron).
- Bar içeriği (sol): repo'da terminal varsa "Terminals" label'ı + "N / max" sayacı + GridLayoutPopup (grid düzeni seçici — TerminalPanel'den paylaşılan) + PersonaDropdown (yeni terminal / persona spawn).
  - Yeni terminal: max limit kontrolü (`alert()` ile "Maximum N terminals allowed" — **DEFAULT_CONFIG.maxTerminals kullanılır, kullanıcının config'i değil; bilinen tutarsızlık**), spawn + AI provider launch komutu + sync.
  - Persona seçimi: `spawnPersona(personaId, repoPath)` + sync.
- Bar sağı: "Exit Focus Mode" butonu (X ikonu) → toggle.

### 8. FileViewer

- Global modal; `useAppStore.fileViewer` state'i ile sürülür. Üç tetikleyici: ProjectContext dosya tıklaması ('view'), FileChangeItem göz ikonu ('diff'), BranchSection commit tıklaması ('commit-diff').
- Çerçeve: backdrop fade 0.15s + modal `opacity/scale 0.95→1` 0.15s. Backdrop tıklaması veya Escape kapatır. Başlık: moda göre — view: dosya path'i (FileText ikonu); diff: dosya adı (GitCompare); commit-diff: "Commit <7-char-hash>".
- **view modu (FileContentView)**: Monaco Editor, read-only, dark tema, minimap kapalı, 13px font, satır numaraları açık, line highlight kapalı, ince scrollbar (8px). Dil, uzantıdan map'lenir (ts/tsx→typescript, js/jsx, json, md, css, scss, html, py, rs, go, yaml/yml, sh/bash→shell, toml→ini, sql, xml/svg, graphql, dockerfile; bilinmeyen → plaintext).
- **diff modu (FileDiffView)**: Monaco DiffEditor, **side-by-side**, read-only, aynı görsel ayarlar; dil map'i biraz daha dar (shell/toml/sql/xml yok).
- **commit-diff modu (CommitDiffView)**: solda dosya listesi sidebar'ı (commit hash kısaltması + "N files" başlığı; her dosya: FileText ikonu + durum harfi renkli [M sarı/A yeşil/D kırmızı/R mor] + dosya adı), sağda seçili dosyanın FileDiffView'ı. İlk dosya default seçili.

### 9. Notifications (Toast)

- ToastContainer sağ tarafta sabit konumda; `AnimatePresence mode="popLayout"` ile liste animasyonu.
- Toast türleri: `bell` (assistant input bekliyor), `error`, `success`, `info` — her birinin ikonu ve stil varyantı var.
- Animasyon: giriş `opacity 0, x:50 → 1,0` 0.2s easeOut; çıkış tersi; `layout` prop'u ile yer değiştirmeler animasyonlu.
- İçerik: ikon + başlık (repo adı) + mesaj + X kapat butonu (stopPropagation) + altta **5 sn'lik auto-dismiss progress bar'ı** (50ms'de bir güncellenen width%; süre dolunca store toast'u kaldırır).
- **Bell toast tıklaması**: ilgili repo tab'ı açıksa aktive edilir, terminal minimize ise restore edilip focus alır, toast kapanır. Bell olmayan toast'lar tıklanamaz (cursor default).

### 10. CloseTabDialog ve QuitDialog

İkisi de aynı yapıdadır: settings-overlay üstünde küçük onay kartı, AlertTriangle ikonu, overlay fade 0.15s + kart scale 0.95→1, Escape ve overlay tıklaması = iptal, onay butonu `autoFocus`.

- **CloseTabDialog**: `closeTab()` minimize edilmiş terminal tespit ederse açılır. Metin: "Close {repo}?" + "You have N minimized terminal(s) that will be terminated." (tekil/çoğul eki dinamik). "Close" → `confirmCloseTab()`: guard'ı atlayarak terminalleri kill eder, tab'ı kapatır, state persist eder.
- **QuitDialog**: main process quit isteğini intercept edip `onConfirmQuit(terminalCount)` gönderince açılır. Metin: "Quit Lumi?" + "You have N active terminal session(s). All running processes will be terminated." "Quit" → `confirmQuit()` IPC (main gerçek çıkışı yapar). Cancel → sadece dialog kapanır, uygulama açık kalır.

### 11. common / ui / icons

- **ErrorBoundary**: React class boundary; hata yakalayınca koyu temalı "Something went wrong" ekranı + hata mesajı + "Try again" (state reset, çocuklar yeniden mount). Native karşılığı: crash-safe panel/recovery UI veya en azından alt sistem bazlı hata izolasyonu.
- **LoadingSpinner**: sadece "Loading..." metni (placeholder seviyesinde).
- **SearchInput**: kontrollü arama input'u — büyüteç ikonu, değer varken X temizle butonu (temizleyince focus input'ta kalır), Escape = temizle + `onClose`, opsiyonel `onBlur`, `autoFocus` desteği. Kendi CSS dosyası var.
- **Button**: primary/ghost varyantlı, leftIcon/rightIcon slotlu buton. **IconButton**: tek ikonlu, `title` tooltip'li buton (native tooltip). **Badge**: default/accent/success/warning/error varyantları. **Card**: stil eklemeyen passthrough div (fiilen kullanım değeri düşük). **EmptyState**: ikon + başlık + opsiyonel açıklama + opsiyonel aksiyon.
- **icons/Logo**: SVG ahtapot logosu — gradyan + glow filter'lı, 8 tentacle + uçlarında terminal node daireleri, gövde + gözler; `animated` class opsiyonu. ID çakışmasına karşı size bazlı unique id üretir.
- **icons/Mascot**: 6 varyantlı webp maskot görseli (`app-icon`, `loading`, `onboarding`, `error`, `success`, `empty`); draggable=false.
- **icons/StatusDot**: terminal status'una göre sınıf alan renkli nokta (`status-dot--<status>`), `aria-label` status.

---

## Veri akışı ve bağımlılıklar

### Store'lar (Zustand → native'de observable state karşılığı)
- **useAppStore**: `openTabs[]`, `activeTab`, sidebar açık/kapalı, `focusModeActive`, `settingsOpen`, quit/closeTab dialog state'leri, `fileViewer` state'i, `collapsedGroups` (RepoSelector grupları), `projectGridLayouts`, `aiProvider`. `saveUIState` çağrıları tab/sidebar değişimlerinde anında, grid layout değişiminde 500ms debounce'lu.
- **useRepoStore**: `repos`, `additionalPaths`, `branches: Map<repoPath, Branch[]>`, `changes: Map<repoPath, FileChange[]>`, `selectedFiles: Map<repoPath, Set<path>>`, `commitChanges`, `groupReposBySource` yardımcı fonksiyonu.
- **useTerminalStore**: `terminals: Map`, `activeTerminalId`, `lastActiveByRepo`, `syncFromMain()` (main process = source of truth; tüm spawn/kill akışları sonrası çağrılır), minimize/restore.
- **useNotificationStore**: toast kuyruğu.

### Kullanılan IPC kanalları (window.api üzerinden)
- Bootstrap/config: `isFirstRun`, `getConfig`, `setConfig`, `getUIState`, `setUIState`.
- Repo/git: `onReposChanged`, `getFileTree`, `watchFileTree`, `unwatchFileTree`, `onFileTreeChanged`, `readFile`, `deleteFile`, `revealInFileManager`, `getFileDiff`, `getCommitDiff` (+ store içinden branch/changes/commit IPC'leri).
- Terminal: `spawnTerminal`, `writeTerminal`, `killTerminal`, `spawnPersona`, `onTerminalSync`, terminal snapshot/event bridge.
- Actions: `getActions`, `getDefaultActionIds`, `executeAction`, `createNewAction`, `editAction`, `deleteAction`, `getActionHistory`, `restoreAction`, `loadProjectActions`, `onActionsChanged`.
- Pencere/OS: `toggleMaximize`, `minimizeWindow`, `closeWindow`, `setTrafficLightVisibility`, `openFolderDialog`, `platform`.
- Bildirim/quit: `onTerminalBell`, `onNotificationClick`, `onConfirmQuit`, `confirmQuit`, `onShortcut`.
- Setup: `runSystemChecks`, `fixSystemCheck`.
- Dormant: `getCollection`.

### Cross-component akışlar
- ⌘O kısayolu: main menü → `onShortcut('open-repo-selector')` → window CustomEvent → RepoSelector açılır (native'de doğrudan çağrı yeterli).
- FileViewer üç farklı component'ten store üzerinden açılır (tek global modal instance).
- FocusExitControl, TerminalPanel'in `GridLayoutPopup` ve `PersonaDropdown` bileşenlerini paylaşır.
- ToastContainer + useNotificationListener, terminal/tab focus mantığını (restore-then-activate) paylaşır.

---

## Persistence / config

Bu katman doğrudan dosya yazmaz; her şey IPC ile main process'e gider:

- **UIState** (`setUIState`): `openTabs`, `activeTab`, `leftSidebarOpen`, `rightSidebarOpen`, `projectGridLayouts` (repo path → {mode, count}). Tab/sidebar değişiminde senkron, grid'de 500ms debounce. Eski `gridColumns` alanından migration var (yüklemede repo path'lerine dağıtılır).
- **Config** (`setConfig`): `projectsRoot`, `additionalPaths[] {id, path, type: root|repo, label?}`, `aiProvider`, `theme`, `maxTerminals`, `terminalFontSize`, `notifications {unseenEnabled, unseenIntervalMinutes, seenEnabled, seenIntervalMinutes}`. Settings modal'ı "load on open, save on Save" modelini kullanır.
- **Quick Actions**: YAML dosyaları (user-scope global dizin + project-scope repo dizini), history yedekleri `2026-02-11T14-30-00.yaml` formatlı timestamp dosyaları — hepsi main process tarafında; UI sadece ID/timestamp ile konuşur.
- **Session-local (persist edilmeyen)**: RepoSelector `collapsedGroups`, dosya ağacı cache+expand durumu, CommitTree branch expand durumu, changes dosya seçimleri, settings modal taslağı.

---

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **Custom titlebar / drag region**: Header `-webkit-app-region: drag` + platform-conditional padding + Linux custom pencere butonları + çift-tık maximize. macOS native'de NSWindow standart titlebar veya `titlebarAppearsTransparent` + NSToolbar ile çözülür; Linux/Windows dalları tamamen düşer.
2. **Traffic light gizleme** (focus mode): `setTrafficLightVisibility` IPC'si → native'de `NSWindow.standardWindowButton(...).isHidden` doğrudan çağrılır.
3. **IPC köprüsü**: Tüm `window.api.*` çağrıları native'de doğrudan service/manager çağrısına döner; "main = source of truth, sonra syncFromMain" reconcile deseni tek process'te basitleşir ama terminal state'inin UI thread dışında tutulması korunmalı.
4. **Monaco Editor** (FileViewer): native karşılık gerekir — seçenekler: syntax highlight'lı read-only text view (örn. tree-sitter/Highlightr/Runestone) + kendi diff renderer'ı, veya STTextView üzerine custom side-by-side diff. Monaco'nun side-by-side DiffEditor'ı en maliyetli parça.
5. **Framer Motion animasyonları**: spec boyunca süre/easing'leri verildi; SwiftUI `withAnimation`/`transition` ile birebir karşılanabilir. Kalıplar: overlay fade 0.15s + içerik scale 0.95→1 (tüm modal'lar); height-collapse 0.15–0.2s (gruplar/section'lar); slide+fade (header y:-20, toast x:50, focus bar y:-20); spring rozetler (NEW badge, Ready check).
6. **createPortal kullanımları** (RepoSelector dropdown, ContextMenu, action tooltip): native'de NSPopover/NSMenu veya overlay window'lara döner; viewport-clamp mantığı (ContextMenu'nün kenarlardan 8px içeride kalması) NSMenu'da bedava.
7. **HTML5 drag**: dosya ağacından path sürükleme `dataTransfer text/plain` — native'de NSDraggingSource/NSPasteboard (`.string`) ile.
8. **document.visibilitychange / window focus / powerMonitor**: NSApplication didBecomeActive + NSWorkspace didWake notification'larına map edilir.
9. **`alert()`** (focus mode max-terminal uyarısı): NSAlert veya inline uyarıya çevrilmeli.
10. **CustomEvent ile kısayol köprüsü** (`open-repo-selector`): native'de gereksiz dolaylama; doğrudan action çağrısı.
11. **webp Mascot asset'leri ve SVG Logo**: asset katalog + vektör/PNG dönüşümü gerekir.
12. **ErrorBoundary**: React'a özgü; native'de süreç içi hata izolasyonu farklı (do/catch + degraded UI; renderer crash kavramı yok).
13. **Klavye kısayolları**: yarısı Electron Menu accelerator (main process), yarısı renderer keydown. Native'de tamamı NSMenu key equivalents'a taşınmalı (tek kaynak).

---

## Native rewrite notları (riskler ve dikkat edilecekler)

- **Bootstrap sırası korunmalı**: `loadRepos` → `loadUIState` bağımlılığı (migration) ve setup-sonrası aynı dizinin tekrarı. Native'de migration main-side'a taşınırsa UI bu kısıttan kurtulur — önerilir.
- **Terminal reconcile deseni**: Bu UI hiçbir yerde optimistic terminal eklemez; her spawn/kill sonrası snapshot sync bekler. Native'de de "terminal manager tek gerçek kaynak, UI observe eder" kuralı korunmalı; aksi halde sleep/wake ve dış process ölümleri tutarsızlık yaratır.
- **Minimize semantiği UI'nin her yerine sızmış durumda**: session list stili, tab kapatma guard'ı (CloseTabDialog), focus/navigasyonun minimize'ları atlaması, bildirim tıklamasının restore etmesi. Spec'teki bu kuralların hepsi tek bir "visible terminals" soyutlamasından türetilmeli.
- **Tab kapatma yan etkileri**: terminal kill (paralel, hataya dayanıklı) + file tree unwatch + aktif tab fallback'i (son tab) + persist. Atomik olmayan bu dizinin native'de tek transaction benzeri akışta toplanması iyi olur.
- **Dosya ağacı UX detayları kolay kaçar**: stale-while-revalidate (eski ağaç ekranda kalır), scroll pozisyonu restorasyonu, filtre öncesi expand-state snapshot/restore, repo başına cache, root klasörlerin ilk yüklemede auto-expand'i, ignored klasörlerin tıklanamazlığı. Bunlar hissedilen kaliteyi belirleyen davranışlar.
- **Bilinen tutarsızlık (bug, taşımayın)**: FocusExitControl, useKeyboardShortcuts **ve TerminalPanel** ([20](./20-renderer-terminal.md) §15: limit alert'i, "N / 12" sayacı, dropdown disabled durumu) max terminal kontrolünde kullanıcının config'indeki `maxTerminals` yerine `DEFAULT_CONFIG.maxTerminals` sabitini kullanıyor — yani renderer'daki **tüm** limit kontrolleri kullanıcı config'ini yok sayar; gerçek limiti yalnızca main'deki TerminalManager uygular. Native'de gerçek config değeri okunmalı.
- **CollectionProgress dormant**: component var ama mount edilmemiş; 3sn polling + konfeti içerir. Taşıma kararı ürün tarafında verilmeli; taşınacaksa polling yerine event-driven yapılmalı.
- **SessionList "NEW" rozeti dormant**: JSX'i ve CSS'i (`session-item__new-badge`, `sparkle-pulse` animasyonu) mevcut ama `isNew` hiç `true` olmadığı için hiç render edilmez (bkz. §3.1). CollectionProgress ile aynı kapsam kararına bağlı: codename gamification'ı tamamlanırsa canlanır, atılırsa rozet de spec dışı kalmalı.
- **BrowserSlot boş**: implementasyon yok; spec dışı.
- **Settings'in "draft + Save" modeli**: değişiklikler Save'e kadar uygulanmaz (anlık-uygula değil). Native'de macOS konvansiyonu anlık uygulamadır — bilinçli ürün kararı gerekir; mevcut davranış korunacaksa `hasChanges` ve Escape=discard akışı birebir taşınmalı.
- **Relative-time formatlamaları** üç yerde hafif farklı (QuickActions history, BranchSection, ileride toast olabilir) — native'de tek util'e (`RelativeDateTimeFormatter`) toplanmalı.
- **Monaco diff en büyük teknik risk**: side-by-side diff + dil highlight'ı için native kütüphane seçimi erken prototiplenmeli; gerekirse ilk sürümde unified diff'e düşülebilir (UX kararı).
- **Toast auto-dismiss**: 5 sn + progress bar; 50ms timer yerine native'de tek animasyonla (progress'i animate edip completion'da kapatma) çözülmeli.
- **Hover-intent zamanlamaları**: focus bar (üst 50px bölge, 500ms reveal), action tooltip (300ms show / 150ms hide) — bu gecikmeler bilinçli; aynen taşınmalı, dropdown-açıkken-gizleme istisnası unutulmamalı.
- **Klavye kısayolu platform dallanmaları** (mac: Cmd; diğer: Ctrl+Shift) macOS-only rewrite'ta sadeleşir; ShortcutsSection içeriği tek set'e iner.
