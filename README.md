# Lumi (macOS Native)

Birden çok Claude Code CLI instance'ını yöneten desktop dashboard **Lumi**'nin macOS-native (Swift) yeniden yazımı. Mevcut Electron sürümünün (`ai-orchestrator` reposu) yerini alacak.

## Neden rewrite?

Electron sürümünde yaşanan iki kritik sorun keşif fazında kök nedenine kadar analiz edildi ve native tasarımın zorunlu gereksinimlerine dönüştürüldü:

1. **Siyah ekran + terminallere kaçan random karakterler** — Yoğun PTY çıktısında renderer'ın GC fırtınasıyla donması/çökmesi, otomatik reload sonrası ham ANSI backlog replay'i sırasında terminal emülatörünün ürettiği otomatik yanıtların (CPR/DA) canlı PTY'ye girdi olarak yazılması ([analiz](docs/spec/40-bug-black-screen.md)).
2. **Büyük stream'de V8 OOM** — Renderer tarafında sınırsız string birikimi × chunk başına O(n) iş = O(n²); uçtan uca hiçbir backpressure yok ([analiz](docs/spec/41-bug-stream-oom.md)).

Bu nedenle native tasarımda **baştan bağlayıcı** üç gereksinim var: PTY→UI ack-tabanlı backpressure, render-crash izolasyonu (PTY'ler UI'dan bağımsız yaşar) ve replay güvenliği (sequence-güvenli kesim, otomatik yanıt filtresi). Detay: [00-overview.md §4](docs/spec/00-overview.md).

## Spec dokümanları

Keşif fazı Electron kod tabanının tamamını davranış spec'ine çevirdi (~213 davranış maddesi, 62 IPC kanalı). Yeni implementasyon eski kodu görmeden bu dokümanlardan yazılabilir:

| Doküman | İçerik |
|---|---|
| [00-overview.md](docs/spec/00-overview.md) | Keşif özeti: kavramlar, feature haritası, mimari, zorunlu gereksinimler |
| [01-decisions.md](docs/spec/01-decisions.md) | **Bağlayıcı karar kaydı** (14 karar, 2026-06-11) |
| [10-main-terminal-pty.md](docs/spec/10-main-terminal-pty.md) | PTY yönetimi: spawn, OSC parser, StatusStateMachine, OutputBuffer |
| [11-ipc-surface.md](docs/spec/11-ipc-surface.md) | 62 kanallık IPC haritası → native servis API'sinin temeli |
| [12-git-vcs.md](docs/spec/12-git-vcs.md) | Git entegrasyonu: repo keşfi, status, commit log, file tree |
| [13-main-services.md](docs/spec/13-main-services.md) | Config, persona, action, notification, system servisleri |
| [20-renderer-terminal.md](docs/spec/20-renderer-terminal.md) | Terminal UI: render path, grid matematiği, spawn akışları |
| [21-renderer-state.md](docs/spec/21-renderer-state.md) | State modeli: store'lar, reconciliation, odak kuralları, persistence |
| [22-renderer-ui.md](docs/spec/22-renderer-ui.md) | UI kabuğu: layout, sidebar'lar, Settings, Setup, FileViewer |
| [23-design-system.md](docs/spec/23-design-system.md) | Görsel tasarım sistemi: token'lar, tipografi, component görünümleri |
| [30-app-shell.md](docs/spec/30-app-shell.md) | App lifecycle: pencere, quit akışı, menü, izinler, paketleme |
| [40](docs/spec/40-bug-black-screen.md) / [41](docs/spec/41-bug-stream-oom.md) | Bug kök neden analizleri |

## Kapsam (karar kaydından)

> **Mevcut davranış paritesi** (ölü/dormant kod hariç) **+ onaylı bug düzeltmeleri + 3 bilinçli değişiklik** (Settings anlık uygulama, commit-diff lazy-load, gerçek gitignore semantiği) **− atılan kapsam** (gamification, work-log, create-project action, auto-update, terminal içi arama, side-by-side diff).

Öne çıkan kararlar: görsel kimlik korunuyor (mor/violet dark tema + JetBrains Mono, semantic uyarlama ile), `~/.lumi` persistence formatları aynen okunup yazılıyor (Electron ↔ native gidip-gelme mümkün), diff görünümü unified diff ile başlıyor. Tamamı: [01-decisions.md](docs/spec/01-decisions.md).

## Durum

- [x] Keşif fazı — spec dokümanları tamam
- [x] Kapsam kararları — 14/14 karara bağlandı
- [ ] Tasarım fazı — native mimari (SwiftTerm, PTY servis katmanı, DI, SwiftUI/AppKit dengesi)
- [ ] İmplementasyon
- [ ] Davranış-eşleşme ve SOLID denetimi
