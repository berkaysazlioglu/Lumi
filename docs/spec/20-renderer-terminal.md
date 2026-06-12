# Renderer Terminal Alt Sistemi (Terminal + TerminalPanel)

Kaynak: `src/renderer/components/Terminal/` (hooks dahil) ve `src/renderer/components/TerminalPanel/`.
İlişkili store: `src/renderer/stores/useTerminalStore.ts` (output modeli bu spec'in ayrılmaz parçası olduğu için davranışı burada da belgelenmiştir).

## Amaç ve sorumluluk

Bu alt sistem, main process'te yaşayan PTY session'larının **görsel temsilini** sağlar:

- Her PTY session için bir **terminal kartı** (xterm.js emülatörü + header) render eder.
- PTY çıktısını store üzerinden alıp emülatöre yazar (delta/append stratejisi ile, OOM-safe).
- Kullanıcı girdisini (klavye, paste, drag-drop edilen dosya yolu) IPC ile PTY'ye iletir.
- Kartların **grid layout**'unu (auto / N kolon / N satır), spawn akışlarını (provider, bash, persona) ve boş durum ekranlarını yönetir.

Mimari ilke: **Main process terminal'lerin source of truth'udur.** Renderer hiçbir zaman kendi başına terminal kaydı oluşturmaz; spawn/kill IPC çağrısından sonra `syncFromMain()` ile main'den snapshot çekip reconcile eder.

---

## Feature envanteri

### 1. xterm.js emülatör instance'ı (kart başına bir adet)

**Davranış:** Her terminal kartı mount olduğunda bir xterm.js instance'ı yaratılır ve container div'e bağlanır. Ayarlar:

| Ayar | Değer |
|---|---|
| `allowProposedApi` | `true` (Unicode11 addon için zorunlu) |
| `fontSize` | Config'den (`terminalFontSize`, default 13) |
| `fontFamily` | `'JetBrains Mono', monospace` |
| `cursorBlink` | `true` |
| `cursorStyle` | `block` |
| `cursorInactiveStyle` | `none` (odakta olmayan terminalde cursor görünmez) |
| `scrollback` | **5000 satır** |
| `theme` | Aşağıdaki sabit palet |

**Edge-case'ler:**
- Init, container DOM node'u henüz hazır değilse veya instance zaten varsa atlanır (double-init koruması).
- `terminalId` veya `fontSize` değişirse instance **dispose edilip yeniden yaratılır** (font değişikliği = full re-init; buffer kaybı store'dan replay ile telafi edilir).
- Instance hazır olduğunda `xtermReady` flag'i set edilir; output renderer bu flag'i beklemeden yazmaz (restore ile init race'i önlenir).

**Kullanıcıya görünen etki:** Tanıdık terminal deneyimi; 5000 satır geriye scroll; blok cursor sadece odaktaki kartta yanıp söner.

### 2. Addon seti

Yüklenen addon'lar ve sırası:

1. **FitAddon** — emülatör boyutunu container'a uydurur; `open()` sonrası ilk `fit()` çağrılır.
2. **WebLinksAddon** — URL algılama; tıklamada custom callback ile `openExternal(url)` IPC'si çağrılır (link **uygulama içinde değil, sistem default browser'ında** açılır).
3. **Unicode11Addon** — yüklendikten sonra `unicode.activeVersion = '11'` set edilir (emoji/CJK genişlik hesapları için).
4. **WebglAddon** — `open()` SONRASINDA yüklenir, GPU render için. `try/catch` ile sarılı: WebGL yoksa sessizce canvas renderer'a düşülür. `onContextLoss` olayında addon kendini dispose eder (canvas fallback).

**Not:** **SearchAddon YOK** — terminal içi arama feature'ı mevcut implementasyonda bulunmuyor. Native rewrite'ta isteğe bağlı eklenebilir ama parite için zorunlu değil.

### 3. Tema ve renk paleti

Sabit koyu tema (`XTERM_THEME`), uygulamanın mor/violet temasıyla uyumlu. Native implementasyonda aynen taşınması gereken değerler:

- background `#12121f`, foreground `#e2e2f0`
- cursor `#a78bfa`, cursorAccent `#12121f`
- selection `rgba(139, 92, 246, 0.3)`
- scrollbar slider: normal `rgba(42,42,74,0.5)`, hover `rgba(74,74,106,0.7)`, active `rgba(74,74,106,0.9)`
- ANSI 16: black `#0a0a12`, red `#f87171`, green `#4ade80`, yellow `#fbbf24`, blue `#a78bfa`, magenta `#8b5cf6`, cyan `#22d3ee`, white `#e2e2f0`; bright: `#4a4a6a`, `#fca5a5`, `#86efac`, `#fde68a`, `#c4b5fd`, `#a78bfa`, `#67e8f9`, `#ffffff`

**Edge-case:** Tema runtime'da değiştirilemez (tek dark tema). Font boyutu config'den **async** yüklenir; ilk render 13px ile başlar, config gelince re-init olur.

### 4. Output write path ve store output modeli (V8 OOM fix — commit 04009f6)

Bu alt sistemin en kritik ve en yeni davranışı. PTY çıktısı şu yolu izler:

```
PTY (main) → safeSend → IPC 'terminal:output' (terminalId, chunk)
  → global bridge (useTerminalStore.connectTerminalEventBridge, Layout ömründe)
  → appendOutput(id, chunk) → store'daki TerminalOutput güncellenir
  → React subscription → useTerminalOutputRenderer → xterm.write
```

**Store output modeli (`TerminalOutput`):**
```
{ text: string, totalLength: number, epoch: number }
```
- `text` — output stream'inin **cap'lenmiş kuyruğu** (max 500.000 karakter, main'deki `OutputBuffer` cap'iyle birebir aynı).
- `totalLength` — şimdiye dek append edilmiş **mutlak karakter sayısı** (monotonik artar, trim'den etkilenmez). Delta rendering'i bu sürer.
- `epoch` — incremental olmayan her rewrite'ta (ör. snapshot ile diverge) +1 artar; xterm'e "full redraw yap" sinyali.

**Trim davranışı (`trimOutputTail`, main ile paylaşılan utility):**
- `text.length <= maxSize` (500k) ise dokunma.
- Aksi halde baştan kes; kesim noktasından itibaren **2048 karakterlik pencerede ilk `\n` aranır** ve kesim oraya kaydırılır — ANSI escape sequence'lerin ortadan bölünmesini engellemek için. Newline bulunamazsa ham offset'ten kesilir.

**Renderer patch hesabı (`computeOutputPatch`):** Render edilen son durum `{ totalLength, epoch }` cursor'u olarak tutulur (React ref). Yeni output geldiğinde:
- `epoch` aynı ve `delta = output.totalLength - rendered.totalLength`:
  - `delta == 0` → **noop** (hiçbir şey yazma).
  - `0 < delta <= text.length` → **append**: `text`'in son `delta` karakteri xterm'e yazılır (O(delta), string karşılaştırması YOK).
  - `delta > text.length` (renderer trim sınırından fazla geride kaldı) → **replace**.
  - `delta < 0` (rollback) → **replace**.
- `epoch` farklı → **replace**.
- **replace**: `xterm.clear()` + tüm `text`'in chunked yazımı.

**Tarihçe/rasyonel (belgelenmeli):** Eski implementasyon store'da unbounded string biriktiriyor ve her chunk'ta `startsWith` prefix karşılaştırması (O(n) tarama) yapıyordu. Ağır PTY çıktısında bu, renderer V8 heap'inde OOM crash'e yol açtı. Fix: (a) renderer buffer'ı 500k'da cap'le, (b) prefix karşılaştırması yerine mutlak stream offset (`totalLength`) + `epoch` ile delta hesapla, (c) main tarafında `safeSend`'i crash/destroyed webContents'e karşı sertleştir (crash ile recovery reload arasında PTY çıktısının konsolu floodlamasını engelle).

**Snapshot reconciliation (`mergeSnapshotOutput`):** `syncFromMain()` main'den snapshot (`output` string'i = main'in 500k buffer'ı) çektiğinde:
- Renderer'da output yoksa → snapshot'ı al, `epoch+1` (full redraw).
- Snapshot boş ya da birebir aynı → dokunma.
- Snapshot, mevcut text ile **başlıyorsa** (renderer event kaçırmış) → incremental uzat, epoch aynı (redraw yok, sadece append).
- Mevcut text, snapshot ile başlıyorsa (renderer ileride; sync canlı output ile yarıştı) → mevcut korunur (rollback flicker yok).
- Diverge → uzun olan buffer tercih edilir; snapshot alınırsa `epoch+1`.
- Ek koruma (`preserveNewerLiveOutputs`): sync IPC'si beklenirken gelen canlı `appendOutput`'lar, reconcile sonucunun `totalLength`'ini geri sarmasın diye final commit'te daha yeni canlı output korunur. Aksi halde destructive full redraw olur.

**Kullanıcıya görünen etki:** Ağır çıktıda (build logları, uzun stream'ler) UI donmaz, app crash etmez; repo sekmesi değişiminde / restore'da terminal içeriği kaldığı yerden görünür; sync'lerde içerik titreşmez (flicker yok).

### 5. Chunked yazım (`writeChunked`)

**Davranış:** xterm'e tek seferde 10.000 karakterden büyük veri yazılacaksa (yalnızca **replace** path'inde kullanılır), veri 10KB'lık parçalara bölünür ve her parça bir `requestAnimationFrame` tick'inde yazılır. ≤10KB veriler doğrudan tek seferde yazılır.

**Amaç:** Büyük replay'lerde (örn. repo değişiminde 500k'lık buffer redraw'u) main thread'in bloklanmasını ve frame drop'u önlemek.

**Edge-case:** rAF zincirinin ortasında xterm dispose edilirse yazım orphan kalabilir (mevcut kodda iptal mekanizması yok — xterm dispose sonrası write no-op olduğu için zararsız, ama native'de lifecycle'a dikkat).

### 6. Resize / fit

**Davranış:** İki gözlemci tetikler, ikisi de aynı 150ms debounce'lu handler'a girer:
1. **ResizeObserver** (container div) — pencere/grid boyutu değişince.
2. **IntersectionObserver** (threshold 0.01) — kart **görünür hale gelince** (repo sekmesi değişimi sonrası `display:none`'dan çıkış). Görünmezken fit çağrılmaz.

Handler: debounce dolunca `fitAddon.fit()` çalışır, ardından yeni `cols`/`rows` değerleri `resizeTerminal(terminalId, cols, rows)` IPC'si ile main'e (PTY resize, SIGWINCH) iletilir.

**Edge-case'ler:**
- `cols`/`rows` 0/undefined ise IPC çağrılmaz.
- Debounce timer unmount'ta temizlenir.
- IntersectionObserver kritik: gizliyken (`display:none`) fit yapılırsa xterm 0 boyut hesaplar; bu yüzden sadece görünürken fit edilir.

**Kullanıcıya görünen etki:** Kart boyutu değişince TUI uygulamaları (Claude Code dahil) doğru genişliğe reflow olur; sekme değişiminde dönen terminal düzgün boyutlanır.

### 7. Klavye girdisi ve copy/paste

**Davranış:**
- Tüm tuş girdisi `xterm.onData` ile yakalanıp `writeTerminal(terminalId, data)` IPC'si ile PTY'ye gönderilir. Renderer'da local echo yok; her şey PTY'den döner.
- **Yalnızca Windows/Linux'ta** (platform ≠ darwin) custom key handler:
  - `Ctrl+Shift+C` → seçili metin varsa `navigator.clipboard.writeText` ile kopyala, tuşu PTY'ye iletme.
  - `Ctrl+Shift+V` → async `clipboard.readText()` → `xterm.paste(text)`. **`isPasting` lock'u:** async clipboard okuma sürerken GELEN TÜM tuş girdisi bloklanır — paste içeriği ile sonraki tuşların sıra karışması önlenir. Okuma bitince (başarılı/başarısız) lock açılır.
- macOS'ta native Cmd+C/Cmd+V akışı kullanılır (custom handler takılmaz).

**Kullanıcıya görünen etki:** Platforma uygun kopyala/yapıştır; hızlı yazan kullanıcıda paste sırasında karakter sırası bozulmaz.

### 8. Link handling

**Davranış:** WebLinksAddon terminal çıktısındaki URL'leri algılar, hover'da altını çizer; tıklamada URL `openExternal` IPC'si (`shell:open-external`) üzerinden **sistem default browser'ında** açılır. Uygulama içinde webview açılmaz.

### 9. Focus yönetimi

**Davranış:**
- Karta tıklamak `setActiveTerminal(terminalId)` çağırır (store).
- Aktif terminal değiştiğinde: (a) o kartın xterm'i `focus()` alır (klavye girdisi oraya akar), (b) `focusTerminal(terminalId)` IPC'si main'e bildirilir — main bu bilgiyi status hesaplamasında kullanır (örn. `waiting-unseen` → `waiting-focused` geçişi, status dot rengi).
- Aktif kart `terminal-card--focused` CSS sınıfı alır (görsel vurgu).
- Store, repo başına son aktif terminali `lastActiveByRepo` map'inde tutar; sekme değişiminde o repo'nun son aktif terminali odaklanır.
- **Kapatma sonrası komşu odak:** aktif terminal kapatılırsa odak **aynı repo içindeki, minimize edilmemiş** önceki komşuya (ilk eleman kapanıyorsa sonrakine) geçer; komşu yoksa `null`. Komşu, silme işleminden ÖNCE hesaplanır.
- **Minimize sonrası odak:** aktif terminal minimize edilirse odak proaktif olarak görünür komşuya kayar.

**Edge-case:** `setActiveTerminal` store'da olmayan bir id ile çağrılırsa yine de set edilir (sync ile düzelir); minimize edilmiş terminaller hiçbir otomatik odak akışında hedef olamaz.

### 10. Terminal kartı header'ı

**Davranış:** Her kartın üstünde:
- **StatusDot** — terminal status'üne göre renkli nokta (`idle | working | waiting-unseen | waiting-focused | waiting-seen | error`; status main'den IPC ile gelir).
- **Başlık** — öncelik sırası: `oscTitle` (PTY'nin OSC escape ile set ettiği başlık) → `task` (spawn'da verilen etiket, ör. "Bash") → `name` (main'in verdiği isim) → fallback `"Terminal"`.
- **Minimize butonu** (− ikonu) — kartı gizler (renderer-only state; PTY yaşamaya devam eder), sidebar'dan geri açılır.
- **Close butonu** (× ikonu) — `killTerminal` IPC + `syncFromMain()`; PTY öldürülür.
- Buton tıklamaları `stopPropagation` yapar (kart odaklanma tıklamasını tetiklemesin).

### 11. Drag & drop ile dosya yolu yazma

**Davranış:** Kartın üzerine bir şey sürüklenince `dropEffect='copy'` ve kart `terminal-card--drag` görseline geçer + "Drop file here" overlay'i görünür. Drop'ta `dataTransfer`'ın `text/plain` verisi (uygulamanın dosya ağacından sürüklenen dosya yolu) **olduğu gibi** `writeTerminal` ile PTY'ye yazılır (newline eklenmez — kullanıcı komutuna path eklemiş olur). Boş string drop'u yok sayılır. Drag leave'de overlay kalkar.

### 12. Output replay / kalıcı mount stratejisi

**Davranış:** Terminal kartları **repo sekmesi değişiminde unmount EDİLMEZ**; tüm repoların tüm kartları mount kalır, görünmeyenler `display:none` ile gizlenir. Amaç: xterm scrollback/state'inin korunması ve sekme dönüşünde anında görünüm.

- Görünürlük koşulu: `terminal.repoPath === aktifRepo.path && !terminal.minimized`.
- Kart yeniden görünür olduğunda IntersectionObserver fit tetikler.
- Bir kart (font değişimi vb. ile) yeniden init olursa, output renderer cursor'u sıfırlanır ve store'daki cap'li buffer **replace** path'i ile xterm'e replay edilir.

### 13. Grid layout (auto / columns / rows)

> **NATIVE DEĞİŞİKLİĞİ ([01-decisions.md](./01-decisions.md) Karar 15):** Bu bölüm v1 davranışını belgeler. Native'de tek-eksenli `auto/columns/rows` yerine **iki eksen** vardır: kolon (`auto`/`columns N`) × yükseklik (`fit`/`scroll`). `rows` emekli (eski dosyalar `auto`+`fit`'e migrate). `fit` = hepsi viewport'a sığar; `scroll` = satır yüksekliği `kolon genişliği × heightRatio` (%100/%50/%33, default %50; sabit oran, fit ile max'lanmaz), içerik taşınca dikey scroll. Aşağıdaki kolon-sayısı ve son-satır-stretch matematiği aynen geçerlidir.

**Davranış:** Görünür kartlar bir CSS grid'de dizilir. Üç mod, **repo (proje) başına ayrı** saklanır:
- **auto** (default): kolon sayısı = `floor((containerWidth + 12) / (400 + 12))`, min 1. (Kart min genişliği 400px, grid gap 12px.) Satır yükseklikleri içerik/CSS default'u.
- **columns N** (N ∈ {2,3,4,5}): tam N kolon; kolon genişliği piksel cinsinden eşit bölünür: `floor((containerWidth - (N-1)*12) / N)`.
- **rows N** (N ∈ {2,3,4,5}): satır sayısı sabit N; kolon sayısı = `max(1, ceil(görünürSayısı / N))`; hem kolon genişliği hem satır yüksekliği viewport'a eşit bölünerek piksel olarak hesaplanır (scroll çıkmaz).

**Son satır stretch davranışı (auto modda YOK):** Görünür kart sayısı kolon sayısına tam bölünmüyorsa, son (eksik) satırdaki kartlar tüm genişliği dolduracak şekilde `grid-column: span X` alır. Dağıtım: `baseSpan = floor(cols / remainder)`; `cols % remainder` kadar fazla kolon, son satırın **sondaki** kartlarına +1 span olarak verilir. Örn. 5 kolonda 2 artık kart → span 2 ve span 3.

**Edge-case'ler:** containerWidth henüz ölçülmemişse (0) kolonlar `1fr` ile render edilir; tek kolonda veya 0 kartta span hesabı yapılmaz.

### 14. Focus mode grid'i

**Davranış:** Uygulama "focus mode"a girince (app-level state) terminal paneli header'ı gizlenir ve grid, **tüm görünür kartları viewport'a sığdıracak** şekilde explicit satır yükseklikleri hesaplar:
- Kolon şablonu: auto modda `repeat(auto-fit, minmax(400px, 1fr))`, diğer modlarda normal hesap.
- Satır sayısı: rows modunda N, diğer modlarda `ceil(görünür / kolon)`.
- Satır yüksekliği: `floor((containerHeight - (rows-1)*12) / rows)` — dikey scroll çıkmaz, her kart görünür.

### 15. Spawn akışları (panel header + boş durum)

Üç spawn yolu, hepsi şu kalıbı izler: **limit kontrolü → IPC spawn → (gerekirse launch komutu yaz) → `syncFromMain()` → `setActiveTerminal(yeniId)`**:

1. **New \<Provider\>** (ana buton): `spawnTerminal(repoPath)` → dönen id'ye provider launch komutu yazılır: `"claude\r"` veya `"codex\r"` (aktif AI provider config'ine göre; buton etiketi de "New Claude"/"New Codex" olur). Yani önce shell açılır, sonra CLI komutu enjekte edilir.
2. **New Bash** (dropdown'dan): `spawnTerminal(repoPath, 'Bash')` — task etiketi 'Bash' geçilir ki kartın görünür bir adı olsun; launch komutu yazılmaz (düz shell).
3. **Persona** (dropdown'dan): `spawnPersona(personaId, repoPath)` — main, persona tanımına göre spawn'ı yapar.

**Limit:** `maxTerminals = 12` (global, tüm repolar toplamı). Aşılırsa `alert("Maximum 12 terminals allowed")` gösterilir ve spawn yapılmaz. Panel header'ında `görünür / 12` sayacı gösterilir. Repo'daki terminal sayısı limite ulaşınca dropdown butonu disabled olur.

> **Bilinen bug (taşımayın):** TerminalPanel bu üç limit kontrolünün **hepsinde** (spawn öncesi limit alert'i, header'daki "N / 12" sayacı, dropdown'un disabled durumu) kullanıcının config'indeki `maxTerminals` yerine `DEFAULT_CONFIG.maxTerminals` sabitini (12) kullanır. Aynı bug FocusExitControl ve useKeyboardShortcuts'ta da vardır ([22](./22-renderer-ui.md)) — yani renderer'daki tüm limit kontrolleri kullanıcı config'ini yok sayar; gerçek config limitini yalnızca main process'teki TerminalManager uygular (aşımda sessiz `null` döner). Native'de tüm call-site'lar gerçek config değerini okumalı.

**Edge-case'ler:** Aktif repo yoksa spawn no-op. IPC hatası `console.error`'a yazılır, kullanıcıya toast gösterilmez (zayıflık — native'de düzgün hata UI'ı düşünülmeli). Spawn sonrası `setActiveTerminal` açıkça çağrılmalıdır çünkü `syncFromMain` mevcut aktifi korur.

### 16. PersonaDropdown

**Davranış:** "New \<Provider\>" butonunun yanındaki chevron'lu hover dropdown:
- **Hover ile açılır**, mouse ayrılınca **150ms gecikmeyle** kapanır (menüye geçiş için tampan); tekrar girilirse kapanma timer'ı iptal edilir.
- İçerik: "New Bash" + (varsa separator +) repo'ya yüklü persona listesi ("New \<persona.label\>").
- Persona listesi: mount'ta ve repo değişiminde `getPersonas(repoPath)` ile çekilir; ayrıca `loadProjectPersonas(repoPath)` tetiklenir (main, projedeki persona dosyalarını yükler) ve `onPersonasChanged` IPC event'i ile liste canlı yenilenir. Yükleme hatasında liste boşa düşer.
- `onOpenChange` callback'i dışarıya açıklık durumu bildirir (focus-mode hover davranışı için).
- Seçim yapınca dropdown kapanır.

### 17. GridLayoutPopup

**Davranış:** Panel header'ındaki grid ikonu **tıklama ile** popup açar (hover değil):
- Trigger ikonu aktif moda göre değişir (LayoutGrid / Columns3 / Rows3); tooltip: "Auto grid" / "N columns" / "N rows".
- Popup içeriği: "Auto" satırı + Columns için 2-5 sayı butonları + Rows için 2-5 sayı butonları; aktif seçim vurgulanır.
- Seçim `setProjectGridLayout(repoPath, {mode, count})` çağırır (repo başına persist; store tarafında 500ms debounce ile diske yazılır). Auto seçiminde count 2 gönderilir ama anlamsızdır.
- Dışarı tıklayınca kapanır (document mousedown listener'ı yalnızca açıkken takılı).
- Açılış/kapanış 150ms fade+slide animasyonlu.

### 18. Boş durum ekranları

1. **Repo seçili değil:** klasör ikonu + "No repository selected" + yönlendirme metni.
2. **Repo'da hiç terminal yok:** maskot görseli + "No terminals running" + "Spawn a new terminal to start coding with \<Provider\>" + spawn dropdown'u (aksiyon olarak).
3. **Tümü minimize:** maskot + "All terminals minimized" + "Click a session in the sidebar to restore". Bu durumda grid `display:none` ile gizlenir ama kartlar mount kalır.

---

## Veri akışı ve bağımlılıklar

### IPC kanalları (preload `window.api` üzerinden)

**Renderer → Main (invoke):**
| API | Kanal | Kullanım |
|---|---|---|
| `spawnTerminal(repoPath, task?)` | `terminal:spawn` | Yeni PTY; `{id, name, isNew}` döner |
| `spawnPersona(personaId, repoPath)` | `personas:spawn` | Persona terminali |
| `writeTerminal(id, data)` | `terminal:write` | Klavye/launch komutu/drop edilen path |
| `killTerminal(id)` | `terminal:kill` | Kart kapatma |
| `resizeTerminal(id, cols, rows)` | `terminal:resize` | Fit sonrası PTY resize |
| `getTerminalSnapshots()` | `terminal:snapshot` | `syncFromMain` için tam snapshot (output dahil) |
| `focusTerminal(id\|null)` | `terminal:focus` | Aktif terminal bildirimi (status hesapları için) |
| `getConfig()` | `config:get` | `terminalFontSize` okuma |
| `openExternal(url)` | `shell:open-external` | Link tıklaması |
| `getPersonas(repoPath?)` / `loadProjectPersonas(repoPath)` | personas kanalları | Dropdown listesi |

**Main → Renderer (event, global bridge `Layout` ömründe bağlanır):**
| Event | Payload | Etki |
|---|---|---|
| `terminal:output` | `(id, chunk)` | `appendOutput` → store cap'li buffer |
| `terminal:status` | `(id, status)` | StatusDot güncellenir |
| `terminal:title` | `(id, title)` | `oscTitle` → kart başlığı |
| `terminal:exit` | `(id, code)` | `removeTerminal` + komşu odak |

**Kritik mimari nokta:** Output/status/exit listener'ları **kart component'inde değil**, app-level `Layout` component'inin bağladığı **global bridge**'dedir. Böylece kart görünmese/farklı repo'da olsa bile output birikmeye devam eder. Bridge idempotent bağlanır (zaten bağlıysa no-op).

### Diğer alt sistemlerle ilişki
- **Main terminal yöneticisi:** PTY yaşam döngüsü, `OutputBuffer` (aynı 500k cap, aynı `trimOutputTail`), status hesaplama, OSC title parse — hepsi main'de. Renderer sadece yansıtır.
- **`safeSend` (main):** PTY output'u renderer'a gönderilmeden önce window/webContents destroyed/**crashed** kontrolü yapılır; frame disposed hataları yutulur. Renderer crash ile recovery reload arasında output IPC'si susturulur.
- **Sidebar / sessions listesi:** minimize edilen terminaller oradan restore edilir; notification tıklaması minimize'ı kaldırıp odaklar.
- **useAppStore:** `activeTab` (hangi repo görünür), `focusModeActive`, `aiProvider`, `projectGridLayouts`.
- **useRepoStore:** `getRepoByName(activeTab)` → repoPath.

---

## Persistence / config

Bu alt sistemin kendisi diske yazmaz; okuduğu/tetiklediği kalıcı state:

| Veri | Nerede | Format |
|---|---|---|
| `terminalFontSize` (default 13) | App config (main, config dosyası) | number; mount'ta `getConfig()` ile okunur |
| `maxTerminals` | `DEFAULT_CONFIG` sabiti (12) — **bug:** kullanıcı config'indeki değer renderer'da hiç okunmaz (bkz. §15 notu) | number |
| Grid layout (repo başına) | UI state — `projectGridLayouts: Record<repoPath, {mode: 'auto'\|'columns'\|'rows', count: number}>` | `setProjectGridLayout` ile, store tarafında 500ms debounce'la main'e yazdırılır |
| `aiProvider` | App config | `'claude' \| 'codex'` |
| Output buffer'ları | **Persist EDİLMEZ** | App restart'ta kaybolur; app içi geçişlerde main'in 500k `OutputBuffer`'ından snapshot ile geri gelir |
| `minimized` flag'i | Renderer-only (persist edilmez) | Snapshot'ta yoktur; reconcile sırasında mevcut renderer değeri korunur |

---

## Electron'a özgü kısımlar (native'de farklı çözülecekler)

1. **xterm.js + addon'lar:** Native'de terminal emülatörü olarak **SwiftTerm** (veya eşdeğeri) kullanılmalı. Fit/WebGL/Unicode11 addon'larının karşılığı SwiftTerm'de built-in (autoresize, CoreText/Metal render, grapheme genişliği). WebLinks karşılığı SwiftTerm'in link detection'ı + `NSWorkspace.shared.open(url)`.
2. **Renderer/main process ayrımı ve IPC:** Native'de PTY ile view aynı process'te olacağından `terminal:output` IPC'si, global bridge, `safeSend`, snapshot/`syncFromMain` reconcile makineleri **tamamen ortadan kalkabilir**. PTY veri akışı doğrudan terminal view'a (ve status parser'a) beslenebilir.
3. **Store'daki ikinci output buffer'ı (500k) + `totalLength`/`epoch` delta modeli:** Bu mekanizmanın varlık sebebi IPC üzerinden process sınırını aşan, kaybolabilen/yarışabilen event akışıdır. Native tek-process mimaride muhtemelen **gereksiz** — ancak "görünmeyen terminal'in scrollback'ini canlı tutma" ihtiyacı kalır; SwiftTerm view'larını canlı tutarak ya da PTY başına tek bir cap'li buffer + reattach-replay ile çözülebilir.
4. **`display:none` ile mount tutma + IntersectionObserver:** Electron'da xterm state'i DOM'a bağlı olduğu için kartlar gizlenip mount tutuluyor ve görünür olunca fit tetikleniyor. AppKit/SwiftUI'da view hidden tutulabilir veya terminal state view'dan ayrıştırılıp görünürlükte reattach edilebilir; "görünür olunca resize/fit" davranışı korunmalı.
5. **`requestAnimationFrame` chunked write:** JS main-thread bloklanmasına karşı bir önlem. Native'de SwiftTerm feed'i zaten incremental; büyük replay'lerde background parse / chunked feed ile eşdeğeri düşünülmeli.
6. **`navigator.clipboard` + Ctrl+Shift+C/V handler'ı:** Yalnızca Windows/Linux içindi; macOS-native rewrite'ta **gereksiz** — standart Cmd+C/V, `NSPasteboard` ile. `isPasting` lock'una da gerek kalmaz (NSPasteboard senkron).
7. **WebGL fallback:** SwiftTerm'de render backend'i platformun kendisi; context-loss fallback senaryosu yok.
8. **CSS Grid + span hesapları:** Auto-fit/kolon/satır modları ve son-satır span dağıtımı native layout'ta (SwiftUI Grid / manuel frame hesabı) aynı matematikle yeniden kurulmalı: 400px min kart, 12px gap, `floor` tabanlı piksel bölüşümü, focus mode'da viewport'a tam sığdırma.
9. **`alert()` ile limit uyarısı:** Native'de `NSAlert`/SwiftUI alert; bu vesileyle daha iyi bir UX (toast) düşünülebilir.
10. **Framer Motion animasyonları (dropdown/popup 150ms fade+slide):** SwiftUI transition'larıyla birebir karşılanır.

---

## Native rewrite notları (riskler, dikkat edilecekler)

- **OOM fix'in dersi taşınmalı:** Sınırsız output birikimi crash sebebiydi. Native'de bellek modeli farklı olsa da PTY başına buffer **mutlaka cap'li** olmalı (500k karakter paritesi makul bir başlangıç) ve trim **newline'a hizalanmalı** (2048 karakterlik arama penceresi) — ANSI sequence ortadan bölünürse emülatör state'i bozulabilir. SwiftTerm'in kendi scrollback limiti (5000 satır paritesi) ayrıca set edilmeli.
- **Per-chunk O(n) işlem yapmamak:** Eski bug'ın ikinci yarısı, her chunk'ta tüm buffer'ı taramaktı. Native'de de chunk işleme O(chunk) kalmalı.
- **Status/focus sözleşmesi:** `focusTerminal` bildirimi main'in status makinesini besliyor (`waiting-unseen` ↔ `waiting-focused`). Native'de tek process olsa bile "hangi terminal odakta" bilgisi status motoruna aynı semantikle akmalı; yoksa bildirim/dot davranışı bozulur.
- **Odak kuralları ince ayrıntılı:** (a) kapatmada aynı-repo görünür önceki komşu, (b) minimize'da görünür komşuya proaktif kayış, (c) minimize terminaller asla otomatik odak almaz, (d) spawn sonrası yeni terminal açıkça odaklanır, (e) repo başına lastActive hatırlanır. Bunlar test edilebilir saf fonksiyonlar olarak yazılmıştı; native'de de saf/test edilebilir tutulmalı.
- **Başlık önceliği** (`oscTitle > task > name > "Terminal"`) ve OSC title'ın canlı güncellenmesi korunmalı — Claude Code çalışırken başlığa durum yazar, kullanıcı buna alışkın.
- **Launch komutu enjeksiyonu:** "New Claude" akışı shell spawn + `"claude\r"` yazma şeklindedir (PTY'ye carriage return ile). Native'de de aynı iki-aşamalı model (shell + komut enjeksiyonu) korunmalı; doğrudan `claude` binary spawn etmek shell ortamını (rc dosyaları, PATH) kaybettirir.
- **Drag&drop sözleşmesi:** Drop edilen path'e newline EKLENMEZ; kullanıcı yazmakta olduğu komuta path ekler. `NSItemProvider`/file URL drop'unda path'in quote'lanması gerekebilir (mevcut kod quote'lamıyor — boşluklu path'lerde bilinen zayıflık, native'de düzeltmek değerlendirilebilir ama davranış değişikliği olarak not edilmeli).
- **Search yok:** Mevcut üründe terminal içi arama yok; SwiftTerm search desteği eklenirse bu bir feature ekleme kararıdır, parite gereksinimi değildir.
- **Hata UX'i zayıf:** Spawn/kill hataları sadece console'a gidiyor; limit uyarısı blocking `alert`. Native'de kullanıcıya görünür ama rahatsız etmeyen hata bildirimi tasarlanmalı.
- **Grid matematiği piksel-hassas:** `floor` tabanlı bölüşüm ve son-satır span dağıtımı (sondaki kartlara +1) birebir kopyalanmalı; aksi halde 5 kolon/7 kart gibi durumlarda görsel fark oluşur.
- **Font boyutu değişimi şu an full re-init:** xterm dispose + replay. SwiftTerm'de font değişimi in-place yapılabilir — buffer kaybetmeyen daha iyi bir davranış olur, regression değil iyileştirme sayılır.
