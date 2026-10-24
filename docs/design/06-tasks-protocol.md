# Lumi Native — Tasks: Lumi Tasks Protocol v1 ve adapter mimarisi

> Karar 137 (2026-10-24). Tasks route'u kullanıcının **kendi sunucusundaki** task listesini gösterir, düzenler ve task'i bir ajana verir. Lumi sunucu barındırmaz: açık, sürümlü bir HTTP protokolü tanımlar; kullanıcı bunu setup prompt'u yapıştırdığı kendi ajanına kendi projesinde (Heroku, Railway, VPS…) kurdurur. Plan ve kullanıcı kararları: [`docs/plans/2026-10-24-tasks-providers.md`](../plans/2026-10-24-tasks-providers.md).

## 1. Kanonik metin

Protokolün **tek kaynağı** `LumiKit/Tasks/TaskSetupPrompt.swift`'teki metindir — kullanıcının kopyaladığı setup prompt'un kendisi. Uçlar, task nesnesi, hata zarfı, kimlik doğrulama ve "bitince yazdır" adımı oradadır. Ayrı bir OpenAPI dosyası **bilinçli olarak yok** (plan taslağında vardı): ajanlar düz metin şartnameyi iyi uyguluyor, iki kaynak ise zamanla ayrışır. `TaskSetupPromptTests` her ucun, durumun, önceliğin, yeteneğin ve alanın metinde geçtiğini kilitler; protokole bir şey eklenince test kırılır.

Özet:

| Uç | Zorunlu mu |
|---|---|
| `GET /lumi/v1` — discovery: `protocol`, `version`, `name?`, `me?`, `capabilities`, `fields` | ✓ |
| `GET /lumi/v1/tasks?status&project&cursor&limit` → `{ tasks, nextCursor }` | ✓ |
| `GET /lumi/v1/tasks/{id}` | ✓ |
| `PATCH /lumi/v1/tasks/{id}` (kısmi; en az `status`) | ✓ |
| `POST /lumi/v1/tasks` | `create` |
| `DELETE /lumi/v1/tasks/{id}` → 204 | `delete` |
| `GET /lumi/v1/users` → `{ users }` | `users` |
| `GET /lumi/v1/projects` → `{ projects }` | `projects` |

Task: zorunlu `id`, `title`, `status` (`todo | in_progress | in_review | done`), `updatedAt`; opsiyonel `createdAt`, `body`, `project {key,name,repo}`, `priority`, `labels`, `assignee {id,name,email}`, `dueDate`, `url`, `images [{url,thumbnailUrl,name,width,height}]`, `lumi` (opak). Hata zarfı `{ "error": { "code", "message" } }`; token `Authorization: Bearer`, sunucuda `LUMI_TASKS_TOKEN`.

## 2. Katmanlar

```
LumiKit     TaskItem/TaskPatch/TaskDraft · TaskSourceInfo (capabilities + fields + me)
            TaskProviding · TaskProviderMaking · TaskCredentialStoring · HTTPTransporting
            TaskSourceVerifier · TaskBoard/TaskFilter · TaskRequestFailure · TaskSetupPrompt
            TaskAgent* (Start sheet modeli, TaskAgentRunning dikişi) · TaskEndpoint
LumiServices LumiTasksHTTPProvider + LumiTasksWire (custom) · DemoTaskProvider (demo)
            LiveTaskProviderFactory · URLSessionTransport · KeychainTaskCredentialStore
            TaskImageCache · PreviewTaskAgentRunner · Config/TaskSourceCodec
LumiState   TasksStore (+Writes, +Failures, +Agents, +Sheets, +Sources)
LumiUI      TasksScreen · TasksHeaderBar · TaskBoardView · TaskListView · TaskDetailPanel
            TaskConnectOverlay · NewTaskOverlay · StartTaskOverlay · TaskFailureLogOverlay
LumiAppCore TasksFeatureAssembly (store'u kurar, route + 4 sheet'i descriptor'la kaydeder)
```

- **Adapter = `TaskProviding`.** UI ve store hangi adapter'la konuştuğunu bilmez. v1'de `custom` (HTTP) ve `demo` (bellek içi) var; GitHub/Linear aynı protokole oturacak, sağlayamadıklarını `TaskSourceInfo`'da beyan edecek.
- **Kabuk dosyalarına dokunulmaz (karar 33).** Store `ShellContext`'e girmez; route ve sheet descriptor'ları onu closure'dan zayıf okur (`build` öncesi kayıt testlerde de güvenli).

## 3. "UI, kaynağın beyan ettiği kadardır"

Görünümler alan/yetenek sorusunu yalnız `TaskSourceInfo`'ya sorar (`canRead`, `canWrite`, `supports`, `canAssign`). Beyan edilmeyen alanın chip'i, filtresi, kolonu, menüsü çizilmez; `r` alan menüsüz durur; `PATCH`'e yalnız `rw` alanlar girer. Bozuk task atılmaz, `needsAttention` ile Todo'da durur. Tam tablo planda.

## 4. Okuma hoşgörülü, hata ayrıntılı

- `LumiTasksWire` sayı kimliği string'e çevirir, bilinmeyen alanı yok sayar, `{ "error": "msg" }` sapmasını da okur, kesirli/kesirsiz ISO 8601 kabul eder.
- `LumiTasksHTTPProvider` her hatayı `TaskRequestFailure` olarak fırlatır: istek satırı, HTTP durumu, sunucu kodu/mesajı, yanıt gövdesinin başı (600 karakter), task kimliği. Ağ hataları insan diliyle (`Nothing is listening at this address`, uyuyan dyno için zaman aşımı notu). 401/403 → `unauthorized`, 404 → `notFound`, 409 → `conflict`, 405/501 → `unsupported`, diğerleri → `invalidResponse`; 429'da `Retry-After` mesaja eklenir.
- Token yalnız `Authorization` başlığında gider; hata kaydına, rapora, config'e girmez. Görsellere yalnız kaynağın kendi origin'inde eklenir (`authorization(for:)`).
- Zaman aşımı 20 sn; sayfalama `limit=200`, en çok 50 sayfa, tekrar eden imleçte durur.

## 5. Kalıcılık

- `config.json` → additive `taskSources: [{ id, name, kind, baseURL? }]` (`TaskSourceCodec`; bilinmeyen tür, tekrarlanan kimlik, geçersiz adres düşer — karar 9). Token **asla** burada değil.
- Keychain → servis `com.lumi.tasks`, hesap kaynak kimliği (`KeychainTaskCredentialStore`, karar 56'nın `SecurityKeychain`'i).
- Açılışta yalnız kayıtlar + token'lar okunur, **ağ isteği atılmaz**; discovery route açılınca. Token yoksa/okunamazsa kaynak `Reconnect` durumunda açılır ve hata kaydına yazılır.
- `Reconnect…` aynı kaynağın token'ını (ve gerekirse adresini) yeniler; kimlik, task'ler, filtreler yerinde kalır.
- Kaynak kaldırılınca config kaydı ve Keychain token'ı silinir.

## 6. Tazeleme ve yazım

- İstek yalnız route görünürken: `TasksScreen`'in `.task`'ı `keepFresh` döngüsünü (hemen + 15 sn'de bir) yaşatır; route'tan çıkınca iptal.
- Düzenleme anında görünür; sunucuya task başına 2 sn ertelenip tek `PATCH`'e birleşerek gider; route'tan çıkışta ve kapanışta `flushAll`. Bekleyen/uçuştaki yazım tazelemeyle ezilmez; ret halinde son onaylı hâle dönülür.

## 7. Dogfood (2026-10-24)

Setup prompt'u bir Express + `node:sqlite` projesinde `claude -p --model sonnet`'e verildi. Ajan protokolü projenin mevcut veritabanıyla kurdu (sabit zamanlı token karşılaştırması, zarf, keyset sayfalama, `updatedAt` artışı); Lumi'nin gerçek adapter'ı + Verify bu sunucuya karşı geçti (`LumiTasksLiveServerTests`, `LUMI_TASKS_E2E_URL`/`LUMI_TASKS_E2E_TOKEN` ile). İlk turda çıkan iki sorun prompt'a işlendi: ajan token'ı üretip yazdırmalı; token tanımlı değilse uygulamanın geri kalanı açılmalı, yalnız `/lumi/v1` `503 not_configured` dönmeli.

## 8. Sonraki faz

Faz 3 — gerçek ajan: `TaskAgentRunning`'in terminal + `submit_for_review` MCP aracıyla yazılması, git origin'li proje eşleşmesi, ajan bağlantısının kalıcılığı, terminal kartında task çipi (plan: "Task → ajan").
