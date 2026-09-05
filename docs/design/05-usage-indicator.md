# Lumi Native — Kullanım Göstergeleri Tasarımı

> **2026-09-05 refactor (Faz 1–7) ile güncellendi:** K38 kararı A uygulandı (aralık seti {5, 15, 30}, `CachingUsageService` 300 sn TTL), Claude OAuth hata politikası ve Codex probe iptali netleşti, sunum string'leri LumiUI presenter'ına taşındı.
>
> Kullanıcının **Claude ve Codex** aboneliklerinin kullanım durumunu (5 saatlik oturum limiti + haftalık pencereler + reset zamanları) dashboard'da gösterir. Bu doküman implementasyon sözleşmesidir; davranış burada tanımlanır.
>
> **Karar 32 (2026-09-04) §1'i değiştirdi:** veri kaynağı artık sağlayıcı başına, Orca'nın kullandığı yolun aynısıdır — Claude için OAuth endpoint'i (CLI yedekli), Codex için `codex app-server` JSON-RPC. Aşağıdaki §1'in ilk sürüm kararı tarihsel kayıt olarak durur; geçerli kaynak [§1.1](#11-veri-kaynağı-karar-32--2026-09-04)'dir.

Genel kurallar:
- Servis sadece I/O + parse yapar; iş mantığı/UI yok (SOLID, view'dan ayrık).
- Parse mantığı saf/test edilebilir fonksiyon olarak process spawn'dan ayrılır.
- Store→UI akışı projedeki desenle: servis sonucu store'a yazılır, UI `@Observable` ile dinler (Combine yok).
- DI: kullanım servisleri `ServiceRegistry.usage(for:)` üzerinden alınır; store'ları ve yaşam döngüsünü `UsageFeatureAssembly` kurar ([00 §3](./00-architecture.md)).

---

## 1. Veri kaynağı kararı

İki yol değerlendirildi:

| | `claude -p "/usage"` parse | `GET api.anthropic.com/api/oauth/usage` |
|---|---|---|
| ToS | Temiz (resmi araç üzerinden) | Gri alan — OAuth token cc/claude.ai dışında kullanım Consumer ToS ihlali |
| Hız | ~1–2 sn process spawn | Anlık HTTP |
| Rate limit | cc kendi yönetiyor | Sen yönetmelisin (cache zorunlu) |
| Bağımlılık | cc kurulu olmalı | Sadece OAuth token |

**Karar (ilk sürüm, 2026-06-12 — karar 32 ile değişti):** `claude -p "/usage"` çıktısını parse et. `oauth/usage` endpoint'ine doğrudan geçmek ayrı bir karar olarak ertelenmişti; karar 32 o kararı verdi.

## 1.1 Veri kaynağı (karar 32 — 2026-09-04)

**Kural: Orca hangi yoldan erişiyorsa Lumi de aynı yoldan erişir.** Sağlayıcı başına:

| | Claude | Codex |
|---|---|---|
| Birincil | `GET api.anthropic.com/api/oauth/usage`, `Authorization: Bearer <access_token>` + `anthropic-beta: oauth-2025-04-20` + `User-Agent: claude-code/2.1.0` | `codex -c approval_policy=never -s read-only -a never app-server` üzerinden JSON-RPC `account/rateLimits/read` |
| Kimlik kaynağı | macOS Keychain (`Claude Code-credentials` / `$USER`) → yedek `~/.claude/.credentials.json`; `claudeAiOauth.accessToken` | Kapı: `$CODEX_HOME/auth.json` (yoksa `~/.codex/auth.json`) var mı |
| Yedek | Eski `claude -p "/usage"` + `UsageOutputParser` yolu | Yok (Orca'nın PTY `/status` yedeği taşınmadı — [§7](#7-kapsam-dışı-şimdilik)) |
| Yanıt biçimi | `limits[]`: `session` / `weekly_all` / `weekly_scoped`(+`scope.model.display_name`) | `rateLimits.primary` + `.secondary`, `usedPercent` + `windowDurationMins` + `resetsAt` (Unix **saniye**) |

**Gerekçeler:**
- OAuth yolu anlıktır, process spawn'ı yoktur ve **abonelik kotasından düşmez** — `claude -p "/usage"` her çağrıda kotadan düşüyordu. Token kullanıcının kendi hesabınındır, yalnız kendi kullanım verisini okumak için kullanılır; hiçbir yere yazılmaz/loglanmaz.
- Codex penceresi SIRAYA göre değil `windowDurationMins`'e göre sınıflandırılır (300 → oturum, 10080 → haftalık, ±1 dk tolerans); süre tanınmazsa Orca'nın eski primary→session / secondary→weekly eşlemesine düşülür.
- **Codex probe'unda stdin yanıt gelene kadar AÇIK tutulmalıdır.** Üç mesajı peş peşe yazıp stdin'i kapatmak (`SystemProcessRunner`'ın `standardInput` davranışı) sunucunun ikinci isteği hiç yanıtlamamasına yol açıyor — EOF'u kapanma sinyali sayıyor. Bu yüzden `CodexAppServerProbe` kendi pipe yaşam döngüsünü yönetir.
- Auth kapısı (`auth.json` yok → hiç spawn yok) Orca'nın gerekçesiyle aynıdır: giriş yapmamış kullanıcıda spawn zaten başarısız olur ve arka planda beklenmedik bir Codex süreci görünür.
- **Probe iptal edilebilir olmalıdır (Faz 1.7).** `awaitResponse` iptali `try?` ile yutuyordu: çağıran vazgeçtikten sonra probe 30 sn boyunca yoklamaya devam ediyor ve arkasında görünmez bir `codex` süreci bırakıyordu. Artık döngüde `try Task.checkCancellation()` vardır, konuşma `withTaskCancellationHandler` içinde koşar ve hem `defer` hem `onCancel` yolunda `session.shutdown()` çağrılır (`terminate()` sonrası `waitUntilExit()` — zombi bırakılmaz).

**Göstergeler opt-in'dir (karar 32):** `config.usageIndicators` — sağlayıcı başına açık/kapalı. Kapalı sağlayıcı topbar'da çizilmez ve **hiçbir istek atmaz** (manuel refresh dahil); kapı tek yerdedir, `UsageStore.isEnabled`. Default: claude açık (mevcut davranış), codex kapalı.

**Token maliyeti notu:** Çağrıyı bir Agent/subagent ile yapma — subagent spawn'ı ~19k token harcıyor. Doğrudan `claude` binary'sini `Process` ile spawn et; bunun token maliyeti yok (yalnız abonelik kotasından düşer, ki zaten ölçtüğümüz şey o).

## 2. Çağrı

Subprocess olarak:
```
claude -p "/usage"
```
- Interactive REPL'e girmez; print modda çalışır, exit 0 ile döner.
- Binary yolu sabit varsayılmaz; `which claude` / kullanıcının PATH'inden çözülür. Bulunamazsa `.cliNotFound` durumu.
- **Timeout:** Asılı kalmaya karşı ~15 sn. macOS'ta `timeout`/`gtimeout` yok — Swift tarafında `Process` + zamanlayıcı ile kendi timeout'un kurulur, harici komuta güvenilmez.

## 3. Beklenen çıktı (stdout)

```
You are currently using your subscription to power your Claude Code usage

Current session: 0% used · resets Jul 27 at 7:59pm (Europe/Istanbul)
Current week (all models): 7% used · resets Aug 1 at 3:59pm (Europe/Istanbul)
Current week (Fable): 2% used · resets Aug 1 at 3:59pm (Europe/Istanbul)

What's contributing to your limits usage?
...
Last 24h · 684 requests · 11 sessions
  Top MCP servers: UnityMCP 36%
```

Toleranslar:
- **Model-özel haftalık satırların sayısı ve adı SABİT DEĞİLDİR** (`Sonnet only` / `Opus` / `Fable` … gelir, gider). Parse bu satırları isme göre sabit alanlara bağlamaz; 3 yerine 2 limit dönmesi hata değildir.
- API key ile (abonelik yerine) çalışan kullanıcıda ilk satır farklıdır ve yüzde satırları hiç gelmeyebilir → `.apiKey` modu, crash yok.
- Çıktı, limitlerden sonra bir **"What's contributing"** bölümü içerir; oradaki `Top MCP servers: … 36%` gibi satırlar limit DEĞİLDİR ve listeye girmemelidir.
- Çıktı İngilizce gelir (locale İngilizce varsayılır).

## 4. Parse

Satır-bazlı, dayanıklı (tam string eşleşmesine güvenme, regex):

1. Her satır `:` öncesi **etiket** + sonrası **değer** olarak ayrılır.
2. Satır ancak değer kısmı `N% used` kalıbına uyuyorsa **ya da** `resets` içeriyorsa limit sayılır (contributing bölümü bu filtreyle elenir).
3. Etiket sınıflandırması (case-insensitive) — `UsageLimit.Kind`:
   - `session` içeren → `.session` (**öncelikli alan**, topbar göstergesi)
   - `week` içeren + parantez yok / parantez içi `all models` → `.weeklyAll`
   - `week` içeren + parantez içi model adı (`only` eki atılır) → `.weeklyModel("Fable")` — ad çıktıdan gelir, whitelist YOK
   - hiçbiri değil → `.other` (ham etiketle gösterilir, veri düşürülmez)
4. Değer satırından:
   - **Yüzde:** `(\d+)%` → `Int` (0–100), bulunamazsa `nil`.
   - **Reset:** `resets (.+?)(?:\s*\(.*\))?$` → ham reset string'i (örn. `Jun 12 at 1:39pm`); parantez içi timezone (`Europe/Istanbul`) ayrı yakalanır.
5. Reset zamanı mümkünse `Date`'e çevrilir: format `MMM d 'at' h:mma`, yıl yok → içinde bulunulan yıl. Parse başarısızsa ham string saklanır ve UI'da gösterilir — parse hatası veriyi düşürmez.

## 5. Değer tipleri

Immutable struct'lar, alanlar opsiyonel:

```
UsageWindow = {
  percentUsed: Int?      // 0–100
  resetsAt:    Date?     // parse edilebildiyse
  resetsRaw:   String    // ham metin (her zaman)
  timezone:    String?
}

UsageLimit = {
  kind:     .session | .weeklyAll | .weeklyModel(String) | .other
  rawLabel: String        // ":" öncesi ham etiket
  window:   UsageWindow
  id:       String        // dedupe anahtarı (kind'dan türer)
}
// UI başlığı ("5-hour session" / "Weekly (Fable)") MODELDE DEĞİLDİR:
// LumiUI'daki `UsageLimit.displayTitle` presenter extension'ında (refactor 5.9).

UsageSnapshot = {
  limits:     [UsageLimit]   // CLI SIRASINI korur; uzunluk sabit DEĞİL
  mode:       .subscription | .apiKey | .unknown
  fetchedAt:  Date
  // türetilmiş erişimler:
  fiveHour:   UsageWindow?   // en önemlisi (topbar)
  weekAll:    UsageWindow?
  weekly(model:) -> UsageWindow?
}
```

**Neden liste (2026-07-27):** Sabit `weekSonnet`/`weekOpus` alanları CLI'ın model satırlarını değiştirmesine dayanmıyordu — `Current week (Fable)` satırı, niteliyici tanınmadığı için `weekAll` alanına düşüp haftalık toplamı EZİYORDU. Liste + `Kind` modeli hem bu hatayı kökten kaldırır hem de limit sayısının azalıp artmasını (Fable satırının ileride kalkması dâhil) kod değişikliği olmadan taşır. UI `limits`'i olduğu gibi gezer.

`parseUsageOutput(_ raw: String) -> UsageSnapshot` saf fonksiyon olur — process spawn'dan bağımsız, örnek çıktılarla unit test edilebilir. (Kodda `UsageOutputParser.parse(_:now:)`; OAuth ve RPC yolları için kardeşleri `ClaudeUsageAPIParser.parse(_:now:)` ve `CodexUsageParser.parse(responseLine:now:)` — üçü de AYNI `UsageSnapshot` modelini üretir.)

**Model UI string'i taşımaz (refactor 5.9):** `UsageLimit.title` kaldırıldı; başlık LumiUI'daki `displayTitle` extension'ında türetilir. Aynı gerekçeyle yüzdenin uyarı seviyesi LumiKit'te saf bir tiptir (`UsageLevel`: `< 50` normal, `50–79` warning, `≥ 80` critical; `UsageLevel(percent:)` aralık dışı bozuk veriyi en yakın banda düşürür) ve renk eşlemesi (`UsageLevel.color`) LumiUI'dadır. Durum satırının metni de tek yerdedir: `UsageStatusKind` (`idle` / `loading` / `failed` / `updated(fetchedAt:)` / `staleWithError(fetchedAt:message:)`) `UsageStore.statusKind`'den gelir, biçimlendirme `UsageStatusFormatter` (`resetText(for:now:)`, `clockText(_:)`) ile yapılır — topbar popover'ı ve Settings satırı artık aynı üçlüyü iki farklı kuralla çizmez.

## 6. Mimariye yerleştirme

- `LumiKit`'te `UsageServicing` protokolü (yalnız `LumiError` fırlatır, payload `Sendable`).
- `LumiServices` içinde sağlayıcı başına servis: `ClaudeUsageService` (OAuth → CLI yedeği), `CodexUsageService` (auth kapısı → `CodexAppServerProbe`). İkisi de `UsageServicing`; `provider` alanı store ve UI etiketini (ikon, başlık) belirler.
- **Cache dekoratörü (K38-A):** `LiveServiceRegistry` her sağlayıcının servisini `CachingUsageService(wrapping:ttl:)` ile sarar. Cache bir dekoratör detayıdır, `UsageServicing` sözleşmesine girmez; boşaltma yeteneği ayrı ve tek üyeli `UsageCacheInvalidating` protokolüyle duyurulur (ISP).
- Sonuç sağlayıcı başına bir `UsageStore`'a yazılır; UI `@Observable` ile dinler. Topbar'da her sağlayıcı KENDİ toolbar descriptor'ıdır (Faz 6.4): `UsageFeatureAssembly` `AgentProvider.allCases` için birer `ToolbarItemDescriptor` kaydeder, açık/kapalı durumu descriptor'ın `isVisible` kapısında okunur ve `UsageToolbarItem` → `UsageIndicatorView` çizer.
- Servis tipi: dosya/process/ağ-I/O ağırlıklı ve durum tutuyor → `actor` + `async throws` (UI-yüzlü değil, [02 §11](./02-services.md) izolasyon kuralıyla tutarlı).

### Cache & yenileme (K38 kararı A — 2026-09-05)

`/usage` (ve arkasındaki `oauth/usage`) **agresif rate-limit'lidir** — sık çağırma. Üç ayrı kapı vardır ve **farklı işleri yaparlar**; hiçbiri diğerinin yerine geçmez:

| Kapı | Yer | Değer | Ne sınırlar |
|---|---|---|---|
| TTL cache | `CachingUsageService` (servis dekoratörü) | `LiveServiceRegistry.usageCacheTTL = 300 sn` | Ağ/process trafiğini: TTL içinde aynı snapshot döner, sarmalanan servise hiç gidilmez |
| Anti-spam min aralık | `UsageStore.minRefreshInterval = 60 sn` | 60 sn | Kullanıcının tıklama sıklığını (`canRefresh` false ise `refresh()` no-op) |
| Otomatik tazeleme aralığı | `UsageAutoRefresh.allowedIntervals = [5, 15, 30]` dk, default **5** | opt-in | Arka plan döngüsünün periyodunu |

- **Yalnız başarı cache'lenir.** Hata cache'lenmez (geçici bir 5xx'i 5 dk dondurmak göstergeyi ölü tutardı); hata anında elde HÂLÂ TAZE bir cache varsa o döner. Eşzamanlı çağrılar actor sayesinde serileşir.
- **Manuel refresh cache'i geçersizler:** `UsageStore.refresh()` önce `UsageCacheInvalidating.invalidateCache()` çağırır, sonra çeker — aksi hâlde kullanıcı 5 dk boyunca aynı bayat yüzdeyi görür ve buton "bozuk" sanılır. Anti-spam kapısı (60 sn) yine önde durur.
- **En küçük otomatik aralık TTL'e eşittir (5 dk = 300 sn):** daha sık bir aralık cache'e takılıp gerçek bir tazeleme üretmezdi. Bu yüzden eski `{1, 5}` seti düştü; `UsageAutoRefresh.init` izinli set dışındaki her değeri (eski dosyalardaki `intervalMinutes: 1` dahil) default'a **clamp**'ler. Karar 9 ihlali değildir: tip zaten baştan doğrulayan bir init'e sahipti, yalnız izinli set daraldı.
- Çağrı arka planda; UI bloklanmaz. Sonuç gelene kadar son snapshot gösterilir.
- Hata/timeout/rate-limit → son başarılı snapshot korunur, üstüne "güncellenemedi (zaman damgası)" durumu eklenir (`UsageStatusKind.staleWithError`). Ekran boşaltılmaz.

### Hata yönetimi

**Claude — OAuth yolu hata politikası (Faz 1.8, bağlayıcı).** CLI yedeği abonelik kotasından düştüğü için "her hatada CLI'a düş" yanlıştır; yollar ayrılmıştır:

| Durum | Davranış |
|---|---|
| Token okunamadı (keychain + dosya boş) | CLI yedeğine düş |
| HTTP 401 / 403 (token geçersiz) | CLI yedeğine düş |
| Diğer 4xx (endpoint değişmiş olabilir) | CLI yedeğine düş |
| 200 ama gövde tanınmadı | CLI yedeğine düş |
| Transport hatası / non-HTTP yanıt / 429 / 5xx | **CLI'a DÜŞÜLMEZ.** Jitter'lı (300 ms + 0–150 ms) **tek** yeniden deneme; hâlâ hata varsa `LumiError.usageUnavailable` ve stderr'e iz |

- Binary yok → `.cliNotFound(binary:)`; CLI exit ≠ 0 / boş stdout / tanınmayan biçim → `.usageUnavailable(detail:)`. Önceki snapshot her hâlükârda korunur.
- Codex: `auth.json` yok → hiç spawn yok, `.usageUnavailable("Codex not signed in")`; RPC hataları da `.usageUnavailable`.
- **Token hiçbir koşulda loglanmaz.** Hiçbir hata sessizce yutulmaz; her başarısız yol `[lumi-usage]` önekiyle stderr'e iz bırakır.

### Test

- `parseUsageOutput`: tam çıktı, eksik "Sonnet only", API-mode, bozuk/yarım satır, farklı timezone, %0 ve %100 sınırları.
- Reset string→Date dönüşümü ayrı testler.

## 6.1 Uygulama durumu (2026-06-12 — uygulandı; 2026-09-05 refactor'uyla güncellendi)

Implementasyon bu doküman + kullanıcı kararıyla yazıldı; tek bilinçli sapma **yenileme politikası**:

- **Auto-refresh: default KAPALI, opt-in (kullanıcı kararı 2026-06-12 → revize 2026-06-15, karar 20).** Varsayılan akış değişmedi: bootstrap'te **bir kez** ilk yükleme (`UsageStore.loadInitialIfNeeded`) + popover'daki **manuel refresh**; anti-spam min aralık (`UsageStore.minRefreshInterval = 60sn`) korunur. **Ek olarak** Settings → **Usage** sekmesinden (`UsageSettingsTab`) kullanıcı isterse opt-in periyodik tazeleme açılır (aralık seti `UsageAutoRefresh.allowedIntervals = {5, 15, 30}` dk, default 5 — K38-A; eski `{1, 5}` seti düştü, `1` değeri default'a clamp'lenir). Açıkken `UsageAutoRefreshStore` (LumiState) `intervalMinutes`'te bir, **yalnızca kullanıcı aktifse** (`ActivityMonitoring.secondsSinceUserInput() < interval`, idle-gate) `UsageStore.refresh()` çağırır. **Uyku:** Mac uykudayken process askıda olduğundan döngü ateşlenemez; `Task.sleep` `ContinuousClock` kullandığından uyanışta bir kez dönülür ama idle-gate orada da devrededir (ayrı sleep/wake bildirimi gerekmez). Bkz. [decisions.md](../decisions.md) karar 20.
- **Hata görünürlüğü:** Hata/timeout/rate-limit son başarılı snapshot'ı korur (ekran boşaltılmaz); hata mesajı **popover içinde** "Güncellenemedi: …" satırıyla görünür kılınır (toast yerine — karar 5 görünürlük şartı sağlanır, her başarısız tazelemede toast spam'i olmaz).

Bileşenler (SOLID/DI):
- `LumiKit`: `UsageWindow`/`UsageSnapshot`/`UsageLimit` (immutable, **UI string'i taşımaz**), saf parser'lar — `UsageOutputParser.parse(_:now:)` (CLI), `ClaudeUsageAPIParser.parse(_:now:)` (OAuth gövdesi), `CodexUsageParser.parse(responseLine:now:)` (JSON-RPC satırı) —, `UsageServicing` + `UsageCacheInvalidating` protokolleri, `UsageIndicators` / `UsageAutoRefresh` config modelleri, saf sunum yardımcıları `UsageLevel` / `UsageStatusKind` / `UsageStatusFormatter` / `UsageResetFormatter`, `LumiError.cliNotFound`/`.usageUnavailable`. Üç parser da aynı `UsageSnapshot` modelini üretir: `limits` listesi değişken uzunluktadır, UI sabit satır beklemez. Sayı okuma üçünde de ortak `JSONValue`'dan geçer (kullanım uçlarında `acceptingStrings: true`, yüzdelerde `roundedInt`).
- `LumiServices`: `ClaudeUsageService` / `CodexUsageService` (`actor`) — `BinaryLocating` + `ProcessRunning` enjekte edilir (SystemService ile ortak, DRY; testte `FakeProcessRunner`/`FakeBinaryLocator`); ayrıca `ClaudeOAuthCredentials` (keychain `security` çağrısı 5 sn timeout → `~/.claude/.credentials.json` yedeği; `expiresAt` bilinçli olarak değerlendirilmez, 401 sunucuya bırakılır), `CodexAppServerProbe` (JSON-RPC stdio, kendi pipe yaşam döngüsü) ve **`CachingUsageService<ClockType>`** dekoratörü (`UsageServicing & UsageCacheInvalidating`, saat enjekte edilebilir).
- `LumiState`: `UsageStore` (`@Observable @MainActor`, sağlayıcı başına bir örnek + `isEnabled` kapısı + opsiyonel `cache` bağı), test için `now` enjekte edilebilir; `UsageAutoRefreshStore` (`StoreLifecycle`; opt-in periyodik tazeleme, idle-gate'li döngü — `SessionScheduleStore` ile aynı iskelet: `configure` → `start` → `update` → `stop`).
- `LumiKit`/`LumiServices`: `ActivityMonitoring` protokolü + `SystemActivityMonitor` (CGEventSource idle sayacı, izin gerektirmez).
- `LumiUI`: `UsageToolbarItem` (sağlayıcı başına toolbar descriptor'ı, trailing bölge, `AgentProvider.allCases` sırasında 10'ar adım — göstergeler trailing bölgenin en solunda kalır) → `UsageIndicatorView`: kompakt 5sa yüzdesi; gerçek bir `Button`'dır (Faz 7.6 — `onTapGesture` klavye/VoiceOver'a kapalıydı) ve **tıklamayla** (hover değil — 2026-06-12 kullanıcı kararı) tüm pencereleri progress bar + reset süreleri + refresh ile gösteren popover açar. Popover satırları `snapshot.limits` üzerinde `ForEach` ile üretilir (sabit satır listesi yok). Durum satırı topbar ve Settings'te tek bileşendir: `UsageStatusRow` (refactor 7.9).
- DI: `LiveServiceRegistry` sağlayıcı başına servisi kurup `CachingUsageService` ile sarar (`usageCacheTTL = 300 sn`) ve `usage(for:)` ile verir; `UsageFeatureAssembly` store'ları (`[AgentProvider: UsageStore]`) inşa eder, cache yüzünü store'a bağlar (`service as? any UsageCacheInvalidating`), config'teki açık/kapalı durumunu yansıtır, toolbar descriptor'larını kaydeder ve bootstrap'te AÇIK olanların ilk yüklemesini **arka planda** tetikler (bootstrap'i bloklamaz).

Testler: `UsageOutputParserTests` (tam çıktı, limit sırası/başlıkları, **Fable satırı haftalık toplamı ezmez** regresyonu, 2 limitli çıktı, bilinmeyen model adı, contributing bölümünün elenmesi, API-key, Opus, reset'siz satır, bozuk satır, %0/%100, çöp girdi, reset→Date+tz+yıl), `ClaudeUsageAPIParserTests`, `CodexUsageParserTests`, `UsageStoreTests` (load-once, min-interval, hata son snapshot'ı korur), `UsageAutoRefreshStoreTests` (idle-gate + aralık), `CachingUsageServiceTests` (TTL, hata cache'lenmez, invalidate), `ClaudeUsageServiceTests` (URLProtocol stub ile dört yol: başarı / CLI'a düş / retry / `.usageUnavailable`), `ClaudeOAuthCredentialsTests`, `CodexAppServerProbeTests`, `UsageLevelTests`, `UsageStatusFormatterTests`, `UsageIndicatorsTests`, `UsageServiceCompositionTests` (registry'nin cache dekoratörünü gerçekten taktığı). Gerçek `claude -p "/usage"` çıktısı §3 kontratıyla birebir doğrulandı (2026-07-27, Fable satırlı sürüm).

## 7. Kapsam dışı (şimdilik)

- ~~`GET api.anthropic.com/api/oauth/usage`~~ — karar 32 ile **kapsama alındı**, bkz. [§1.1](#11-veri-kaynağı-karar-32--2026-09-04).
- **Codex PTY yedeği:** Orca, RPC başarısız olursa gizli bir PTY'de `codex` açıp `/status` ekranını parse ediyor. Taşınmadı: RPC yolu codex-cli 0.153.2'de doğrulandı ve PTY probe'u kullanıcı görmeden terminal açmayı gerektiriyor. RPC'nin yetmediği bir vaka çıkarsa ayrı karar.
- **Codex reset kredileri / plan bilgisi:** `rateLimitResetCredits`, `planType` alanları okunmuyor (Orca gösteriyor). Kapsam dışı — gösterge yalnız pencere yüzdelerini taşır.
