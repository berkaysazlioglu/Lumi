# Lumi Native — Prototip Planı ve İmplementasyon Sıralaması

> Tasarımın en riskli bahisleri implementasyona girmeden önce prototiple doğrulanır. Her prototipin geçme kriteri ve başarısızlık durumunda mimariyi değiştirmeyen fallback knob'u tanımlıdır.

---

## 1. Prototipler (P1–P6, sırayla)

| # | Prototip | Doğruladığı | Geçme kriteri | Fallback knob'u |
|---|---|---|---|---|
| **P1** | 12 gizli + 1 görünür `TerminalView`, tam yük (`yes`, 1GB `cat`, alt-screen TUI örn. `htop`), 10 dk | Seçenek A topolojisinin ana bahsi: gizli-parse CPU'su + scrollback belleği ([01 §1](./01-terminal-subsystem.md)) | RSS < 300MB; main thread < %40 (M-serisi); görünür terminalde girdi gecikmesi hissedilmez | Gizli coalescing 100→250ms; gizli oturumlara düşük-watermark önyargısı; `TerminalOptions.scrollback` düşür — mimari değişmez |
| **P2** | `feed()` gecikme bütçesi: 16/64/128KB batch'ler, SGR-yoğun + alt-screen çıktı, main thread'de ölçüm | Frame-hızı batching'in main-thread jank üretmediği (bug 40 halka 1) | 128KB batch < ~4ms | Flush boyut eşiğini düşür (knob hazır) |
| **P3** | `PTYProcess` yaşam döngüsü: flood altında suspend → yazanın bloklanması (`yes` CPU'sunun düşmesi); `killpg` ile `zsh -l → claude` ağacının ölümü; `DispatchSourceProcess` exit sıralaması; SIGWINCH | Gereksinim 4.1-2 uçtan uca + sıfır-zombi garantisi | Suspend'de yazan process bloklanır, veri kaybı yok; `ps` ile zombi yok | — (geçemezse PTY katmanı yeniden ele alınır; temel POSIX davranışı, risk düşük) |
| **P4** | Oto-yanıt & mode-1004: DSR/DA gönderen TUI ile round-trip; `?1004h` set edip filtrenin `ESC[I/O`'yu ayıkladığı; arka plandaki (gizli) terminalde Claude ✳ spinner/title takibinin sürdüğü; **detach/attach boyunca mock PTY'ye sıfır istenmeyen byte** entegrasyon testi | Gereksinim 4.2-9/12 + status-tespiti körlük regresyonu | TUI'lar bozulmaz; filtre yalnız focus event'lerini ayıklar; test yeşil | `PTYInputFilter` kapsamı ayarlanır |
| **P5** | Gizli view resize semantiği: gizliyken frame değişimi → unhide → doğru cols/rows, reflow fırtınası yok; 150ms debounce bağlantısı | `display:none`+IntersectionObserver ikamesi ([03 §3](./03-ui-shell.md)) | Attach sonrası TUI doğru genişlikte | Attach'te zorunlu fit+resize sırası ayarlanır |
| **P6** | CoreText vs Metal: P1/P2 çizim-bağlı maliyet gösterirse Metal'i tek paylaşımlı `MTLDevice` ile dene | Gereksinim 4.2-11 (GPU context bütçesi) | Varsayılan CoreText'te kal | Metal yalnız ölçümle haklı çıkarsa |

P1–P3 **walking skeleton içinde** koşar (aşağıda faz 1); P4–P5 faz 1'in çıkış kriteridir; P6 ihtiyaca bağlıdır.

---

## 2. İmplementasyon faz sıralaması (riskli olan önce)

### Faz 1 — Walking skeleton + terminal köprüsü (en yüksek risk)
App target + `LumiPackages` iskeleti; AppKit pencere (fullSizeContentView, traffic light'lar, koyu zemin, JetBrains Mono kaydı); trivial `RootView`'lu `NSHostingView`; `LumiTerminal` sınırı: gerçek PTY'de `claude` koşan tek oturum, `TerminalViewRegistry` + `TerminalHostView` attach/detach. **Kanıtlanacaklar:** SwiftUI re-render'larında terminal hayatta kalımı; tab-değişimi detach/attach; P1–P5 prototipleri. Geri kalan her şey bunun üstünde durur.

### Faz 2 — Composition root + Config + hata hattı
`AppContainer`; `ConfigService` — gerçek `~/.lumi` fixture'larına karşı **byte-format-parite golden testleri** (`~/.lumi-dev` ve `~/.pulpo` fallback dahil); `fixProcessPath`; `SystemService` check'leri; `LumiError` + `ToastStore` hattı uçtan uca.

### Faz 3 — Çoklu terminal UX
`TerminalListStore` + status event'leri; grid layout matematiği (auto/columns/rows, [spec/20 §grid](../spec/20-renderer-terminal.md)); repo tab'ları (`RepoService` tarama + FSEvents watcher + debounce); tam `NSMenu` kısayol seti; minimize/komşu-odak kuralları; `NotificationService` (izin akışı, focus guard, interval timer'lar, `terminalRemoved` temizliği) — status makinesinden sürülür.

### Faz 4 — Git paneli + FileViewer
`GitService` porcelain parse; sağ sidebar (commits/changes); commit akışı; Highlightr viewer + unified-diff renderer; lazy commit-diff; `git check-ignore` file-tree bayrakları.

### Faz 5 — Actions & Personas
Seed asimetrisi; YAML store'lar + dizin izleme + `.history/`; `ActionEngine` (rolling-buffer `wait_for`); `AgentCommandBuilder` (temp system-prompt temizliği, codex rastgele-delimiter heredoc dahil); AI destekli create/edit.

### Faz 6 — Kabuk cilası + paketleme
4 adımlı onboarding; Settings anlık-uygulama + yan etki koordinatörü; focus mode + hover bar + traffic-light gizleme; quit-onay sağlamlaştırma; sleep/wake; **mikrofon-izni TCC zinciri testi** (audio-input entitlement + PTY çocuklarına inherit — claude voice mode); Developer ID imza + notarization; DMG. Auto-update yok (karar 8).

Faz 3–5, faz 2 bittikten sonra paralelleştirilebilir: her dikiş yeri fake'i olan bir `LumiKit` protokolüdür.

---

## 3. Faz çıkış kriterleri (test)

- **Faz 1:** P1–P5 geçer; "view yok edilir → PTY yaşar → reattach → PTY'ye sıfır istenmeyen byte" entegrasyon testi yeşil ([spec/00 §4.2-12](../spec/00-overview.md)).
- **Faz 2:** Golden format-parite testleri yeşil (Electron ↔ native gidiş-geliş — karar 9); hata koridoru testi: fırlatılan her `LumiError` toast'a düşer.
- **Faz 3:** `StatusStateMachine` + `OSCStreamParser` + `ProviderInferencer` + `PTYInputFilter` + `OutputCoalescer` + `FlowController` + `UTF8StreamDecoder` saf unit testleri (bölünmüş-✳ testi dahil); bildirim interval-sızıntısı testi; komşu-odak/minimize kural testleri.
- **Faz 4:** `defaultBranch..branch` log semantiği, porcelain parse, path-traversal guard testleri.
- **Faz 5:** Seed asimetrisi (persona ezilir / `modified_at`'li action korunur), `.history/` max-20, `wait_for` rolling-ring + timeout testleri.
- **Faz 6:** Quit akışının her yolu (Cmd+Q/Dock/logout) onaydan geçer; notarized build Gatekeeper'dan geçer; voice-mode mikrofon zinciri gerçek cihazda doğrulanır.
