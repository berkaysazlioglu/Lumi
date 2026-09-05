# Lumi — Temel Sağlamlaştırma ve Generic Shell Fix Planı (2026-09-04)

Bu plan, 7 paralel mimari denetimin (UI kabuğu, State, Composition root/DI, Services+Kit, Terminal alt sistemi, SwiftUI içerik view'ları, proje sağlığı) bulgularından derlendi. Amaç: büyük güncellemeler öncesi temeli SOLID'e oturtmak ve left/right/top/center alanlarını generic (slot/route/toolbar-descriptor tabanlı) hale getirmek.

Durum özeti (plan yazıldığında): build temiz (1 uyarı), 474/474 test yeşil, modül grafiği CLAUDE.md ile uyumlu, katman ihlali yok. **(Plan tamamlandığında: build temiz, 1191/1191 test yeşil.)** Temel sağlam; sorun **kompozisyon esnekliğinin sıfır olması** ve orkestrasyon katmanlarının (RootView, AppContainer, AppDelegate, WorkspaceStore, TerminalSession) god-object'e dönüşmesi.

Kanıt sayısı: bugün "Tasks görünümü + servis + store" eklemek ≈ **11 dosya / 19-20 dokunuş**. Hedef: **4-5 dosya / 3 kayıt satırı**.

---

## 0. Bağlayıcı kayıt kararları — ✅ onaylandı / uygulandı (K33–K38, 2026-09-04/05)

CLAUDE.md gereği `docs/design/` ve `docs/decisions.md` bağlayıcı. Aşağıdakiler ONAY olmadan yapılmazdı; **hepsi 2026-09-04'te onaylandı ve uygulandı** — kalıcı kayıt [decisions.md](./decisions.md) karar 33–38'dedir (K33→33, K34→34, K35→35, K36→36, K37→37, K38→38).

| # | Karar | Etkilenen doküman |
|---|---|---|
| K33 | Generic shell kompozisyonu: `PanelSlot`/`PanelItemDescriptor`, `ContentRoute`, `ToolbarItemDescriptor`, `ShellContext` Environment enjeksiyonu | `03-ui-shell.md` yeni §7; `00-architecture.md` §2 LumiUI public yüzeyi + §3 |
| K34 | `UIState`'e additive alanlar (`panelLayout`, `visibleSlots`, `activeRoute`); `leftSidebarOpen`/`rightSidebarOpen`/`activeTab` okunup yazılmaya devam eder (karar 9 korunur) | `decisions.md`, `ConfigServiceTests` golden dosyaları |
| K35 | `WorkspaceStore` → `NavigationStore` + `LayoutStore` + `DialogRouter`; store tablosu 11 store'a güncellenir | `03-ui-shell.md` §4 |
| K36 | `FeatureAssembly` + `ServiceRegistry` composition kalıbı; `MainWindowController`/`MenuActionDispatcher` gerçekten çıkarılır (tasarımda zaten var, kodda yok) | `00-architecture.md` §3 |
| K37 | `TerminalSurfaceState` (foreground/background/minimized) + `TerminalViewProviding` genişlemesi (`isAttached`, `refreshAttachedViews`, `detachAll`) | `01-terminal-subsystem.md`, `TerminalServicing` |
| K38 | Usage aralık seti: kod {1,5} dk vs tasarım {5,15,30} + "≥5 dk TTL cache" — hangisi geçerli? **Karar: seçenek A** — {5,15,30}, default 5, legacy `1` → 5 clamp, `CachingUsageService` 300 sn TTL | `05-usage-indicator.md` |
| Doküman drift | Prompt Queue tasarımda yok (canlı özellik); `TerminalInputGate` tasarımda yok; `Lumi.xcodeproj`/`Yams`/`Debouncer`/`LumiKitTestSupport` tasarımda var kodda yok; `02-services.md §9` LumiError bloğu bayat; `03 §2` kısayol listesi eksik (Cmd+Ctrl+M) | ilgili dosyalar |

---

## Faz 1 — Acil hata düzeltmeleri (davranış korunur, 1-2 gün) — ✅ tamamlandı (commit `11339a8`, 2026-09-04)

Refactor'dan bağımsız, hemen yapılmalı. Her madde için önce kırmızı test.

| # | Şiddet | Bulgu | Yer | Fix |
|---|---|---|---|---|
| 1.1 | **KRİTİK** | Backpressure kayıp-uyanma: `.suspend` dönüşü ile `suspendReading()` arası pencerede MainActor `resumeReading()` çağırır, `readSuspended==false` → no-op; sonra suspend → **terminal kalıcı donar** | `PTYProcess.swift:148-184`, `FlowController.swift:30-51`, `TerminalSession.swift:125-132` | `PTYProcess`'e `resumeRequested` bayrağı: `resumeReading` suspend değilse bayrağı set eder; `suspendReading` bayrak set ise suspend'i iptal eder. Test: `BackpressureRaceTests` (noteConsumed'ı pencereye enjekte eden double) |
| 1.2 | **KRİTİK** | Notifications sekmesi body-anı snapshot'ına yazıyor → ayar clobber'ı | `SettingsView.swift:371-418` | `SettingsStore.updateNotifications(_ mutate:)` (taze okur); `updateTrigger`/`updateUsageAutoRefresh` de store'a taşınır. Test: iki ardışık alan değişimi birbirini ezmez |
| 1.3 | **KRİTİK** | Diff/markdown modeli `GeometryReader` altında her body'de yeniden parse | `FileViewerView.swift:14,133,152`, `SideBySideDiffView.swift:14` | Modeli `FileViewerStore.renderedModel`'e taşı (içerik değişince bir kez); view hazır modeli alır |
| 1.4 | YÜKSEK | `cleanupIO` kilit dışı `readSource/writeSource` mutasyonu; MainActor kilit altında okuyor → veri yarışı, kapanışta crash riski | `PTYProcess.swift:343-368` | Referansları kilit altında yerel değişkene al ve nil'le; cancel'ı kilit dışında yap. `cleanedUp` okumasını da (`:197`) kilit altına al |
| 1.5 | YÜKSEK | `statusMachine.onExit(code:)` hiç çağrılmıyor; exit-cleanup sırası (01 §6) uygulanmıyor; exit code yok sayılıyor | `TerminalSession.swift:151-158`, `TerminalPipeline.swift:145-149`, `TerminalListStore.swift:191` | `TerminalPipeline.finishExit(code:)` (silenceTimer.cancel → oscParser.reset → statusMachine.onExit); `TerminalListStore.apply(.exited)` code≠0 ve ≠SIGHUP ise toast. Test: `TerminalSessionExitOrderTests` |
| 1.6 | YÜKSEK | `GitService.commit` hata yolunda `git add` ikinci kez koşuyor | `GitService.swift:148-154` | `addOutput?.stderr ?? "timeout"` kullan. Test: commit hata yolu |
| 1.7 | YÜKSEK | `CodexAppServerProbe.awaitResponse` iptali `try?` ile yutuyor → 30 sn busy-loop | `CodexAppServerProbe.swift:124-135` | `try Task.checkCancellation()` + `withTaskCancellationHandler { onCancel: session.shutdown() }`; `shutdown` sonrası `waitUntilExit` |
| 1.8 | YÜKSEK | Claude OAuth yolunda tüm hatalar tek `try?`; 5xx → kotadan düşen CLI fallback | `ClaudeUsageService.swift:41-57` | Yalnız token-yok/401 → CLI; transport/5xx → log + `.usageUnavailable`; 1 retry+jitter. Test: URLProtocol stub ile 4 yol |
| 1.9 | YÜKSEK | `GitStore.loadAll` branch başına sınırsız paralel git (N branch → 2N process), her FSEvents'te | `GitStore.swift:42-57`, `GitService.swift:55` | TaskGroup eşzamanlılık sınırı (K≈4); `defaultBranch` bir kez hesaplanıp geçilir; `refresh()` yalnız changes + current branch |
| 1.10 | YÜKSEK | CI yalnız cron + manuel; push/PR test kapısı yok | `.github/workflows/ci.yml:2-5` | `push: main` + `pull_request` tetikleyicileri |
| 1.11 | ORTA | `ProcessRunner` timeout/launch-failure yolunda DispatchGroup `leave` eksik → process sızıntısı; iptal desteği yok | `ProcessRunner.swift:144-170` | Kalan enter'ları leave et; `withTaskCancellationHandler` → `terminate()` |
| 1.12 | ORTA | Path-traversal guard symlink çözmüyor | `GitService.swift:309-317` | İki tarafı `resolvingSymlinksInPath()`; symlink testi |
| 1.13 | ORTA | Bozuk config → ilk yazımda bilinmeyen anahtarlar kaybolur (karar 9 ihlali), hata yalnız console'a | `ConfigService.swift:33-43,110-118` | Parse hatasında `.bak`'a taşı + `ConfigEvent`/toast; ui-state yazım hatası da event |
| 1.14 | ORTA | `PromptQueueStore.injectHead` `catch {}` — karar 5 ihlali | `PromptQueueStore.swift:156-165` | `ToastStore` enjekte; N. ardışık hatada bir kez toast |
| 1.15 | ORTA | PTY `drainWrites` EPIPE sessiz; ölü terminale yazım sessiz | `PTYProcess.swift:212-219`, `TerminalSession.swift:182-189` | `onWriteFailure` → `TerminalEvent.writeFailed` → toast |
| 1.16 | ORTA | `SettingsStore.apply` optimistik güncelleme diskle uzlaşmıyor | `SettingsStore.swift:44-53` | `apply` sonunda `refresh()` veya `updateConfig` yeni değeri döndürsün |
| 1.17 | ORTA | `WorkspaceStore.persist()` sırasız Task'lar → bayat snapshot yazımı | `WorkspaceStore.swift:256-271` | Tek `pendingPersistTask` (cancel + yeniden kur) veya version sayacı |
| 1.18 | ORTA | Store `for await` döngüleri `self?` ile hiç sonlanmıyor; `shutdown()` store'ların yarısını durdurmuyor; `bridgeTasks` sınırsız büyür; `configCoordinator.stop()` çağrılmaz | `TerminalListStore:42`, `PromptQueueStore:37`, `RepoStore:29`, `SettingsStore:24`, `AppContainer:159-170,299-316` | `guard let self else { return }`; tek-atımlı Task'ları ayrı değişkende tut (öncekini iptal); `shutdown` simetrisi (Faz 3'te `StoreLifecycle` ile kalıcı çözüm) |
| 1.19 | ORTA | `EventBroadcaster` unbounded; tasarım `.bufferingNewest` sınırlı diyor; `outputStream` ölü seam | `EventBroadcaster.swift:13-23`, `TerminalServicing.swift:31` | YAGNI: `outputStream`/`onOutputText` kaldır; ya da `bufferingPolicy` parametresi + `.bufferingNewest(64)` |
| 1.20 | ORTA | `ImagePreviewView` body'de `NSImage(data:)` decode | `ImagePreviewView.swift:45,71-77` | Decode + caption'ı `FileViewerStore.presentImage`'a taşı |
| 1.21 | DÜŞÜK | Tek derleme uyarısı (gereksiz `await`) | `ConfigService.swift:88` | Kaldır; `-warnings-as-errors` politikası düşün |
| 1.22 | DÜŞÜK | Ölü kod: `LumiError.yamlInvalid`, `.notificationPermissionDenied`, `LumiServicesModule`, `ToastStore.clearAll`, `RepoStore.isNodeExpanded`, `ConfigSideEffectCoordinator.terminal` (kullanılmayan bağımlılık), `TerminalSessionManager.keyMonitor/mouseMonitor` alanları | ilgili dosyalar | Sil |
| 1.23 | DÜŞÜK | `PTYChildRegistry` kapasite 128, taşma sessiz (karar 29 sonrası limit yok) | `PTYChildRegistry.swift:9,44-51` | 512 + log |
| 1.24 | DÜŞÜK | Sıcak yolda `lowercased()` kopyası ve her tuşta regex derleme | `ProviderInferencer.swift:9-26`, `OSCStreamParser.swift:150-167` | Hint belirlenince erken çıkış; `.caseInsensitive` range; `static let` regex cache |

---

## Faz 2 — Test altyapısı ve karakterizasyon (refactor güvenlik ağı, 2-3 gün) — ✅ tamamlandı (commit `e598836`, 2026-09-04)

Refactor'a başlamadan önce mevcut davranışı kilitle.

| # | İş | Detay |
|---|---|---|
| 2.1 | `LumiTestSupport` target'ı | Tasarımın öngördüğü paylaşılan fake target'ı. Mevcut 6 fake (`FakeTerminalService`, `FakeGitService`, `FakeUsageService`, `FakeActivityMonitor`, `FakeSessionStarter`, `FakeConfigService`) taşınır; eksikler eklenir: `FakeRepoService`, `FakeSystemService`, `FakeNotificationService`, `FakeTerminalViewProvider`, `FakeProcessRunner` |
| 2.2 | `LumiAppTests` target'ı | `LumiApp`'ı library + ince `main` executable'a böl. İlk testler: `ConfigSideEffectCoordinator` 8 diff kuralı (karar 11 regresyon kalkanı), `MainMenuBuilder` kısayol tablosu, `TrafficLightLayout` geometrisi, bootstrap sırası sözleşmesi |
| 2.3 | Ek A zorunlu entegrasyon testi | `TerminalSessionReattachTests`: gerçek `/bin/cat` PTY + `TerminalSession`, attach→detach→attach→`refreshAttachedViews`, PTY'ye yazılan byte = 0. Ön koşul: `TerminalSession`'a `PTYSpawning`/`TerminalViewMaking` factory enjeksiyonu (Faz 4.1) |
| 2.4 | `TerminalPipelineTests` + `CodexSilenceTimerTests` | Sıfır testli orkestrasyon katmanı; "turn-complete chunk'ta timer resetlenmez" kuralı, `applyHint` → timer iptali |
| 2.5 | Store karakterizasyon testleri | `WorkspaceStore`: sidebar toggle→persist, focusMode callback, quit dialog, `onActiveRepoChanged` unwatch; `GitStore`, `RepoStore`, `SettingsStore` için ilk testler (bugün 0) |
| 2.6 | Config bütünlük testi | `Mirror(AppConfig.defaults)` alan adları ⊆ `configOverlay` anahtarları; aynı `UIState`. Yeni alan eklerken overlay'i unutma = derleme değil test hatası |
| 2.7 | `ShortcutReference` ↔ `MainMenuBuilder` gerçek senkron testi | Faz 3.5'teki `AppCommand` tek kaynağı sonrası tautoloji test silinir |
| 2.8 | Saf mantık testleri | `SyntaxHighlighting.language(forFileName:)`, `UsageTint` eşikleri, `ImagePreview.caption`, `ClaudeUsageService` 4 yolu, `CodexAppServerProbe` (2.1 sonrası) |
| 2.9 | Flaky riski | `LaunchCommandGateTests` sabit uykuları `waitUntil` polling'e çevir |

---

## Faz 3 — Composition root ve DI (Tasks özelliğinin ön koşulu, 3-4 gün) — ✅ tamamlandı (commit `1031d44`, 2026-09-04)

| # | İş | Detay |
|---|---|---|
| 3.1 | `ProcessRunning` + `BinaryLocating` protokolleri | Tüm process I/O static `ProcessRunner` enum'undan geçiyor (7 çağıran). `SystemProcessRunner` impl; her servis `init(runner:locator:)`. Tek değişiklikle 6 test boşluğu açılır, yeni Tasks servisi test edilebilir doğar |
| 3.2 | `ServiceRegistry` protokolü | `LiveServiceRegistry` (bugünkü `AppContainer.init` gövdesi) + `FakeServiceRegistry`. `LumiPaths.Mode` `#if DEBUG`'dan çıkar, parametre olur |
| 3.3 | `FeatureAssembly` protokolü | `bootstrapPhase`, `build(services, shared)`, `start()`, `configDidChange(old,new)`, `shutdown()`. `AppContainer` → feature tanımayan ince koşucu. `ConfigSideEffectCoordinator` callback-şişmesi yerine observer listesi (`register(_:)`) |
| 3.4 | `StoreLifecycle` protokolü | `start()/stop()` simetrisi; `AppContainer.lifecycles` dizisi; bugünkü 3 farklı kalıp (start/stop, update/stop, hiçbiri) tekilleşir |
| 3.5 | `AppCommand` tek kaynağı (LumiKit) | `id/title/menu/key/modifiers`; `MainMenuBuilder` bundan menü kurar, `ShortcutReference` bundan tablo üretir, `MenuActionDispatcher` `id → closure`. Yeni komut = 1 satır + 1 handler (bugün 5 dokunuş) |
| 3.6 | `AppDelegate` bölünmesi (436 satır, 7+ sorumluluk) | `MainWindowController` (pencere, bounds persistence, traffic light, fullscreen), `MenuActionDispatcher`, `AppLifecycleBridges` (NotificationCenter token'ları saklanıp kaldırılır), `AppDelegate` ~80 satır. `fixCheck` URL eşlemesi → `SystemCheckResult.fixURL` |
| 3.7 | `TerminalServicing` ISP bölünmesi | `TerminalSessionControlling` + `TerminalAppearanceControlling` (`applyFont(family:size:)`, `applyCursor`) + event enum'una `.viewFocused`. `AppContainer.terminal` somut tipten protokole iner; font/cursor callback dansı (~20 satır) silinir. `refreshAttachedViews` → `TerminalViewProviding` |
| 3.8 | `GitServicing` ISP | `GitReading` (sessiz liste) / `GitContentReading` (throws) / `GitWriting` (commit); fake'ler küçülür |
| 3.9 | `SystemService` ayrışması | `SystemCheck` protokolü + `[any SystemCheck]`; `PathEnvironmentFixer`, `ExternalURLOpener`, `FileSystemOperations`, `FolderChooser`. `trash/reveal`'e path guard (02 §8 sapması) |
| 3.10 | `GitService` üçe bölünmesi | `GitCommandRunner` / `GitPorcelainParser` (saf, unit test) / `RepoPathGuard` |
| 3.11 | Servis dekoratörleri | `CachingUsageService(wrapping:ttl:)` — rate-limit kapısı store'dan servis katmanına (K38 kararına bağlı) |
| 3.12 | Protokol yeri / kalıp dokümanı | `RepoServicing` → `Protocols/`; `SystemCheckResult` → `Models/`; `02-services.md`'ye "yeni servis ekleme" kontrol listesi + izolasyon seçim kuralı (UI-yüzlü → `@MainActor`, dosya/process I/O → `actor`, stateless → `Sendable` struct) |
| 3.13 | Bootstrap/shutdown yarışı | `startTask` sakla; `shutdown()` önce onu bekler/iptal eder |

---

## Faz 4 — Terminal alt sistemi sınırları (view-switch ön koşulu, 3-4 gün) — ✅ tamamlandı (commit `1628347`, 2026-09-05)

| # | İş | Detay |
|---|---|---|
| 4.1 | `TerminalSession` enjeksiyonu + SRP | `PTYSpawning`/`TerminalViewMaking` factory'leri constructor'a; görsel komutlar (`setFont/setCursorStyle/requestRepaint/redrawFromBuffer`) → `TerminalPresentation`; `terminalView.superview?.needsLayout` (`:264`) yerine `onLayoutInvalidated` callback'i (katman ihlali) |
| 4.2 | `FeedWatchdog` (Ek A §A.2-10 — **hiç implemente edilmemiş**) | Feed süresi ölçümü, 2 sn stall heartbeat → `TerminalEvent.stalled(id)`, >4ms'de coalescer eşiği yarıya; UI'da stalled rozeti (ephemeral `Set<TerminalID>`, `TerminalMeta` formatı değişmez). Terminaller arka planda yaşayacaksa donmayı kimse görmez; view-switch'in ön koşulu |
| 4.3 | `TerminalSurfaceState` | `foreground/background/minimized`; `setSurfaceState` atomik olarak coalescer aralığı + `statusMachine.onBlur/onFocus` + `activeTerminalID` tutarlılığı. Bugün görünürlük ve odak iki bağımsız kanal → Tasks açıkken `waitingFocused` yanlış yükselir, bildirim/auto-minimize (karar 24) bozulur |
| 4.4 | `TerminalViewProviding` genişlemesi | `isAttached(_:)`, `refreshAttachedViews()`, `detachAll()` — Tasks'a geçişte SwiftUI dismantle sırasına güvenmek yerine tek açık çağrı |
| 4.5 | Layout otoritesi tekleştirme | `TerminalGridFit.fit` üç yerden çağrılıyor (`attachView`, `refreshAttachedViews`, `pinTerminalView`); `reassertAttachment` her layout frame'inde `updateFullScreen()`. `fit` yalnız host'ta; `onRedraw` attach olayına bağlı, frame deltasına değil |
| 4.6 | `TerminalInputGate.shared` kaldırılması | Global bayrak yerine monitörde `window.contentView?.hitTest(...)`; overlay üstteyse event doğal geçer. Tasks eklendiğinde "tek satır eklemeyi unutma" riski sıfırlanır |
| 4.7 | `TerminalEventMonitor` | Manager `init`'teki global keyDown/leftMouseDown monitörleri + `DropAwareTerminalView`'daki N adet wheel/hover monitörü tek `@MainActor` tipe; `AppContainer`'dan enjekte; `shutdown`'da `removeMonitor`; `NSEvent`'i async sınırdan geçirme |
| 4.8 | OSC semantik katmanı (OCP) | `OSCStreamParser` yalnız `(code, payload)` üretir; `OSCSemantics` protokolü + `ClaudeSemantics`/`CodexSemantics` enjekte edilen dizi; `AgentHint` açık struct. Yeni ajan/OSC 7/133 = yeni dosya |
| 4.9 | Odak otoritesi birleştirme | `activeTerminalID` / `statusMachine.focused` / `firstResponder` üç otorite; 4.3 ile dördüncü eklenmeden `TerminalListStore.setTerminalSurfaceVisible` tek intent'i |

Beklenen davranış tablosu (tasarım kaydına eklenmeli):

| Olay | View | PTY | Status makinesi | Coalescer |
|---|---|---|---|---|
| Tasks'a geçiş | detach (yok edilmez) | çalışır | `onBlur()` | 100ms |
| Tasks açıkken resize | frame donuk | resize yok | değişmez | 100ms |
| Grid'e dönüş | attach + tek fit | tek resize | `onFocus()` yalnız aktif | 16ms |
| Tasks açıkken exit | — | reap | `onExit(code)` | flush |

---

## Faz 5 — State katmanı ayrışması (3 gün) — ✅ tamamlandı (commit `34226ba`, 2026-09-05)

| # | İş | Detay |
|---|---|---|
| 5.1 | `WorkspaceRoute` sum type | `enum WorkspaceRoute { case repo(String), tasks, none }` (genişletilebilir: `ContentRouteID`); `activeRepoPath` adaptörüyle 12+ çağrı yeri kademeli taşınır; `onActiveRepoChanged` yalnız `.repo`'da ateşlenir. Persist: `activeTab` repo path yazmaya devam eder, route additive anahtara (karar 9) |
| 5.2 | `WorkspaceStore` → 3 store | `NavigationStore` (openTabs, activeRoute), `LayoutStore` (visibleSlots, panelLayout, grid, maximize, focusMode) + `LayoutSnapshot` tek persist, `DialogRouter` (`enum ActiveDialog` — 5 bayrak yerine sum type; `isInputBlockingOverlayOpen` otomatik türer). `TerminalListStore` somut bağı → `TerminalFocusCoordinating` dar protokolü veya event |
| 5.3 | `FileViewerStore` sum type | 4 opsiyonel + mode (48 durum, 5 geçerli) → `ViewerPresentation { hidden, file(..., Loadable<ViewerContent>), commit(...) }`; 5 yerdeki elle nil temizliği yapısal olarak kalkar |
| 5.4 | Kapsülleme | `autoMinimizeOnSend`, `additionalPaths` (iki yazar!), `commitMessages` → `private(set)` + intent |
| 5.5 | Cache eviction | Tab kapanınca `gitStore/repoStore` sözlükleri + `maximizedByRepo` + `projectGridLayouts` temizlenmiyor → `onTabClosed` event + `evict(repoPath)`; generic `KeyedCache`/`KeyedToggleSet` (3 kopya) |
| 5.6 | `events()` `nonisolated` | `ConfigServicing`/`RepoServicing`'de stream Task içinde alınıyor → boot penceresinde event kaybı; `TerminalListStore` kalıbına (Task öncesi al) uydur |
| 5.7 | Config alanı tek tanım | `ConfigModels.swift` (361 satır, 10 tip) feature başına bölünür; bölüm başına codec struct (`NotificationSettingsCodec` vb.); config ailesinden ölü `Codable` kaldırılır (karar 9 tuzağı) |
| 5.8 | `OnboardingStore` | Adım/kural/check yürütme `@State`'ten store'a; "fail bloklar, warn bloklamaz" test edilir |
| 5.9 | Model → UI sızıntısı | `UsageLimit.title`, `FileChangeStatus.badge`, `HeightRatio.label`, `AgentProvider.displayName` → LumiUI presenter extension'ları |

---

## Faz 6 — Generic Shell: panel / route / toolbar kompozisyonu (ana hedef, 5-7 gün) — ✅ tamamlandı (commit `70941cd`, 2026-09-05)

Ön koşullar: Faz 3.3-3.5, 4.3-4.6, 5.1-5.2.

### 6.1 `ShellContext` + Environment enjeksiyonu (davranış değişmez, en büyük kazanç)
- `@Observable @MainActor final class ShellContext` — tüm store'lar + `TerminalViewProviding` + `ShellActions` (reveal/trash/chooseFolder/runChecks/openFile/presentDiff). Türevler `@ObservationIgnored` computed.
- `NSHostingView(rootView: RootView().environment(shellContext))`; `RootView.init` 14 → 1 parametre. `@Environment` bugün LumiUI'da **0 kez** kullanılıyor; tasarım (00 §3, 03 §4) kullanılacağını yazıyor.
- Registry'den dinamik inşa edilen öğelerin ön koşulu: `init()` boş, bağlamı Environment'tan okur.

### 6.2 Panel slot + item registry (left ↔ right taşınabilirlik)
```swift
// LumiKit — persist edilebilir
enum PanelSlot: String, Codable, CaseIterable { case left, right, bottom }
struct PanelItemID: Hashable, Codable, RawRepresentable { let rawValue: String }
struct PanelLayout: Codable, Equatable { var slots: [PanelSlot: [PanelItemID]]; var visibleSlots: Set<PanelSlot>; var widths: [PanelSlot: Double] }

// LumiUI/Shell
struct PanelItemDescriptor: Identifiable { id, title, icon, defaultSlot, makeView: () -> AnyView, isAvailable: (ShellContext) -> Bool }
struct PanelItemRegistry { func resolved(slot:layout:context:) -> [PanelItemDescriptor] }  // saf, test edilir
```
- `PanelHostView(slot:)` listeyi VStack + divider ile çizer. `LeftSidebarView` kaybolur → `.sessions` + `.fileTree` item'ları; `GitSidebar` → `.gitCommits` + `.gitChanges`. Taşıma = tek `PanelLayout` mutasyonu (`LayoutStore.move(item:to:index:)`).
- Panel toggle'ları ve Cmd+B/Cmd+Shift+B `visibleSlots`'tan türetilir (bugün 6 dosyaya yayılmış). Focus mode = `visibleSlots` geçici override'ı.
- Panel öğeleri parent closure'larından arınır (`onOpenFile/onReveal/onTrash/onSelectCommit/onShowFileDiff` → `ShellActions`).

### 6.3 Orta alan router (terminaller yerine Tasks)
```swift
struct ContentRouteDescriptor: Identifiable { id: ContentRouteID, title, icon, makeView: (routeContext) -> AnyView }
struct ContentRouteRegistry { func routes() -> [...]; func resolve(_:) -> ContentRouteDescriptor /* fallback: terminals */ }
```
- `RootView.repoContent` → `ContentRouterView`. Bugünkü `maximized ? MaximizedTerminalView : TerminalGridView` + `minimizedStrip` + `emptyRepoState` → `TerminalsRouteView` içine (route'un iç meselesi).
- Route geçişinde `TerminalViewProviding.detachAll()` + `setSurfaceState(.background)`; dönüşte `refreshAttachedViews()` + `.foreground`. **Entegrasyon testi şart** (`TerminalGridFitIntegrationTests` deseni): "Tasks'a geç → dön" turunda boş/bayat kart yok, PTY'ye 0 byte.
- View butonları `routes()`'tan üretilir (bir panel item'ı veya toolbar item'ı olarak).
- `AnyView` yalnız route/panel-item düzeyinde; terminal kartı içi asla sarılmaz.

### 6.4 Toolbar kompozisyonu
- `ToolbarItemDescriptor { id, region: leading/center/trailing, order, isVisible: (ShellContext) -> Bool, makeView }` + `ToolbarRegistry`. `HeaderBarView` üç `ForEach`. Mevcut `ForEach(usageIndicators.enabledProviders)` bu desenin habercisi; `GridSettingsControl`, `NewTerminalButton`, `UsageIndicatorView`, panel toggle'ları birer descriptor.

### 6.5 Overlay host
- `OverlayDescriptor { id, isPresented, blocksTerminalInput, makeView }` + `OverlayHost`; `DialogRouter` ile birleşir. Manuel `||` listesi kalkar.

### 6.6 Kayıt yeri
- Descriptor **tipleri** LumiUI'da, **kümesi** `LumiApp/ShellComposition.swift`'te (feature assembly'ler kendi item/route/toolbar/overlay'lerini kaydeder). Yeni Tasks özelliği: `TasksAssembly` = servis + store + route + panel item + komut, tek dosyada; `assemblies += [TasksAssembly()]` tek satır.

### 6.7 DRY temizliği (route çıkarımıyla birlikte)
- `TerminalCardChrome` + `TerminalChipStrip` (kart ve şerit 2 kez kopyalı); `TerminalMeta.displayTitle` (5 yerde `oscTitle ?? task ?? name`); `GitStore.canCommit`; `RelativeTimeFormatter(now:)` (LumiKit, test edilir); `FileTreeSearchModel` (debounce state machine view'dan çıkar).

---

## Faz 7 — LumiUI bileşen kütüphanesi ve dosya yapısı (3-4 gün, Faz 6 ile paralel yapılabilir) — ✅ tamamlandı (commit `2869b17`, 2026-09-05)

| # | İş | Detay |
|---|---|---|
| 7.1 | `Theme` token'ları | `Theme.Typography` / `Radius` / `Spacing` / `Motion` / `Diff` (tasarım 03 §5 bunları bağlayıcı sayıyor; bugün yalnız renk). 200 literal `size:`, 17 farklı font boyutu, 9 farklı radius. Lint testi: literal `.font(.system(size:` sayısı eşiği |
| 7.2 | `Components/` | `IconButton` (zorunlu `accessibilityLabel`), `HoverButtonStyle` (40+ `@State isHovering` yerine), `Badge`, `Keycap`, `Panel` (3 kopya), `ModalOverlay` (3 kopya, 3 farklı opaklık), `StatusLine`, `EmptyStatePlaceholder`, `ProviderIcon`. `SettingsComponents` "yalnız Settings" kısıtı kalkar → `Form/` |
| 7.3 | `SettingsView` (820 satır) bölünmesi | `Settings/` klasörü: `SettingsShell`, `SettingsTab`, `SettingsNav`, sekme başına dosya; `SettingsTabContent` protokolü; her sekme yalnız ihtiyacı olan store'u alır |
| 7.4 | Klasörleme | LumiUI düz 36 dosya → `Theme/ Components/ Form/ Settings/ FileViewer/ Usage/ PromptQueue/ Shell/` |
| 7.5 | LumiUI dışına taşıma | `HighlightrEngine` + dil tablosu → LumiServices (view modülünde JSCore/DispatchQueue); `MarkdownDiffBuilder`/`SideBySideDiffBuilder` → LumiKit; `UsageTint` + durum metni → LumiKit/`UsageStore`; `RepoSelectorView.filteredGroups/flatRepos` → `RepoStore` |
| 7.6 | Erişilebilirlik | Modülde 0 `accessibility*`; `UsageIndicatorView` `onTapGesture` → `Button`; dekoratif öğeler `accessibilityHidden` |
| 7.7 | `#Preview` altyapısı | Modülde 0 preview; `LumiTestSupport` fake'leriyle `Store.preview()` fabrikaları; her yeni bileşene preview |
| 7.8 | `PromptQueuePanel` | `ForEach(id: \.offset)` + `onMove` kırılgan → kuyruk elemanına stabil id; magic 44/8/180; `DispatchQueue.main.async` focus hack → `Task { @MainActor }` / `defaultFocus` |
| 7.9 | Diff/usage kopyaları | Diff renk eşlemesi 3 yerde (0.13 opaklık dahil) → `Theme.diffBackground(for:)`; usage durum satırı 2 farklı davranışla 2 yerde → tek `UsageStatusRow` |

---

## Faz 8 — Dokümantasyon senkronu (her faz sonunda, K33-K38 onayı sonrası) — ✅ tamamlandı (2026-09-05)

- `00-architecture.md`: §2 modül ağacı (SPM-only, Yams yok, `LumiTestSupport`), §3 composition (`FeatureAssembly`, `ServiceRegistry`, Environment enjeksiyonu), Ek A'ya `FeedWatchdog` durumu.
- `01-terminal-subsystem.md`: `TerminalSurfaceState`, view-switch davranış tablosu, düzeltilmiş backpressure açıklaması (01 §2'nin "yarış yok" iddiası yanlıştı).
- `02-services.md`: §9 LumiError bloğu, `watchFileTree/[FileTreeNode]` isimleri, yeni servis kontrol listesi, path-guard kapsamı.
- `03-ui-shell.md`: §4 store tablosu (11 store), yeni §7 panel/route/toolbar kompozisyonu, `TerminalInputGate` kaldırılması, Prompt Queue bölümü, kısayol listesi.
- `05-usage-indicator.md`: aralık seti ve TTL kararı.
- `decisions.md`: K33-K38; karar 19'a "prompt kuyruğu ayrı özellik olarak yaşıyor" notu.
- `CLAUDE.md` Durum bölümü güncellenir.

---

## Sıralama ve bağımlılık özeti

```
Faz 1 (acil fix)  ──► Faz 2 (test ağı) ──► Faz 3 (DI/composition) ──┐
                                        └─► Faz 4 (terminal sınırları) ─┼─► Faz 6 (generic shell) ──► Faz 8 (docs)
                                        └─► Faz 5 (state ayrışması) ────┘        ▲
                                                                     Faz 7 (bileşen kütüphanesi) ─┘ (paralel)
```

Her faz tek başına yeşil test bırakır ve ayrı PR(lar) halinde gider. Faz 6.3 öncesi 6.3'teki entegrasyon testi yazılır. Toplam kaba tahmin: 20-27 iş günü.

## "Tasks görünümü" için hedef maliyet (plan sonrası)

```
YENİ:  LumiKit/Protocols/TasksServicing.swift
       LumiServices/Tasks/TasksService.swift
       LumiState/Features/Tasks/TasksStore.swift
       LumiUI/Tasks/TasksRouteView.swift (+ küçük bileşenler)
       LumiApp/Features/TasksAssembly.swift   ← servis+store+route+panel item+komut kaydı
DEĞİŞEN: ShellComposition.swift  assemblies += [TasksAssembly()]   (1 satır)
```
Bugün: ~11 dosya, ~19-20 dokunuş, `RootView`/`AppContainer`/`AppDelegate`/`WorkspaceStore`/`SettingsView` merge darboğazları.

---

## Sonuç (2026-09-05)

Plan yedi fazın tamamıyla uygulandı; her faz ayrı commit ve yeşil test bırakarak gitti.

| Ölçüt | Plan öncesi | Plan sonrası |
|---|---|---|
| Test | 474 | **1191** (0 hata) |
| Build | temiz (1 uyarı) | temiz |
| "Tasks ekleme" maliyeti | ~11 dosya / ~19-20 dokunuş, 5 merge darboğazı | **1 assembly dosyası + register satırları + `AppComposition`'da 1 satır** |
| Kabuk kompozisyonu | elle yazılmış ağaç | `ShellRegistries` (panel / route / toolbar / overlay descriptor'ları) |
| Modüller | 5 kütüphane + `LumiApp` executable | 5 kütüphane + `LumiAppCore` + ince `LumiApp` + `LumiTestSupport` |

Bağlayıcı kayıt: [decisions.md](./decisions.md) karar 33–38 + "Refactor 2026-09 davranış notları"; mimari kayıt `docs/design/` altında güncellendi.

### Kalan borçlar

Bilinçli olarak ertelenen ya da hedefin altında kalan maddeler:

- **6.2 — `.bottom` yuvası boş:** `PanelSlot.bottom` tanımlı, `PanelHostView` ve toolbar toggle'ı destekliyor ama **kayıtlı öğesi yok**; yuva ilk `.bottom` öğesi kaydedilene kadar gizli kalıyor. Genişlik yerine yükseklik politikası da o zaman yazılacak (`PanelHostView` bugün `.bottom` için `width` uygulamıyor).
- **3.6 — `AppDelegate` 168 satır** (hedef ~80). `MainWindowController`, `MenuActionDispatcher` ve `AppLifecycleBridges` çıkarıldı; kalan gövde bootstrap sırası, TCC/izin akışı ve quit protokolü. Daha fazla bölmek için ayrı bir "app lifecycle" sahibi gerekiyor — YAGNI sayıldı.
- **5.3 — `ViewerPresentation.commit` içindeki `filePath`/`content` eşleşmesi tip düzeyinde zorlanmıyor:** ikisi de opsiyonel (commit açıldı, dosya henüz seçilmedi) ve "birlikte hareket ederler" kuralı yorumda duruyor. İç içe bir `Loadable<(String, ViewerContent)>` sarmalayıcı okunabilirliği düşürdüğü için tercih edilmedi; kural testle kilitli.

