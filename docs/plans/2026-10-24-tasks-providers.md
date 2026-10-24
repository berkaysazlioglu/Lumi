# Tasks — kendi sunucunu bağla (Lumi Tasks Protocol + adapter'lar) (plan)

Durum: **plan, onay bekliyor** (2026-10-24). Onaylanınca `docs/decisions.md`'ye karar olarak girer (karar 55'in Tasks yer tutucusunu değiştirir), protokol `docs/design/06-tasks-protocol.md` olarak bağlayıcı tasarım kaydına geçer.

Kullanıcı isteği: "Tasks sekmesini canlandırmak istiyorum … herkes kendi sisteminde kullanabilsin … user tasks sekmesindeki özel prompt'u alıp kendi heroku projesindeki bir agent'a yapıştırınca agent öyle bir sistem inşa edecek ki user o linki app'e yapıştırınca lumi task'leri çekebilecek, done'a atabilecek … token sistemi de olur … başka user railway'i bağlar."

## Kullanıcı kararları (2026-10-24)

1. Durum modeli **sabit dört durum**: `todo` / `in_progress` / `in_review` / `done`.
2. Lumi içeride **adapter** mimarisiyle kurulur; ilk (ve v1'deki tek) adapter **Custom — Lumi Tasks API**. GitHub Issues / Linear / Jira sonraki adapter'lardır.
3. Implementasyondan önce plan; **önce UI** (sahte veriyle), onaydan sonra protokol.
4. **Yorum yok** — `comments` capability'si ve uçları plandan çıktı.
5. **Atama:** kaynak `users` capability'sini beyan ederse kullanıcı listesi gelir ve task herhangi birine atanabilir; seçicide **`You` en üsttedir** (token'ın sahibi — discovery'deki `me`).
6. **Tazeleme:** Tasks route'u kapalıyken istek atılmaz; route açıldığı an güncel hâl çekilir ve açık kaldığı sürece periyodik olarak güncel tutulur.

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

**Start in Lumi** (Faz 3): checkout seçimi (eşleşen projenin mevcut checkout'ları ya da karar 58 dialoguyla yeni workspace — dal adı önerisi `task/<id>-<slug>`), ajan (New Claude modelleri dahil — karar 121), prompt şablonu ön izlemesi → terminal açılır, task `in_progress`'e çekilir (ayar), `lumi` metadata'sı yazılır. Ajanın turn'ü bitince kartta `waiting` görünür; `Move to In Review` önerisi kartta tek tıkla — **otomatik taşıma yok** (ajan bitti ≠ iş bitti).

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

1. **UI, sahte veriyle.** LumiKit modeli + `TasksStore` + tüm görünümler + `DemoTaskProvider` (bellek içi, gecikme simülasyonlu). Bağlama sheet'inde `Demo data` adapter'ı gerçekten bağlanır ve Verify kontrol listesi ona karşı koşar; `Custom` akışı (URL + token) görünür ama adapter'ı Faz 2'ye kadar "not available yet" hatası döner. Demo kaynağın menüsünde capability/alan anahtarları vardır ki "X yoksa" kuralları gözle denensin. Kaynaklar bu fazda kalıcı değildir (yeniden başlatınca gider). → **Gözden geçirme, görsel onay.**
2. **Protokol.** `docs/design/06-tasks-protocol.md` (+ OpenAPI dosyası), setup prompt metni, HTTP adapter, Keychain, codec, cache, gerçek Verify. Doğrulama: setup prompt'u boş bir Node projesinde gerçekten bir ajana koşturup çıkan sunucuyu Lumi'ye bağlamak (dogfood). Setup prompt'ta Heroku/Railway uyarısı: dosya sistemi geçicidir, kalıcılık için Postgres vb. kullanılmalı.
3. **Lumi entegrasyonu.** Proje eşleşmesi, `Start in Lumi`, ajan ↔ task bağlantısı (`lumi` metadata ya da yerel `taskLinks`), kartta ajan durumu, `Move to In Review` önerisi.
4. **Genişleme (ayrı onay).** Orchestrator MCP araçları (`list_tasks`, `update_task`), telefonda Tasks, GitHub/Linear adapter'ları, artımlı senkron.

## Riskler

1. **Ajanların farklı implementasyonları** — Verify + "bilinmeyeni yok say" kuralı + minimum zorunlu yüzey. Verify raporu ajana yapıştırılacak biçimde yazılır.
2. **Token sızıntısı** — token yalnız Keychain'de; log'lara, cache'e, hata raporuna yazılmaz (rapor `Bearer ***`).
3. **Uyuyan sunucular** (Heroku eco dyno ilk istekte ~10 sn) — istek zaman aşımı 20 sn, cache'ten gösterim; Verify yavaşlığı uyarı olarak söyler.
4. **Kalıcı olmayan sunucu deposu** — setup prompt'ta açık uyarı; Verify bunu algılayamaz.
5. **Verify'ın yan etkisi** — test task'i `[Lumi verify]` başlığıyla oluşturulup silinir; `create` yoksa durum testi kullanıcıya sorularak mevcut bir task üzerinde yapılır ve eski hâline döndürülür.
