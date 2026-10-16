# Terminal Grupları — seçilen projelerin terminalleri tek yüzeyde (plan)

Durum: **plan, implementasyon bekliyor** (2026-10-16). Onaylanınca `docs/decisions.md`'ye karar olarak girer (proje görünümü karar 120'yi aldığı için 121), `docs/design/03-ui-shell.md` §4/§7.3 ve `docs/design/01-terminal-subsystem.md` §3.4 güncellenir.

Kullanıcı isteği: "2 farklı projeye ait terminalleri tek yerde görmek." Bugün iki uç var — tek checkout (repo route'u) ya da hepsi (All Terminals, karar 103). Kullanıcı önerisi: grup Projects altında bir proje gibi görünsün (karar 108 `Other` kalıbı gibi); seçili terminal hangisiyse sağ panel o projeye göre kurulsun.

Bağımlılık: proje görünümü (karar 120 — proje rengi). Gruptaki kartları renk ayırt eder.

## Kullanıcı kararları (2026-10-16)

1. Bağlam kuralı (sağ panel + hızlı komutlar + Files odaktaki kartın checkout'una göre) **All Terminals'a da uygulanır**. Serbest karta odaklanınca sağ panel **açık kalır**, `No project context` yer tutucusu gösterir (ızgara resize olmasın).
2. Grup kart sırası **All Terminals'tan türer, ilk Edit takasında kopyalanıp bağımsızlaşır** (copy-on-first-swap).
3. Oluşturma: **`New Group…` modalı + proje sağ tık menüsünde `New Group with <proje>…` / `Add to Group ▸`**. ⌘-tık çoklu seçim v2.
4. Serbest terminaller (`Other`) v1'de gruba **giremez** (varsayılan, sorulmadı).

## Alternatifler (özet)

- (a) All Terminals'a geçici proje filtresi — ucuz ama her seferinde yeniden kurulur; maximize/Edit/sıra All ile ortak kalır. v2'de aynı `.group` altyapısıyla persist edilmeyen grup olarak gelebilir.
- **(b) Kaydedilen gruplar — seçilen.** Kendi grid/sıra/maximize'ı, `TerminalScope` modeline oturur, proje düzeyi üyelik yeni worktree'leri (karar 115) kendiliğinden alır.
- (c) Terminal pinlenen board — `TerminalID` süreçle ölür, shell'ler kalıcı değil, yeni terminal kendiliğinden girmez.

## Model (LumiKit)

- `TerminalGroupID` (UUID string, `RawRepresentable`), `TerminalGroup { id, name, projectPaths }` — Codable değil, codec'ten geçer (karar 9).
- **Üye birimi projedir:** kökü + tüm checkout'ları (yönetilen workspace + keşfedilen worktree), karar 65'in `projectCheckouts` köprüsünden. Saf `TerminalGroupMembership.checkouts(group:liveProjects:projectCheckouts:) -> Set<String>`; `sidebarProjectPaths`'te olmayan yetim yol okumada atlanır, silinmez (proje geri eklenince gruba döner).
- `TerminalScope.group(TerminalGroupID)`; `repoPath` yalnız `.repo`'da dolu. `contains(repoPath:groupCheckouts:)` — çözücü zorunlu parametre (sessiz `false` tuzağı olmasın). `isMultiCheckout` (`.all` ve `.group`) — kart etiketleri, proje rengi ve bağlam kuralının kapısı.
- `ContentRouteID.terminalGroup(_:)`, `.terminalGroupID`, `.family` (`:`'den önceki kısım); route değeri `"terminalGroup:<uuid>"`. `WorkspaceRoute` enum'una case eklenmez (karar 35); `WorkspaceRoute.terminalScope` `.group` döner.
- Saf `SurfaceRepoContext.resolve` (bağlam kuralı, aşağıda).

## Projects panelinde sanal satır

- `TerminalGroupsSection` Projects listesinin **başında**, gerçek projelerin üstünde (`ProjectsPanel.projectList`'e tek satır, `OtherTerminalsSection` gibi).
- Grup satırı proje satırı gibi: `square.stack` ikonu, ad, üye projelerin renk noktaları (en çok 4 + `+N`), canlı terminal sayısı, aktifken accent kenar çubuğu. **Ada tıklamak gruba geçer**; daraltma yalnız chevron'dadır (proje satırından bilinçli fark).
- Altında üye terminaller mevcut `AgentRow` ile (renk noktası + `Proje / workspace` etiketi + durum ikonu + karar 77 vurgusu). Gerçek projenin altında da göründükleri için bilinçli tekrar.
- **Grup altındaki ajan satırına tıklamak grupta kalır** (`ShellContext.focusAgent(_:preferring: .group(id))` → `NavigationStore.openTerminalSurface(for:preferring:)`: hedef kapsam yolu içeriyorsa route değişmez). Gerçek projenin altındaki satır bugünkü gibi repo route'una gider.
- Grup proje değildir: ⌃1–9'a girmez, `+` (Create Workspace) yok, ⇧⌘W / `Remove from Projects` uygulanmaz. Aramada grup adı ve üye proje adları eşleşir. Daralt durumu oturumluk.

## Kapsam ve geçiş sözleşmesi

- `TerminalListStore.groupCheckouts: ((TerminalGroupID) -> Set<String>)?` (bağlanmamışsa grup boş). Closure @Observable store'ları her çağrıda canlı okur — önbellek yok.
- **`activateSurface` küme kuralına genelleşir:** önceki kapsamın yeni kapsamda olmayan terminalleri arkaya, yeni kapsamın hepsi öne. Bugünkü repo/All özel durumunu aynı sonuçla kapsar.
- **Kritik tuzak:** `setSurfaceState(_, in: nil)` servis kanalında "tümü" demek. `.group` HER ZAMAN terminal başına `setSurfaceState(_, for:)` ile yürür; toplu kanal yalnız `.repo` ve `.all` için. Kapsamdaki minimize kartlara `.minimized` geri yazılır (karar 103 inceleme 2). Testle kilitlenir.
- `neighborScope` / `isSurfaceForeground` aynı çözücüyle genelleşir (grupta odak grup içinde kalır).
- Üyelik değişince, grup aktifse `activateSurface(scope)` yeniden koşar.
- `NavigationStore.restoreRoute`: enjekte `terminalGroupExists` (karar 65 `projectOrder` deseni) — silinmiş grup → `.content(.allTerminals)`.

| Geçiş | Terminal yüzeyi |
|---|---|
| yüzey → `.group(g)` | önceki ∖ g arkaya, g öne (terminal başına), minimize'lar `.minimized` |
| `.group(g)` → All | kimse arkaya alınmaz, hepsi toplu öne |
| `.group(g)` → repo(r) | g ∖ r arkaya, r öne; ertelenmiş `detachView` |
| `.group(g)` → `.group(h)` | g ∖ h arkaya, h öne; ortak kartlar önde kalır |
| yüzey-dışı ⇄ `.group` | mevcut kural (`detachAll` / `refreshAttachedViews`) |

## Bağlam repo'su — sağ panel odaktaki karta göre

- İki kavram: `activeRepoPath` (route projeksiyonu, aynen kalır — ⌘W tab yedeği, ⇧⌘W, checkout vurgusu; yıkıcı eylemler route'a bağlı) ve yeni **`NavigationStore.contextRepoPath`** (sağ panel, dosya izleyici, git/Plastic yüklemesi, top bar'ın "hangi checkout" sorusu).

| Route | `contextRepoPath` |
|---|---|
| `.repo(p)` | `p`, hemen (bugünkü davranış birebir) |
| grup ve All Terminals | odaktaki kartın `repoPath`'i — serbest değilse (`isLooseTerminalPath`) ve kapsamdaysa |
| odak yok | yapışkan: önceki değer kapsamdaysa korunur, yoksa grubun ilk üyesinin `checkoutToOpen`'ı ya da `nil` |
| odak serbest terminalde | `nil` |
| Tasks / Remote / `.none` | `nil` |

- **Karar 108 güvenlik kapısıyla uzlaşma:** izleyici/tarama/git/sağ panel yine TEK repo'ya bağlı; yalnız kaynağı değişir. `onActiveRepoChanged` artık `contextRepoPath` değişiminden ateşlenir (imza ve `RepoFeatureAssembly.wireActiveRepo` aynı). Serbest yol çözücüde elenir (`~` asla izlenmez). Bağlam değişimi repo tab'ı açmaz, `openTabs`'a ve route'a dokunmaz; tek yan etki `lastCheckouts` güncellemesi (kartı odaklamak checkout'u kullanmak sayılır).
- `SurfaceContextTracker` (LumiState, `StoreLifecycle`; `RepoFeatureAssembly` başlatır): `withObservationTracking` ile `activeRoute` + `activeTerminalID` + `meta.repoPath`. Route değişimi hemen uygulanır ve bekleyeni iptal eder; aynı route içinde odak değişimi **200 ms debounce** (enjekte saat), aynı checkout no-op.
- Maliyet gerekçesi: her bağlam değişimi bir repo geçişinin işi — unwatch/watch, `loadFileTree` (karar 28 tavanlı), git `loadAll` (5+ süreç) / Plastic `cm`. Yol anahtarlı cache'ler dönüşte anında çizer. Opsiyonel `RepoContextLoadThrottle` (son 5 sn'de yüklenen checkout'ta git atlanır) ölçümden sonra.
- Sağ panel: `projectTools.isAvailable` → `contextRepoPath != nil` ya da çok-checkout'lu yüzey; serbest odakta yuva açık + `No project context`. Panel başlığına bağlam etiketi (renk noktası + `Proje / workspace`). `presentFile`/`presentDiff`/`presentCommit`/`reveal`/`trash` `contextRepoPath`'i okur.

## Top bar

- **Hızlı komutlar ve Files** bağlam kuralına bağlanır (`QuickCommandTarget.active` → `contextRepoPath`; görünürlük kapısı `contextRepoPath != nil`). Kontrol hedefi taşır: renk noktası + checkout etiketi (`▶ Start App · api`). **Düzeltme şart:** `ShellContext.runQuickCommand` bugün `navigation.openTab(context.path)` çağırıyor — çok-checkout'lu yüzeyde route değişmez, yalnız yeni `NavigationStore.registerOpenTab(_:)` (`openTabs`'a ekler + persist; route ve `onActiveRepoChanged` yok).
- **New <Provider>, grupta:** hedef `contextRepoPath`, yoksa ilk üyenin `checkoutToOpen`'ı, üye yoksa toast. Dropdown'da `Open in` bölümü (karar 108 kalıbı): `Follow focus` (varsayılan) + grubun checkout'ları; satır yalnız hedefi seçer, oturumluk, grup başına (`TerminalGroupStore.spawnTargets`). Etiket hedefi söyler (`New Claude · api / wt`). ⌘T ve focus bar aynı `ShellContext.spawnTerminal(in:)` kapısından. **Spawn sonrası `registerOpenTab(checkout)` şart** — `resumableEntries` yalnız `openTabs`'taki ya da serbest yolları resume eder.
- **New <Provider>, All Terminals'ta:** karar 108 aynen (serbest konum, `~`).
- Grid ayarı, Edit, route başlığı her yüzeyde. Grup route başlığı: grup adı + `⌄` menüsü (`Rename…` / `Edit Group…` / `Delete Group`).

## Layout ve kart sırası

- `maximizedByScope` / `arrangingScope` zaten `TerminalScope` anahtarlı. Grid: `LayoutStore.terminalGroupGridLayouts: [String: GridLayout]?`, yoksa `allTerminalsGridLayout ?? defaultGridLayout`. `LayoutStore.evict(scope:)` grup silinince maximize/Edit/grid'i (persist dahil) düşürür.
- `TerminalListStore.arrangements: [TerminalScope: TerminalArrangement]` (`allArrangement` erişimci kalır). Grup sırası ilk takasa kadar `allArrangement.ordered(members)`; ilk takasta kopyalanır. Takas kapsam içi guard'lı; kopyalanmış gruplar `affectsArrangement` olaylarında üyelerle `pin` edilir; `dropArrangement` silmede.

## Persist (karar 9/34 — yalnız additive)

Sığ merge yüzünden tüm grup anahtarlarında kural: **nil → yazılmaz, bir kez kullanıldıysa boş da yazılır** (`orchestratorWatchedSessions` deseni).

- `config.json` → `terminalGroups: [{id, name, projectPaths}]` (`TerminalGroupCodec` + `AppConfigCodec`). Bozuk girdi atılır, tekrarlanan id'de ilki kazanır. Telefonun `configChanged` tetikleyicisini etkilemez.
- `ui-state.json` → `terminalGroupGridLayouts` (`{id: GridLayout}`), `terminalGroupOrders` (`{id: [resumeKey]}` — yalnız kopyalanmış sıralar; karar 90 checkpoint'iyle yazılır, açılışta resume spawn'larından önce `restoreArrangements`). `activeRoute` yeni değer alabilir: `"terminalGroup:<uuid>"`.
- Eski sürüme dönüş: tanınmayan route `resolve` fallback'iyle Welcome açar; veri bozulmaz.

## Oluşturma / düzenleme / silme

- `ActiveDialog.terminalGroupEditor(TerminalGroupEditorState)` + `OverlayID.terminalGroupEditor`: ad alanı + Projects'in renk noktalı checklist'i, `Save ⌘↩` / `Cancel`. Varsayılan ad `api + web`. Tek projeli grup serbest (bir projenin tüm checkout'ları tek ızgarada — yeni yetenek). Kayıt yetimleri budar; oluşturulan gruba geçilir.
- Giriş: proje sağ tık menüsünde `New Group with <proje>…` + `Add to Group ▸` (`PopoverMenu.Item.submenu`, karar 93); grup satırı sağ tık ve route başlık menüsü: `Rename…` / `Edit Group…` / `Delete Group`. Projects başlığındaki `+` değişmez.
- Silme onaysız (terminallere dokunmaz), toast `Deleted group <ad>`. Tek kapı `ShellContext.deleteTerminalGroup(_:)`: config + aktifse route → All Terminals + `layout.evict(scope:)` + `terminals.dropArrangement(scope)`.

## Kısayollar ve kenar durumlar

- ⌃1–9 projeler (gruplar girmez). ⌘1–9 / ileri-geri grubun görünür sırası. ⌘T grubun hedefi. ⌘W aktif terminal, yoksa grupta no-op. ⇧⌘W grupta no-op. Grup kısayolu v2 (aday ⌃⌥1–9; `AppCommandsTests` ⌘'siz istisnası genişler).
- Proje kaldırılınca: checkout'lar/terminaller bugünkü gibi kapanır, grup tanımı yolu yetim tutar. Üyesi kalmayan grup satırda soluk ve 0; görünüm "This group has no projects" + `Edit Group…`. Üye var terminal yoksa "No terminals in this group" + `ScopedNewTerminalButton(scope:)`.
- Telefon ve orchestrator kapsam dışı (`ProjectTree`, `projects` payload'ı, `OrchestratorWatchList` değişmez). Activity `Open` ve Resource Manager `focusAgent` `preferring` kuralını izler.

## Generic shell uyumu (karar 33)

`RootView` / `PanelHostView` / `HeaderBarView` / `ContentRouterView`'a dokunulmaz.

- Yeni `TerminalGroupsFeatureAssembly` (`BootstrapPhase.config` — route restore'dan önce): `TerminalGroupStore` kurar; `terminals.groupCheckouts`, `navigation.terminalGroupExists`, config observer bağlar; route descriptor (`id: "terminalGroup"`, `makeView` → `TerminalsRouteView(scope: shell.activeTerminalScope)`), başlık toolbar öğesi ve editör overlay'ini kaydeder. `AppComposition`'a 1 satır, `ShellComposition`'da `ShellContext`'e 1 parametre (karar 108 `looseTerminals` deseni).
- **Tasarım değişikliği (onay gerekli):** `ContentRouteRegistry.resolve` önce tam id, sonra `id.family`, sonra `terminals` fallback'i — design/03 §7.3 güncellenir; `:` ayırıcısı rezerve.
- Dokunulan diğer dosyalar: `ProjectsPanel` (section + menü), `TerminalsRouteView` (`scope == .all` → `scope.isMultiCheckout`, grup boş durumları; proje renk Environment'ı da bu kapıyla), `NewTerminalMenu`, `ShellContext`, `ProjectToolsPanel`, `QuickCommandMenu`, `RepoFeatureAssembly` (toolbar/panel `isAvailable` kapıları).

## Fazlar (her biri derlenir, testler yeşil)

1. **LumiKit modeli ve kapsam** — `TerminalGroup*`, `TerminalScope.group`, `ContentRouteID` family, `WorkspaceRoute.terminalScope`, `SurfaceRepoContext.resolve`; exhaustive switch'lerde geçici `.group` dalları. Testler: `TerminalGroupModelTests`, `TerminalScopeTests`, `WorkspaceRouteScopeTests`, `SurfaceRepoContextTests`.
2. **Persist** — `AppConfig.terminalGroups`, `UIState.terminalGroupGridLayouts`/`terminalGroupOrders` + codec'ler. Testler: `TerminalGroupsConfigCodecTests`, `TerminalGroupsUIStateCodecTests`, `ConfigCodecIntegrityTests`; `ConfigGoldenBytesTests` nil'de değişmemeli.
3. **State** — `TerminalGroupStore`; `TerminalListStore` (çözücü, küme farkı `activateSurface`, terminal başına yüzey, `neighborScope`, `arrangements` + copy-on-first-swap); `LayoutStore` (grup grid'i, `evict`); `NavigationStore` (`terminalGroupExists`, `registerOpenTab`, `openTerminalSurface(for:preferring:)`); `WorkspaceBootAssembly` (grup sıraları). Testler: `TerminalGroupScopeTests` (**üye olmayan terminal öne gelmez**), `TerminalGroupStoreTests`, `RouteTransitionTests`, `LayoutStoreTests`, `NavigationStoreTests`, `WorkspaceBootResumeTests`; `AllTerminalsScopeTests` aynen geçmeli.
4. **Bağlam repo'su** — `contextRepoPath` + `setContextRepo`, `onActiveRepoChanged` kaynağı, `SurfaceContextTracker`, sağ panel/hızlı komut/Files kapıları (grup + All Terminals), `runQuickCommand` route düzeltmesi, `No project context` yer tutucusu. Testler: `SurfaceContextTrackerTests` (debounce, hızlı ⌘1–9'da tek yükleme, serbest → unwatch), `RepoFeatureAssembly` köprü testi, `ShellToolbarCompositionTests`.
5. **Kabuk ve UI** — assembly, `ContentRouteRegistry` family, `TerminalGroupsSection`, `TerminalGroupRouteView`, `TerminalGroupEditorView` + `ActiveDialog`, menüler, boş durumlar, `NewTerminalMenu` grup bölümü, başlık menüsü. Testler: `ContentRouteRegistryTests`, `TerminalGroupsShellTests`, `NewTerminalMenuTests`, `ShellToolbarCompositionTests`, lint testleri.
6. **Doküman + manuel doğrulama** — decisions.md, design/03 ve design/01, CLAUDE.md Durum. Elle: tüm yüzey geçişlerinde klavye odağı, grupta Edit/maximize/focus bar, renkli kart ayrımı, bağlam değişiminde Instruments ile süreç sayısı, quit/relaunch'ta grup route'u + sırası + grid'i.

## Riskler

1. `scope.repoPath == nil` = "tümü" tuzağı — terminal başına yol + test.
2. First responder (karar 103 inceleme 1) — tüm geçişler `attachView` odak kurtarmasından geçmeli; manuel test.
3. Bağlam değişimi maliyeti — debounce + cache; Faz 6'da ölçüm.
4. `registerOpenTab` unutulursa grup içinden açılan terminal resume edilmez.
5. `onActiveRepoChanged` kaynağı değişiyor — repo route'unda davranış birebir aynı olmalı; mevcut repo testleri regresyon kalkanı.
6. Odak takipli hedefler şaşırtabilir — etiket + renk noktası zorunlu.
7. Sığ merge — "bir kez kullanıldıysa boş da yaz" kuralı.
8. `TasksPanelItem`/Projects yüksekliği grup sayısıyla büyür — kabul.

## Yan bulgu (kapsam dışı)

Orchestrator `start_terminal` (`OrchestratorToolbox+Actions.swift`) checkout'u `openTabs`'a eklemiyor; tab'ı kapalı checkout'ta açılan ajan quit sonrası resume edilmez. `registerOpenTab` gelince tek satırla düzelir — ayrıca sorulacak.
