# Main Process Servisleri (config, persona, action, notification, system, platform, browser)

Bu doküman Lumi'nin main process'indeki yedi alt sistemi kapsar: `src/main/config`, `src/main/persona`, `src/main/action`, `src/main/notification`, `src/main/system`, `src/main/platform`, `src/main/browser` ve repo kökündeki `default-actions/`, `default-personas/` klasörleri.

> Not: `src/main/browser` klasörü **boş** (hiç dosya içermiyor). "Browser" davranışları aslında `src/main/index.ts` içinde (external link'leri sistem tarayıcısına yönlendirme) ve `SHELL_OPEN_EXTERNAL` IPC handler'ında yaşıyor; bu doküman onları da kapsıyor.

---

## 1. ConfigManager (src/main/config)

### Amaç ve sorumluluk
Kalıcı uygulama konfigürasyonu, UI layout state'i, günlük work-log kayıtları ve keşfedilen terminal codename koleksiyonunun disk üzerinde JSON olarak saklanması. Tüm veriler platform-spesifik config dizininde yaşar (bkz. Platform bölümü).

### Feature envanteri

#### 1.1 App Config (config.json)
- **Davranış:** `getConfig()` dosyayı okur, `DEFAULT_CONFIG` ile merge eder (`{...DEFAULT_CONFIG, ...diskteki}`). `setConfig(partial)` mevcut config'i okuyup partial ile merge edip pretty-printed (2 space indent) JSON yazar.
- **Migration kuralları (`migrateConfig`):**
  - `additionalPaths` array değilse `[]`'e zorlanır.
  - `aiProvider` geçerli değer değilse (`'claude' | 'codex'` dışında) default `'claude'`'a düşer.
  - Eksik tüm alanlar default'tan tamamlanır (forward-compatible).
- **Config şeması (defaults):**
  - `projectsRoot: string` (default `''`)
  - `additionalPaths: AdditionalPath[]` — `{id, path, type: 'root'|'repo', label?}`
  - `aiProvider: 'claude' | 'codex'` (default `'claude'`)
  - `maxTerminals: number` (default `12`)
  - `theme: 'dark' | 'light'` (default `'dark'`)
  - `terminalFontSize: number` (default `13`)
  - `notifications: NotificationSettings` — `{unseenEnabled: true, unseenIntervalMinutes: 1, seenEnabled: true, seenIntervalMinutes: 5}`
- **Edge-case'ler:** Dosya yoksa veya parse hatası varsa sessizce default döner (console.error loglar). Yazma hatası handle edilmiyor (exception fırlar).
- **Kullanıcıya etki:** Settings ekranındaki tüm tercihler; restart sonrası korunur.

#### 1.2 First-run tespiti
- **Davranış:** `isFirstRun()` → config.json yoksa, okunamıyorsa veya `projectsRoot` boşsa `true`. Onboarding/setup ekranını tetikler.

#### 1.3 UI State (ui-state.json)
- **Davranış:** `getUIState()`/`setUIState(partial)` config ile aynı merge mantığı. `DEFAULT_UI_STATE` ile merge edilir.
- **Şema:** `openTabs: string[]`, `activeTab: string|null`, `leftSidebarOpen` (default true), `rightSidebarOpen` (default false), `projectGridLayouts: Record<repoPath, {mode: 'auto'|'columns'|'rows', count}>`, `windowBounds?: {x,y,width,height}`, `windowMaximized?: boolean`.
- **Kullanıcıya etki:** Uygulama yeniden açıldığında açık tab'lar, sidebar durumları, pencere konumu/boyutu geri gelir. `index.ts` pencere kapanırken `windowMaximized` ve (maximize değilse) `windowBounds` kaydeder.

#### 1.4 Work Logs (work-logs/<YYYY-MM-DD>/<repo>_<id>.json)
- **Davranış:** `saveWorkLog(log)` bugünün tarihiyle (`toISOString().split('T')[0]`) alt klasör oluşturup `<repo>_<id>.json` yazar. `getWorkLogs(date?)` verilen (veya bugünün) tarihindeki tüm `.json` dosyalarını okur; parse edilemeyenleri atlar (log'lar).
- **WorkLog şeması:** `{id, repo, task, startedAt, completedAt?, status: 'running'|'completed'|'error', output}`.
- **Not:** Şu an main tarafında aktif çağıran yok gibi görünüyor — terminal yaşam döngüsüyle entegrasyon renderer/terminal tarafında olabilir; rewrite'ta kullanım yeri doğrulanmalı.

#### 1.5 Discovered Codenames (discovered-codenames.json)
- **Davranış:** Terminal'lere rastgele "codename" isimleri verilir (TerminalManager, `generateCodename`). `addDiscoveredCodename(name)`: zaten listede ise `false`, yeni ise listeye ekleyip dosyayı (compact JSON, indent yok) yazar ve `true` döner. Bu boolean UI'da "yeni codename keşfedildi" animasyonunu tetikler.
- **Format:** Düz string array: `["nimbus", "quasar", ...]`.
- **Bağlantı:** TerminalManager `ICodenameTracker` interface'i üzerinden ConfigManager'ı kullanır (DI, `handlers.ts`'te wire edilir).
- **Not:** `COLLECTION_GET` IPC kanalı tanımlı ama hiçbir yerde handle edilmiyor — ölü kanal, rewrite'ta ya implemente edilmeli ya atılmalı.

### Persistence özeti
| Dosya | Format | İçerik |
|---|---|---|
| `<configDir>/config.json` | pretty JSON | App config |
| `<configDir>/ui-state.json` | pretty JSON | UI layout state |
| `<configDir>/work-logs/<date>/<repo>_<id>.json` | pretty JSON | Oturum logları |
| `<configDir>/discovered-codenames.json` | compact JSON array | Codename koleksiyonu |

Dizinler constructor'da otomatik oluşturulur (`mkdir -p` semantiği).

### IPC kanalları
- `config:get`, `config:set`, `config:is-first-run`
- `ui-state:get`, `ui-state:set`
- **Side-effect propagation (CONFIG_SET handler'ında):** `maxTerminals` → `TerminalManager.setMaxTerminals`; `projectsRoot` → `RepoManager.setProjectsRoot`; `additionalPaths` → `RepoManager.setAdditionalPaths`; `notifications` → `NotificationManager.updateSettings`. Repo'ları etkileyen değişiklikte renderer'a `repos:changed` push edilir.

---

## 2. PersonaStore (src/main/persona)

### Amaç ve sorumluluk
YAML tabanlı "persona"lar: önceden tanımlanmış davranış/system-prompt ile Claude/Codex CLI oturumu başlatan ön ayarlar. İki scope: **user** (`<configDir>/personas/`) ve **project** (`<repo>/.lumi/personas/`).

### Feature envanteri

#### 2.1 Persona yükleme ve şema
- **YAML şeması:** zorunlu `id`, `label`; opsiyonel `provider` (`claude`/`codex`), `claude` (ClaudeConfig bloğu), `codex` (`{model?}`). `id` veya `label` eksikse dosya sessizce atlanır. Parse hatası loglanıp atlanır.
- **ClaudeConfig alanları:** `appendSystemPrompt`, `systemPrompt`, `model`, `allowedTools[]`, `disallowedTools[]`, `tools` (string), `permissionMode`, `maxTurns`.

#### 2.2 Default persona seeding
- **Davranış:** Başlangıçta `app.getAppPath()/default-personas/` içindeki tüm `.yaml/.yml` dosyaları user dizinine **her zaman üzerine yazılarak** kopyalanır. Yani kullanıcı default persona dosyasını düzenlerse her restart'ta değişiklikleri kaybolur (bilinçli davranış — action'lardan farklı!).
- **Gelen defaultlar:** `architect`, `expert`, `fixer`, `reviewer` — hepsi sadece `appendSystemPrompt` içerir (rol talimatları).

#### 2.3 File watching ve canlı reload
- **Davranış:** User dizini `fs.watch` ile izlenir; her değişiklikte tüm dizin yeniden yüklenir ve `onChange` callback tetiklenir → renderer'a `personas:changed` push edilir. Project dizinleri `loadProjectPersonas(repoPath)` çağrıldığında (IPC `personas:load-project`) yüklenir ve izlenmeye başlanır. Dizin yoksa boş liste set edilir, watcher kurulmaz.
- **Edge-case:** Watcher kurulurken dizin yoksa hata yutulur. Aynı dizine ikinci watcher kurulmaz (Map ile dedupe).

#### 2.4 Scope merge / override
- **Davranış:** `getPersonas(repoPath?)` → user persona'lar + project persona'lar; aynı `id`'ye sahip project persona, user persona'yı **gizler** (override).

#### 2.5 Persona spawn (IPC `personas:spawn`)
- **Davranış (handler'da):** Yeni terminal spawn edilir, terminalin "task" etiketi persona `label`'ı yapılır. Provider = `persona.provider ?? aktif config provider`. Base komut: claude için `claude ""\r`, codex için `codex\r`. Komut `buildAgentCommand` ile flag'ler enjekte edilerek terminale yazılır.
- **Kullanıcıya etki:** Sidebar'dan persona'ya tıklayınca o rolde hazır bir AI oturumu açılır.

### Persistence
- User: `<configDir>/personas/*.yaml`
- Project: `<repo>/.lumi/personas/*.yaml` (repo ile birlikte versiyonlanır, ekiple paylaşılır)

### IPC: `personas:list`, `personas:spawn`, `personas:load-project`, push: `personas:changed`.

---

## 3. Action Sistemi (src/main/action)

### Amaç ve sorumluluk
YAML tabanlı "Quick Action"lar: tek tıkla yeni terminal açıp sıralı adımlar (shell komutu yazma, output bekleme, gecikme) çalıştıran otomasyonlar. Dört parça: **ActionStore** (yükleme/izleme/history), **ActionEngine** (step çalıştırıcı), **build-agent-command** (provider-aware komut inşası), **create/edit action prompt'ları** (AI destekli action oluşturma/düzenleme akışları).

### Feature envanteri

#### 3.1 Action YAML şeması
- Zorunlu: `id`, `label`, `steps`. Opsiyonel: `description` (sidebar tooltip), `icon` (default `'Zap'`; değerler: Terminal, TestTube, Package, GitBranch, FileEdit, Zap, vb. — Lucide ikon adı), `provider`, `claude` (ClaudeConfig), `codex` (`{model?}`), `modified_at` (ISO timestamp — kullanıcı düzenlemesi işareti).
- Step tipleri:
  - `write` — terminale keystroke olarak yazılır; içerik `\r` ile bitmeli (Enter). YAML'da çift tırnak şart (`\r` escape'inin çalışması için).
  - `wait_for` — `pattern` regex'i terminal output'unda eşleşene kadar bloklar; `timeout` default **10000ms**, aşılırsa hata fırlatılır (`wait_for timeout: pattern "..." not matched in Xms`).
  - `delay` — sabit `ms` bekleme.

#### 3.2 Default action seeding (akıllı, persona'dan farklı)
- Başlangıçta `app.getAppPath()/default-actions/` → user actions dizinine kopyalanır, **AMA** hedef dosyada `modified_at` alanı varsa atlanır (kullanıcı düzenlemesi korunur; ID yine default olarak işaretlenir). Parse edilemeyen mevcut dosya üzerine yazılır.
- Default ID'leri `defaultIds` set'inde tutulur; `actions:default-ids` IPC ile renderer'a verilir (UI'da "default" rozetleme/silme koruması için).
- **Deprecated temizliği:** Artık ship edilmeyen eski default dosyalar (`new-terminal.yaml`, `create-action.yaml`, `git-pull.yaml`, `install-deps.yaml`, `install-plugins.yaml`) user dizininden silinir.
- **Gelen default action'lar:** `create-project` (zsh `read` ile isim sorup `~/.lumi/templates/CLAUDE.md.template`'ten proje iskeleti + git init; `wait_for "Project created:"` 60sn), `run-tests` (claude + sonnet + test allowedTools), `sync-plugins` (claude + sonnet + uzun appendSystemPrompt ile plugin kurulum workaround'u, maxTurns 15), `update-claude-md` (claude + CLAUDE.md bakım prompt'u).
  - Dikkat: `create-project` action'ı `~/.lumi/templates/` altında template dosyaları varsayıyor — bu template'lerin nereden seed edildiği bu alt sistemlerde değil; rewrite'ta doğrulanmalı.

#### 3.3 File watching + otomatik history/backup
- User dizini `fs.watch` ile izlenir. Olay geldiğinde:
  - Dosya hâlâ varsa (create/modify): **backup alınır** → `<userDir>/.history/<action-id>/<ISO-timestamp>.yaml` (timestamp'te `:` → `-`, milisaniye kısmı kırpılır). Action başına **max 20** backup; eskiler silinir. Best-effort (hatalar yutulur).
  - Dosya silinmişse: `reseedIfDefault()` → seedDefaults yeniden çalışır, silinen bir default anında geri gelir.
  - Her durumda dizin yeniden yüklenir ve `actions:changed` push edilir.
- `.history` alt dizini action yüklemesine girmez (sadece kök dizindeki yaml'lar okunur).

#### 3.4 History API
- `getActionHistory(actionId)` → backup dosya adları, yeniden eskiye sıralı.
- `restoreAction(actionId, timestamp)` → backup'ı aktif dosyanın üzerine kopyalar; aktif dosya bulunamazsa `<actionId>.yaml` adıyla restore eder. Backup yoksa `false`.
- **Kullanıcıya etki:** Action düzenlemeleri otomatik versiyonlanır; UI'dan eski versiyona dönülebilir.

#### 3.5 Scope merge, silme, dosya erişimi
- `getActions(repoPath?)`: persona ile aynı override mantığı (project, user'ı id ile gizler).
- `deleteAction(id, scope, repoPath?)`: ilgili dizindeki yaml'ları tarayıp `id` eşleşen ilk dosyayı siler. **Dosya adı ID ile aynı olmak zorunda değil** — tüm aramalar içerikteki `id` alanına göre yapılır (`getActionContent`, `getActionFilePath` de öyle).
- Default bir action silinirse watcher'daki reseed onu anında geri getirir (kasıtlı: defaultlar silinemez, sadece düzenlenebilir).

#### 3.6 ActionEngine — step çalıştırma
- `execute(action, repoPath)`: ana pencere yoksa hata. `TerminalManager.spawn(repoPath, window)` ile **her zaman yeni terminal** açar (limit doluysa `null` döner, action çalışmaz). Step'leri sırayla işler:
  - `write`: içerik `buildAgentCommand(content, action)` ile dönüştürülüp terminale yazılır.
  - `wait_for`: TerminalManager'ın `output` EventEmitter'ına handler takılır; ilgili terminalin her data chunk'ında regex test edilir; eşleşmede resolve, timeout'ta reject + handler temizliği.
  - `delay`: `setTimeout`.
- Dönüş: `SpawnResult {id, name, isNew}`. Handler bu sonuçla terminalin task etiketini `action.label` yapar.
- **Edge-case:** `wait_for` regex'i tek bir output chunk'ı içinde eşleşmek zorunda (chunk'lar birleştirilmiyor) — pattern chunk sınırına denk gelirse kaçabilir. Native rewrite'ta rolling buffer düşünülmeli.

#### 3.7 buildAgentCommand — provider-aware komut inşası
- Akış: `provider = action.provider ?? 'claude'` → `remapProviderCommand` satır başındaki `claude` kelimesini provider binary'sine çevirir (codex seçiliyse `claude "..."` → `codex "..."`).
- **Claude yolu (`buildClaudeCommand`):** içerik `claude ` ile başlamıyorsa dokunulmaz (örn. `git pull\r`). Flag enjeksiyonu:
  - `systemPrompt` → temp dosyaya yazılır (`<tempDir>/system-prompt-<Date.now()>.txt`), `--system-prompt-file '<path>'`
  - `appendSystemPrompt` → temp dosya, `--append-system-prompt-file '<path>'`
  - `model` → `--model X`; `allowedTools`/`disallowedTools` → her tool çift tırnaklı, `--allowedTools "A" "B"`; `tools` → `--tools "..."`; `permissionMode` → `--permission-mode X`; `maxTurns` → `--max-turns N`
  - Sonuç: `claude <flags> -- <orijinal-prompt>` (flag yoksa içerik aynen döner).
- **Codex yolu (`buildCodexCommand`):** içerik `codex` ile başlamıyorsa veya config'te `model` yoksa veya komutta zaten `--model` varsa dokunulmaz; aksi halde `codex --model X ...`.
- **Temp dosya notu:** System prompt dosyaları hiç temizlenmiyor (sadece OS tmp temizliğine güveniliyor). Dosya adı `Date.now()` bazlı — aynı milisaniyede çakışma teorik risk.

#### 3.8 AI destekli "Create Action" akışı (IPC `actions:create-new`)
- Sentetik bir action (`id: '__create-action'`) inşa edilir: provider claude ise `CREATE_ACTION_PROMPT` `appendSystemPrompt` olarak verilir ve terminale `claude "."\r` yazılır (prompt flag'le enjekte edilir). Codex ise prompt heredoc ile gömülür: `codex exec - <<'__AI_ORCH_<uuid>__' ... marker\r` (randomized delimiter — prompt injection güvenliği).
- `CREATE_ACTION_PROMPT` içeriği: AI'ya action YAML şemasını, step tiplerini, YAML quoting kurallarını (`\r` çift tırnak içinde olmalı), zsh uyumluluk notlarını (`read "var?prompt"`, `${PWD:h}`), scope açıklamasını, ClaudeConfig rehberini, 4 örnek pattern'i, tasarım kurallarını (tek amaç, wait_for > delay, description zorunlu) ve ikon rehberini verir. AI'dan YAML'ı onay sormadan doğrudan doğru path'e yazması istenir. Dosya yazılınca watcher yakalar → sidebar otomatik güncellenir.

#### 3.9 AI destekli "Edit Action" akışı (IPC `actions:edit`)
- Mevcut YAML içeriği + dosya yolu `buildEditActionPrompt`'a gömülür; sentetik `__edit-action` action'ı ile terminal açılır (create ile aynı provider mantığı). Prompt AI'ya: değişikliği uygula, **`modified_at` alanını mutlaka güncelle** (default'un seed'le ezilmesini engeller), aynı dosya yoluna onaysız yaz, id/scope'u koru. Terminal task'i `Edit: <actionId>` yapılır. `repoPath` verilmemişse terminal user actions dizininde açılır.

#### 3.10 Action çalıştırma (IPC `actions:execute`)
- `actionId` ile action bulunur (bulunamazsa hata), `provider` boşsa aktif config provider'ı atanır, engine ile çalıştırılır, terminal task'i action label'ı yapılır.

### Persistence
- User: `<configDir>/actions/*.yaml`; history: `<configDir>/actions/.history/<id>/<timestamp>.yaml` (max 20)
- Project: `<repo>/.lumi/actions/*.yaml`
- Temp system prompt'lar: `<tempDir>/system-prompt-*.txt`, `append-system-prompt-*.txt`

### IPC: `actions:list`, `actions:execute`, `actions:delete`, `actions:load-project`, `actions:create-new`, `actions:edit`, `actions:history`, `actions:restore`, `actions:default-ids`; push: `actions:changed`.

---

## 4. NotificationManager (src/main/notification)

### Amaç ve sorumluluk
Terminal status state machine geçişlerine göre OS native bildirimleri ve renderer toast'larını yönetmek. PTY output'u taramaz — tüm tetikleme status machine'den `notifyStatusChange` çağrısıyla gelir.

### Feature envanteri

#### 4.1 Status-driven bildirim mantığı
Terminal status'ları: `idle | working | waiting-unseen | waiting-focused | waiting-seen | error`.
- `waiting-unseen` (asistan input bekliyor, kullanıcı görmedi): **anında** bildirim ("Assistant is waiting for input") + `unseenIntervalMinutes` (default 1 dk) aralıkla tekrar.
- `waiting-seen` (kullanıcı gördü ama hâlâ bekliyor): anında bildirim YOK, `seenIntervalMinutes` (default 5 dk) aralıkla tekrar ("Assistant is still waiting for input").
- `waiting-focused` (kullanıcı o terminale bakıyor): bildirim yok, mevcut interval temizlenir.
- `error`: tek seferlik "Assistant exited with error", tekrar yok.
- `working`/`idle`: interval temizlenir.
- Her status değişiminde önce o terminalin interval'i temizlenir (state başına en fazla bir interval).

#### 4.2 Ayar güncelleme
- `updateSettings(NotificationSettings)`: ayarları değiştirir ve **takip edilen tüm terminaller için** son bilinen status'a göre interval'leri yeni süre/enable bayraklarıyla yeniden kurar. `CONFIG_SET` ile `notifications` değişince ve startup'ta çağrılır.

#### 4.3 Bildirim gönderimi
- Pencere **focus'ta değilse**: native OS `Notification` gösterilir — `title` = mesaj, `body` = repo adı (path'in son segmenti), `silent: true` (ses yok). Tıklanınca pencere `show()` + `focus()` ve renderer'a `notification:click` (terminalId ile) gönderilir → UI ilgili terminale gider.
- **Her durumda** (focus olsun olmasın) renderer'a `terminal:bell` (terminalId, repoName) push edilir → in-app toast.

#### 4.4 Temizlik
- `removeTerminal(terminalId)`: terminal kapanınca interval + context + status kayıtları silinir. Çağrılmazsa interval sızar (terminal exit akışında zorunlu).
- Interval tick'inde pencere destroyed ise interval kendini temizler.

### Persistence: yok (ayarlar ConfigManager'da, `config.json > notifications`).

### Native rewrite notu: macOS'ta `UNUserNotificationCenter` ile birebir karşılanır; "window focused" kontrolü `NSApplication.isActive` + key window kontrolüne çevrilmeli. Bildirim izni istenmesi gerekir (Electron'da otomatikti).

---

## 5. SystemChecker (src/main/system)

### Amaç ve sorumluluk
Uygulamanın çalışması için ön koşulların sağlık kontrolü (settings/onboarding'deki "System Check" ekranı). Senkron check listesi + opsiyonel `fix` aksiyonları.

### Feature envanteri
Her check sonucu: `{id, label, status: 'pending'|'running'|'pass'|'fail'|'warn', message, fixable?}`.

1. **shell**: `getDefaultShell()` başarılıysa pass (`Found: zsh`), exception'da fail.
2. **node-pty**: test amaçlı gerçek bir PTY spawn edilip hemen kill edilir (macOS/Linux: `echo test`, Win: `powershell.exe`). Başarısızsa fail + "reinstall" önerisi. (Native rewrite'ta karşılığı: kendi PTY mekanizmanın smoke testi.)
3. **Platform check'leri** (`getPlatformChecks()`):
   - macOS **spawn-helper**: node-pty kurulum dizinini hem packaged (`Resources/app.asar.unpacked/node_modules/node-pty`) hem dev konumlarında arar; `prebuilds/darwin-*/spawn-helper` ve `build/Release/spawn-helper` binary'lerinin varlığı + execute izni (`X_OK`) kontrol edilir. Eksik/izinsizse **warn** (asla fail değil), hepsi tamamsa pass.
   - Windows **conpty**: `os.release()` build numarası >= 17763 (Win10 1809) kontrolü.
4. **claude-cli**: `which claude` (Win: `where`), 5sn timeout. Bulunamazsa fallback olarak `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin` altında executable aranır. Yine yoksa: seçili provider claude **değilse** sadece **warn** ("ileride provider değiştirirsen kur"), claude **ise** **fail + fixable**. `fix()` = install sayfasını (`https://code.claude.com/docs/en/setup`) tarayıcıda açar, "Re-run checks after installing" mesajı döner.
5. **codex-cli**: claude-cli ile simetrik; install URL `https://github.com/openai/codex`.

- Provider bilgisi constructor'a verilen `getSelectedProvider` callback'i ile **her çalıştırmada taze** okunur (config değişikliğine duyarlı).
- `runAll()` tüm check'leri sırayla senkron çalıştırır. `fix(checkId)`: bilinmeyen id veya fix'i olmayan check için fail mesajı döner.

### IPC: `system:check-run`, `system:check-fix`.

---

## 6. Platform Katmanı (src/main/platform)

### Amaç ve sorumluluk
Tüm platform-spesifik mantığın tek modülde toplanması. Kural: app genelinde inline `process.platform` kontrolü yasak; her şey buradan geçer.

### Feature envanteri

#### 6.1 Platform detection (index.ts)
`isMac`, `isWin`, `isLinux` sabitleri + tüm alt modüllerin re-export'u.

#### 6.2 Config/Temp dizin çözümü (paths.ts)
- `getConfigDir()`:
  - macOS/Linux: `~/.lumi` (dev modda `~/.lumi-dev`)
  - Windows: `%APPDATA%/lumi` (env yoksa `~/AppData/Roaming/lumi`; dev: `lumi-dev`)
  - **Legacy migration (sadece production):** yeni dizin yoksa ama `.pulpo` varsa onu kullanır; o da yoksa `.ai-orchestrator` varsa onu kullanır. (Yani gerçek bir "taşıma" yapılmıyor — eski dizin yerinde kullanılmaya devam ediliyor.)
  - Dev/prod izolasyonu: `NODE_ENV=development` → `-dev` suffix; dev verisi production'ı kirletmez.
- `getTempDir()`: `os.tmpdir()/lumi` (dev: `lumi-dev`) — system prompt temp dosyaları için.

#### 6.3 Shell çözümü (shell.ts)
- `getDefaultShell()`: platform başına fallback zinciri — macOS: `zsh → bash → sh`; Windows: `powershell.exe → cmd.exe`; Linux: `bash → zsh → sh`. Her aday `which`/`where` (5sn timeout) ile denenir, ilk bulunan **cache'lenir** (process ömrü boyunca; shell ortamı değişirse restart gerekir). Hiçbiri yoksa açıklayıcı hata fırlatılır.
- `getShellArgs()`: macOS/Linux'ta `['-l']` (login shell — kullanıcı profili, tam PATH, alias'lar yüklensin), Windows'ta `[]`.

#### 6.4 PATH düzeltme (shellEnv.ts) — kritik
- `fixProcessPath()`: Dock/Finder'dan başlatılan GUI app minimal PATH alır (`/usr/bin:/bin:/usr/sbin:/sbin`); `claude`/`codex` bulunamaz. Çözüm:
  1. `$SHELL -ilc 'echo -n "$PATH"'` ile (interactive login shell, 5sn timeout) kullanıcının gerçek PATH'i alınır; başarısızlık sessizce yutulur.
  2. Her durumda bilinen dizinler eklenir (varsa): `~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `~/.nvm/current/bin`, `~/.volta/bin`.
  3. Set semantiğiyle dedupe edilip `process.env.PATH` güncellenir. Windows'ta no-op.
- Startup'ta, herhangi bir SystemChecker veya PTY spawn'dan **önce** bir kez çağrılır.

#### 6.5 Pencere konfigürasyonu (window.ts)
- macOS: `titleBarStyle: 'hiddenInset'`, traffic light pozisyonu `{x:15, y:19}` (custom titlebar üstünde).
- Windows: `titleBarStyle: 'hidden'` + `titleBarOverlay` (renk `#12121f`, sembol `#8a8aa3`, yükseklik 52 — native min/max/close butonları korunur).
- Linux: sadece `hidden` (overlay Wayland/tiling WM'lerde unstable).

#### 6.6 Platform health check'leri (systemChecks.ts)
Bkz. SystemChecker bölümü madde 3.

---

## 7. Browser davranışları (src/main/browser boş; gerçek davranış index.ts + system handler)

- `src/main/browser/` dizini **boş** — muhtemelen planlanıp vazgeçilmiş. Rewrite'ta ayrı bir alt sistem gerekmiyor.
- **External link politikası (index.ts):**
  - `webContents.setWindowOpenHandler`: tüm `window.open`/target=_blank → `shell.openExternal(url)` + `action: 'deny'` (app içinde asla yeni pencere açılmaz).
  - `will-navigate`: mevcut URL dışına her navigasyon engellenir ve sistem tarayıcısında açılır (renderer'ın app dışına gitmesi imkânsız — güvenlik sınırı).
- **`shell:open-external` IPC:** renderer'dan gelen URL yalnızca `http://` veya `https://` ile başlıyorsa `shell.openExternal` ile açılır (scheme whitelist — `file://`, `javascript:` vb. engelli).
- SystemChecker `fix()` aksiyonları da `shell.openExternal` kullanır.
- **Native karşılık:** `NSWorkspace.shared.open(url)` + aynı scheme whitelist'i. WKWebView kullanılmayacaksa navigasyon koruması zaten konu dışı kalır.

---

## Veri akışı ve bağımlılıklar (genel)

```
setupIpcHandlers() (startup):
  ConfigManager ──config──> NotificationManager.updateSettings
                ──maxTerminals, codenameTracker──> TerminalManager
                ──projectsRoot, additionalPaths──> RepoManager
  ActionStore / PersonaStore ──onChange──> renderer push (actions:changed / personas:changed)
  ActionEngine ──spawn/write/output events──> TerminalManager
  SystemChecker ──getSelectedProvider()──> ConfigManager (lazy)
```

- ActionEngine ve persona spawn **TerminalManager**'a bağımlı (bu dokümanın kapsamı dışında, ayrı spec).
- `buildAgentCommand()` tek giriş noktası: ActionEngine `write` step'leri, `personas:spawn`, `actions:create-new`, `actions:edit` hepsi bunu kullanır. Native rewrite'ta da tek modülde tutulmalı.
- Renderer bir repo tab'ı açtığında `actions:load-project` / `personas:load-project` çağırarak `<repo>/.lumi/` scope'unu yükletir.

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **`app.getAppPath()` ile default seed'ler:** `default-actions/`, `default-personas/` app bundle'ından okunur. Native'de `Bundle.main.resourceURL` altına resource olarak konmalı.
2. **`fs.watch`:** macOS native'de FSEvents/`DispatchSource.makeFileSystemObjectSource`. Not: `fs.watch` macOS'ta dosya adı verir ama güvenilmez; mevcut kod her event'te tüm dizini yeniden yükleyerek bunu telafi ediyor — aynı "olay → tam reload" stratejisi korunmalı.
3. **Electron `Notification`:** → `UNUserNotificationCenter` (+ izin isteme akışı yeni gereksinim). `silent: true` → ses ataması yapılmaması.
4. **`BrowserWindow.isFocused()/isDestroyed()` guard'ları:** → `NSApp.isActive` / window lifecycle.
5. **IPC kanalları:** Native'de IPC yok; bu kanal listesi doğrudan in-process servis API'sine (örn. ObservableObject / Combine / delegate) dönüşür. Kanal isimleri davranış envanteri olarak kullanılmalı.
6. **node-pty / spawn-helper check'leri:** Native'de `posix_openpt`/`forkpty` kullanılacağı için `node-pty` ve `spawn-helper` check'leri anlamsızlaşır; yerine kendi PTY smoke testi konmalı. Windows ConPTY check'i macOS-only rewrite'ta düşer.
7. **PATH problemi aynen geçerli:** GUI app olarak başlatılan native app de minimal PATH alır. `fixProcessPath` mantığı (login shell'den PATH çekme + bilinen dizinler) birebir taşınmalı; `which` yerine `Process` ile `/usr/bin/which` veya kendi dosya-sistemi araması.
8. **`execSync` (senkron, 5sn timeout):** Ana thread'i bloklar; native'de async `Process` + timeout ile yapılmalı (özellikle startup'taki login-shell PATH çözümü ~yüzlerce ms sürebilir).
9. **`dialog.showOpenDialog`** → `NSOpenPanel`; **window kontrol IPC'leri** (minimize/maximize/close/traffic-light visibility) → native pencere API'leri.
10. **Dev/prod veri izolasyonu:** `NODE_ENV` yerine `#if DEBUG` ile `~/.lumi-dev` ayrımı korunmalı (kullanıcılar mevcut `~/.lumi` verisini native sürümde aynen kullanabilmeli — format değişmemeli!).

## Native rewrite notları (riskler, dikkat edilecekler)

- **Veri formatı geriye dönük uyumlu kalmalı:** `~/.lumi` altındaki tüm JSON/YAML formatları (config.json, ui-state.json, actions/*.yaml, personas/*.yaml, .history yapısı, discovered-codenames.json, work-logs) Electron sürümüyle birebir aynı kalmalı; kullanıcı iki sürüm arasında geçiş yapabilmeli.
- **Seed asimetrisi kritik:** Personalar her startup'ta **ezilir**, action'lar `modified_at` varsa **korunur**. Bu fark bilinçli; yanlış kopyalanırsa ya kullanıcı action düzenlemeleri kaybolur ya da güncellenen default persona'lar kullanıcıya ulaşmaz.
- **`modified_at` sözleşmesi:** Edit Action AI prompt'u bu alanı eklemekle yükümlü. AI eklemeyi unutursa kullanıcının düzenlemesi sonraki restart'ta default ile ezilir. Native'de daha sağlam bir mekanizma (örn. dosya hash karşılaştırması) düşünülebilir ama format uyumu bozulmamalı.
- **wait_for chunk problemi:** Regex tek output chunk'ında aranıyor; native PTY'de chunk boyutları farklı olacağından pattern kaçırma davranışı değişebilir. Küçük bir rolling buffer (örn. son 4KB) üzerinde arama daha güvenilir olur — ama timeout semantiği (default 10sn, hata fırlatma) korunmalı.
- **zsh varsayımı:** Action içerikleri ve AI prompt'ları zsh sözdizimi varsayar (`read "var?..."`, `${PWD:h}`). Default action'lar (özellikle `create-project`) zsh dışında bozulur. macOS-native'de sorun değil ama shell fallback zinciri bash'e düşerse default action'lar kırılır.
- **Temp dosya sızıntısı:** System prompt temp dosyaları temizlenmiyor; native'de app çıkışında veya yaşlanmaya göre temizlik eklenebilir (davranış değişikliği değil, iyileştirme).
- **Path quoting güvenliği:** `--system-prompt-file '<path>'` tek tırnakla sarılıyor; path'te tek tırnak varsa komut kırılır (tmpdir'de pratikte olmaz ama bilinçli kalınmalı). `buildDelimitedInputCommand`'daki rastgele heredoc delimiter (UUID tabanlı) prompt injection önlemi — aynen taşınmalı.
- **Watcher → onChange fırtınası:** Backup yazmak da `.history` altına olduğundan kök watcher'ı tetiklemez, ama AI bir action dosyası yazarken birden çok event gelebilir; renderer `actions:changed`'i debounce'suz alıyor. Native'de coalescing eklenebilir.
- **`COLLECTION_GET` ölü kanal** ve **work-log API'sinin main tarafında aktif kullanıcısı görünmüyor** — rewrite kapsamı netleştirilirken bu ikisi ürün kararına bağlanmalı (taşı/at).
- **NotificationManager interval sızıntısı:** `removeTerminal` çağrısı terminal exit akışına bağlı; native'de terminal lifecycle ile bildirim yöneticisi arasındaki sözleşme (her exit'te cleanup) test edilmeli.
- **SystemChecker senkronluğu:** `runAll` UI thread'de saniyeler sürebilir (5 × 5sn timeout worst case). Native'de async/await ile arka planda koşturulup `running` status'u gerçek anlamda kullanılmalı.
