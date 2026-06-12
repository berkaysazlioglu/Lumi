# Lumi Native Rewrite — Karar Kaydı

> [00-overview.md](./00-overview.md) §6'daki 14 açık soru 2026-06-11 tarihinde kullanıcı ile birlikte karara bağlandı. Tasarım ve implementasyon fazları bu kararları bağlayıcı kabul eder.

| # | Konu | Karar |
|---|---|---|
| 1 | Codename/Collection gamification | **Tamamen at** |
| 2 | Work-log API'si | **At** |
| 3 | Settings modeli | **macOS anlık uygulama** |
| 4 | FileViewer diff | **Unified diff ile başla** |
| 5 | Hata UX'i | **Tek tip sözleşme + görünür hatalar** |
| 6 | Commit diff yükleme | **Lazy-load** |
| 7 | gitignore semantiği | **`git check-ignore`** |
| 8 | Auto-update | **Yok (planlanmıyor)** |
| 9 | Config migration | **Aynı formatı oku/yaz** |
| 10 | Terminal içi arama | **İlk sürümde yok** |
| 11 | Bug düzeltme listesi | **Düzeltmeler onaylandı, parite yok** |
| 12 | `create-project` templates | **Action default set'ten çıkarılır** |
| 13 | Görsel kimlik | **Mevcut kimlik korunur (semantic uyarlama)** |
| 14 | `docs/plans/` action-auto-discovery | **İptal** |

## Karar detayları ve etkileri

### 1. Gamification tamamen atılıyor
Codename üretimi, collection persistence, CollectionProgress bileşeni ve SessionList "NEW" rozeti native spec'e girmez. `collection:get` ile birlikte [00-overview.md](./00-overview.md) §2'deki ölü kapsam listesinin tamamı taşınmaz. Veri modelinde codename alanı için yer ayrılmaz (YAGNI).

### 2. Work-log API'si atılıyor
ConfigManager'daki work-log persistence native servis katmanına taşınmaz. İleride gerçek bir ihtiyaç doğarsa sıfırdan tasarlanır.

### 3. Settings macOS konvansiyonuna geçiyor
"Draft + Save, Escape=discard" modeli terk edilir; System Settings gibi her değişiklik anında uygulanır ve persist edilir. [22-renderer-ui.md](./22-renderer-ui.md)'deki Settings draft-state davranışları parite hedefi değildir. `config:set` yan etki propagasyonunun ([11-ipc-surface.md](./11-ipc-surface.md)) native karşılığı alan-bazına iner: her ayar değişikliği kendi yan etkisini anında tetikler.

### 4. Diff görünümü unified diff ile başlıyor
Monaco DiffEditor'a native karşılık ilk sürümde aranmaz; tek kolonlu unified diff (satır ekleme/silme renklendirmeli) yeterlidir. Side-by-side görünüm ileri sürüm adayıdır. Bu, en büyük UI riskini ([00-overview.md](./00-overview.md) §5) ortadan kaldırır.

### 5. Tek tip hata sözleşmesi + görünür hatalar
Tüm servisler tek hata modeli kullanır (Swift'te typed `Result`/`Error`). Mevcut tutarsızlıklar (çoğu throw, `git:commit` envelope, spawn-limit sessiz `null`, `openExternal` sessiz yutma) taşınmaz; spawn-limit aşımı dahil kullanıcıyı etkileyen her hata görünür bildirimle sunulur.

### 6. Commit diff lazy-load
Commit seçilince yalnızca dosya listesi yüklenir; diff içeriği dosyaya tıklanınca alınır. `getCommitDiff`'in N+1 `git show` problemi ([12-git-vcs.md](./12-git-vcs.md)) tasarımla çözülür; UX değişikliği kabul edildi.

### 7. Gerçek gitignore semantiği
File tree ignored-flag'leri `git check-ignore` (veya eşdeğer libgit2 API'si) ile hesaplanır: nested `.gitignore`, global excludes ve `.git/info/exclude` hesaba katılır. Yalnız-kök-`.gitignore` davranışından bilinçli sapma onaylandı.

### 8. Auto-update planlanmıyor
Sparkle entegrasyonu hiçbir faza alınmaz. Dağıtım manuel (DMG/zip). İleride fikir değişirse bu karar güncellenir.

### 9. Persistence formatları korunuyor
Native sürüm `~/.lumi` altındaki mevcut JSON/YAML formatlarını okur ve yazar; geçiş döneminde Electron ve native sürümler arasında gidip-gelme mümkün kalır. `NSWindow` frame autosave gibi native-idiomatik mekanizmalara geçilmez; pencere bounds'u dahil mevcut dosya tabanlı persistence sürer ([30-app-shell.md](./30-app-shell.md)).

### 10. Terminal içi arama ilk sürümde yok
SwiftTerm search desteğine rağmen kapsam disiplini için parite hedeflenir; arama sonraki sürüme aday feature olarak not edilir.

### 11. Bug düzeltmeleri onaylandı
[00-overview.md](./00-overview.md) §5 sonundaki "native'de düzeltilmesi önerilen bug listesi" (drop edilen path'in quote'lanmaması, `maxTerminals`'ın üç renderer call-site'ta config'i yok sayması, tanımsız CSS token'ları, ChangesSection/CommitDiffView palet tutarsızlığı vb.) düzeltilmiş davranışla yazılır. Bug paritesi taşınmaz; liste "bilinçli sapma" kaydı olarak spec'te kalır.

### 12. `create-project` action'ı default set'ten çıkıyor
Seed kaynağı bulunamayan `~/.lumi/templates/` bağımlılığı nedeniyle action default set'e konmaz. Action sistemi custom action'ları desteklemeye devam ettiği için kullanıcı isterse kendisi tanımlar.

### 13. Görsel kimlik korunuyor (semantic uyarlama)
Mevcut mor/violet dark tema, JetBrains Mono tipografi ve component görünümleri ([23-design-system.md](./23-design-system.md)) native'de yeniden üretilir. Hedef piksel paritesi değil **semantic uyarlama**: token'lar native renk/spacing sistemine (Asset Catalog / SwiftUI theme katmanı) eşlenir, macOS system look benimsenmez. 23'teki tanımsız-token bug'ları düzeltilerek eşlenir (karar 11 ile tutarlı).

### 14. Action auto-discovery iptal
`docs/plans/2026-02-06-action-auto-discovery.md` (CommandCapture/SessionRecorder/DiscoveryEngine) tamamen iptal edildi; hiçbir sürümde hedeflenmez, doküman arşiv niteliğindedir.

### 15. Grid: iki eksenli model (rows emekli) + maximize/solo
v1'in `auto/columns/rows` tek-eksenli grid'i, dizilim ve yükseklik politikasını iç içe geçirip ("rows" = viewport'a sığar/scroll yok; auto/columns = sabit satır + scroll) zayıf bir UX üretiyordu. Native'de iki eksen ayrılır:
- **Kolon ekseni:** `auto` (genişliğe göre) veya sabit `columns N`.
- **Yükseklik ekseni:** `fit` (hepsi pencereye sığar, scroll yok) veya `scroll` (satır yüksekliği = **kolon genişliği × `heightRatio`** {%100/%50/%33, default %50}; terminal sayısından bağımsız sabit oran, içerik viewport'u aşınca dikey scroll — oran büyüdükçe terminaller uzar, daha çok kaydırma).

`rows` modu **emekli**: yeni yazımda üretilmez, eski/v1 dosyalarında karşılaşılırsa `auto`+`fit`'e migrate edilir. Persistence karar 9 uyumlu kalır — `mode`/`count` alanları korunur, `heightMode` **eklenir** (additive; format değişmez). Ayarlar header'daki butondan açılan sade bir popover'da (Kolon + Yükseklik segmented). Ek olarak tek terminalle rahat çalışmak için **maximize/solo**: bir terminal tam içerik alanını kaplar, diğer görünürler alt şeride iner (oturumluk, persist edilmez). Bu değişiklik [20-renderer-terminal.md](./20-renderer-terminal.md) §13'ün yerine geçer.

## Kapsam özeti

Bu kararlarla native rewrite kapsamı: **mevcut davranış paritesi** (ölü/dormant kod hariç) **+ onaylı bug düzeltmeleri + 4 bilinçli davranış değişikliği** (Settings anlık uygulama, commit-diff lazy-load, gerçek gitignore semantiği, iki-eksenli grid + maximize) **− atılan kapsam** (gamification, work-log, create-project action, auto-update, terminal arama, side-by-side diff).

Buna ek olarak [00-overview.md](./00-overview.md) §4'teki bug-türevli zorunlu gereksinimler (PTY→UI backpressure, render-crash izolasyonu, replay güvenliği) tasarımın başından bağlayıcıdır.
