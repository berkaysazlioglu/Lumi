# Uygulama Kabuğu (App Shell)

> Kaynak: `src/main/index.ts`, `src/main/platform/*`, `src/main/safeSend.ts`,
> `src/main/ipc/handlers/register-config-window-handlers.ts` (window kısmı),
> `electron-builder.config.ts`, `electron.vite.config.ts`, `package.json`,
> `build/`, `scripts/`.

## Amaç ve sorumluluk

App shell, Lumi'nin yaşam döngüsünü yöneten katmandır: ana pencerenin oluşturulması ve
durumunun (boyut/konum/maximize) kalıcılaştırılması, uygulama menüsü ve global kısayollar,
quit/close akışı (aktif terminal varsa onay isteme), renderer crash recovery, mikrofon izni,
PATH düzeltmesi (Dock'tan başlatılan uygulamanın kısıtlı PATH'i), sleep/wake sonrası terminal
senkronizasyonu ve paketleme/dağıtım (codesign, notarization, entitlements).

macOS-native rewrite'ta bu katman `NSApplicationDelegate` + `NSWindow` yönetimi +
`Info.plist`/entitlements + menü tanımına karşılık gelir. Electron'a özgü parçaların çoğu
(renderer crash recovery, sandbox flag'leri, preload/IPC köprüsü) native'de ya tamamen
ortadan kalkar ya da çok daha basit hale gelir.

## Feature envanteri

### 1. Ana pencere oluşturma ve görünüm

- **Davranış:** Tek bir ana pencere oluşturulur. Varsayılan boyut 1400x900, minimum
  1000x600. Arka plan rengi `#0a0a12` (koyu tema; pencere içerik yüklenmeden bu renkte
  görünür — beyaz flash önleme).
- **macOS'a özgü:** `titleBarStyle: 'hiddenInset'` — sistem title bar gizli, traffic light
  butonları içerikte, custom pozisyonda: `x: 15, y: 19`. Yani UI kendi başlık çubuğunu
  çizer ve traffic light'lar bunun içine gömülüdür. Ayrıca `acceptFirstMouse: true` —
  pencere arka plandayken ilk tıklama hem pencereyi öne getirir hem de tıklanan öğeyi
  etkiler (terminal kullanımı için önemli).
- **Edge-case:** Pencere `show: false` ile oluşturulur, içerik hazır olunca (`ready-to-show`)
  gösterilir. Eğer 5 saniye içinde içerik hazır olmazsa pencere zorla gösterilir
  (ARM64 GPU hang workaround'u — native'de gereksiz).
- **Kullanıcıya etkisi:** Uygulama açılışında flash'sız, koyu temalı, custom başlıklı pencere.

### 2. Pencere durumu kalıcılığı (bounds + maximize)

- **Davranış:** Pencere boyutu/konumu `ui-state.json` içinde `windowBounds`
  (`{x, y, width, height}`) ve `windowMaximized` (boolean) alanlarına kaydedilir.
  - `resize` ve `move` olaylarında **500ms debounce** ile kaydedilir; pencere maximize
    veya minimize durumdaysa kaydedilmez (normal bounds korunur).
  - `maximize`/`unmaximize` olaylarında `windowMaximized` anında güncellenir.
  - Pencere kapanırken son durum bir kez daha yazılır (maximize değilse bounds da).
- **Geri yükleme:** Açılışta kaydedilmiş bounds varsa, **görünür bir ekranda olup olmadığı
  doğrulanır**: tüm display'lerin `workArea`'ları ile kesişim testi yapılır (pencerenin en
  az bir kısmı herhangi bir ekranda görünüyorsa geçerli). Geçersizse default boyut/konum
  kullanılır (monitör söküldüğünde pencerenin ekran dışında açılmasını önler).
  `windowMaximized: true` ise pencere gösterilmeden önce maximize edilir.
- **Native karşılık:** macOS'ta `NSWindow.setFrameAutosaveName` bu işin çoğunu bedavaya
  yapar; ancak mevcut JSON formatıyla migration istenirse manuel okumak gerekir.

### 3. Quit/close akışı ve terminal onayı

- **Davranış:** Pencere kapatma (`close` event) yakalanır:
  1. Son pencere durumu kaydedilir.
  2. Aktif terminal (PTY) sayısı sorgulanır. Eğer `terminalCount > 0` ve quit henüz
     onaylanmamışsa, kapatma **iptal edilir** ve renderer'a `app:confirm-quit` IPC
     mesajı terminal sayısıyla gönderilir → UI bir onay dialogu gösterir.
  3. Renderer onaylarsa `app:quit-confirmed` mesajı gelir → `isQuitting = true` set
     edilir, tüm PTY'ler öldürülür (`killAll`), repo watcher'ları dispose edilir,
     `app.quit()` çağrılır.
  4. Terminal yoksa kapatma direkt ilerler; yine `killAll` + repo dispose yapılır.
- **Menüden Quit (Cmd+Q):** `app.quit()` değil `mainWindow.close()` çağrılır — böylece
  aynı onay akışından geçer. **Native rewrite'ta kritik:** Cmd+Q doğrudan terminate
  etmemeli, `applicationShouldTerminate` içinde aynı onay akışı uygulanmalı.
- **window-all-closed:** macOS'ta uygulama pencere kapatılınca **çıkmaz** (standart macOS
  davranışı); diğer platformlarda çıkar. Dock ikonuna tıklanınca (`activate`) pencere
  yoksa yeniden oluşturulur.
- **will-quit:** Temp dizini (`os.tmpdir()/lumi`, dev'de `lumi-dev`) recursive silinir
  (sistem prompt dosyaları vb. geçici dosyalar). Hata sessizce yutulur.
- **Kullanıcıya etkisi:** Çalışan AI session'ları varken yanlışlıkla quit edilemez.

### 4. Crash recovery

- **Main process uncaughtException:** Hata loglanır, tüm PTY'ler öldürülür (zombi process
  önleme), repo watcher'lar dispose edilir, `app.exit(1)`. **Native notu:** zombi PTY
  child process'leri bırakılmamalı; crash handler veya process group ile temizlik gerekir.
- **unhandledRejection:** Sadece loglanır, uygulama devam eder.
- **Renderer crash (`render-process-gone`):** Sebep `crashed` veya `oom` ise 1 saniye
  sonra sayfa reload edilir. **Native'de yok** — tek process. Ancak bu davranışın varlığı,
  terminal output'unun renderer'ı OOM'a sürükleyebildiğini gösterir (commit `04009f6` bunu
  cap'leyerek düzeltmiş); native tarafta da terminal buffer'ları sınırlandırılmalı.
- **Yükleme hatası (`did-fail-load`):** `-3` (iptal) dışındaki hatalarda 1 saniye sonra
  reload. Native'de karşılığı yok.

### 5. Uygulama menüsü ve kısayollar

Accelerator kuralı: macOS'ta `Cmd+<key>`, Windows/Linux'ta `Ctrl+Shift+<key>`.
Menü eylemlerinin çoğu renderer'a `'shortcut'` kanalından bir string event yollar;
UI bu string'e göre davranır.

| Menü | Öğe | Kısayol (macOS) | Renderer eventi / eylem |
|---|---|---|---|
| Lumi (app) | About, Services, Hide, Hide Others, Unhide | sistem | sistem rolleri |
| Lumi (app) | Quit | Cmd+Q | `mainWindow.close()` (onay akışı) |
| File | New Session | Cmd+T | `new-terminal` |
| File | Close Terminal | Cmd+W | `close-terminal` |
| File | Open Repository | Cmd+O | `open-repo-selector` |
| Edit | Undo/Redo/Cut/Copy/Paste/Select All | sistem | sistem rolleri (terminal copy-paste için şart) |
| View | Toggle Left Sidebar | Cmd+B | `toggle-left-sidebar` |
| View | Toggle Right Sidebar | Cmd+Shift+B | `toggle-right-sidebar` |
| View | Settings | Cmd+, | `open-settings` |
| View | Focus Mode | Cmd+Shift+F | `toggle-focus-mode` |
| View | Reload / Force Reload / DevTools | sistem | Electron'a özgü, native'de gereksiz |
| View | Reset Zoom / Zoom In / Zoom Out | sistem | native'de istenirse font-size scaling |
| View | Toggle Full Screen | sistem | sistem |
| Window | Minimize, Zoom, (macOS) Bring All to Front | sistem | sistem rolleri |

- **Önemli:** Cmd+W pencereyi değil **aktif terminali** kapatır. Native'de
  `performClose` override edilmeli ya da menüde standart Close yerine custom action olmalı.
- **Edge-case:** Tüm `shortcut` gönderimleri `safeSend` üzerinden (bkz. madde 10).

### 6. Fullscreen takibi

- `enter-full-screen` / `leave-full-screen` olaylarında renderer'a
  `window:fullscreen-changed` (boolean) gönderilir. UI bunu custom title bar /
  traffic light boşluğu layout'unu ayarlamak için kullanır.

### 7. Pencere odak takibi (bildirim kararları için)

- `focus`/`blur` olaylarında TerminalManager'a `setWindowFocused(bool)` bildirilir.
  Bildirim alt sistemi "pencere odakta mı" bilgisine göre native notification gösterip
  göstermemeye karar verir. Native'de `NSWindowDelegate.windowDidBecomeKey/ResignKey`.

### 8. Dış link davranışı

- Yeni pencere açma istekleri (`window.open` vb.) engellenir, URL sistem tarayıcısında
  açılır. Mevcut sayfadan farklı bir URL'ye navigasyon da engellenip tarayıcıya
  yönlendirilir. **Native'de:** terminal/UI içindeki linkler `NSWorkspace.open` ile
  açılmalı; uygulama içinde asla web navigasyonu olmamalı.

### 9. Mikrofon izni (commit 225bc01)

- **Davranış:** Electron session'ına permission request + permission check handler
  takılır; **yalnızca `media` izni** otomatik verilir, diğer tüm izinler reddedilir.
  Amaç: Claude Code CLI'ın voice mode'unun renderer üzerinden mikrofona erişebilmesi.
- **Paketleme tarafı:** `Info.plist`'e `NSMicrophoneUsageDescription` ("Lumi needs
  microphone access for Claude Code voice mode.") eklenir; entitlements'ta
  `com.apple.security.device.audio-input` vardır.
- **Native'de:** `NSMicrophoneUsageDescription` + `AVCaptureDevice.requestAccess(for: .audio)`
  yeterli; Electron'daki handler katmanı tamamen ortadan kalkar. Dikkat: izni asıl
  kullanan PTY içindeki **child process (claude CLI)** ise, mikrofon erişimi TCC'de
  Lumi'nin iznine bağlanır — hardened runtime + audio-input entitlement şart.

### 10. safeSend — güvenli IPC gönderimi

- **Davranış:** Renderer'a mesaj göndermeden önce pencere/webContents'in destroyed veya
  crashed olup olmadığı kontrol edilir; değilse `mainFrame.send` try-catch içinde çağrılır.
  Sebep: crash ile reload arasında PTY output akmaya devam eder ve konsolu hata ile boğar.
- **Native'de karşılığı yok** (IPC yok); ancak ders şu: terminal output event'leri UI'a
  ulaştırılırken UI lifecycle'ına (pencere kapalı/yeniden oluşturuluyor) dayanıklı bir
  event-bus tasarlanmalı.

### 11. PATH düzeltmesi (`fixProcessPath`)

- **Problem:** Dock/Finder'dan başlatılan GUI uygulaması minimal PATH alır
  (`/usr/bin:/bin:/usr/sbin:/sbin`); `claude`, `git` gibi CLI'lar bulunamaz.
- **Davranış (startup'ta bir kez, IPC kurulumundan önce):**
  1. Kullanıcının login shell'i (`$SHELL`, fallback `/bin/zsh`) `-ilc 'echo -n "$PATH"'`
     ile çalıştırılır (5 sn timeout); dönen PATH mevcut PATH ile **set olarak** birleştirilir.
  2. Bilinen dizinler — `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`,
     `/opt/homebrew/sbin`, `~/.nvm/current/bin`, `~/.volta/bin` — diskte mevcutsa eklenir.
  3. Sonuç `process.env.PATH`'e yazılır; tüm `which`/`spawn`/PTY çağrıları bunu görür.
- **Edge-case:** Login shell çağrısı başarısız olursa (hata/timeout) sessizce yalnızca
  bilinen dizin fallback'i kullanılır. Windows'ta no-op.
- **Native'de aynen gerekli:** macOS GUI app'ler de aynı kısıtlı PATH problemini yaşar.
  Aynı strateji (login shell'den PATH çözme + bilinen dizinler) Swift'te uygulanmalı ve
  PTY spawn ortamına enjekte edilmeli.

### 12. Sleep/wake senkronizasyonu

- `powerMonitor` `resume` olayında renderer'a `terminal:sync` gönderilir; UI terminal
  state'ini main process ile yeniden senkronize eder (uyku sırasında kaçan output/state).
- **Native'de:** `NSWorkspace.didWakeNotification` ile aynı tetikleyici; tek process
  olduğundan "sync" ihtiyacı azalır ama PTY'lerin uyku sonrası sağlığı kontrol edilmeli.

### 13. Window-control IPC'leri (custom title bar için)

Renderer'daki custom başlık çubuğu şu komutları main'e yollar:
- `window:toggle-maximize` — maximize/unmaximize toggle (macOS'ta zoom).
- `window:minimize`, `window:close`.
- `window:set-traffic-light-visibility` (yalnız macOS) — `setWindowButtonVisibility`;
  UI bazı modlarda (ör. focus mode) traffic light'ları gizler/gösterir.
- `dialog:open-folder` — native klasör seçme dialogu; iptal edilirse `null`,
  seçilirse path döner. (Repo ekleme akışında kullanılır.)
- **Native'de:** title bar zaten native olacağından toggle/minimize/close IPC'leri
  gereksiz; traffic light gizleme `NSWindow.standardWindowButton(...).isHidden` ile,
  klasör seçimi `NSOpenPanel` ile yapılır.

### 14. Config/temp dizin çözümü ve legacy migration

- **Config dizini:** macOS/Linux `~/.lumi`, Windows `%APPDATA%/lumi`. Dev modda
  (`NODE_ENV=development`) `-dev` suffix'i: `~/.lumi-dev` — dev ve prod verisi izole.
- **Legacy migration (yalnız production):** `~/.lumi` yoksa ama `~/.pulpo` varsa onu,
  o da yoksa `~/.ai-orchestrator` varsa onu kullanır (kopyalama değil, **doğrudan eski
  dizini kullanma**). Native rewrite bu eski dizin adlarını da kontrol etmeli ya da tek
  seferlik gerçek bir migration yapmalı.
- **UI state dosyası:** `<configDir>/ui-state.json`, pretty-printed JSON. App shell'in
  kullandığı alanlar: `windowBounds`, `windowMaximized` (diğer alanlar — `openTabs`,
  `activeTab`, sidebar durumları, `projectGridLayouts` — renderer'a aittir, aynı dosyada).
- **Temp dizini:** prod `os.tmpdir()/lumi`, dev `os.tmpdir()/lumi-dev`; quit'te silinir.

### 15. Dev/prod yükleme ve dev başlık

- Dev modda renderer `http://localhost:5173`'ten yüklenir ve pencere başlığı
  `Lumi [DEV]` olur; prod'da paketlenmiş `index.html`. Native'de karşılığı: dev build'in
  görsel olarak ayırt edilebilmesi (başlık veya ikon farkı) korunmaya değer bir alışkanlık.

### 16. Güvenlik ayarları (web tarafı)

- `nodeIntegration: false`, `contextIsolation: true`; renderer yalnızca preload'da
  expose edilen API'lere erişir. Native'de güvenlik modeli tamamen farklı; bu maddenin
  tek mirası "UI katmanı dosya sistemine/process'lere doğrudan değil, kontrollü bir
  servis katmanı üzerinden erişir" mimari prensibi.

### 17. Linux'a özgü başlatma bayrakları

- Linux'ta sandbox/GPU ile ilgili çok sayıda Chromium switch'i kapatılır
  (`no-sandbox`, `disable-gpu`, vb.) ve Wayland desteği açılır. macOS-native rewrite
  için **tamamen ilgisiz**; sadece "bu rewrite macOS-only olacaksa Linux/Windows desteği
  düşüyor" bilgisi olarak not edilir.

## Veri akışı ve bağımlılıklar

- **TerminalManager** (terminal alt sistemi): `getCount()` (quit onayı için),
  `killAll()` (quit/crash temizliği), `setWindowFocused()` (bildirim kararı),
  `setMaxTerminals()` (config değişiminde).
- **RepoManager:** `dispose()` (quit/crash'te watcher temizliği).
- **ConfigManager:** UI state okuma/yazma (window bounds), genel config.
- **NotificationManager:** config değişiminde settings güncelleme (window handler
  üzerinden; bildirim mantığı ayrı alt sistem).
- **IPC kanalları (app shell'in sahibi olduğu/kullandığı):**
  - Main → Renderer: `app:confirm-quit` (terminalCount), `window:fullscreen-changed`
    (bool), `terminal:sync` (wake sonrası), `'shortcut'` (string event adı),
    `repos:changed`.
  - Renderer → Main: `app:quit-confirmed`, `window:toggle-maximize`, `window:minimize`,
    `window:close`, `window:set-traffic-light-visibility`, `dialog:open-folder`,
    `ui-state:get/set`, `config:get/set`, `config:is-first-run`.
- **Dış process'ler:** startup'ta PATH çözümü için login shell (`zsh -ilc`); PTY'ler
  terminal alt sistemine ait ama lifecycle temizliği app shell'in sorumluluğunda.

## Persistence / config

| Ne | Nereye | Format |
|---|---|---|
| Pencere bounds + maximize | `<configDir>/ui-state.json` → `windowBounds`, `windowMaximized` | JSON (pretty, 2 space) |
| Genel app config | `<configDir>/config.json` (ConfigManager; ayrı alt sistemin detayı) | JSON |
| Geçici dosyalar (system prompt vb.) | `os.tmpdir()/lumi[-dev]` | dosyalar; quit'te silinir |
| configDir | prod: `~/.lumi` (legacy fallback: `~/.pulpo`, `~/.ai-orchestrator`); dev: `~/.lumi-dev` | dizin |

## Paketleme ve dağıtım (electron-builder.config.ts, build/, scripts/)

- **Kimlik:** appId `com.lumi.app`, ürün adı `Lumi`, versiyon `package.json`'dan (0.2.4),
  kategori `public.app-category.developer-tools`. İkon: `build/icon.png` (tek PNG,
  electron-builder platform formatlarına çevirir; native'de `.icns` / Asset Catalog gerekir).
- **macOS hedefleri:** `dmg` + `zip`; artifact adı `Lumi-<version>-<arch>-mac.<ext>`.
- **Codesigning:** `hardenedRuntime: true`, `notarize: true` (Apple notarization),
  `gatekeeperAssess: false`.
- **Entitlements (`build/entitlements.mac.plist` ve inherit varyantı, ikisi de aynı set):**
  - `com.apple.security.cs.allow-jit`
  - `com.apple.security.cs.allow-unsigned-executable-memory`
  - `com.apple.security.cs.allow-dyld-environment-variables`
  - `com.apple.security.cs.disable-library-validation`
  - `com.apple.security.device.audio-input`
  - (inherit dosyasında ek olarak `com.apple.security.inherit` — child process'ler için)
  - **Native notu:** İlk dördü V8 JIT/Electron için gereklidir; Swift app'te **gerekmez**
    ve güvenlik açısından kaldırılmalıdır. `audio-input` (mikrofon) ve child process'lerin
    entitlement inheritance'ı (PTY'de çalışan claude CLI için) korunmalıdır.
    **App Sandbox kullanılmıyor** — uygulama keyfi dizinlere ve process spawn'a ihtiyaç
    duyduğundan native'de de sandbox'sız (Developer ID dağıtımı, Mac App Store değil)
    kalması gerekir.
- **Auto-update YOK:** Publish `never`; `electron-updater` veya benzeri bir mekanizma yok.
  Kullanıcı yeni sürümü manuel indirir. Native'de Sparkle eklemek bir iyileştirme fırsatı
  ama mevcut davranış "güncelleme yok"tur.
- **Paket içeriği:** `out/**` (derlenmiş kod), `default-actions/**` ve `default-personas/**`
  (YAML şablonları — Resources olarak bundle'lanır; ilgili alt sistemler ilk çalıştırmada
  bunları config dizinine kopyalar/okur). `node-pty` asar dışında unpack edilir
  (native binary + spawn-helper). **Native notu:** default YAML'lar app bundle
  Resources'ına konmalı.
- **Diğer platformlar:** Windows NSIS + portable, Linux AppImage + deb (deb bağımlılık
  listesi dahil) — macOS-native rewrite kapsamı dışı.
- **Build pipeline:** `electron-vite` üç hedef derler (main → `out/main`, preload →
  `out/preload`, renderer → `out/renderer`); `electron`/`node-pty` external. Script'ler:
  `dev`, `build`, `test` (vitest), `lint`, `typecheck`, `build:mac|win|linux|all`.
  Node >= 22 gerekir.
- **scripts/runtime-regression-smoke.sh:** CI/lokal smoke check — lint + typecheck +
  "kaldırılmış legacy IPC kanalları ve preload alias'ları kaynakta yok", "deprecated
  terminal status `'running'` yok", "modüler IPC handler dosyaları mevcut" kontrolleri.
  Native projede karşılığı: benzer bir lint+test+convention smoke script'i.

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **Main/renderer ayrımı ve tüm IPC katmanı** — native'de tek process; IPC kanalları
   doğrudan method call / Combine-NotificationCenter / delegate'e dönüşür. `safeSend`,
   preload, contextIsolation tamamen kalkar.
2. **Renderer crash recovery ve `did-fail-load` reload** — karşılığı yok; ama kök neden
   (sınırsız terminal buffer → OOM) native'de de buffer cap ile adreslenmeli.
3. **JIT/unsigned-memory/dyld entitlements** — kaldırılmalı.
4. **`ready-to-show` 5sn force-show, Linux GPU/sandbox switch'leri** — tamamen Electron
   workaround'u, taşınmaz.
5. **Custom title bar + traffic light konumlandırma/gizleme** — native'de
   `NSWindow` `titlebarAppearsTransparent` / `fullSizeContentView` + `standardWindowButton`
   ile çözülür; `hiddenInset` görünümü birebir taklit edilebilir.
6. **Menü 'shortcut' string event köprüsü** — native'de menü item'ları doğrudan
   action/selector'a bağlanır.
7. **Zoom (Cmd+/Cmd-) ve Reload/DevTools menüleri** — web içeriği olmadığından ya düşer
   ya da font-scaling olarak yeniden tasarlanır.
8. **electron-vite / electron-builder pipeline** — Xcode + `codesign`/`notarytool`
   (veya tuist/fastlane) pipeline'ına dönüşür.

## Native rewrite notları (riskler, dikkat edilecekler)

- **Quit onayı akışını Cmd+Q dahil her çıkış yoluna bağla.** Electron'da bu, menüdeki
  Quit'in `close()` çağırmasıyla sağlanıyor. Native'de `applicationShouldTerminate(_:)`
  içinde aktif PTY sayısı > 0 ise `.terminateLater` dönüp onay dialogu göstermek;
  onaydan sonra PTY'leri öldürüp `reply(toApplicationShouldTerminate:)` çağırmak gerekir.
  Ayrıca crash/force-quit durumlarında zombi PTY bırakmamak için child process'ler bir
  process group'ta tutulup SIGTERM/SIGKILL ile topluca temizlenmeli.
- **PATH problemi native'de de birebir var.** Finder'dan başlatılan Swift app de minimal
  PATH alır. `fixProcessPath` stratejisi (login shell'den `$PATH` çözme, 5 sn timeout,
  bilinen dizin fallback'leri) PTY ve `Process` spawn ortamlarına uygulanmalı. Login
  shell çağrısının başlangıcı bloklamaması (async) ve fish/nushell gibi shell'lerde
  farklı syntax gerekebileceği değerlendirilmeli.
- **Mikrofon/TCC:** Voice mode'u kullanan asıl process PTY içindeki claude CLI'dır;
  mikrofon izni Lumi'nin TCC kaydı üzerinden akar. `NSMicrophoneUsageDescription` +
  `audio-input` entitlement + (gerekirse) child'ların entitlement inheritance'ı test
  edilmeli — bu zincir kırılırsa voice mode sessizce çalışmaz.
- **App Sandbox kullanma.** Keyfi repo dizinlerine erişim, login shell çalıştırma ve
  PTY spawn sandbox ile uyumsuz; dağıtım Developer ID + notarization olmalı (mevcutla aynı).
- **ui-state.json formatı paylaşımlı:** window bounds ile renderer UI state'i aynı
  dosyada. Native'de ya aynı dosya formatı okunarak migration yapılmalı ya da
  `NSWindow` frame autosave + ayrı state dosyasına geçilmeli; mevcut kullanıcıların
  pencere/tab durumunu kaybetmemesi için tek seferlik migration önerilir.
- **Legacy config dizinleri** (`~/.pulpo`, `~/.ai-orchestrator`) hâlâ canlı kullanıcı
  verisi içerebilir; native ilk açılışta `~/.lumi` yoksa bunlardan migration yapmalı.
- **Çoklu monitör bounds doğrulaması** native'de de gerekli (`NSScreen.screens` ile
  kesişim testi) — frame autosave kullanılırsa AppKit bunu kısmen kendisi halleder.
- **Sleep/wake sonrası PTY sağlığı:** `terminal:sync`'in amacı uyku sonrası state
  tutarlılığı; native'de `NSWorkspace.didWakeNotification` ile PTY'lerin yaşadığını
  doğrulayıp UI'ı tazelemek korunmalı.
- **Auto-update yok** — scope'a Sparkle eklenecekse ayrıca planlanmalı; mevcut davranış
  parite hedefi değildir.
- **Tray/menubar ikonu ve dock badge app shell'de yok** (bildirim alt sistemi ayrıca
  incelenmeli); dock davranışı yalnızca standart `activate`-ile-pencere-yeniden-aç.
