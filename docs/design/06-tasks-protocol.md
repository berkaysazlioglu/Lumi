# Lumi Native — Tasks: Lumi Tasks Protocol v1 ve adapter mimarisi

> Karar 137 (2026-10-24). Tasks route'u kullanıcının **kendi sunucusundaki** task listesini gösterir, düzenler ve task'i bir ajana verir. Lumi sunucu barındırmaz: açık, sürümlü bir HTTP protokolü tanımlar; kullanıcı bunu setup prompt'u yapıştırdığı kendi ajanına kendi projesinde (Heroku, Railway, VPS…) kurdurur. Plan ve kullanıcı kararları: [`docs/plans/2026-10-24-tasks-providers.md`](../plans/2026-10-24-tasks-providers.md).

## 1. Kanonik metin

Protokolün **tek kaynağı** `LumiKit/Tasks/TaskSetupPrompt.swift`'teki metindir — kullanıcının kopyaladığı setup prompt'un kendisi. Uçlar, task nesnesi, hata zarfı, kimlik doğrulama ve "bitince yazdır" adımı oradadır. Ayrı bir OpenAPI dosyası **bilinçli olarak yok** (plan taslağında vardı): ajanlar düz metin şartnameyi iyi uyguluyor, iki kaynak ise zamanla ayrışır. `TaskSetupPromptTests` her ucun, durumun, önceliğin, yeteneğin ve alanın metinde geçtiğini kilitler; protokole bir şey eklenince test kırılır.

Özet:

| Uç | Zorunlu mu |
|---|---|
| `GET /lumi/v1` — discovery: `protocol`, `version`, `name?`, `me?`, `capabilities`, `fields` | ✓ |
| `GET /lumi/v1/tasks?status&project&cursor&limit&since` → `{ tasks, nextCursor, syncToken?, ids? }` | ✓ (`since` önerilir) |
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
            TaskAgent* (Start sheet modeli, TaskAgentRunning dikişi, TaskAgentTools) · TaskEndpoint
LumiServices LumiTasksHTTPProvider + LumiTasksWire (custom) · DemoTaskProvider (demo)
            LiveTaskProviderFactory · URLSessionTransport · KeychainTaskCredentialStore
            TaskImageCache · TaskAgentMCPServer · Config/TaskSourceCodec + TaskLinkCodec
LumiState   TasksStore (+Writes, +Failures, +Agents, +Sheets, +Sources) · LiveTaskAgentRunner
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
- **Artımlı senkron (2026-10-25):** liste cevabı opak `syncToken` taşıyabilir; Lumi sonraki tazelemede `since=<syncToken>` gönderir. Delta cevabı yalnız değişen task'leri (`tasks`) ve kaynaktaki TÜM kimlikleri (`ids`) taşır — silinen kimlikten çıkarılır, sunucu mezar taşı tutmaz. `ids`'siz cevap tam listedir; `since`'i yok sayan eski sunucu bu yüzden değişmeden çalışır (`TaskListing`, `TasksStore.applyingDelta`). Delta yereldeki bilinmeyen bir kimliği gösterirse aynı tazelemede tam liste istenir; tazeleme bir sunucu kopyasını yerel yazım yüzünden attıysa jeton ilerlemez (değişiklik sonraki deltada yeniden gelir). Jeton discovery ve yeniden bağlanmada sıfırlanır, bellekte tutulur (açılışta ilk istek tam liste).
- **Görsel kimliği:** pre-signed adresler (S3/GCS/CloudFront/Azure SAS) her listede yeniden imzalanır; önbellek ve görünüm kimliği bilinen imza parametreleri atılmış adrestir (`TaskImageIdentity`) — aynı görsel bir kez iner, imza tazelenince spinner çıkmaz. Bellekteki küçük resim hücrenin ilk karesinde çizilir.

## 7. Dogfood (2026-10-24)

Setup prompt'u bir Express + `node:sqlite` projesinde `claude -p --model sonnet`'e verildi. Ajan protokolü projenin mevcut veritabanıyla kurdu (sabit zamanlı token karşılaştırması, zarf, keyset sayfalama, `updatedAt` artışı); Lumi'nin gerçek adapter'ı + Verify bu sunucuya karşı geçti (`LumiTasksLiveServerTests`, `LUMI_TASKS_E2E_URL`/`LUMI_TASKS_E2E_TOKEN` ile). İlk turda çıkan iki sorun prompt'a işlendi: ajan token'ı üretip yazdırmalı; token tanımlı değilse uygulamanın geri kalanı açılmalı, yalnız `/lumi/v1` `503 not_configured` dönmeli.

## 8. Task → ajan (Faz 3)

```
Start sheet ─▶ TasksStore.start ─▶ LiveTaskAgentRunner
                                    1. yeni workspace? ProjectWorkspaceStore.createWorkspace (task/<id>-<slug>)
                                    2. TaskAgentMCPServer.register → task kapsamlı token + 0600 mcp config
                                    3. ClaudeWorkspaceTrust.markTrusted(checkout)
                                    4. terminals.spawn("claude '<prompt>' --model … --mcp-config '<file>'
                                                         --allowedTools mcp__lumi__get_task,mcp__lumi__submit_for_review")
                                    5. cardBadges[terminal] = "<task id>"
                                    6. terminal durumunu izle (withObservationTracking) → TaskAgentState
ajan ─ submit_for_review(summary) ─▶ MCP ─▶ .submitted ─▶ TasksStore: In Review'a taşı + hemen gönder
```

- **Görünür terminal.** Ajan normal bir claude terminalidir: Projects'te, ızgarada, telefonda görünür; `--session-id` enjeksiyonu (karar 23) korunur, resume (karar 90) çalışır. Kart başlığında task rozeti (`TerminalListStore.cardBadges` — özelliğe bağımsız kanal), task kartında ajan çipi, detayda `Open Terminal` (`ShellContext.focusAgent`).
- **Komut sırası.** Prompt konumsal argüman olarak **önce** gelir: `--mcp-config` ve `--allowedTools` çok değerli seçeneklerdir, arkalarındaki argümanı yutarlar. `--strict-mcp-config` verilmez — kullanıcının kendi MCP'leri ajanda kalır.
- **Sunucu.** `TaskAgentMCPServer` orchestrator'ınkinden ayrıdır (aynı `MCPRequestRouter`, araç listesi parametreli): tek loopback dinleyici, **terminal başına token**; token kayda çözülür, bir ajan başka bir task'i teslim edemez. Araçlar `get_task` (Start anındaki başlık/durum/açıklama) ve `submit_for_review(summary)`; ikisi de `--allowedTools` ile onaysız. Terminal kapanınca kayıt ve dosya düşer.
- **Durum eşlemesi.** working → Working; karar bekliyor → Needs input; turn bitti → Waiting; claude çıktı (provider `nil`) ya da terminal kapandı → Exited. Terminal listede bir kez görünmeden "kapandı" sayılmaz (`spawn` meta'yı `.spawned` olayından önce döner). Teslimden sonra yalnız kapanış çipi değiştirir.
- **Proje eşleşmesi.** `project.repo` ↔ Lumi projesinin git origin'i (`git@host:o/r.git`, `https://host/o/r`, `ssh://git@host:22/o/r.git` aynı sayılır), sonra ad.
- **Kalıcılık.** Oturum kimliği bilinen bağlantılar `ui-state.json`'ın additive `taskLinks` anahtarına yazılır (`TaskLinkCodec`; nil → yazılmaz, bir kez kullanıldıysa boş da yazılır). Açılışta resume edilen terminal oturum kimliğiyle 10 sn'ye kadar beklenip yeniden bağlanır; bulunamayan kayıt düşer. **Yeniden bağlanan ajanın MCP aracı yoktur** (resume komutu `--mcp-config` taşımaz) — detay bunu söyler, teslim `Move to In Review` ile.
- **Doğrulama.** `TaskAgentClaudeLiveTests` (`LUMI_TASKS_AGENT_E2E=1`) gerçek `claude`'u aynı bayraklarla koşturur; ajan `get_task` + `submit_for_review`'u çağırdı (2026-10-25).

## 9. Bilinen sınırlar

- Lumi yeniden açılınca ajan teslim aracını kaybeder (yukarıda).
- Yalnız Claude; Codex ajanı (MCP `config.toml`) sonra.
- `lumiMetadata` henüz sunucuya yazılmıyor — bağlantı yalnız bu Mac'te.
- Settings ▸ Tasks sekmesi yok; kaynak yönetimi kaynak menüsünden (`Reconnect…`, `Disconnect`).
