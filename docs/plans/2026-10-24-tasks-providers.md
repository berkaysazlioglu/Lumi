# Tasks — kendi sunucunu bağla (Lumi Tasks Protocol + adapter'lar) (plan)

Durum: **onaylandı, karar 137** (2026-10-24). Faz 1, 1b ve 2 tamam; protokol ve mimari `docs/design/06-tasks-protocol.md`'de. Sıradaki: Faz 3 (gerçek ajan).

Kullanıcı isteği: "Tasks sekmesini canlandırmak istiyorum … herkes kendi sisteminde kullanabilsin … user tasks sekmesindeki özel prompt'u alıp kendi heroku projesindeki bir agent'a yapıştırınca agent öyle bir sistem inşa edecek ki user o linki app'e yapıştırınca lumi task'leri çekebilecek, done'a atabilecek … token sistemi de olur … başka user railway'i bağlar."

## Kullanıcı kararları (2026-10-24)

1. Durum modeli **sabit dört durum**: `todo` / `in_progress` / `in_review` / `done`.
2. Lumi içeride **adapter** mimarisiyle kurulur; ilk (ve v1'deki tek) adapter **Custom — Lumi Tasks API**. GitHub Issues / Linear / Jira sonraki adapter'lardır.
3. Implementasyondan önce plan; **önce UI** (sahte veriyle), onaydan sonra protokol.
4. **Yorum yok** — `comments` capability'si ve uçları plandan çıktı.
5. **Atama:** kaynak `users` capability'sini beyan ederse kullanıcı listesi gelir ve task herhangi birine atanabilir; seçicide **`You` en üsttedir** (token'ın sahibi — discovery'deki `me`).
6. **Tazeleme:** Tasks route'u kapalıyken istek atılmaz; route açıldığı an güncel hâl çekilir ve açık kaldığı sürece periyodik olarak güncel tutulur.
7. **Asıl amaç task'i ajana vermek** (2026-10-24 ikinci tur): "bu task'leri görmek için eklemiyorum, bir task'i ai agent'a verebilmek için ekliyorum … direkt claude gibi düşünebiliriz". Görünürlük ve kendini In Review'a taşıma kararı bana bırakıldı — aşağıda "Task → ajan".
8. **Birleşik yazım:** her düzenleme ayrı istek olmasın; kısa bir gecikmeyle birleşsin (kullanıcı önerisi 2–3 sn; protokol tarafı bana bırakıldı).
9. **Görseller:** API'da link listesi olarak `images`; task sayfasında gösterilir, optimize yüklenir, tıklanınca Lumi viewer'ında açılır.
10. **Hatalar:** API hata verdiğinde Lumi bunu düzeltmeyi kolaylaştıracak ayrıntıda göstermeli.

## Terimler

| Terim | Anlamı |
|---|---|
| **Task Source** | Kullanıcının bağladığı tek bir kaynak: ad + adapter türü + adres + token. Birden çok olabilir (iş Heroku'su + kişisel Railway'i). |
| **Adapter** (`TaskProviding`) | Bir kaynağı Lumi'nin ortak task modeline çeviren katman. Custom adapter HTTP ile Lumi Tasks Protocol'ü konuşur; GitHub adapter'ı ileride GitHub API'sini konuşur. UI hangi adapter olduğunu bilmez. |
| **Lumi Tasks Protocol (v1)** | Custom adapter'ın konuştuğu açık, sürümlü HTTP sözleşmesi. Kullanıcının sunucusu bunu uygular. |
| **Setup prompt** | Tasks sekmesinden kopyalanan, protokolün tamamını içeren talimat. Kullanıcı kendi projesindeki ajana yapıştırır, ajan sunucuyu kurar ve sonunda URL + token'ı yazdırır. |
| **Capabilities** | Kaynağın neleri desteklediğinin beyanı (oluşturma, silme, kullanıcı listesi, hangi alanlar…). Lumi UI'ı buna göre açar/kapatır. |
| **Verify** (uygunluk testi) | Lumi'nin sunucuya karşı koştuğu otomatik kontrol listesi; hatayı ajana yapıştırılabilir bir raporla verir. |

## Ortak task modeli (Lumi içi, `LumiKit`)

Adapter ne olursa olsun UI yalnız bunu görür. **Zorunlu** alanlar az tutulur ki her sunucu uygulayabilsin; geri kalanı opsiyoneldir ve kaynak desteklemiyorsa UI'da hiç görünmez.

| Alan | Tür | Zorunlu | Not |
|---|---|---|---|
| `id` | string | ✓ | Kaynak içinde tekil. Lumi içinde `(sourceID, id)` çiftiyle anılır. |
| `title` | string | ✓ | |
| `status` | `todo` \| `in_progress` \| `in_review` \| `done` | ✓ | Sabit küme. |
| `updatedAt` | ISO 8601 UTC | ✓ | Sıralama, değişiklik algısı ve çakışma kontrolü için. |
| `createdAt` | ISO 8601 UTC | | |
| `body` | markdown string | | Detayda Lumi'nin markdown görünümüyle (karar 109) çizilir. |
| `project` | `{ key, name?, repo? }` | | Lumi projesiyle eşleşme ipucu (aşağıda). |
| `priority` | `none` \| `low` \| `medium` \| `high` \| `urgent` | | |
| `labels` | [string] | | |
| `assignee` | `{ id, name, email? }` | | Tek kişi. Yazılabilirse (`rw`) atama `assigneeId` ile yapılır. |
| `dueDate` | `YYYY-MM-DD` | | |
| `url` | string | | Sunucunun kendi web arayüzü varsa `Open in Browser`. |
| `images` | `[{ url, thumbnailUrl?, name?, width?, height? }]` | | Yalnız adresler; v1'de salt okunur (yükleme sonraki sürüm). Bkz. "Görseller". |
| `lumi` | `{ sessionId?, checkoutPath?, branch?, agent? }` | | Lumi'nin task'e iliştirdiği bağlantı; sunucu yalnız saklar ve geri döner (capability `lumiMetadata`). |

## Lumi Tasks Protocol v1 (taslak)

Tümü JSON, alan adları camelCase, tüm uçlar `Authorization: Bearer <token>` ister (discovery dahil — token hatasını Verify ilk adımda yakalasın).

```
GET    /lumi/v1                     → discovery: sürüm + capabilities + alan beyanı
GET    /lumi/v1/tasks               → ?status=todo,in_progress&project=<key>&cursor=&limit=
                                      { tasks: [...], nextCursor: string|null }
GET    /lumi/v1/tasks/{id}
PATCH  /lumi/v1/tasks/{id}          → kısmi güncelleme; en az `status` ZORUNLU desteklenir
POST   /lumi/v1/tasks               → capability `create`
DELETE /lumi/v1/tasks/{id}          → capability `delete`
GET    /lumi/v1/users               → capability `users`: { users: [{ id, name, email? }] }
GET    /lumi/v1/projects            → capability `projects` (oluşturmada proje seçimi için)
```

Discovery yanıtı:

```json
{
  "protocol": "lumi-tasks",
  "version": 1,
  "name": "Acme backlog",
  "me": { "id": "u_1", "name": "Berkay" },
  "capabilities": ["create", "delete", "users", "projects", "lumiMetadata"],
  "fields": {
    "body": "rw", "project": "rw", "priority": "rw", "labels": "r",
    "assignee": "rw", "dueDate": "rw", "url": "r"
  }
}
```

- `me` opsiyoneldir: token'ın sahibi olan kullanıcı. Varsa atama seçicisinde `You` olarak en üstte durur ve `Assigned to me` filtresi açılır.

- **Minimum uyumlu sunucu** = discovery + liste + tekil okuma + `PATCH status`. Bu kadarı Board'u çalıştırır.
- Hata zarfı: `{ "error": { "code": "not_found", "message": "..." } }`. Kodlar: `unauthorized` (401), `not_found` (404), `validation_failed` (422), `conflict` (409), `rate_limited` (429 + `Retry-After`).
- **Sunucu tanımadığı alanı yok sayar** (MUST) — Lumi ileride alan eklerse eski sunucular kırılmaz.
- Çakışma (opsiyonel): `PATCH`'e `If-Unmodified-Since: <updatedAt>`; destekleyen sunucu bayat yazıma 409 döner.
- Silinen task'ler: v1'de artımlı senkron yok, liste periyodik olarak **tamamen** çekilir (sayfalamayla). Artımlı senkron (`updatedSince` + silinme kaydı) v2 capability'si.
- Güvenlik: token sunucu kurulumunda üretilir (≥ 32 bayt rastgele), sunucuda env değişkeninde (`LUMI_TASKS_TOKEN`) durur, sabit zamanlı karşılaştırılır. Lumi `https` dışındaki adresi yalnız loopback'te (`localhost`, `127.0.0.1`) kabul eder.

## "Kullanıcıda X yoksa" — Lumi'nin davranış kuralları

Tek ilke: **UI, kaynağın beyan ettiği kadardır.** Desteklenmeyen şey boş ya da bozuk görünmez, hiç görünmez.

| Durum | Lumi ne yapar |
|---|---|
| Opsiyonel alan discovery'de yok (ör. `priority`) | O alanın chip'i, filtresi, sıralaması ve düzenleme kontrolü gizlenir. |
| Alan `r` (salt okunur) | Gösterilir, düzenleme kontrolü kapalıdır. Lumi `PATCH`'e yalnız `rw` alanları koyar. |
| Alan beyan edilmiş ama task'te boş | Kartta yer kaplamaz; detayda gizlenir. |
| Yanıtta beyan dışı/bilinmeyen alan | Yok sayılır. |
| `create` yok | `New Task` butonu yok. |
| `delete` yok | Sil seçeneği yok. |
| `assignee` `rw` ama `users` yok | Seçicide yalnız `You` (`me` varsa) ve `Unassigned` bulunur; `me` de yoksa atama salt okunurdur. |
| `users` var, `assignee` `r` | Liste yalnız filtrede kullanılır; atama kontrolü kapalıdır. |
| `projects` yok | Oluşturmada proje alanı serbest metin `key`'dir (ya da gizli, alan da yoksa). |
| `lumiMetadata` yok | Ajan ↔ task bağlantısı **yerelde** tutulur (`ui-state` additive `taskLinks`); yalnız o Mac'te görünür. |
| Zorunlu alan eksik / `status` dört değerden biri değil | Task listeden atılmaz: `Needs attention` rozetiyle Todo kolonunda gösterilir, durum değiştirmek sunucuya geçerli değeri yazar. Verify bunu hata olarak raporlar. |
| `version` > 1 (major) | Kaynak bağlanmaz: "This server speaks lumi-tasks v2; update Lumi." |
| 401 | Kaynak `Reconnect` durumuna düşer (token yeniden istenir); veri silinmez. |
| Ağ hatası / sunucu uyuyor (Heroku free dyno) | Son başarılı liste yerel cache'ten (`~/.lumi/tasks/<sourceID>.json`) gösterilir + `Offline · updated 5 min ago` şeridi. Yazımlar kuyruğa alınmaz: iyimser güncelleme geri alınır + toast. |
| 404 on PATCH | Task listeden düşer + toast. |
| 409 | Sunucudaki güncel hâl çekilir, kullanıcıya `Task changed on server` denir. |

Gelecek adapter'lar aynı tabloya oturur: ör. GitHub'da `in_review` doğal olarak yoktur — adapter bunu etiket/Project kolonu eşlemesiyle sağlar ya da sağlayamıyorsa capability'de söyler; UI aynı kuralı uygular.

## Birleşik yazım (kullanıcı kararı 8)

- Düzenleme ekranda **anında** görünür (iyimser); sunucuya gidiş **task başına 2 sn** ertelenir. O sürede aynı task'e yapılan her düzenleme (durum, öncelik, atama, başlık) tek yamada birleşir (`TaskPatch.merging` — sonraki dolu alan kazanır) ve **tek `PATCH`** olarak gider. Farklı task'ler birbirini beklemez.
- **Protokol değişmez:** toplu uç (`PATCH /tasks` dizi) yok. Gerekçe: her ajanın doğru yazması gereken yüzeyi büyütür, birleşmenin asıl kazancı (aynı task'e art arda düzenleme) istemci tarafında zaten alınır; farklı task'lere yapılan düzenlemeler zaten seyrek.
- **Kaybolmama:** route'tan çıkınca (`onDisappear`) ve uygulama kapanırken (`TasksFeatureAssembly.shutdown`) bekleyenler hemen gönderilir (`flushAll`). Başlıkta bekleyen yazım varken `Saving…`.
- **Tutarlılık:** bekleyen ya da uçuştaki yazımın task'i tazelemeyle ezilmez; gönderim sürerken yeni düzenleme gelirse sunucunun cevabı yalnız yeni taban olur. Sunucu reddederse task **son onaylı hâline** döner, hata kaydı + toast.
- **Ertelenmeyenler:** silme, oluşturma ve ajanın teslimi (In Review'a taşıma hemen gider).

## Görseller (kullanıcı kararı 9)

- **Kart hiçbir şey indirmez**, yalnız `📷 3` sayısını gösterir.
- Detay açılınca şerit görünür hücrelerin önizlemesini ister: önce `thumbnailUrl`, yoksa asıl görsel. Görsel **disk önbelleğine** iner (`~/.lumi/tasks/images/<sha256(url)>.<ext>`, 200 MB'ı aşınca en eski silinir, aynı adrese eşzamanlı istekler tek indirmeye bağlanır) ve **ImageIO ile hücre boyutuna küçültülerek** çözülür (büyük görsel asla tam belleğe alınmaz); küçük önizlemeler oturumluk bellek önbelleğindedir.
- Tıklanınca tam görsel (önbellekten) **Lumi viewer'ında** (FileViewer görsel önizlemesi) açılır.
- Yetki (Faz 2): `Authorization` başlığı **yalnız kaynağın kendi sunucusundaki** adreslere eklenir; S3/CDN gibi başka hostlara token gitmez (oralar için imzalı URL beklenir).
- Görsel yüklenemezse hücrede uyarı ikonu, hata kaydına `Load image` satırı.

## Hatalar (kullanıcı kararı 10)

- HTTP adapter'ı her başarısız isteği **`TaskRequestFailure`** olarak fırlatır: işlem (`Update task`…), istek satırı (`PATCH /lumi/v1/tasks/DEMO-1`), HTTP durumu, sunucunun hata zarfındaki `code` + `message`, yanıt gövdesinin ilk 600 karakteri (zarf bozuksa — ör. Heroku'nun HTML hata sayfası — tek ipucu budur), task kimliği, zaman. **Token asla girmez.**
- **Toast** kısa özettir: `Couldn't save DEMO-1 — HTTP 422 · validation_failed — status must be one of …`.
- **Hata kaydı** (`Request Errors` sheet'i; başlıkta kırmızı `⚠ 3` butonu ve bandın `Details…`'ı açar): solda istekler (aynı hata art arda tekrar ederse tek satırda `×N`), sağda tüm ayrıntı + **"What Lumi expected"** (protokolün o durumda beklediği, hata türüne göre) + yanıt gövdesi + **`Copy for Agent`** (sunucuyu yazan ajana yapıştırılacak hazır rapor). Kayıt oturumluk, en çok 50 satır.
- Bant durumları ayrıldı: ulaşılamıyor → `offline` (sarı); ulaşıldı ama 5xx/bozuk yanıt → `failing` (kırmızı, "answered with an error"); 401 → `reconnect`; sürüm → `unsupported`. Hepsinde son liste ekranda kalır.
- Demo kaynağın `Simulate Errors` menüsü (422 / 500 / 401 / offline) bu yüzeyleri gerçek ayrıntı düzeyinde gösterir.

## Task → ajan (kullanıcı kararı 7)

**Task bir prompt'tur.** Kartta hover'da `▶`, detayda `Start with Claude…` → Start sheet'i:

- **Project:** task'in `project`'i Lumi projesiyle eşleşirse seçili gelir (Faz 3'te git origin'i de), yoksa kullanıcı seçer.
- **Where:** git projesinde varsayılan **task'e özel yeni workspace** (`task/<id>-<slug>` dalı, karar 48–50 workspace'leri) — paralel task'ler birbirine dokunmaz; ya da mevcut bir checkout.
- **Model:** Default / Fable / Opus / Sonnet / Haiku (karar 121 takma adları).
- **Prompt:** düzenlenebilir; şablon task başlığı + açıklaması + teslim talimatı.
- `Move to In Progress` (varsayılan açık), `Assign to me` (atanabiliyorsa ve bana atanmamışsa).

**Ajan normal, görünür bir terminaldir — gizli değil.** Gerekçe: Claude izin ister, soru sorar; gizli terminalde ajan sessizce takılır. Görünür terminal Projects'te checkout altında, ızgarada kart, telefonda chat olarak durur; resume (karar 90) ve dikkat vurgusu (karar 77) bedavaya gelir. Orchestrator'ın gizli terminali (karar 123) bilinçli bir istisnadır, örnek değildir. Terminal kartının başlığında task çipi (`DEMO-1`), task kartında ajanın durum çipi (`✦ Claude Opus · Working` / `Needs input` / `Waiting` / `Submitted for review`) ve `Open Terminal` vardır.

**Kendini In Review'a taşıma:** ajan, Lumi'nin loopback MCP sunucusundaki (karar 114'ün `LumiMCPServer`'ı) **`submit_for_review(summary)`** aracını çağırır. Araç yalnız o terminale verilen, o task'e kapsamlı bir token'la çalışır (`--mcp-config` ile yalnız bu terminale eklenir; kullanıcının diğer MCP'leri korunur). Lumi task'i hemen In Review'a taşır, özeti kartta gösterir ve `lumiMetadata` destekleniyorsa sunucuya yazar. Prompt şablonu aracı ve "Done'a sen taşıma" kuralını söyler.

**Yedekler:** ajan teslim etmeden turn'ünü bitirirse (hook `Stop`, karar 45) çip `Waiting` olur ve detayda `Move to In Review` butonu çıkar; terminal kapanırsa `Exited`. **Done'a yalnız insan taşır.** Ajan → In Review taşıması sunucuda başarısız olursa hata kaydı + aynı buton.

**Faz 3 işi:** gerçek `TaskAgentRunning` (workspace oluşturma → `terminals.spawn(command: "claude --model … --mcp-config …", environment: LUMI_TASK_*)` → prompt'un ilk mesaj olarak verilmesi → hook durumlarının (`AgentActivityState`) `TaskAgentState`'e çevrilmesi), MCP aracı + task kapsamlı token, bağlantının kalıcılığı (`ui-state` additive `taskLinks` + `lumi` metadata), terminal kartında task çipi, `Open Terminal`. Şimdilik `PreviewTaskAgentRunner` akışı taklit eder (UI'da `Preview` rozeti).

## Proje eşleşmesi

Task'in `project`'i Lumi'nin Projects listesine şu sırayla bağlanır:

1. `project.repo` ↔ Lumi projesinin git `origin` adresi (normalize: `git@`/`https`, `.git` soneki; origin karar 84'te zaten cache'li).
2. `project.key`/`name` ↔ proje klasör adı (büyük-küçük harf duyarsız, tek aday varsa).
3. Kullanıcının elle eşlemesi: kartta `Link to Project…` → `config.json` additive `taskProjectLinks: { sourceID: { projectKey: path } }`.

Eşleşmeyen task da gösterilir; yalnız `Start` eşleme ister. Kartlarda eşleşen projenin rengi (karar 120) kullanılır.

## UI planı

**Sol panel:** mevcut `Tasks` satırı (karar 55) aynen kalır.

**Boş durum (kaynak yok):** kısa açıklama + `Connect Task Source`.

**Bağlama sayfası (sheet, 3 adım):**
1. Adapter seçimi — `Custom (Lumi Tasks API)` etkin; `GitHub Issues` / `Linear` `Coming soon` olarak soluk.
2. `Copy Setup Prompt` + "Paste this into an agent working in your server's project" açıklaması.
3. `URL` + `Token` alanları → `Verify & Connect`: kontrol listesi canlı dolar (✓ discovery, ✓ auth, ✓ list, ✓ status update — test task'inde, ✓ create/delete varsa…), hata olursa `Copy Report for Agent`.

**Ana görünüm (route):**
- Route'un kendi başlık şeridi (top bar'da yalnız route adı kalır): kaynak seçici (birden çok kaynak varsa; `All Sources` birleşik görünüm), arama, proje filtresi, `Board | List`, `New Task` (capability'ye bağlı), yenile.
- **Board:** Todo / In Progress / In Review / Done kolonları; kart kolonlar arası sürüklenince `PATCH status` (iyimser). Done kolonu son 20 ile sınırlı, `Show all`.
- **Kart:** başlık, proje rengi noktası + adı, öncelik ikonu, etiketler (en çok 2 + `+N`), atanan baş harfleri, bağlı ajan varsa `AgentActivityIcon` (çalışıyor / karar bekliyor / bitti — karar 81 dili).
- **List:** aynı veri tablo hâlinde, kolon başlığıyla sıralanır.
- **Detay** (sağdan açılan çekmece): başlık, durum menüsü, atama seçicisi (`You` en üstte), öncelik menüsü, markdown gövde, metadata, eylemler: `Start in Lumi` (Faz 3), `Open in Browser` (url varsa), `Copy as Prompt`, `Delete` (varsa).

**Start with Claude:** bkz. "Task → ajan" (ajan `submit_for_review` ile kendini In Review'a taşır; teslim etmeden durursa `Move to In Review` butonu; Done her zaman insanda).

**Tazeleme (kullanıcı kararı 6):** route görünür olduğu sürece yaşayan tek bir döngü — açılışta hemen istek, sonra 15 sn'de bir; route'tan çıkılınca döngü iptal olur ve hiçbir istek atılmaz (SwiftUI `.task` ömrü). Kendi düzenlemesi yoldayken gelen liste o task'i ezmez (bekleyen yazımlar korunur). Sol paneldeki satırda sayı rozeti yoktur — kapalıyken veri tazelenmediği için bayat sayı gösterilmez.

**Settings ▸ Tasks:** kaynak listesi (ad değiştir, token yenile, Verify, kaldır), Start prompt şablonu, "Start'ta In Progress'e taşı" anahtarı.

Mobil ve orchestrator v1 kapsamı dışında; mimari onları engellemez (Faz 4).

## Lumi tarafı mimari

- **LumiKit:** `TaskItem`, `TaskStatus`, `TaskPriority`, `TaskUser`, `TaskSourceID`, `TaskSource` (`id, name, kind, baseURL`), `TaskSourceInfo` (capabilities + alan erişimi + `me`), `TaskProviding` protokolü (`discover / listTasks / update / create / delete / listUsers / listProjects`), `TaskProviderMaking` (kaynak → adapter), `TaskProviderKind` (`.demo`, `.custom`; ileride `.github`, `.linear`), adapter'dan bağımsız `TaskSourceVerifier`, saf `TaskBoard` (kolonlama/filtre) ve `TaskUserOrdering` (`You` en üstte), ileride `TaskProjectMatcher`.
- **LumiServices:** `LumiTasksHTTPProvider` (custom adapter), yeni `HTTPTransporting` dikişi (URLSession sarmalayıcı; fake'i `LumiTestSupport`'a), `TaskProtocolVerifier`, `TaskSourceCodec` (`config.json` additive `taskSources` — **token config'e yazılmaz**, `KeychainAccessing` ile `com.lumi.tasks` / `<sourceID>`), `TaskCache` (dosya). `LiveServiceRegistry`/`FakeServiceRegistry`'ye birer satır.
- **LumiState:** `TasksStore` — kaynak başına durum (`loading / loaded / offline(stale) / reconnect / unsupported`), birleşik task listesi, filtreler, iyimser güncelleme + geri alma, `AutoRefreshing` (karar 75 deseni).
- **LumiUI:** `TasksRouteView` yer tutucusu yerine `TasksBoardView`, `TaskCardView`, `TaskDetailDrawer`, `ConnectTaskSourceSheet`, `TasksSettingsTab`. Tüm ölçüler token'dan (karar 61).
- **LumiAppCore:** `TasksFeatureAssembly`'nin boş `build`/`start`'ı dolar; toolbar öğeleri ve overlay'ler descriptor'larla kaydedilir — kabuk dosyalarına dokunulmaz (karar 33).

## Fazlar (her biri derlenir, testler yeşil, faz sonu onay)

1. ✅ **UI, sahte veriyle.** LumiKit modeli + `TasksStore` + tüm görünümler + `DemoTaskProvider` (bellek içi, gecikme simülasyonlu). Bağlama sheet'inde `Demo data` adapter'ı gerçekten bağlanır ve Verify kontrol listesi ona karşı koşar; `Custom` akışı (URL + token) görünür ama adapter'ı Faz 2'ye kadar "not available yet" hatası döner. Demo kaynağın menüsünde capability/alan anahtarları vardır ki "X yoksa" kuralları gözle denensin. Kaynaklar bu fazda kalıcı değildir (yeniden başlatınca gider). → **Gözden geçirme, görsel onay.**
1b. ✅ **İkinci tur (kullanıcı kararları 7–10), sahte veriyle:** birleşik yazım (`TasksStore+Writes`), hata kaydı + `Request Errors` sheet'i + `failing` bandı + demo hata taklidi, `images` alanı + disk önbelleği (`TaskImageCache`) + küçültülmüş önizleme şeridi + viewer'da açma, Start sheet'i + ajan çipi/bölümü + `PreviewTaskAgentRunner`.
2. ✅ **Protokol.** `docs/design/06-tasks-protocol.md` (OpenAPI dosyası bilinçli olarak yazılmadı — kanonik metin setup prompt'tur, bkz. design/06 §1), setup prompt metni, HTTP adapter, Keychain, codec, cache, gerçek Verify. Doğrulama: setup prompt'u boş bir Node projesinde gerçekten bir ajana koşturup çıkan sunucuyu Lumi'ye bağlamak (dogfood). Setup prompt'ta Heroku/Railway uyarısı: dosya sistemi geçicidir, kalıcılık için Postgres vb. kullanılmalı.
3. **Gerçek ajan.** "Task → ajan" bölümündeki Faz 3 işi: gerçek koşucu, `submit_for_review` MCP aracı, git origin'li proje eşleşmesi, bağlantı kalıcılığı, terminal kartında task çipi.
4. **Genişleme (ayrı onay).** Orchestrator MCP araçları (`list_tasks`, `update_task`), telefonda Tasks, GitHub/Linear adapter'ları, artımlı senkron.

## Riskler

1. **Ajanların farklı implementasyonları** — Verify + "bilinmeyeni yok say" kuralı + minimum zorunlu yüzey. Verify raporu ajana yapıştırılacak biçimde yazılır.
2. **Token sızıntısı** — token yalnız Keychain'de; log'lara, cache'e, hata raporuna yazılmaz (rapor `Bearer ***`).
3. **Uyuyan sunucular** (Heroku eco dyno ilk istekte ~10 sn) — istek zaman aşımı 20 sn, cache'ten gösterim; Verify yavaşlığı uyarı olarak söyler.
4. **Kalıcı olmayan sunucu deposu** — setup prompt'ta açık uyarı; Verify bunu algılayamaz.
5. **Verify'ın yan etkisi** — test task'i `[Lumi verify]` başlığıyla oluşturulup silinir; `create` yoksa durum testi kullanıcıya sorularak mevcut bir task üzerinde yapılır ve eski hâline döndürülür.
