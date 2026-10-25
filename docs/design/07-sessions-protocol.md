# Lumi Native — Agent History paylaşımı: Lumi Sessions Protocol v1

> Karar 138 (2026-10-25). Agent History oturumları (Claude/Codex chat'leri) ekip arkadaşlarıyla **kullanıcının kendi sunucusu** üzerinden paylaşılır. Tasks'te olduğu gibi (karar 137, [`06-tasks-protocol.md`](06-tasks-protocol.md)) Lumi sunucu barındırmaz: açık, sürümlü bir HTTP protokolü tanımlar; kullanıcı setup prompt'unu kendi sunucu projesindeki ajana verir.

## 1. Kanonik metin

Protokolün **tek kaynağı** `LumiKit/SessionShare/SessionShareSetupPrompt.swift`'teki metindir. `SessionShareSetupPromptTests` her ucun, alanın ve hata kodunun metinde geçtiğini kilitler.

| Uç | Ne |
|---|---|
| `GET /lumi/sessions/v1` | discovery: `protocol: "lumi-sessions"`, `version: 1`, **`me` zorunlu**, `name?`, `maxUploadBytes?` |
| `GET /lumi/sessions/v1/sessions?cursor&limit` | `{ sessions: [özet], nextCursor }` — paket YOK |
| `GET /lumi/sessions/v1/sessions/{id}` | özet + `archive` (yüklenen paket aynen) |
| `POST /lumi/sessions/v1/sessions` | `{ title, project, provider, archive }` → 201 özet |
| `DELETE /lumi/sessions/v1/sessions/{id}` | yalnız yükleyen; başkası → `403 forbidden` |

Özet: `id`, `title`, `project` (yükleyenin verdiği **düz ad** — yol, dal, repo adresi değil), `provider?`, `uploader {id,name}`, `uploadedAt`, `size?`. Hata zarfı Tasks'tekiyle aynı; ek kodlar `forbidden` (403) ve `payload_too_large` (413).

- **Önek `/lumi/sessions/v1`:** Tasks'in `/lumi/v1`'iyle aynı sunucuda çakışmadan yaşar; bağlantılar yine ayrıdır (adres + token ayrı kaydedilir).
- **Kişi başına token (kullanıcı kararı):** sunucu `lumi_session_users` tablosunda token'ın yalnız SHA-256 özetini tutar; `add-user` komutu token'ı bir kez yazdırır. Yükleyen gövdeden değil token'dan gelir; silme yetkisini sunucu uygular. Lumi de silme düğmesini yalnız `uploader.id == me.id` satırlarında gösterir ve store başkasınınkini hiç göndermez.
- **Paket:** karar 52'nin `.lumisession.json`'ı (kişisel kayıtlar `AgentSessionSanitizer` ile ayıklanmış). Sunucu için opaktır; 64 MB'a kadar. İstemci 64 MB'ı yeniden ayrıştırmamak için gövdeyi küçük alanlar + ham `archive` baytları olarak birleştirir.

## 2. Katmanlar

```
LumiKit      SharedSession · SharedSessionUploader · SessionServerInfo · SessionServer (config kaydı)
             SessionSharing · SessionSharingMaking · SessionServerCredentialStoring
             SessionShareFailure (istek, HTTP durumu, sunucu zarfı, yanıt başı, ipucu, agentReport)
             SessionShareSetupPrompt · AgentSessionTransferring.exportArchive/importArchive
LumiServices LumiSessionsHTTPClient (+ LiveSessionSharingFactory, KeychainSessionServerCredentialStore)
             Config/SessionServerCodec · Tasks/HTTPNetworkMessage (iki istemcinin ortak ağ hata dili)
LumiState    SessionShareStore (AgentHistoryStore'un import/export yolunu kullanır)
LumiUI       SessionShareBrowserOverlay (+ ConnectForm) · SessionShareBrowserContent · SessionShareExportOverlay
LumiAppCore  RepoFeatureAssembly store'u kurar, iki overlay descriptor'ını kaydeder; ShellContext.sessionShare
```

Overlay durumları `DialogRouter`'da değil store'dadır (`isBrowserPresented`, `connectForm`, `exportDraft`) — Tasks sheet'leriyle aynı kalıp. `ShellContext.sessionShare` opsiyoneldir: önizleme/test bağlamında nil ve sunucu seçenekleri görünmez.

## 3. Akışlar

- **Import:** Agent History'nin Import düğmesi doğrudan dosya seçici açmaz; popover `Import from File…` (karar 52) / `Import from Server…`. İkincisi ortada popup açar: bağlı değilse kurulum (Copy Setup Prompt → adres → kişisel token → Connect = discovery + liste), bağlıysa solda `All` + yükleyenler (`me` en üstte, `(You)`), sağda oturumlar. Satır seçilip `Import…` (ya da çift tık) → Projects'teki projelerden seçim (sağ panelin projesi işaretli) → paket indirilir → karar 52'nin `importArchive`'ı hedef projeye kurar → Agent History yenilenir.
- **Tazeleme (kullanıcı kuralı):** istek yalnız popup açılırken (son başarılı liste 5 dakikadan eskiyse), popup'taki Refresh'te ve kullanıcı eylemlerinde (bağlan, yükle, indir, sil) gider. Arka planda hiç istek yok; açılışta yalnız config kaydı + Keychain okunur.
- **Export:** satır menüsünde `Export as File…` (karar 52) ve `Export to Server…`. İkincisi onay penceresi açar: başlık (varsayılan oturum başlığı) ve proje adı (varsayılan Lumi'deki projenin adı — checkout değil proje) düzenlenebilir, yükleyen satırı ve ayıklama notu görünür. Bağlantı yoksa `Set Up Server…` popup'a geçer. `maxUploadBytes` bildirilmişse sınırı aşan paket gönderilmeden reddedilir.
- **Hatalar:** bağlanma/yükleme formunda ve liste üstünde `SessionShareFailureView` — özet, protokolün beklentisi, `Copy Report for Agent` (token hiçbir metne girmez).

## 4. Kalıcılık

- `config.json` → additive `sessionServer: { id, name, baseURL }`; bağlantı yoksa `null` yazılır (merge eski kaydı bırakmasın — karar 56'nın `activeClaudeAccountId` kalıbı). Adres `TaskEndpoint.normalize` kuralına tabidir (https; http yalnız loopback).
- Keychain → servis `com.lumi.sessions`, hesap sunucu kaydının kimliği. `Disconnect` ikisini de siler; `Reconnect…` kimliği koruyup token/adresi yeniler.

## 5. Dogfood (2026-10-25)

Setup prompt'u bir Express + `node:sqlite` projesinde `claude -p --model sonnet`'e aynen verildi (yalnız "My name is Berkay" eklendi — prompt ilk kullanıcının adını sordurur, `-p`'de soru sorulamaz). Ajan router'ı global `express.json()`'dan önce bağladı (100 KB varsayılan limit 64 MB yüklemeyi keserdi), token'ları SHA-256 özetiyle sakladı, paketi gzip BLOB olarak tuttu, `lumi:add-user` / `list-users` / `revoke-user` komutlarını ve kendi testlerini (4/4) yazdı; mevcut proje yerel SQLite kullandığı için kalıcı depolama uyarısını kendisi yaptı. Lumi'nin gerçek bileşenleriyle uçtan uca (`LumiSessionsLiveServerTests`, `LUMI_SESSIONS_E2E_URL` / `_TOKEN` / `_TOKEN2`): Agent History'deki oturum → `exportArchive` → yükleme (yükleyen token'dan) → ikinci kullanıcı listeler, silemez (403) → indirir → başka makine/başka projeye `importArchive` (cwd yeniden yazılır, kişisel kayıt yok, alt ajan dahil, Agent History'de listelenir) → yükleyen siler → 404; yanlış token 401 zarfı. 20 MB paket yüklendi, indi, silindi.

## 6. Bilinen sınırlar

- Tek sunucu bağlantısı (Tasks'teki gibi çoklu kaynak yok).
- Popup'ta arama ve proje filtresi yok; sol panel yalnız yükleyene göre süzer.
