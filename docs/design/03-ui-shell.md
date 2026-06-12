# Lumi Native — UI Kabuğu ve State Tasarımı

> App target (AppKit kabuk) + `LumiState` + `LumiUI` modüllerinin bağlayıcı tasarımı. Davranış kaynağı: [spec/21](../spec/21-renderer-state.md), [spec/22](../spec/22-renderer-ui.md), [spec/23](../spec/23-design-system.md), [spec/30](../spec/30-app-shell.md).

---

## 1. AppKit / SwiftUI sınırı

| Alan | Sahip |
|---|---|
| App lifecycle, quit akışı, sleep/wake, menü | AppKit (`AppDelegate`) |
| Pencere, traffic light, bounds persistence, key-status → focus | AppKit (`MainWindowController`) |
| Pencere içindeki her şey | SwiftUI — tek `NSHostingView` (`RootView`) = `window.contentView` |
| Terminal emülatör view'ları | AppKit; `TerminalViewRegistry` sahipliğinde, SwiftUI'a salt-köprü |
| FileViewer metin render'ı | `NSTextView` (TextKit 2) `NSViewRepresentable` ile (§6) |

App **pure AppKit lifecycle** kullanır (`@main` AppDelegate + `MainWindowController`), SwiftUI `App` protokolü değil. Gerekçe: `.terminateLater` quit akışı, özel traffic-light geometrisi, `fullSizeContentView` ve ui-state.json bounds persistence (karar 9 `frameAutosave`'i dışlar).

---

## 2. Pencere, menü, quit

**Pencere:** `NSWindow(styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`; default 1400×900, min 1000×600; traffic light'lar titlebar-layout kancasında `standardWindowButton(_:)` frame'leriyle (x:15, y:19) konumlanır; `acceptFirstMouse` davranış paritesi.

**Bounds persistence (karar 9):** `windowDidMove/windowDidResize` → 500ms debounce → `config.updateUIState { $0.windowBounds = ... }`; maximize anında. Restore'da tüm `NSScreen` workArea'larına karşı overlap doğrulaması; geçersizse default boyut. Maximize state show'dan önce uygulanır (flash önleme).

**Focus köprüsü:** `windowDidBecomeKey/ResignKey` → `terminal.setWindowFocused(_:)` — bildirim semantiği buna bağlıdır ([spec/00 §5](../spec/00-overview.md): "aynı semantikle akmalı, yoksa bildirimler bozulur").

**Menü = TEK kısayol kaynağı.** `MainMenuBuilder` tüm `NSMenu`'yu key equivalent'larla kurar: Cmd+T (yeni terminal), **Cmd+W (terminali kapatır, pencereyi DEĞİL — menü interception)**, Cmd+O (repo seçici), Cmd+B / Cmd+Shift+B (sidebar'lar), Cmd+, (settings), Cmd+Shift+F (focus mode), Cmd+1…9 (terminal N), Cmd+Shift+←/→ (önceki/sonraki terminal); standart Edit menüsü (terminal copy-paste için zorunlu), Window menüsü. Item'lar `MenuActionDispatcher`'a (@MainActor, app target) hedeflenir → store intent'leri çağrılır; `validateMenuItem` store state okur (örn. aktif terminal yokken Cmd+W disabled). **SwiftUI `.keyboardShortcut` ve `keyDown` handler'ı hiçbir yerde kullanılmaz** — Electron'un çift-kaynak bug sınıfı yapısal olarak silinir.

**Quit akışı (her çıkış yolu):** `applicationShouldTerminate` → canlı terminal varsa `.terminateLater` + `workspace.quitConfirmationVisible = true` (custom SwiftUI dialog — görsel kimlik korunur); onay → `await terminal.killAll()` → `NSApp.reply(toApplicationShouldTerminate: true)`; iptal → `false`. Cmd+Q, Dock quit ve logout dahil hepsi bu akıştan geçer. Çıkışta temp dizini (`tmp/lumi*`) silinir.

**Sleep/wake:** `NSWorkspace.didWakeNotification` → watcher tazeleme + repo listesi yenileme. Electron'daki 3-tetikleyicili terminal re-sync zinciri **gerekmez** — terminal state'i tek process'te hiç kopmaz.

**Focus mode:** `workspace.isFocusMode` SwiftUI chrome gizlemeyi + hover-reveal bar'ı sürer (mouse-üstten-50px / 500ms gecikme / dropdown-açıkken-kal kuralları SwiftUI'da); `MainWindowController` aynı bayrağı `withObservationTracking` ile izleyip traffic-light'ları gizler/gösterir. AppKit yan etkileri window controller'da kalır; store AppKit'siz kalır.

---

## 3. Terminal view'larının SwiftUI dışında sahipliği (yük taşıyan desen)

- `TerminalViewRegistry` (@MainActor, `LumiTerminal` içinde; `LumiKit.TerminalViewProviding` implementasyonu) spawn'da SwiftTerm tabanlı NSView'ı yaratır ve **PTY ömrü boyunca retain eder**. SwiftUI asla sahip olmaz.
- `TerminalHostView: NSViewRepresentable` (`LumiUI`): `makeNSView` boş container `NSView` döner; `updateNSView` → `registry.attachView(for:into:)` (canlı terminal view'ını reparent eder, constraint'lerle sabitler, **fit tetikler** — `display:none`+IntersectionObserver'ın yerine geçen "görünür olunca fit" garantisi); `dismantleNSView` → yalnız `detachView`. `.id(terminalID)` ile yapısal kimlik sabitlenir.
- Sonuç: SwiftUI bir container'ı yıksa bile (tab değişimi, grid mod değişimi, minimize) emülatör view'ı ve state'i registry'de yaşar — **re-render hiçbir koşulda terminal state'ini yok edemez**. Detach edilen oturumda coalescing genişler ve çizim durur ([01 §3](./01-terminal-subsystem.md)); attach = reparent + fit + tek çizim geçişi.

---

## 4. Store'lar (`LumiState`)

Hepsi `@Observable @MainActor final class`; Environment ile enjekte edilir; her biri composition root'un çağırdığı `start()` ile kendi servis stream'ini tüketen tek `Task` koşturur. **Tek process ⇒ doğrudan gözlem:** `syncFromMain`, snapshot reconciliation, event bridge **yoktur**. **Ham terminal çıktısı hiçbir store'da, asla.**

| Store | Tuttuğu (yalnız UI/metadata) | Beslendiği | Kritik kurallar |
|---|---|---|---|
| `TerminalListStore` | **Sıralı** `[TerminalMeta]`, `activeTerminalID`, `minimizedIDs: Set`, `lastActiveByRepo` | `TerminalEvent` stream | Kapanışta komşu-odak (silmeden önce hesap: önceki → sonraki → ilk, aynı repo); minimize-asla-otomatik-odak (tek istisna: bildirim tıklaması); minimize'da görünür kardeşe proaktif odak; repo'da görünür terminal kalmazsa `activeTerminalID = nil` |
| `WorkspaceStore` | `openTabs: [String]` (**repo path** — ad-çakışması bug fix'i, karar 11), `activeTab`, sidebar görünürlükleri, repo başına grid layout (iki eksen: kolon `auto/columns` × yükseklik `fit/scroll` — karar 15; spec/20 §13 kolon matematiği), repo başına oturumluk `maximizedByRepo` (maximize/solo, persist edilmez), `isFocusMode`, dialog state'leri, `fileViewerPresentation` | UI intent'leri; açılışta `ui-state.json` (okurken tek seferlik ad→path migration; legacy `rows`→`fit` migrasyonu ConfigCodec'te) | Persist edilen her alan mutasyonu → `config.updateUIState` (servis 500ms debounce'lar). Tab kapatma: minimize guard'ı (`CloseTabDialog`) → repo terminallerini kill → persist |
| `RepoStore` | `repos`, kaynak-gruplu görünüm, `fileTrees` cache (stale-while-revalidate, scroll-pozisyon korumalı yenileme) | `RepoEvent` stream | Event → tam yeniden çekme (pull-after-push). Aktif tab'ın reposunu watch eder, tab kapanınca unwatch |
| `GitStore` | Repo başına commits/branches/status cache'leri; `selectedCommit`, `commitFiles`, `[FilePath: Loadable<UnifiedDiff>]` | `RepoEvent.fileTreeChanged` invalidation + intent'ler | Lazy commit-diff (karar 6): commit seçimi dosya listesini, dosya tıklaması tek diff'i yükler. Changes yüklenince tüm dosyalar seçili (parite) |
| `ActionsStore` / `PersonasStore` | Listeler, default-id seti, seçili action history'si | Void changed-stream → yeniden çek | |
| `ToastStore` | `[Toast]` (max 5, 5sn auto-dismiss `Task`'leri, `LumiError` eşitliği/mesajla dedupe) | diğer store'lar `reporting {}` ile | Uygulamanın tek hata lavabosu |
| `SettingsStore` | `AppConfig` alanlarının binding aynası | `ConfigEvent` stream | **Anlık uygulama (karar 3):** her kontrol değişikliği → `config.update {}`; yan etkiler `ConfigSideEffectCoordinator`'dan. Draft/Save/Escape yok |

**Hata koridoru:**

```swift
@MainActor extension ToastStore {
    func reporting(_ op: @MainActor () async throws -> Void) async {
        do { try await op() }
        catch let e as LumiError { show(.error(e)) }
        catch { show(.error(.underlying(domain: "unknown", message: "\(error)"))) }
    }
}
```

**Bootstrap UI zinciri** ([spec/22](../spec/22-renderer-ui.md) sırası, native'e indirgenmiş): loading ekranı → `isFirstRun` → onboarding (4 adım: Welcome/SystemChecks/ProjectsRoot/Ready; fail bloklar, warn bloklamaz) **veya** `repos + additionalPaths` paralel yükle → `uiState` yükle (migration repo listesini okur) → ana UI. `syncFromMain` adımı yoktur.

---

## 5. Tasarım sistemi (karar 13: semantic uyarlama)

- `Theme` namespace'i (`LumiUI`): [spec/23](../spec/23-design-system.md) token'ları semantic adlarla — zemin `#0a0a12 / #12121f / #1a1a2e`, metin `#e2e2f0 / #8888a8 / #4a4a6a`, accent `#a78bfa / #8b5cf6 / #7c3aed / #22d3ee / #4ade80 / #fbbf24 / #f87171`, border `#2a2a4a` + glow. macOS system look benimsenmez.
- **Tanımsız-token bug'ları düzeltilerek** eşlenir; git-status renk paleti tek kaynağa konsolide edilir (ChangesSection/CommitDiffView tutarsızlığı taşınmaz — karar 11).
- Tipografi: **JetBrains Mono** (Apache 2.0 — bundle edilebilir) launch'ta `CTFontManagerRegisterFontsForURL` ile kaydedilir; 13px taban, spec/23 ölçeği `Theme.Typography`'de.
- Animasyonlar (fade/slide/height-collapse, 0.1–0.3s; spring'ler) SwiftUI `transition`/`withAnimation` ile; spec'teki parametreler `Theme.Motion` sabitlerine taşınır.
- StatusDot durum renk sistemi (working=success+pulse, waiting-unseen=warning+pulse, …) birebir.

---

## 6. FileViewer v1 metin stack'i

- **Görüntüleme modu:** `NSTextView` (TextKit 2, non-editable) + **Highlightr** (highlight.js → `NSAttributedString`); Lumi violet paletinden üretilmiş custom highlight.js teması; JetBrains Mono 13. Highlight main-actor dışında; **~1MB üstü dosyada düz metne düşülür** (Highlightr'ın JSCore maliyeti nötralize edilir). Dil eşleme tablosu spec/22'deki uzantı→dil haritasından.
- **Side-by-side diff modu (karar 4 revize):** `GitServicing`'in tiplenmiş `UnifiedDiff` modeli → saf `SideBySideDiffBuilder` (hizalı sol/sağ hücre satırları: del[i]↔add[i], context iki tarafta, fazlalar filler) → `SideBySideDiffView` (SwiftUI `LazyVStack`, satır sarmalı, kolon başına gutter + arka plan renkleri Theme token'larından). Monaco portu değil; `UnifiedDiffParser` korunur (yalnız sunum değişti). Eski tek-kolon `DiffAttributedTextBuilder` kaldırıldı.
- **Değiştirilebilirlik:** view yalnız iç `SyntaxHighlighting` protokolüne bağlanır (`func highlight(code:language:) async -> NSAttributedString`) — Highlightr yetersiz kalırsa tree-sitter'a (SwiftTreeSitter/Runestone) view'a dokunmadan geçilir. v1'de tree-sitter'ın grammar-bundle maliyeti salt-okunur viewer için alınmaz.
- Görünüm paritesi: 85vw×80vh eşdeğeri oran, commit sidebar 220px, ilk dosya default seçili, satır numaraları açık, minimap yok.
