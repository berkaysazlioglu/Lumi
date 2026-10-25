# Demo / örnek veri temizliği (2026-10-25)

Amaç: örnek veriler son kullanıcının önünde "gerçek seçenek" gibi durmasın.
Geliştirme, test ve App Review için gereken kısım kalır ama kenara çekilir;
yalnız UX'i bozan ve kimsenin ihtiyaç duymadığı kısım silinir.

## Envanter

| # | Yer | Ne | Kullanıcı nerede görüyor |
|---|-----|----|--------------------------|
| M1 | `LumiServices/Tasks/DemoTaskProvider.swift`, `DemoTaskImages.swift` (~290 satır) | Bellek içi örnek pano | Connect Task Source sheet'inde `Custom`'ın hemen altında birinci sınıf seçenek: **"Demo data — Sample tasks kept in memory"** |
| M2 | `TasksHeaderBar.demoToggles/errorToggles`, `TasksStore.setCapability/setField/setSimulatedFailure`, `TaskSimulatedFailure`, `TaskProviderSimulating`, `TaskSourceInfo.masked` | Demo kaynakta `Simulate Missing` / `Simulate Errors` alt menüleri | Kaynak menüsünde, `Prompt Template…` ile aynı seviyede |
| M3 | `TaskProviderKind.github/.linear` | Soluk "Coming soon" satırları | Connect sheet'i |
| M4 | `TasksRouteView` (karar 55) | `Remote is coming soon` gövdesi | Sol panel ▸ Remote sekmesi |
| M5 | Telefona köprü (`RemoteTasksBridge`) | Mac'te demo kaynak bağlıysa örnek task'ler gerçek modda telefona da gider | Telefon ▸ Tasks |
| P1 | `LumiMobileKit/Demo/` (11 dosya, ~1400 satır: `DemoRelayClient`, `DemoWorld`, `DemoTasks`, `DemoUsage`, `DemoTerminalScreens`) | Mac'siz tam demo dünyası | Pairing ekranında ayrı bölüm: **✨ "Try with demo data"** |
| P2 | `Demo/DemoTranscripts*.swift`, `DemoChatBuilder.swift` | Örnek chat geçmişleri | Yalnız demo modunda; `NoChatCache` + `DemoSecureStore` kullandığı için gerçek chat önbelleğine/kimlik bilgilerine **sızmıyor** (doğrulandı) |
| P3 | `SettingsView` | `Exit Demo Data` | Yalnız demo modunda — doğru yerde |
| P4 | `DEMO=1 Scripts/make-mobile.sh` → `LumiDemoByDefault` | Demo ile açılan build | Yalnız bilerek alınan build'de |
| K1 | `LumiUI/Preview/PreviewFixtures.swift`, `#Preview`'ler | SwiftUI önizleme verisi | Hiç — `#if DEBUG` |
| K2 | `P1Harness` | Performans ölçüm koşumu | Hiç — env ile tetiklenir |
| K3 | `TaskPromptTemplateOverlay.sampleTask` | Şablon önizlemesi için örnek task | Önizleme etiketi `PREVIEW · …` — meşru |

## Karar önerisi

### Kaldır
- **M3** — GitHub / Linear "Coming soon" satırları connect sheet'inden çıkar
  (`isAvailable == false` olanlar listelenmez; enum case'leri adapter'lar
  gelene kadar kalabilir ya da silinir — YAGNI'ye göre silinir).
- **M2'nin release'teki yüzü** — `Simulate Missing` / `Simulate Errors`
  menüleri release build'de hiç görünmez (aşağıdaki geliştirici kapısı).

### Kenara çek (kalır, göz önünden kalkar)
- **M1 — Demo task kaynağı:** connect sheet'inde yalnız geliştirici kapısı
  açıkken listelenir. Kapı: `#if DEBUG` **veya** `defaults write com.lumi.app
  developerTools -bool YES` (tek bir `DeveloperTools.isEnabled`; Settings'e
  anahtar eklenmez). Zaten bağlı demo kaynağı olan kullanıcı onu kaybetmez —
  codec `isAvailable`'a bakmaya devam eder, yalnız *listelenme* kapıya bağlanır.
  Testler `DemoTaskProvider`'ı kullanmaya devam eder (TasksStore, RemoteTasksBridge,
  TasksScreenSizing).
- **M2:** iki alt menü tek `Developer ▸` alt menüsünde birleşir, kaynak menüsünün
  en altına (Disconnect'in üstüne, ayırıcıyla) iner; yalnız demo kaynakta ve
  kapı açıkken.
- **M5:** M1 kapandığı an kendiliğinden çözülür; ek iş yok.
- **P1 — Mobil demo modu:** App Review'un Mac'siz denemesi için **kalır**, ama
  Pairing'deki ✨ bölüm kalkar; formun en altına bölümsüz, `footnote` boyutunda
  sade bir link olur: "No Mac nearby? Look around with sample data". App Review
  notlarına bu satır yazılır.
- **P1 ek — demo olduğu belli olsun:** demo modunda ana ekran başlığının altında
  ince bir `Sample data · Exit` şeridi (Settings'e gitmeden çıkış). Bugün demo
  ile gerçek bağlantı görsel olarak ayırt edilemiyor; "mock data gerçek gibi
  duruyor" hissinin asıl kaynağı bu.

### Dokunma
- **P2** (demo chat geçmişi) — yalnız demo modunda yaşıyor ve izole; içerik
  olarak kalır. İstenirse transcript sayısı azaltılabilir (opsiyonel, UX'e etkisi yok).
- **P3, P4, K1, K2, K3.**

## Açık sorular
1. **M4 — Remote "coming soon" sekmesi:** mock değil ama aynı "bitmemiş" hissini
   veriyor. Sekme Remote gelene kadar gizlensin mi? (karar 55'i değiştirir →
   `decisions.md` güncellenir, `ui-state` migration'ı `remote` seçiliyse `tasks`'a düşer)
2. **Geliştirici kapısı:** `#if DEBUG` + `defaults` anahtarı yeterli mi, yoksa
   Settings'te gizli bir "Developer" bölümü mü (ör. ⌥ basılıyken görünen)?

## Fazlar
1. **Mac Tasks** — `DeveloperTools` kapısı (LumiKit, saf), connect sheet
   listelemesi, `Developer ▸` menüsü, Coming soon satırları. Testler:
   kapı kapalıyken demo listelenmez / bağlı demo kaynak yüklenmeye devam eder.
2. **Mobil** — Pairing linki, demo şeridi; `DemoRelayClientTests` aynen geçer.
3. **Kayıt** — `decisions.md`'ye yeni karar (137 ve 127'ye atıf), CLAUDE.md
   durum satırı; (M4 onaylanırsa) karar 55 eki.

Her faz sonunda `swift build`, `swift test`, `swift build -c release --product Lumi`
(mobil fazda `Scripts/make-mobile.sh` sim build'i).
