# Git / VCS ve Repo Yönetimi (RepoManager)

> Kaynak: `src/main/repo/RepoManager.ts` (tek sınıf, ~480 satır) + `src/main/ipc/handlers/register-repo-git-handlers.ts`.
> Not: `src/main/vcs/` dizini **boş** (placeholder); bu alt sistemin tüm mantığı `src/main/repo/` altındadır.
> Git erişimi `simple-git` (^3.30.0) ile, ignore eşleştirmesi `ignore` paketiyle yapılır. Native rewrite'ta bunların yerine `git` CLI çağrısı veya libgit2 / sistem git'i kullanılabilir.

## Amaç ve sorumluluk

RepoManager, main process'te yaşayan tek bir singleton servistir ve üç sorumluluğu vardır:

1. **Repo keşfi (discovery):** Kullanıcının `projectsRoot` dizinini ve ek path'leri tarayıp dashboard'da listelenecek proje/repo listesini üretmek.
2. **Git operasyonları:** Seçili repo için commit log, branch listesi, working-tree status, staged commit, dosya diff'i ve commit diff'i sağlamak. (Salt okunur ağırlıklı; tek yazma işlemi `add + commit`.)
3. **Dosya sistemi izleme ve file tree:** Root dizinleri ve aktif reponun dosya ağacını `fs.watch` ile izleyip değişiklikleri renderer'a push etmek; `.gitignore` farkındalıklı file tree üretmek.

Renderer tarafındaki tüketiciler: sol sidebar'daki **Project Context** (file tree), sağ sidebar'daki **Commits** (branch/commit ağacı) ve **Changes** (status + commit UI) bölümleri, **FileViewer** modal'ı (view/diff/commit-diff) ve header'daki **RepoSelector**.

**Önemli:** Bu alt sistemde **git worktree desteği YOKTUR**. "Working tree" yalnızca `git status` anlamında kullanılır; çoklu worktree, branch checkout, pull/push, stash gibi işlemler hiç yok. Polling de yoktur — tüm tazeleme FS watcher event'leriyle (push) veya UI etkileşimiyle (pull) tetiklenir.

## Feature envanteri

### 1. Repo keşfi (`listRepos`)

**Davranış:**
- İki kaynaktan dizin toplar: `projectsRoot` (config'ten) ve `additionalPaths` (config'ten, her biri `{ id, path, type: 'root' | 'repo', label? }`).
- Tüm path'lerde `~` ön eki home directory'ye genişletilir (yalnızca baştaki `~`; `~user` formu desteklenmez — `~` kesilip kalan home'a join edilir).
- `type: 'root'` path'ler ve `projectsRoot`: dizinin **birinci seviye** alt dizinleri taranır (recursive değil). Her alt dizin için:
  - Dizin değilse veya adı `.` ile başlıyorsa atlanır.
  - `<dizin>/.git` **var mı** kontrolüyle `isGitRepo: boolean` belirlenir (dosya da dizin de olabilir — sadece existence; yani git submodule/worktree `.git` dosyası da repo sayılır).
  - Sonuç: `{ name: <dizin adı>, path: <mutlak yol>, isGitRepo, source }`. `source`, projectsRoot için literal `'projectsRoot'` string'i, additional root'lar için **genişletilmemiş** orijinal path string'idir.
- `type: 'repo'` path'ler: taranmaz, doğrudan tek repo olarak eklenir (`name = basename`, source = orijinal path).
- **Duplicate koruması:** mutlak path bazlı `Set` ile aynı dizin iki kez listelenmez (önce gelen kazanır; projectsRoot her zaman önce taranır).
- Var olmayan path'ler sessizce atlanır (boş liste / skip).
- **Git reposu olmayan dizinler de listelenir** (`isGitRepo: false`) — kullanıcı bunları da tab olarak açıp terminal çalıştırabilir; sadece git panelleri boş kalır.

**Kullanıcıya görünen etki:** Sol taraftaki repo listesi/RepoSelector. Renderer `groupReposBySource` ile gruplar: önce "Projects Root", sonra additionalPaths sırasına göre root grupları (label = `ap.label || basename(path)`; boş root grupları da başlık olarak gösterilir), en sonda tüm `type:'repo'` girdileri tek "Standalone Repos" grubunda.

**Edge-case'ler:**
- `projectsRoot` yoksa/boşsa repo listesi sadece additionalPaths'ten gelir.
- Sembolik linkler: `withFileTypes` dirent'inde symlink dizin olarak görünmeyebilir (takip edilmez) — native'de aynı davranış korunmalı veya bilinçli karar verilmeli.

### 2. Commit log (`getCommits(repoPath, branch?)`)

**Davranış:**
- Önce local branch listesi alınır; `main` varsa default branch `main`, yoksa `master` varsa `master`, ikisi de yoksa `null`.
- `--max-count=50` her zaman uygulanır.
- **Branch'e özel log mantığı (kritik UX kararı):**
  - `branch` verilmiş, default branch mevcut ve `branch !== defaultBranch` ise: log aralığı `defaultBranch..branch` — yani **yalnızca o branch'e özgü, main'de olmayan commit'ler** gösterilir.
  - `branch` default branch'in kendisiyse veya default branch yoksa: o branch'in tüm geçmişi (50 ile sınırlı).
  - `branch` hiç verilmemişse: HEAD log'u.
- Dönüş: `{ hash, shortHash (ilk 7 karakter), message, author (author_name), date (Date) }` listesi.
- Herhangi bir hata (git repo değil, boş repo, geçersiz branch) → console.error + **boş dizi** döner; UI'ya hata sızdırılmaz.

**Kullanıcıya görünen etki:** Sağ sidebar "Commits" bölümünde branch başına accordion; her commit satırında mesaj, kısa hash, yazar ve relative tarih ("5m ago" / "3h ago" / "2d ago" formatı renderer'da hesaplanır).

**Edge-case:** Feature branch henüz hiç unique commit içermiyorsa boş liste gelir (UI boş accordion gösterir). Detached HEAD durumunda simple-git'in `branchLocal.current` davranışına bağlı.

### 3. Branch listesi (`getBranches(repoPath)`)

- Sadece **local** branch'ler (`git branch` eşdeğeri; remote'lar dahil değil).
- Dönüş: `{ name, isCurrent }[]` — `isCurrent`, summary'deki current branch ile isim eşleşmesi.
- Hata → boş dizi.
- **UI davranışı:** CommitTree'de kullanıcı hiç toggle yapmadıysa **current branch otomatik expand** edilir; toggle yaptıktan sonra kullanıcının seçimi repo bazlı hatırlanır (sadece oturum içi, persist edilmez).

### 4. Working-tree status (`getStatus(repoPath)`)

- `git status` çıktısından düz `FileChange[]` üretilir: sırayla `modified`, `not_added → 'untracked'`, `deleted`, `created → 'added'`, `renamed (to path'i alınır) → 'renamed'`.
- Staged/unstaged ayrımı YAPILMAZ — simple-git'in birleşik listeleri kullanılır. (Native'de `git status --porcelain=v1` parse edilirken aynı sadeleştirme uygulanmalı: index+worktree durumları tek statüye indirgenir. Bir dosya hem staged hem modified ise simple-git onu tek kez listeler.)
- Hata → boş dizi.

**Kullanıcıya görünen etki:** Sağ sidebar "Changes" bölümü: her dosya için tek harfli rozet (M/A/D/R/U + renk class'ı), checkbox, dosya adı (basename gösterilir, tam path tooltip/diff'te).

### 5. Commit oluşturma (`commit(repoPath, files[], message)`)

- `git add <files>` ardından `git commit -m <message>`. Dönüş `{ success: boolean, error?: string }` (hata `String(error)` olarak).
- **Renderer akışı (ChangesSection + useRepoStore):**
  - Status yüklendiğinde **tüm değişen dosyalar otomatik seçili** başlar (select-all default).
  - Checkbox'larla tekil toggle, "Select All / Deselect All" toggle butonu, `seçili/toplam` sayacı.
  - Commit butonu yalnızca: en az 1 dosya seçili **ve** mesaj trim'lenmiş halde boş değil **ve** commit devam etmiyorken aktif.
  - Cmd/Ctrl+Enter kısayolu commit tetikler.
  - Başarıda: mesaj alanı temizlenir, status yeniden yüklenir, tüm branch commit'leri yeniden yüklenir.
  - Hiç dosya seçilmemişse main'e gitmeden `{ success: false, error: 'No files selected' }` döner.

**Edge-case'ler:** Silinmiş dosyalar için `git add <silinen-dosya>` modern git'te silmeyi stage'ler — bu davranışa güvenilir. Commit hook'ları başarısız olursa error string UI'ya düşer. Yazar bilgisi kullanıcının global git config'inden gelir; uygulama hiçbir git identity yönetimi yapmaz.

### 6. Working-tree dosya diff'i (`getFileDiff(repoPath, filePath)`)

- `original` = `git show HEAD:<filePath>` (hata olursa — dosya untracked ise — boş string).
- `modified` = dosyanın diskteki güncel içeriği (`utf-8` okuma).
- Dönüş `{ original, modified }`; diff hesaplama main'de YAPILMAZ, iki tam içerik renderer'a gönderilir ve FileViewer modal'ı side-by-side/inline diff'i kendisi render eder.
- **Edge-case:** Silinmiş dosya için `readFileSync` fırlatır → IPC üzerinden hata renderer'a düşer, renderer console.error ile yutar (modal açılmaz). Binary dosyalar için anlamsız içerik döner (binary tespiti yok). Bu çağrıda path-traversal koruması YOK (readFile'dakinin aksine) — native'de eklenmesi önerilir.

### 7. Commit diff'i (`getCommitDiff(repoPath, commitHash)`)

- `git diff-tree --no-commit-id -r --name-status <hash>` ile commit'in dosya listesi alınır (satır formatı `STATUS\tpath`; path'te tab olabilir diye split sonrası geri join edilir).
- Her dosya için:
  - `status !== 'A'` ise `original = git show <hash>~1:<path>` (hata → boş string; ilk commit'te parent yoktur, tüm original'ler boş kalır).
  - `status !== 'D'` ise `modified = git show <hash>:<path>` (hata → boş string).
- Status haritalama: `M→modified`, `A→added`, `D→deleted`, `R→renamed`, diğerleri ham harf olarak geçer (örn. `R100` gibi skorlu rename'lerde sadece `R` ile başlamayan tam eşleşme arandığından `R100` ham geçebilir — dikkat).
- Dönüş `CommitDiffFile[] = { path, status, original, modified }[]`. Tüm dosyaların **tam içerikleri** tek IPC cevabında taşınır.
- **Performans riski:** Büyük commit'lerde (çok dosya / büyük dosyalar) bu çağrı yavaş ve bellek yoğun olur; dosya başına 2 ayrı `git show` process'i seri çalışır. Native'de lazy-load (dosyaya tıklayınca içerik çek) düşünülmeli.

**Kullanıcıya görünen etki:** Commits panelinde bir commit'e tıklayınca FileViewer modal'ı `commit-diff` modunda açılır, commit'teki dosyalar arasında gezilebilir.

### 8. Dosya okuma (`readFile(repoPath, filePath)`)

- `path.resolve` ile mutlak yol hesaplanır; **path-traversal koruması**: çözülen yol repo kökünün içinde değilse (`startsWith(repoKök + sep)` veya köke eşit değilse) `'File path is outside repository'` hatası fırlatılır.
- İçerik `utf-8` string olarak döner. Boyut sınırı veya binary kontrolü YOK.
- Kullanım: file tree'de dosyaya tıklanınca FileViewer `view` modunda açılır.

### 9. File tree üretimi (`getFileTree(repoPath)`) — commit f4467ac davranışı dahil

**Davranış:**
- Repo kökünden recursive dizin taraması yapıp `FileTreeNode[]` ağacı üretir: `{ name, path (repo-köküne göre, '/' ayraçlı), type: 'file' | 'folder', children?, ignored? }`.
- **Ignore filtresi:** `ignore` paketiyle iki katman:
  1. Hardcoded default exclude listesi: `.git`, `node_modules`, `dist`, `build`, `.DS_Store`, `*.log`, `.env`, `.env.*`, `coverage`, `.next`, `.nuxt`, `.cache`, `__pycache__`, `.pytest_cache`, `venv`, `.venv`.
  2. Repo kökündeki `.gitignore` içeriği (varsa; okuma hatası sessizce yutulur). **Yalnızca kök `.gitignore`** okunur — alt dizinlerdeki `.gitignore`'lar, `.git/info/exclude` ve global gitignore DİKKATE ALINMAZ.
- **Kritik (f4467ac):** Ignored girdiler ağaçtan **çıkarılmaz**; `ignored: true` flag'iyle dahil edilir. İstisna: `.git` her zaman tamamen gizlenir.
- Ignored **klasörlerin içine girilmez** (`children: []`) — node_modules gibi dev dizinlerde performans için. Dizin eşleştirmesi `path + '/'` (sondaki slash) ile yapılır ki dizin-spesifik gitignore kuralları doğru çalışsın.
- Okunamayan dizinler (izin hatası vb.) boş children olarak sessizce geçilir.
- **Sıralama (her seviyede):** 1) klasörler dosyalardan önce, 2) her grup içinde ignored OLMAYANLAR ignored olanlardan önce, 3) alfabetik (`localeCompare`).
- Derinlik/eleman sayısı sınırı YOK — kökten gerçekten devasa, gitignore'lanmamış ağaçlar tamamen taranır.

**Kullanıcıya görünen etki (ProjectContext):**
- Sol sidebar'da ağaç görünümü; ignored öğeler soluk (faded) CSS class'ı ile gösterilir ve ignored klasörler **expand edilemez** (tıklama no-op).
- İlk yüklemede reponun **kök seviyesindeki klasörler otomatik expand** edilir (repo başına yalnızca ilk kez).
- Repo başına tree cache + expand-state Map'leri oturum içinde tutulur (persist edilmez); tab değişiminde anında cache'ten gösterilir.
- Arama kutusuyla isim bazlı filtre: eşleşen dosyalar + (kendisi veya altında eşleşme olan) klasörler gösterilir; klasör adı eşleşip altında eşleşme yoksa tüm children korunur.
- Sağ-tık context menüsü: **Delete** (yalnızca dosyalar; `shell.trashItem` ile çöp kutusuna — kalıcı silme değil; sonra tree yeniden çekilir, hata sessizce yutulur), **Copy Path** (relative path clipboard'a), **Reveal in Finder/File Explorer/File Manager** (`shell.showItemInFolder`).
- Tree node'ları `draggable`: drag başlangıcında relative path `text/plain` olarak set edilir (terminale dosya yolu sürükleme için).
- Watcher event'iyle tazeleme **stale-while-revalidate**: eski ağaç ekranda kalır, yeni veri gelince değişir; scroll pozisyonu güncellemeden önce kaydedilip `useLayoutEffect` ile geri yüklenir.

### 10. Düz dosya listesi (`getFiles(repoPath)`) — legacy

- Recursive tarama; `.` ile başlayanlar ve `node_modules` atlanır; klasörler `path/` (sonda slash) olarak listelenir; sonuç **ilk 100 girdiyle** kırpılır.
- IPC kanalı (`repos:files`) ve preload metodu (`getRepoFiles`) mevcut ama **renderer'da hiçbir çağıran yok** — ölü/legacy API. Native rewrite'a taşınması GEREKMEZ.

### 11. Root dizin izleme (repo listesi tazelemesi)

**Davranış:**
- `projectsRoot` + tüm `type:'root'` additionalPath'ler için ayrı `fs.watch` watcher'ları (recursive DEĞİL — sadece birinci seviye; yeni repo eklendi/silindi tespiti için yeterli).
- Watcher key'leri `__root__` (projectsRoot) ve `__root_<id>` (additional) prefix'iyle, repo file-tree watcher'larıyla aynı Map'te ayrışır.
- Herhangi bir event → key bazlı **300ms debounce** → `onReposChange` callback → main, renderer'a `REPOS_CHANGED` push eder.
- Renderer (`Layout`) `REPOS_CHANGED` alınca `loadRepos()` + `loadAdditionalPaths()` çağırır → liste tazelenir.
- `setProjectsRoot` / `setAdditionalPaths` çağrıldığında (Settings'ten config değişince) tüm root watcher'ları kapatılıp yeniden kurulur; ayrıca config handler'ı kendisi de bir kez `REPOS_CHANGED` emit eder.
- Var olmayan dizin için watcher kurulmaz; kurulum ve runtime hataları console.error ile yutulur (crash yok).

### 12. Repo file-tree izleme (`watchRepoFileTree` / `unwatchRepoFileTree`)

**Davranış:**
- Renderer'da aktif repo değiştikçe: yeni aktif repo için `watch`, eskisi için `unwatch` IPC çağrısı yapılır → **aynı anda tipik olarak tek repo izlenir** (React effect cleanup sırası nedeniyle kısa süreli çakışmalar olabilir; `watchRepoFileTree` başlarken aynı path'in eski watcher'ını kapattığından idempotent'tir).
- `fs.watch(path, { recursive: true })` — macOS'ta FSEvents tabanlı, recursive desteklenir.
- Event → repo path bazlı **500ms debounce** → `onFileTreeChange(repoPath)` → renderer'a `FILE_TREE_CHANGED(repoPath)` push.
- **İki ayrı renderer tüketicisi aynı event'i dinler:**
  1. ProjectContext: file tree'yi yeniden çeker (stale-while-revalidate).
  2. RightSidebar: event'in path'i aktif repoya aitse `git status` + branch'ler + tüm branch commit'leri yeniden yüklenir. **Yani git panellerinin "canlı" görünmesi tamamen bu FS watcher'a bağlıdır** — `.git` dizini de izlendiğinden commit/checkout işlemleri de (`.git` içi dosya değişimleri yoluyla) tetikler.
- Polling YOK; watcher kaçırırsa (ör. network drive) UI bayatlar, kullanıcı tab değiştirip dönerek tazeleyebilir.

### 13. Yaşam döngüsü (`dispose`)

- Tüm watcher'lar kapatılır, tüm debounce timer'ları temizlenir, callback referansları null'lanır.
- Çağrılma noktaları (`src/main/index.ts`): pencere kapanması/uygulama çıkışı akışlarında 3 ayrı yerde `getRepoManager()?.dispose()`.

## Veri akışı ve bağımlılıklar

```
ConfigManager (config.json: projectsRoot, additionalPaths)
        │ ctor + CONFIG_SET side-effect (setProjectsRoot / setAdditionalPaths)
        ▼
   RepoManager (main, singleton; handlers.ts'te kurulur)
        │  fs.watch (root'lar, aktif repo recursive)
        │  simple-git (repo başına on-demand instance, cache yok)
        ▼
  IPC push:  REPOS_CHANGED ()  /  FILE_TREE_CHANGED (repoPath)   [safeSend ile, window null-guard'lı]
  IPC invoke (renderer → main):
    repos:list, repos:files(legacy), repos:file-tree,
    repos:watch-file-tree, repos:unwatch-file-tree,
    git:commits(repoPath, branch?), git:branches, git:status,
    git:commit(repoPath, files[], message), git:read-file,
    git:file-diff, git:commit-diff,
    context:delete-file (shell.trashItem), context:reveal-in-file-manager (shell.showItemInFolder)
        ▼
  preload (contextBridge 'api'): getRepos, getFileTree, watch/unwatchFileTree,
    onReposChanged, onFileTreeChanged, getCommits, getBranches, getStatus,
    commitFiles, readFile, getFileDiff, getCommitDiff, deleteFile, revealInFileManager
        ▼
  Renderer:
    useRepoStore (Zustand): repos, branches(Map), commits(Map<repo, Map<branch, Commit[]>>),
      changes(Map), selectedFiles(Map<repo, Set>), groupReposBySource()
    Layout (REPOS_CHANGED aboneliği, ilk yükleme), RepoSelector,
    ProjectContext (file tree), RightSidebar/CommitTree/BranchSection/ChangesSection/FileChangeItem,
    FileViewerModal (view / diff / commit-diff modları)
```

- Dış process: yalnızca `simple-git`'in spawn ettiği `git` binary'si (kullanıcının PATH'indeki git). Her metod çağrısında `simpleGit(repoPath)` yeniden oluşturulur — instance cache'i yoktur.
- Context menü işlemleri (delete/reveal) RepoManager'a değil doğrudan Electron `shell` API'sine gider ama aynı handler dosyasında kayıtlıdır; mantıksal olarak bu alt sisteme dahildir. **Dikkat:** `CONTEXT_DELETE_FILE`'da path-traversal koruması yok (`path.join(repoPath, relativePath)` doğrudan).

## Persistence / config

- RepoManager **kendisi hiçbir şey persist etmez.** Tüm kalıcı girdi config'ten gelir:
  - `~/.lumi/config.json` (dev'de `~/.lumi-dev`, Windows'ta `%APPDATA%\lumi`; eski `.pulpo` / `.ai-orchestrator` dizinlerine geriye dönük fallback var) içindeki:
    - `projectsRoot: string` (örn. `~/projects`; `~` destekli)
    - `additionalPaths: AdditionalPath[]` = `{ id: string, path: string, type: 'root' | 'repo', label?: string }[]`
- Oturum içi (RAM) state: renderer'daki tree cache, expand state'leri, branch accordion state'i, seçili dosya set'leri — hiçbiri diske yazılmaz; uygulama yeniden açılınca sıfırlanır.
- Git tarafında yapılan tek kalıcı değişiklik kullanıcının kendi reposundaki `git add` + `git commit`'tir.

## Electron'a özgü kısımlar

1. **IPC mimarisi:** invoke/handle (request-response) + webContents.send (push). Native Swift'te bunlar doğrudan fonksiyon çağrısı / Combine-NotificationCenter-delegate'e dönüşür; `REPOS_CHANGED` ve `FILE_TREE_CHANGED` push event'leri observable/publisher olur. `safeSend`'in "window yok/destroyed ise gönderme" guard'ına gerek kalmaz.
2. **`fs.watch`:** Node'un watcher'ı macOS'ta FSEvents sarmalar. Native'de doğrudan **FSEvents** (veya `DispatchSource.makeFileSystemObjectSource`) kullanılır; recursive izleme FSEvents'te doğaldır. Debounce süreleri (root 300ms, file tree 500ms) korunmalı — FSEvents zaten latency parametresiyle coalescing sunar.
3. **`simple-git`:** Node child-process sarmalayıcısı. Native seçenekler: (a) `Process` ile `git` CLI çağırıp porcelain çıktıları parse etmek (en birebir; `git status --porcelain`, `git log --format=...`, `git show`, `git diff-tree` zaten kullanılan komutlara denk düşer), (b) libgit2 (SwiftGit2). CLI yaklaşımı, kullanıcının git config/hook/credential dünyasıyla otomatik uyumlu olduğundan önerilir; Lumi zaten kullanıcının sistem git'ine bel bağlıyor.
4. **`ignore` npm paketi:** Tam gitignore spec'i uygular (negation `!`, `**`, dizin kuralları). Native'de elle yazmak hataya açık; alternatif: ignored tespitini `git check-ignore --stdin` veya `git status --ignored` / `git ls-files -o -i --exclude-standard` ile git'in kendisine yaptırmak — bu, mevcut implementasyonun yapmadığı nested `.gitignore` ve global ignore desteğini de bedavaya getirir (davranış kasıtlı olarak iyileşir; spec farkı olarak not edilmeli). Hardcoded default exclude listesi her durumda korunmalı (git reposu olmayan dizinler için tek filtre bu).
5. **`shell.trashItem` / `shell.showItemInFolder`:** macOS'ta `FileManager.trashItem(at:)` ve `NSWorkspace.activateFileViewerSelecting(_:)` birebir karşılıklar.
6. **Renderer'a tam içerik taşıma:** Electron'da diff içerikleri IPC ile serialize edilip ayrı process'e taşınıyor. Native tek process'te bu maliyet kalkar; ama UI thread'i bloklamamak için git çağrıları background queue'da çalıştırılmalı (mevcut yapıda Node main thread'i de `readFileSync`/`readdirSync` ile bloklanıyor — native'de düzeltilmeli).

## Native rewrite notları (riskler, dikkat edilecekler)

- **`defaultBranch..branch` log semantiği** bu alt sistemin en kolay gözden kaçacak davranışı: branch accordion'larında feature branch'ler yalnızca kendine özgü commit'leri gösterir. Birebir taşınmalı (`git log main..feature --max-count=50`).
- **Status sadeleştirmesi:** staged/unstaged ayrımı yok, tek düz liste; rename'lerde `to` path'i kullanılır. Porcelain parse ederken index+worktree kodlarını tek statüye indirgeyin ve aynı statü etiketlerini (`modified/added/deleted/renamed/untracked`) üretin.
- **Hata stratejisi "boş ve sessiz":** Read-only git operasyonları hata durumunda boş koleksiyon döner; yalnızca `commit` hatayı kullanıcıya taşır (`{success:false, error}`), `readFile`/`getFileDiff`/`getCommitDiff` hataları renderer'da console'a yutulur. UI hiçbir git hatası göstermez. Native'de aynı toleransı koruyun (git reposu olmayan dizinler de açılabildiği için bu çağrılar rutin olarak başarısız olur) — ama loglama ekleyin.
- **File tree ölçek riski:** Sınırsız recursive senkron tarama. Çok büyük, gitignore'suz repolarda hem yavaşlar hem bellek tüketir. Native'de async/lazy üretim, gerekirse derinlik-on-demand (klasör expand edilince çocukları üret) düşünün; ancak mevcut "tek seferde tüm ağaç + cache + arama filtresi" UX'i tüm ağacın bellekte olmasına dayanır.
- **`getCommitDiff` N+1 problemi:** dosya başına 2 ayrı seri `git show`. Büyük commit'te saniyeler sürebilir. Native'de tek `git show`/`git diff` çağrısıyla batch almak veya dosya seçilince lazy yüklemek daha doğru; UI sözleşmesi (tüm dosyalar + içerikler hazır) değişirse FileViewer'ın commit-diff modu da uyarlanmalı.
- **Watcher tabanlı git tazeleme kırılgan:** Commits/Changes panellerinin güncelliği, aktif reponun recursive FS watcher'ının `.git` değişimlerini yakalamasına bağlı. FSEvents `.git` içi değişimleri görür ama yoğun git işlemlerinde event fırtınası olur — 500ms debounce'u koruyun. Watcher'ın hiç kurulamadığı durumda (izin, ağ diski) fallback olarak app-foreground'da tazeleme eklemek değerli bir iyileştirme.
- **Path-traversal tutarsızlığı (mevcut bug/eksik):** `readFile` korumalı; `getFileDiff`'in `readFileSync`'i ve `CONTEXT_DELETE_FILE`/`REVEAL` korumasız. Native'de tüm "repo + relative path" alan API'lere aynı kök-içi doğrulaması uygulanmalı.
- **`R100` benzeri skorlu rename statüleri** `getCommitDiff`'te ham string olarak geçer (UI bilinmeyen statüde harfi olduğu gibi basar). Native parse'ta `R*`/`C*` prefix'lerini normalize etmek temizlik fırsatı.
- **`source` alanı sözleşmesi:** Renderer gruplaması `repo.source`'un, additionalPath'in **genişletilmemiş orijinal path string'iyle** birebir eşit olmasına dayanır (`'projectsRoot'` literal'i hariç). Bu string eşleşmesi korunmalı veya grup anahtarı id tabanlı hale getirilmeli.
- **Taşınmayacaklar:** `getFiles` (repos:files) ölü API; `src/main/vcs/` boş dizin. Worktree/checkout/pull/push/stash hiç yok — kapsam dışı tutun, "eksik" sanıp eklemeyin (YAGNI).
- **Tarih serileştirme:** `Commit.date` IPC'de Date → ISO string'e serialize olur; renderer `new Date(date)` ile tekrar parse eder. Native'de doğrudan `Date` taşınır, sorun kalkar; relative-time formatlaması ("Xm/Xh/Xd ago") UI katmanında kalmalı.
