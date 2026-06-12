# Lumi Native — Claude Kullanım Göstergesi Tasarımı

> Kullanıcının Claude aboneliğinin kullanım durumunu (5 saatlik oturum limiti + haftalık pencereler + reset zamanları) dashboard'da gösterir. Veri kaynağı: lokalde kurulu Claude Code CLI'ın `/usage` komutu. Bu doküman implementasyon sözleşmesidir; davranış burada tanımlanır.

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

**Karar:** İlk sürümde `claude -p "/usage"` çıktısını parse et. Lumi zaten cc-tabanlı bir dashboard olduğu için ToS açısından güvenli. `oauth/usage` endpoint'ine doğrudan geçmek ayrı bir karar olarak ertelendi ([§7](#7-kapsam-dışı-şimdilik)).

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

Current session: 20% used · resets Jun 12 at 1:39pm (Europe/Istanbul)
Current week (all models): 41% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
Current week (Sonnet only): 1% used · resets Jun 13 at 3:59pm (Europe/Istanbul)
```

Toleranslar:
- Satır sayısı plana göre değişir: "Sonnet only" / "Opus" satırı olmayabilir.
- API key ile (abonelik yerine) çalışan kullanıcıda ilk satır farklıdır ve yüzde satırları hiç gelmeyebilir → `.apiKey` modu, crash yok.
- Çıktı İngilizce gelir (locale İngilizce varsayılır).

## 4. Parse

Satır-bazlı, dayanıklı (tam string eşleşmesine güvenme, regex):

1. Her satır `:` öncesi **etiket** + sonrası **değer** olarak ayrılır.
2. Etiket eşlemesi (case-insensitive, içerir-kontrolü):
   - `Current session` → `fiveHour` (**öncelikli alan**)
   - `Current week (all models)` → `weekAll`
   - `Current week (Sonnet only)` → `weekSonnet`
   - `Opus` içeren → `weekOpus`
3. Değer satırından:
   - **Yüzde:** `(\d+)%` → `Int` (0–100), bulunamazsa `nil`.
   - **Reset:** `resets (.+?)(?:\s*\(.*\))?$` → ham reset string'i (örn. `Jun 12 at 1:39pm`); parantez içi timezone (`Europe/Istanbul`) ayrı yakalanır.
4. Reset zamanı mümkünse `Date`'e çevrilir: format `MMM d 'at' h:mma`, yıl yok → içinde bulunulan yıl. Parse başarısızsa ham string saklanır ve UI'da gösterilir — parse hatası veriyi düşürmez.

## 5. Değer tipleri

Immutable struct'lar, alanlar opsiyonel:

```
UsageWindow = {
  percentUsed: Int?      // 0–100
  resetsAt:    Date?     // parse edilebildiyse
  resetsRaw:   String    // ham metin (her zaman)
  timezone:    String?
}

UsageSnapshot = {
  fiveHour:   UsageWindow?   // en önemlisi
  weekAll:    UsageWindow?
  weekSonnet: UsageWindow?
  weekOpus:   UsageWindow?
  mode:       .subscription | .apiKey | .unknown
  fetchedAt:  Date
}
```

`parseUsageOutput(_ raw: String) -> UsageSnapshot` saf fonksiyon olur — process spawn'dan bağımsız, örnek çıktılarla unit test edilebilir.

## 6. Mimariye yerleştirme

- `LumiKit`'te `UsageServicing` protokolü (yalnız `LumiError` fırlatır, payload `Sendable`).
- `LumiServices` içinde `UsageService`: binary çöz → spawn → stdout → `parseUsageOutput` → `UsageSnapshot`.
- Sonuç bir `UsageStore`'a yazılır; UI `@Observable` ile dinler.
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

- **Auto-refresh YOK (kullanıcı kararı 2026-06-12).** §6'daki "≥5 dk TTL'li arka plan periyodik tazeleme" hedef değildir. Akış: uygulama bootstrap'inde **bir kez** ilk yükleme (`UsageStore.loadInitialIfNeeded`, arka planda, bloklamaz) + popover'daki **manuel refresh** butonu. Anti-spam için min aralık (`UsageStore.minRefreshInterval = 60sn`) korunur; aralık içindeyken buton pasif (`canRefresh`).
- **Hata görünürlüğü:** Hata/timeout/rate-limit son başarılı snapshot'ı korur (ekran boşaltılmaz); hata mesajı **popover içinde** "Güncellenemedi: …" satırıyla görünür kılınır (toast yerine — karar 5 görünürlük şartı sağlanır, her başarısız tazelemede toast spam'i olmaz).

Bileşenler (SOLID/DI):
- `LumiKit`: `UsageWindow`/`UsageSnapshot` (immutable), saf `UsageOutputParser.parse(_:now:)`, `UsageServicing` protokolü, `LumiError.cliNotFound`/`.usageUnavailable`.
- `LumiServices`: `UsageService` (`actor`) — `BinaryLocator` (SystemService ile ortak, DRY) → `ProcessRunner` (15sn timeout) → parse; `claude -p "/usage"`.
- `LumiState`: `UsageStore` (`@Observable @MainActor`), test için `now` enjekte edilebilir.
- `LumiUI`: `UsageIndicatorView` — topbar'da grid kontrolünün **solunda** kompakt 5sa yüzdesi; hover/tıklama ile tüm pencereleri progress bar + reset süreleri + refresh ile gösteren popover.
- DI: `AppContainer` `usageService`/`usageStore`'u inşa eder ve bootstrap'te ilk yüklemeyi tetikler.

Testler: `UsageOutputParserTests` (tam çıktı, eksik Sonnet, API-key, Opus, reset'siz satır, bozuk satır, %0/%100, çöp girdi, reset→Date+tz+yıl), `UsageStoreTests` (load-once, min-interval, hata son snapshot'ı korur). Gerçek `claude -p "/usage"` çıktısı §3 kontratıyla birebir doğrulandı.

## 7. Kapsam dışı (şimdilik)

- `GET api.anthropic.com/api/oauth/usage` endpoint'ine doğrudan HTTP — daha hızlı ama OAuth token'ı cc dışında kullanmak ToS gri alanı. Geçmek istenirse ayrı karar + ToS değerlendirmesi gerekir. Referans (gerekirse): header'lar `Authorization: Bearer <oauth_access_token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>` (sonuncusu olmazsa anında 429); response `five_hour/seven_day/seven_day_opus/seven_day_sonnet` alanlarında `utilization` + `resets_at` (ISO 8601) döner.
