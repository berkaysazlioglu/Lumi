# Lumi (macOS Native)

Birden çok Claude Code CLI instance'ını yöneten desktop dashboard'un macOS-native (Swift) rewrite'ı. Electron sürümünün (`../ai-orchestrator`) yerini alacak.

## Durum

Keşif, tasarım ve implementasyonun 6 fazı (`docs/design/04-prototype-plan.md`) tamamlandı; 231 test yeşil. Kod `LumiPackages/` altında (modüller: LumiKit/LumiTerminal/LumiServices/LumiState/LumiUI/LumiRemote + LumiApp executable). Geliştirme: `cd LumiPackages && swift run Lumi`; paketleme: `Scripts/make-app.sh` (ad-hoc; `IDENTITY=...` ile Developer ID + script içinde notarization adımları). Kalan manuel doğrulamalar: 10 dk tam P1 ölçümü (Instruments), gerçek cihazda voice-mode mikrofon TCC zinciri, notarized build Gatekeeper testi.

Teknoloji kararları (2026-06-11, bağlayıcı — detay ve gerekçeler `docs/design/00-architecture.md`):
- **SwiftTerm** (SPM) + oturum başına kalıcı view-attached emülatör; PTY katmanı kendi `PTYProcess` wrapper'ımız (LocalProcess değil)
- **AppKit kabuk + SwiftUI içerik**; terminal NSView'ları SwiftUI dışında `TerminalViewRegistry`'de
- **Manuel DI + `AppContainer` composition root**; lokal SPM paketleri `LumiKit ← LumiTerminal / LumiServices / LumiState ← LumiUI`
- **macOS 14+**, Swift 6 strict concurrency; servis→store `AsyncStream`, store→UI `@Observable`, Combine yok

## Kurallar

- **Spec bağlayıcıdır:** Her implementasyon `docs/spec/` altındaki davranış spec'lerinden yazılır; eski Electron koduna bakmak gerekmez (gerekirse `../ai-orchestrator` yerinde duruyor).
- **`docs/design/` bağlayıcı tasarım kaydıdır:** Spec davranışın, design implementasyon şeklinin kaynağıdır. Tasarımla çelişen implementasyon yapma; tasarım değişikliği gerekiyorsa önce kullanıcıya sor ve ilgili design dosyasını güncelle.
- **`docs/spec/01-decisions.md` bağlayıcı karar kaydıdır:** Kapsam, atılan özellikler ve bilinçli davranış değişiklikleri burada. Bu kararlarla çelişen bir implementasyon yapma; karar değişikliği gerekiyorsa önce kullanıcıya sor ve dosyayı güncelle.
- **Zorunlu mimari gereksinimler** (`docs/spec/00-overview.md` §4): PTY→UI ack-tabanlı backpressure, render-crash izolasyonu, replay güvenliği (sequence-güvenli kesim, terminal otomatik yanıt filtresi). Bunlar sonradan eklenemez — çekirdek tasarımın parçası.
- **SOLID + dependency injection:** Rewrite'ın ana hedeflerinden biri; view katmanı iş mantığından ayrı tutulur.
- **Persistence uyumluluğu:** `~/.lumi` altındaki mevcut JSON/YAML formatları aynen okunur/yazılır (karar 9) — format değişikliği yapma.
