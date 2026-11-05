# 08 — Mac'ten Mac'e Remote (Hub / Controller)

Durum: taslak, 2026-11-05. Kullanıcı isteği: "Build makinesi güncellenecekken masasına gitmeye üşeniyorum." Bir Lumi kendini relay'de **hub** olarak paylaşır. Aynı ağ token'ını kullanan başka bir Lumi (**controller**) o ağdaki tüm hub'ları görür, şifreyle birine girer ve orada telefondaki gibi terminal açar, yazar, okur. Sonraki fazda bir Claude terminali de aynı hub'ları MCP araçlarıyla kullanır.

## Kullanıcı kararları (2026-11-05)

1. **Ağ token'ı.** Hub'lar ve controller'lar relay'e bir **ağ token'ıyla** bağlanır. Aynı token'la bağlanan controller o token'daki bütün hub'ları görür; başka token'daki hub'ları göremez. (İlk taslaktaki "token yok, relay'deki herkes her hub'ı görür" kararı kullanıcı tarafından geri alındı.)
2. **Hub'a şifreyle girilir.** Her hub kendi şifresini koyar; hub olarak paylaşmak şifre ister. Token hub'ları *görmeyi*, şifre hub'a *girmeyi* sağlar.
3. **Mobil sistem değişmez.** Telefonun token'lı `mac`/`phone` odaları, QR eşleştirmesi ve protokolü aynen kalır. Ağ token'ı telefon token'ından ayrıdır: aynı token'ı iki Mac `mac` rolüyle kullansaydı relay birini odadan atardı.
4. **Önce arayüz, sonra Claude/MCP.**
5. **Settings ▸ Remote kalır.** Hub'a ve hub'lara bağlanmaya dair şeyler soldaki Remote route'una taşınır.

## Terimler

- **Hub:** Kendini relay'de paylaşan Lumi (örn. build makinesi).
- **Controller:** Hub'lara bağlanan Lumi. Bir Lumi aynı anda hem hub hem controller olabilir.
- **Ağ (network):** Aynı ağ token'ını kullanan hub'lar ve controller'lar.
- **Directory:** Relay'in bir ağdaki canlı hub listesi.

## Ağ token'ı

- 32 bayt rastgele, base64url (telefon token'ıyla aynı üretici, `generateToken`). Relay en az 16 karakter ister.
- `remote.json`'a additive `networkToken` olarak yazılır (karar 9). Boşsa Remote route'u `Create Network` (yeni token üretir) ve `Join Network…` (token yapıştırılır) sunar. Doluysa `Copy Token` ve `Leave Network` görünür.
- Token'ı ağdaki her Mac'e bir kez yapıştırmak yeterlidir. Hub da controller da aynı token'ı kullanır.

## Relay (RelayServer)

Telefonun `Registry`/`Room` yapısına dokunulmaz. Yanına token başına ayrı bir `HubDirectory` eklenir.

**Roller (yeni `hello` biçimleri, `v: 1` aynı):**

| hello | Anlamı |
|---|---|
| `{role:"hub", network, hubId, hubKey, name}` | Hub kaydı. `hubId` kurulum başına kalıcı UUID'dir, `hubKey` kurulum başına kalıcı gizli anahtardır (Keychain). Relay `hubId`'yi ilk kayıtta `sha256(hubKey)`'e bağlar: farklı anahtarla aynı kimliği isteyen bağlantı reddedilir (hub çevrimdışıyken de). Böylece token'ı bilen biri listede gördüğü bir hub'ın yerine geçip controller şifrelerini toplayamaz. Aynı anahtarla gelen ikinci bağlantı ilkini ve onun controller'larını `4000 replaced` ile kapatır. Relay yeniden başlarsa bağlama sıfırlanır ve ilk gelen hub kimliği yeniden alır. |
| `{role:"controller", network, controllerId, name}` | Yalnız directory. Relay hello'ya hemen o ağın `hubs` listesiyle cevap verir ve her değişiklikte yeniden yayınlar. |
| `{role:"controller", network, controllerId, name, attach:{hubId, password}}` | Bir hub'a bağlanma soketi. Hub başına ayrı soket açılır, böylece frame'ler telefon protokolüyle birebir aynı kalır ve 1 MB `maxPayload` bütçesi hub başına ayrı işler. |

**`hubs` frame'i:** `{hubs:[{hubId, name, online, lastSeenAt, controllerCount}]}`, yalnız o ağın hub'ları. Çevrimdışı hub relay belleğinde 24 saat `online:false` ile durur (relay yeniden başlarsa liste hub'lar yeniden bağlandıkça dolar).

**Bağlanma el sıkışması.** Şifreyi relay değil hub doğrular:
1. Controller `attach` ile hello gönderir. Relay soketi bekletir ve hub'a `attach_request{requestId, connectionId, controllerId, controllerName, password}` iletir. Hub o ağda çevrimdışıysa relay `4004 hub_offline` ile kapatır.
2. Hub `attach_result{requestId, ok, error?}` döner. 10 sn içinde cevap gelmezse relay `4005 attach_timeout` ile kapatır.
3. `ok` ise relay controller'ı hub'un yayın kümesine ekler ve telefon `welcome`'ının aynısını gönderir: hub'un cache'lenmiş `sessions`, `projects`, `usage`, `tasks` verisi, `hub:{hubId, name}` ve controller'ın bağlantı kimliği `connectionId` (hub'ın gördüğü `from`). Red gelirse `4003 unauthorized` ile kapatır ve IP başına başarısızlık sayacını artırır (mevcut `MAX_FAILED_HELLOS` kalıbı).

**Yönlendirme.** Hub → controller frame'leri (`sessions`, `projects`, `scrollback`, `data`, `chat*`, `prompt`, `command_result`, `usage`, `tasks`) telefon odasındaki `fromMac` mantığıyla o hub'a bağlı tüm controller'lara yayınlanır ve cache'lenir. Controller → hub frame'leri (`subscribe`, `unsubscribe`, `input`, `prompt_respond`, `chat_send`, `command`) hub'a iletilir. Relay her frame'e additive bir **`from`** (controller soket kimliği) ekler, çünkü hub aboneliği abone başına sayar (aşağıda). Hub'ın frame'i `to` taşıyorsa yalnız o controller'a gider (örn. `command_result`). Kabulden önce gönderilen frame'ler düşer. Hub düşünce bağlı ve bekleyen controller'lar `4004 hub_offline` ile kapatılır; controller yeniden bağlanırken şifre yeniden doğrulanır.

Sınırlar: ağ başına 50 hub, hub başına 20 controller, ad 64 karakter. Çevrimdışı hub'lar ve boş ağlar sunucu heartbeat'indeki `sweep` ile temizlenir. Kod: `RelayServer/src/hubs.ts` (`HubBridge`); telefon odasıyla ortak `welcomePayload` ve `relayMacFrame` `bridge.ts`'te.

**Hub'dan relay'e yönetim:** `hub_update{name}` directory'yi günceller. `revoke_controllers{}` o hub'a bağlı bütün controller soketlerini `4003` ile kapatır; hub bunu şifre değişince ve `Disconnect All` ile gönderir. Relay bir controller soketi kapanınca hub'a `controller_left{from}` gönderir.

## Hub tarafı (Mac, LumiRemote)

- **Config (karar 9, additive):** `remote.json`'a `networkToken`, `hubEnabled` (varsayılan `false`), `hubId` (ilk açılışta üretilir) ve `hubName` (varsayılan bilgisayar adı) eklenir. `hubKey` gizli olduğu için Keychain'de durur. Mevcut `enabled` anahtarı telefon kanalının anahtarı olarak anlamını korur. `relayUrl` iki kanal için ortaktır.
- **Şifre:** Hiçbir zaman düz yazılmaz. PBKDF2-HMAC-SHA256 (rastgele 16 bayt salt) hash'i Keychain'de `com.lumi.remote-hub` altında durur. Şifresi olmayan Mac hub olarak paylaşılamaz (`Share This Mac` önce şifre ister). Karşılaştırma sabit zamanlıdır. Aynı `controllerId` için dakikada 5 yanlış denemeden sonra 1 dk kilit uygulanır (relay'in IP sınırına ek).
- **İkinci kanal:** `RemoteService` bugün tek bir `RelayConnecting` üzerinden yayın yapıyor. Hub kanalı ikinci bir `RelayConnection`'dır. Yayınlar her iki açık kanala gider (telefon + controller'lar), gelen frame'ler aynı `handleInbound`'a akar. `attach_request` yalnız hub kanalında işlenir. Komut yüzeyi (`RemoteCommandHandler`) aynıdır: controller'ın yapabildiği her şeyi telefon zaten yapabiliyor.
- **Abonelik sayımı:** Bugün `unsubscribe` terminal aboneliğini küresel olarak iptal ediyor; iki telefon aynı terminale bakarken birinin çıkması diğerininkini de kesiyor. Abonelik `(terminal, from)` çiftleriyle sayılır, son abone çıkınca iptal edilir. Telefon kanalında `from` yoksa tek bir "phone" abonesi sayılır (bugünkü davranış).
- **Yayın ve cevap:** Anlık görüntüler ve akış frame'leri açık her kanala gider (`RemoteService.broadcast`). `command_result` yalnız isteğin geldiği kanala, hub kanalında `to` ile yalnız isteyen controller'a gider (`reply`). Hub'a özgü kod `RemoteService+Hub.swift`'tedir; şifre katmanı `RemoteHubAuth.swift` (`HubPasswordHash`, `RemoteHubSecrets`, `HubAttemptLimiter`), izleyici sayımı `RemoteSubscribers.swift`'tedir. Keychain registry'den gelir (`ServiceRegistry.remoteKeychain`).
- **Görünürlük:** Hub, bağlı controller adlarını tutar (`attach_result ok` ile eklenir, `controller_left` ile düşer) ve Remote route'unda gösterir.

## Controller tarafı (Mac)

- **Wire tipleri:** Controller'ın `sessions`/`projects`/`scrollback`/`data`/`command_result` çözmesi için gereken tipler bugün `LumiMobileKit`'te. `LumiMobileKit` zaten `LumiPackages`'ın `LumiWire` ürününe bağımlı, ters yön bir döngü olurdu. Bu yüzden yalnız gereken saf wire çözümleme tipleri `LumiWire`'a taşınır ve `LumiMobileKit` onları oradan kullanır. Mobil davranış değişmez, `LumiMobileKit` testleri yeşil kalır. `AppModel` ve iOS arayüzü taşınmaz.
- **Servis (LumiRemote):** `RemoteDirectoryClient` directory soketini tutup `hubs` yayınlar. `RemoteHubClient` hub başına bağlanma soketini tutar: oturumlar, proje ağacı, abonelikler, `input` ve `command` istekleri. İkisi de mevcut `RelayConnection`'ı (`start(url:hello:)`) kullanır.
- **Store (LumiState):** `RemoteControllerStore` (`@Observable`) hub listesini, seçili hub'ı, bağlantı durumunu ve seçili oturumu tutar. Kaydedilen şifreler Keychain'de `com.lumi.remote-controller` / `<hubId>` altında durur ve isteğe bağlıdır (`Remember password`). Yanlış şifre gelince silinir.
- **Kendi hub'ı listede görünmez** (`hubId` eşleşmesi).

## Arayüz

**Remote route'u** (karar 55'in yer tutucusu, `ContentRouteID("remote")`) iki sütundan oluşur:

- **Sol sütun:**
  - **Network:** token yoksa `Create Network` / `Join Network…`; varsa `Copy Token` / `Leave Network` ve relay bağlantı durumu.
  - **This Mac:** `Share This Mac` anahtarı, hub adı (düzenlenebilir), şifre (`Set Password…` / `Change…`), bağlı controller'lar ve `Disconnect All`.
  - **Hubs:** ağdaki hub'lar. Satırda çevrimiçi noktası, ad ve bağlı controller sayısı. Tıklayınca şifre sorulur (hatırlanmışsa sorulmaz) ve hub'un `Proje → Checkout → Ajan` ağacı açılır. Checkout'ta `+` menüsü telefon karar 133'ün aynısıdır: Claude, Bash, model kısayolları. Ajan satırının sağ tıkında `Close Terminal` bulunur.
- **Sağ sütun:** seçili ajanın **terminal aynası**. Mac'te Claude TUI'si SwiftTerm'de birebir çizildiği için Claude dahil her terminal ham PTY aynası olarak gösterilir; telefonun chat görünümüne gerek yoktur. Ayna hub'un `cols×rows` boyutundadır (scrollback frame'i otoriterdir); controller pencereyi hub PTY'sini yeniden boyutlandırmadan ölçekleyerek sığdırır. Klavye girişi `input` olarak gider. Başlıkta `hub / proje / ajan` ve bağlantı durumu gösterilir.

**Settings ▸ Remote** yalnız telefonla ilgili ayarları ve ortak relay adresini tutar: `Mobile` anahtarı (eski `Remote'u etkinleştir`), relay adresi, eşleştirme QR'ı, token yenileme. Ağ ve hub ayarları Remote route'una taşınır.

## Claude / MCP (Faz 5)

Lumi'nin loopback MCP sunucusuna (`LumiMCPServer`) `remote_list_hubs`, `remote_list_terminals(hub)`, `remote_read(hub, terminal)`, `remote_send(hub, terminal, text)` ve `remote_start_terminal(hub, checkout, kind, prompt?)` eklenir. Bu araçlar controller servisini ve hatırlanan şifreleri kullanır; her çağrı açık bir `hub` ister. Claude terminalinde `remote_read` cevabı ekrandan kazımak yerine chat aboneliğinden (yapılandırılmış transcript, karar 88) okur. Araçlar normal Claude terminallerine karar 142'nin mod mekanizmasıyla, bir `lumi-remote` modu olarak yüklenir. Orchestrator aynı araçları kendi MCP yapılandırmasından alır. Ayrıntısı o fazın başında netleşir.

## Fazlar

1. **Relay:** token başına `HubDirectory`, hub/controller hello'ları, `hubs` yayını, attach el sıkışması, yönlendirme + `from`, `hub_update` / `revoke_controllers` / `controller_left`, IP sınırı. Testler `RelayServer/test`'te. Railway deploy'u kullanıcı onayıyla yapılır.
2. **Hub:** `remote.json` anahtarları, Keychain şifre hash'i, ikinci kanal, attach doğrulama + kilit, abonelik sayımı.
3. **Controller çekirdeği:** wire tiplerinin `LumiWire`'a taşınması, `RemoteDirectoryClient` / `RemoteHubClient`, `RemoteControllerStore`.
4. **Arayüz:** Remote route'u (Network + This Mac + Hubs + ağaç + terminal aynası), Settings ▸ Remote'un sadeleşmesi, karar kaydı.
5. **Claude/MCP:** `remote_*` araçları + `lumi-remote` modu.

Her faz sonunda `swift build`, `swift test`, `swift build -c release --product Lumi` (relay için `npm test`) koşulur, durum özetlenir ve sonraki faza geçmek için onay beklenir.

## Kapsam dışı (şimdilik)

Doğrudan LAN/Tailscale bağlantısı, controller başına ayrı token, hub'dan dosya aktarımı, uzak oturumun kart olarak controller'ın grid'ine girmesi, telefonun hub directory'sini kullanması.
