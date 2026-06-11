# Görsel Tasarım Sistemi (globals.css)

Kaynak: `src/renderer/styles/globals.css` (~2987 satır, tek dosya — tüm component stilleri burada) + iki yardımcı dosya: `src/renderer/components/ui/SearchInput.css` ve `src/renderer/components/Setup/SetupScreen.css`. xterm.js terminal renk paleti ayrı spec'tedir ([20](./20-renderer-terminal.md) §3); Framer Motion animasyon parametreleri component spec'lerinde ([22](./22-renderer-ui.md)) verilmiştir — bu doküman CSS tarafını (token'lar, tipografi, statik görünümler, CSS keyframe'leri) kapsar.

## Amaç ve sorumluluk

Lumi'nin görsel kimliği tamamen custom bir koyu temadır: mor/violet accent paleti, monospace (JetBrains Mono) tipografi, BEM adlandırmalı component stilleri. macOS-native rewrite'ta bu kimliğin **birebir mi korunacağı, yoksa macOS konvansiyonlarına mı (system font, semantic NSColor, vibrancy) uyarlanacağı** açık bir ürün kararıdır (bkz. [00-overview](./00-overview.md) açık sorular). Her iki durumda da aşağıdaki envanter referans sözleşmedir.

---

## 1. Token envanteri (CSS variables, `:root`)

### 1.1 Zemin ve çerçeve renkleri

| Token | Değer | Kullanım |
|---|---|---|
| `--bg-deep` | `#0a0a12` | Uygulama zemini, input zeminleri, kbd dışı koyu yüzeyler |
| `--bg-surface` | `#12121f` | Header, sidebar, terminal kartı, dialog/modal zemini |
| `--bg-elevated` | `#1a1a2e` | Hover zemini, dropdown/popup/context-menu zemini, kart header'ı |
| `--border` | `#2a2a4a` | Standart 1px çerçeveler, divider'lar |
| `--border-glow` | `rgba(139, 92, 246, 0.25)` | Aktif repo tab çerçevesi |

### 1.2 Metin renkleri

| Token | Değer | Kullanım |
|---|---|---|
| `--text-primary` | `#e2e2f0` | Ana metin, hover'da vurgulanan metin |
| `--text-secondary` | `#8888a8` | İkincil metin, pasif buton/ikon rengi |
| `--text-muted` | `#4a4a6a` | Soluk metin, placeholder, idle status dot |

### 1.3 Accent paleti

| Token | Değer | Kullanım |
|---|---|---|
| `--accent-primary` | `#a78bfa` | Vurgu metin/ikon, focus çerçevesi, terminal cursor, aktif seçimler |
| `--accent-vivid` | `#8b5cf6` | Primary buton, toggle-on, toast sol şeridi, checkbox `accent-color` |
| `--accent-deep` | `#7c3aed` | Primary buton hover'ı, quick-action hover zemini |
| `--accent-cyan` | `#22d3ee` | Commit hash, info toast, REPO tip rozeti, renamed durum harfi |
| `--accent-success` | `#4ade80` | Working status dot, HEAD commit noktası, added, success toast |
| `--accent-warning` | `#fbbf24` | Waiting status dot, modified, dialog uyarı ikonu, folder ikonu |
| `--accent-error` | `#f87171` | Error status dot, deleted, close hover'ları, error toast |

Accent'in alpha türevleri (`rgba(139, 92, 246, 0.06–0.3)` vb.) tokenize **edilmemiştir**; dosya boyunca hardcoded rgba olarak geçer (badge zeminleri %20, settings aktif nav %8, info kartı %6, toast border %30). Native renk sisteminde bunlar semantic varyant olarak tanımlanmalı.

### 1.4 Spacing ve radius ölçekleri

| Spacing | Değer | | Radius | Değer |
|---|---|---|---|---|
| `--spacing-xs` | 4px | | `--radius-sm` | 4px |
| `--spacing-sm` | 8px | | `--radius-md` | 6px |
| `--spacing-md` | 12px | | `--radius-lg` | 8px |
| `--spacing-lg` | 16px | | `--radius-xl` | 12px |
| `--spacing-xl` | 24px | | | |
| `--spacing-2xl` | 32px | | | |

Ölçek dışı hardcoded radius'lar: settings modal 16px, file-viewer modal 12px, toggle 11px (pill), grup sayacı 8px.

### 1.5 Yerleşim sabitleri

| Token / sabit | Değer |
|---|---|
| `--sidebar-width` | 280px |
| `--header-height` | 52px (focus-mode hover bar'ı da 52px) |
| Terminal kartı min genişliği | 400px (grid matematiği [20](./20-renderer-terminal.md) §13) |
| Grid gap | 12px (`--spacing-md`) |
| Settings modal | 700×600px, sol nav 180px |
| File viewer modal | 85vw × 80vh, commit-diff sidebar'ı 220px |
| Dialog kartları (Quit/CloseTab) | 420px |
| Repo dropdown | 320px, max 400px yükseklik |

---

## 2. Tipografi

- **Font stack (her şey monospace):** `'JetBrains Mono', 'Cascadia Code', 'Fira Code', 'SF Mono', 'Menlo', 'Consolas', monospace` — body'de set edilir, tüm UI buna iner. JetBrains Mono uygulamayla gelmiyorsa fallback zinciri devreye girer; native'de font bundle kararı verilmeli.
- **Taban:** 13px / line-height 1.5, antialiased (`-webkit-font-smoothing`). Terminal font boyutu ayrı config'tir (`terminalFontSize`, default 13).
- **Boyut ölçeği (kullanım yerleriyle):**

| Boyut | Kullanım |
|---|---|
| 9px | "NEW" rozeti, ROOT/REPO tip rozetleri (700, uppercase) |
| 10px | Badge'ler, dosya durum harfi (700), commit tarihi, grup sayacı, popup section label'ı |
| 11px | Section başlıkları (600, uppercase, letter-spacing 0.05em), toast mesajı, sayaçlar, hint'ler, kbd, commit hash |
| 12px | Gövde: buton, liste öğeleri, input'lar, dropdown item'ları, commit mesajı |
| 13px | Taban: tab adı, settings nav, dialog mesajı, arama input'u |
| 14px | Panel/empty-state başlığı, app-title, drag overlay |
| 15–16px | Settings section başlığı / dialog başlığı (600) |
| 18px | Settings modal başlığı (600) |
| 20px | Loading ekranı başlığı (600, letter-spacing -0.02em) |

- **Konvansiyon:** Bölüm başlıkları daima 11px/600/uppercase/0.05em; ağırlıklar 500 (buton/label) ve 600 (başlık/vurgu), 700 yalnızca mini rozet/durum harfi.

---

## 3. Status renk sistemi

### 3.1 StatusDot (terminal durumu — 8px daire)

| Status | Renk | Efekt |
|---|---|---|
| `idle` | `--text-muted` | — |
| `working` | `--accent-success` | 8px glow + `subtle-pulse` 1.5s sonsuz |
| `waiting-unseen` | `--accent-warning` | 8px glow + `subtle-pulse` 1.5s sonsuz |
| `waiting-focused` | `--text-muted` | — |
| `waiting-seen` | `--accent-warning` | statik (pulse yok) |
| `error` | `--accent-error` | — |

Yani görsel dil: **yanıp sönen = dikkat ister** (working/waiting-unseen), **statik sarı = görüldü ama yanıtlanmadı**, **soluk = sakin**.

### 3.2 Git dosya durumu harfleri

İki yerde **farklı** palet kullanılır (bilinen tutarsızlık):

| Durum | ChangesSection (`.file-change__status--*`) | CommitDiffView (inline `STATUS_COLORS`) |
|---|---|---|
| modified (M) | `--accent-warning` #fbbf24 | `var(--status-modified, #e2b93d)` |
| added (A) | `--accent-success` #4ade80 | `var(--status-added, #73c991)` |
| deleted (D) | `--accent-error` #f87171 | `var(--status-deleted, #f14c4c)` |
| renamed (R) | `--accent-cyan` #22d3ee | `var(--status-renamed, #dbb6f2)` |
| untracked (U) | `--accent-primary` #a78bfa | — |

`--status-*` token'ları hiçbir yerde **tanımlı değildir**; CommitDiffView fiilen fallback hex'leri (VS Code paleti) kullanır. Native'de tek palete normalize edilmeli (davranış değişikliği olarak notlanarak).

---

## 4. Animasyon kalıpları (CSS keyframes)

| Keyframe | Tanım | Kullanım |
|---|---|---|
| `fadeIn` | opacity 0→1 | context menu (0.1s), loading screen (0.3s) |
| `fadeInUp` | opacity 0→1 + translateY 10px→0 | repo dropdown açılışı (0.15s) |
| `subtle-pulse` | opacity 1↔0.6 | aktif status dot'lar, toast ikonu, "Initializing..." metni (1.5s sonsuz) |
| `glow-pulse` | accent box-shadow 5/10px ↔ 15/30px | loading maskotu (2s sonsuz) |
| `sparkle-pulse` | opacity 1↔0.5 + 6px glow | "NEW" rozeti (1.5s × 3 — dormant, bkz. [22](./22-renderer-ui.md) §3.1) |
| `spin` | rotate 360° | spinner'lar |
| `marquee` | translateX 0→-100% | commit mesajı hover'da kayan yazı (5s linear sonsuz) |

**Transition konvansiyonu:** interaktif öğelerde `all 0.15s ease` standartı; kartlar/tab'lar 0.2s; tree node ve context menu item 0.1s. Hover mikro-hareketleri: primary buton `translateY(-1px)`, icon buton `scale(1.05)` (active'de `scale(0.98)`).

---

## 5. Temel component görünümleri

- **Button (`.btn`):** padding 8×12, radius 6, 12px/500. `--primary`: `--accent-vivid` zemin + beyaz metin, hover `--accent-deep` + 1px yukarı kalkma. `--ghost`: şeffaf, hover'da `--bg-elevated` zemin + border. Disabled: opacity 0.5 (global `button:disabled`).
- **IconButton (`.icon-btn`):** 32×32, radius 6, hover'da `--bg-elevated` + scale 1.05.
- **Badge (`.badge`):** 2×8 padding, radius 4, 10px/500 uppercase. Varyant zemini ilgili accent renginin %20 alpha'sı + accent metin (default: `--bg-elevated` + secondary).
- **Terminal kartı:** `--bg-surface` zemin, 1px `--border`, radius 8. `--focused`: accent çerçeve + 1px ring + 15px mor glow. `--drag`: accent çerçeve + 20px glow + `rgba(139,92,246,0.1)` zeminli "Drop file here" overlay'i. Header: `--bg-elevated`, 12px başlık; minimize butonu hover'ı mor, close hover'ı kırmızı (her ikisi %20 alpha zemin).
- **Session item:** radius 6; aktif: `--bg-elevated` + accent metin + **2px sol accent çizgisi**; minimize: opacity 0.5.
- **Repo tab:** radius 6; aktif: `--bg-elevated` + accent metin + `--border-glow` çerçevesi; X butonu yalnızca hover'da görünür (opacity 0→0.6), hover'ı kırmızı.
- **Toast:** sağ-alt sabit (`bottom/right: 16px`), `rgba(26,26,46,0.92)` + `backdrop-filter: blur(12px)`, 1px mor border + **3px sol tür şeridi** (bell: `--accent-vivid`, error/success/info kendi renkleri), radius 8, 280–360px; altta 2px ilerleyen progress bar (tür renginde).
- **Dialog kartları (Quit/CloseTab):** 420px, `--bg-surface`, radius 12, `0 16px 64px` gölge; 56px daire ikon (warning %10 alpha zemin + `--accent-warning`); onay butonu `--accent-vivid`, iptal ghost.
- **Settings modal:** 700×600, radius 16. Sol nav aktif item'ı: `rgba(139,92,246,0.08)` zemin + accent. Input'lar: `--bg-deep` zemin + `--border`, focus'ta `--accent-vivid` çerçeve; number spinner'ları gizli. Toggle: 40×22 pill, on: `--accent-vivid` + beyaz thumb. Kbd (`.shortcut-kbd`): min 24px, `--bg-surface`, alt border 2px (klavye tuşu görünümü). Footer: sağa yaslı Cancel (ghost) + Save (`--accent-vivid`, disabled opacity 0.4).
- **Dropdown/popup/context-menu ortak kalıbı:** `--bg-elevated` zemin + 1px `--border` + radius 6 + `0 8px 24–32px` siyah gölge; item'lar 12px, hover `--bg-surface`; separator 1px `--border`. (Repo dropdown istisna: `--bg-surface` zemin, header altına ortalanmış, `fadeInUp` 0.15s.)
- **Scrollbar (global):** 8px, şeffaf track, `rgba(42,42,74,0.5)` thumb (hover 0.7, active 0.9), radius 4 — xterm scrollbar'ı da aynı palete override edilir ([20](./20-renderer-terminal.md) §3).
- **Empty state:** 48px soluk ikon (opacity 0.5; maskot ise tam opak), 14px başlık, 12px açıklama (max 240px).
- **Quick action butonu:** `--bg-elevated` zemin, 11px, accent ikon; hover `--accent-deep` zemin + lift; sağ-üst köşede soluk Info ikonu.
- **File tree:** klasör ikonu `--accent-warning`, dosya ikonu `--text-muted`, `ignored` node opacity 0.4, çocuk indent'i 16px.
- **Commit listesi:** her commit 1px sol çizgi + 7px nokta (`--border`; HEAD: `--accent-success` + glow); hash `--accent-cyan` 11px; satırlar arası degrade divider.
- **SearchInput (ayrı dosya):** 28px yükseklik, `--bg-deep` zemin, focus-within'de accent çerçeve.
- **Onboarding (SetupScreen.css, ayrı dosya):** 28px numaralı step dot'ları (aktif: accent çerçeve + 12px glow), 48px ilerleme çizgileri, `--bg-deep` tam ekran zemin.

---

## 6. Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **`-webkit-app-region: drag/no-drag`** (header, focus bar) → `NSWindow` titlebar/drag davranışı ([30](./30-app-shell.md)).
2. **Platform body class'ları:** `body.platform-darwin .header { padding-left: 80px }` (traffic light boşluğu; fullscreen'de 12px), `platform-win32` 140px sağ padding — macOS-only rewrite'ta sadeleşir, AppKit'te traffic light yerleşimi bedavadır.
3. **`::-webkit-scrollbar` stilleri** → `NSScrollView` overlay scroller görünümü (custom çizim gerekirse `NSScroller` subclass).
4. **`backdrop-filter: blur()`** (toast 12px, focus bar 8px, file-viewer backdrop 4px) → `NSVisualEffectView` / SwiftUI `Material`.
5. **`accent-color`** (checkbox'lar `--accent-vivid`) → `NSAppearance`/tint.
6. **xterm CSS override'ları** (`.xterm-viewport` şeffaf zemin, scrollbar radius) → SwiftTerm'de gereksiz.
7. **CSS `var()` fallback semantiği:** tanımsız token kullanan declaration'lar initial değere düşer (aşağıdaki not) — native'de derleyici bu sınıf hatayı imkânsız kılar.

---

## 7. Native rewrite notları (riskler, tutarsızlıklar)

- **En büyük karar: native look vs görsel parite.** Bu envanter parite senaryosu için piksel referansıdır; native-look senaryosunda ise hangi token'ların semantic karşılığa (örn. `--bg-elevated` → `controlBackgroundColor`) maplendiği tek tek kararlaştırılmalı. Karar [00-overview](./00-overview.md) açık sorularına eklenmiştir.
- **Tek tema:** Yalnızca dark tema vardır; Settings'teki Light butonu disabled ("Coming soon"). Tema runtime'da değişmez. Native'de light/dark desteği eklenecekse bu yeni feature kararıdır.
- **Tanımsız token'lar (bug sınıfı):** `--border-subtle` ve `--bg-hover` file-viewer/commit-diff stillerinde kullanılır ama hiçbir yerde tanımlı değildir (CSS gereği declaration initial değere düşer: border `currentColor`, background şeffaf). `--font-mono` ve `--status-*` yalnızca fallback'le kullanılır. Bunlar bilinçli tasarım değildir; rewrite'ta tanımlı token'lara bağlanmalı.
- **Durum rengi tutarsızlığı:** ChangesSection accent paletini, CommitDiffView VS Code-vari fallback hex'lerini kullanır (bkz. §3.2) — tek palete normalize edilmeli.
- **Hardcoded alpha türevleri:** Accent'in rgba varyantları tokenize değil; native'de "accent %X opacity" semantic varyantları tanımlanmalı, yoksa kopya-değer kayması yaşanır.
- **BEM sınıf adları** native'de anlamsızdır ama bu dokümandaki component listesi (badge, status-dot, toast, dialog…) yeniden kullanılabilir view envanteri olarak okunmalı.
- **Üç CSS dosyası vardır:** `globals.css` + `SearchInput.css` + `SetupScreen.css`; spec dışı stil kaynağı yoktur (Monaco/xterm kendi stillerini getirir). `styles/CLAUDE.md` özet dokümanı da güncel tutulmaktadır.
- **Marquee ve sparkle gibi süslemeler** (commit mesajı kayan yazısı, NEW rozeti pulse'ı) düşük maliyetli ama kimlik veren detaylardır; parite hedefleniyorsa unutulması kolaydır. (NEW rozeti hâlihazırda dormant — taşıma kararı gamification kararına bağlı.)
