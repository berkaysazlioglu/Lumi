# Lumi (macOS Native)

Birden çok Claude Code CLI instance'ını yöneten desktop dashboard'un macOS-native (Swift) rewrite'ı. Electron sürümünün (`../ai-orchestrator`) yerini alacak.

## Durum

Keşif fazı tamamlandı, tasarım fazı bekleniyor. Henüz kod yok; teknoloji kararları (SwiftTerm, SwiftUI/AppKit dengesi, DI yapısı) tasarım fazında verilecek.

## Kurallar

- **Spec bağlayıcıdır:** Her implementasyon `docs/spec/` altındaki davranış spec'lerinden yazılır; eski Electron koduna bakmak gerekmez (gerekirse `../ai-orchestrator` yerinde duruyor).
- **`docs/spec/01-decisions.md` bağlayıcı karar kaydıdır:** Kapsam, atılan özellikler ve bilinçli davranış değişiklikleri burada. Bu kararlarla çelişen bir implementasyon yapma; karar değişikliği gerekiyorsa önce kullanıcıya sor ve dosyayı güncelle.
- **Zorunlu mimari gereksinimler** (`docs/spec/00-overview.md` §4): PTY→UI ack-tabanlı backpressure, render-crash izolasyonu, replay güvenliği (sequence-güvenli kesim, terminal otomatik yanıt filtresi). Bunlar sonradan eklenemez — çekirdek tasarımın parçası.
- **SOLID + dependency injection:** Rewrite'ın ana hedeflerinden biri; view katmanı iş mantığından ayrı tutulur.
- **Persistence uyumluluğu:** `~/.lumi` altındaki mevcut JSON/YAML formatları aynen okunur/yazılır (karar 9) — format değişikliği yapma.
