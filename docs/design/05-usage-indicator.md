# Lumi Native — Kullanım Göstergeleri Tasarımı

> Kullanıcının **Claude ve Codex** aboneliklerinin kullanım durumunu (5 saatlik oturum limiti + haftalık pencereler + reset zamanları) dashboard'da gösterir. Bu doküman implementasyon sözleşmesidir; davranış burada tanımlanır.
>
> **Karar 32 (2026-09-04) §1'i değiştirdi:** veri kaynağı artık sağlayıcı başına, Orca'nın kullandığı yolun aynısıdır — Claude için OAuth endpoint'i (CLI yedekli), Codex için `codex app-server` JSON-RPC. Aşağıdaki §1'in ilk sürüm kararı tarihsel kayıt olarak durur; geçerli kaynak [§1.1](#11-veri-kaynağı-karar-32--2026-09-04)'dir.

Genel kurallar:
- Servis sadece I/O + parse yapar; iş mantığı/UI yok (SOLID, view'dan ayrık).
- Parse mantığı saf/test edilebilir fonksiyon olarak process spawn'dan ayrılır.
- Store→UI akışı projedeki desenle: servis sonucu store'a yazılır, UI `@Observable` ile dinler (Combine yok).
- DI: `UsageService` `AppContainer` composition root'tan enjekte edilir.

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
- **Codex probe'unda stdin yanıt gelene kadar AÇIK tutulmalıdır.** Üç mesajı peş peşe yazıp stdin'i kapatmak (`ProcessRunner`'ın `standardInput` davranışı) sunucunun ikinci isteği hiç yanıtlamamasına yol açıyor — EOF'u kapanma sinyali sayıyor. Bu yüzden `CodexAppServerProbe` kendi pipe yaşam döngüsünü yönetir.
- Auth kapısı (`auth.json` yok → hiç spawn yok) Orca'nın gerekçesiyle aynıdır: giriş yapmamış kullanıcıda spawn zaten başarısız olur ve arka planda beklenmedik bir Codex süreci görünür.

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
  title:    String        // türetilmiş UI başlığı ("Weekly (Fable)")
  id:       String        // dedupe anahtarı
}

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

`parseUsageOutput(_ raw: String) -> UsageSnapshot` saf fonksiyon olur — process spawn'dan bağımsız, örnek çıktılarla unit test edilebilir.

## 6. Mimariye yerleştirme

- `LumiKit`'te `UsageServicing` protokolü (yalnız `LumiError` fırlatır, payload `Sendable`).
- `LumiServices` içinde sağlayıcı başına servis: `ClaudeUsageService` (OAuth → CLI yedeği), `CodexUsageService` (auth kapısı → `CodexAppServerProbe`). İkisi de `UsageServicing`; `provider` alanı store ve UI etiketini (ikon, başlık) belirler.
- Sonuç sağlayıcı başına bir `UsageStore`'a yazılır; UI `@Observable` ile dinler. Topbar `config.usageIndicators.enabledProviders` üzerinde gezip her açık sağlayıcı için bir `UsageIndicatorView` çizer.
- Servis tipi: dosya/process-I/O ağırlıklı → `Actor` + `async throws` (UI-yüzlü değil, [02 §genel kurallar](./02-services.md) ile tutarlı).

### Cache & yenileme (önemli)

- `/usage` (ve arkasındaki `oauth/usage`) **agresif rate-limit'li** — sık çağırma.
- **En az 5 dk TTL'li cache.** Manuel "refresh"te bile minimum aralık (≥60 sn) zorlanır; art arda spam engellenir.
- Çağrı arka planda; UI bloklanmaz. Sonuç gelene kadar son snapshot gösterilir.
- Hata/timeout/rate-limit → son başarılı snapshot korunur, üstüne "güncellenemedi (zaman damgası)" durumu eklenir. Ekran boşaltılmaz.

### Hata yönetimi

- Binary yok → `.cliNotFound`.
- Exit ≠ 0 / boş stdout → "kullanım alınamadı", önceki snapshot korunur.
- Parse hiçbir alan bulamadı → ham çıktı debug log'a, UI'da "biçim tanınmadı".
- Hiçbir hata sessizce yutulmaz; loglanır.

### Test

- `parseUsageOutput`: tam çıktı, eksik "Sonnet only", API-mode, bozuk/yarım satır, farklı timezone, %0 ve %100 sınırları.
- Reset string→Date dönüşümü ayrı testler.

## 6.1 Uygulama durumu (2026-06-12 — uygulandı)

Implementasyon bu doküman + kullanıcı kararıyla yazıldı; tek bilinçli sapma **yenileme politikası**:

- **Auto-refresh: default KAPALI, opt-in (kullanıcı kararı 2026-06-12 → revize 2026-06-15, karar 20).** Varsayılan akış değişmedi: bootstrap'te **bir kez** ilk yükleme (`UsageStore.loadInitialIfNeeded`) + popover'daki **manuel refresh**; anti-spam min aralık (`UsageStore.minRefreshInterval = 60sn`) korunur. **Ek olarak** Settings → **Usage** sekmesinden kullanıcı isterse opt-in periyodik tazeleme açılır (aralık seti {5, 15, 30} dk). Açıkken `UsageAutoRefreshStore` (LumiState) `intervalMinutes`'te bir, **yalnızca kullanıcı aktifse** (`ActivityMonitoring.secondsSinceUserInput() < interval`, idle-gate) `UsageStore.refresh()` çağırır. **Uyku:** Mac uykudayken process askıda olduğundan döngü ateşlenemez; `Task.sleep` `ContinuousClock` kullandığından uyanışta bir kez dönülür ama idle-gate orada da devrededir (ayrı sleep/wake bildirimi gerekmez). Bkz. [decisions.md](../decisions.md) karar 20.
- **Hata görünürlüğü:** Hata/timeout/rate-limit son başarılı snapshot'ı korur (ekran boşaltılmaz); hata mesajı **popover içinde** "Güncellenemedi: …" satırıyla görünür kılınır (toast yerine — karar 5 görünürlük şartı sağlanır, her başarısız tazelemede toast spam'i olmaz).

Bileşenler (SOLID/DI):
- `LumiKit`: `UsageWindow`/`UsageSnapshot` (immutable), saf parser'lar — `UsageOutputParser.parse(_:now:)` (CLI), `ClaudeUsageAPIParser.parse(_:now:)` (OAuth gövdesi), `CodexUsageParser.parse(responseLine:now:)` (JSON-RPC satırı) —, `UsageServicing` protokolü, `UsageIndicators` config modeli, `LumiError.cliNotFound`/`.usageUnavailable`. Üç parser da aynı `UsageSnapshot` modelini üretir: `limits` listesi değişken uzunluktadır, UI sabit satır beklemez.
- `LumiServices`: `ClaudeUsageService` / `CodexUsageService` (`actor`) — `BinaryLocator` (SystemService ile ortak, DRY) + `ProcessRunner`; ayrıca `ClaudeOAuthCredentials` (keychain/dosya) ve `CodexAppServerProbe` (JSON-RPC stdio).
- `LumiState`: `UsageStore` (`@Observable @MainActor`, sağlayıcı başına bir örnek + açık/kapalı kapısı), test için `now` enjekte edilebilir; `UsageAutoRefreshStore` (opt-in periyodik tazeleme, idle-gate'li döngü — `SessionScheduleStore` iskeleti).
- `LumiKit`/`LumiServices`: `ActivityMonitoring` protokolü + `SystemActivityMonitor` (CGEventSource idle sayacı, izin gerektirmez).
- `LumiUI`: `UsageIndicatorView` — topbar'da grid kontrolünün **solunda** kompakt 5sa yüzdesi; **tıklamayla** (hover değil — 2026-06-12 kullanıcı kararı) tüm pencereleri progress bar + reset süreleri + refresh ile gösteren popover açılır. Popover satırları `snapshot.limits` üzerinde `ForEach` ile üretilir (sabit satır listesi yok — model limiti eklenir/kalkarsa UI kendiliğinden uyar).
- DI: `AppContainer` `usageServices`/`usageStores` sözlüklerini (`[AgentProvider: …]`) inşa eder, config'teki açık/kapalı durumunu store'lara yansıtır ve bootstrap'te AÇIK olanların ilk yüklemesini tetikler.

Testler: `UsageOutputParserTests` (tam çıktı, limit sırası/başlıkları, **Fable satırı haftalık toplamı ezmez** regresyonu, 2 limitli çıktı, bilinmeyen model adı, contributing bölümünün elenmesi, API-key, Opus, reset'siz satır, bozuk satır, %0/%100, çöp girdi, reset→Date+tz+yıl), `UsageStoreTests` (load-once, min-interval, hata son snapshot'ı korur). Gerçek `claude -p "/usage"` çıktısı §3 kontratıyla birebir doğrulandı (2026-07-27, Fable satırlı sürüm).

## 7. Kapsam dışı (şimdilik)

- ~~`GET api.anthropic.com/api/oauth/usage`~~ — karar 32 ile **kapsama alındı**, bkz. [§1.1](#11-veri-kaynağı-karar-32--2026-09-04).
- **Codex PTY yedeği:** Orca, RPC başarısız olursa gizli bir PTY'de `codex` açıp `/status` ekranını parse ediyor. Taşınmadı: RPC yolu codex-cli 0.153.2'de doğrulandı ve PTY probe'u kullanıcı görmeden terminal açmayı gerektiriyor. RPC'nin yetmediği bir vaka çıkarsa ayrı karar.
- **Codex reset kredileri / plan bilgisi:** `rateLimitResetCredits`, `planType` alanları okunmuyor (Orca gösteriyor). Kapsam dışı — gösterge yalnız pencere yüzdelerini taşır.
