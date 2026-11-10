# 09 — Relay Server: kendi sunucunu bağla (token + IP allowlist + dashboard)

Durum: Faz 1 (sunucu), Faz 2 (Mac) ve Faz 3 (telefon) tamam, 2026-11-09. Railway sunucusunun kapatılması kaldı. 08-mac-remote.md'nin ağ token'ı modelinin yerini alır.

## Kullanıcı kararları (2026-11-06 / 09)

1. **Herkes kendi sunucusunu bağlar.** Uygulamaya relay adresi gömülmez. Kullanıcı **Server URL + Server Token** girer. Adresi bilmek tek başına bağlanmaya yetmez.
2. **Sunucu tek ağdır.** `Create network` / ağ token'ı kalkar. Token'ı olan herkes o sunucudaki hub listesini görür.
3. **Hub şifresi zorunludur.** Şifresi olmayan Mac hub olarak paylaşılamaz. Bunu Mac uygular; şifreyi relay değil hub doğrular (08'deki gibi).
4. **IP allowlist yalnız hub/controller içindir.** Telefon odası (`mac`/`phone` rolleri) her ağdan bağlanır. Başlangıç listesi unco-forge'un varsayılanlarıdır, mod `enforce`.
5. **Telefon QR ile eşleşir.** Mac, server token'ıyla bağlanır ve bugünkü oda token'ını üretir. QR'a URL + server token + oda token'ı gömülür; telefon ikisiyle bağlanır.
6. **Dashboard'a OIDC ile girilir; kullanıcı adı/şifre yoktur** (2026-11-09 düzeltmesi). Lumi'nin sunucusunda sağlayıcı unco-forge'dur; o da Google SSO'ya devreder, yani girişte "Sign in with Google" görünür. Girebilenler alan adıyla belirlenir: `uncosoft.com`, `rollicgames.com`. Yeni Google projesi ya da unco-forge değişikliği gerekmez.
7. **Ortak bağlantı bileşeni.** Remote route'undaki `This Mac` ve `Mobile` ekranları aynı Server URL + Token bileşenini kullanır. Telefonda giriş alanı yoktur, yalnız QR okunur.
8. **Lumi istemcileri (Mac/telefon) login yapmaz.** Sunucuya yalnız server token'ıyla bağlanır. Tek token üretip herkese dağıtmak geçerli bir kullanımdır.

## Sunucu (RelayServer, Faz 1)

**Kapı (WebSocket el sıkışması).**
- `Authorization: Bearer <server token>` zorunludur. Eksik ya da yanlışsa HTTP `401` döner, WebSocket açılmaz.
- IP başına 60 sn'de 10 yanlış denemeden sonra `429` döner.
- Token biçimi `lrs_` + 32 bayt base64url. Store'da yalnız SHA-256'sı tutulur. Dashboard'da isimle üretilir, yalnız üretildiği yanıtta görünür ve tek tek iptal edilir.
- İptal edilen token'ın açık bağlantıları `4007 token_revoked` ile kapanır.

**IP allowlist.**
- `hello`'daki rol `hub` ya da `controller` ise IP listeye göre denetlenir. `enforce` modunda listede olmayan bağlantı `4006 network_not_allowed` ile kapanır; `report` yalnız kaydeder; `off` denetlemez.
- Boş liste denetimi kapatır, herkesi kilitlemez.
- IP, `X-Forwarded-For`'un **en sağdaki** girdisinden okunur (Heroku router'ı gördüğü adresi sona ekler; baştaki girdiler taklit edilebilir).
- Liste ve mod dashboard'dan düzenlenir ve store'da kalıcıdır. `NETWORK_ALLOWLIST` / `NETWORK_ALLOWLIST_MODE` env'leri yalnız ilk açılışta (store'da ayar yokken) tohum olarak okunur.
- Listede olmayan son 50 deneme dashboard'da görünür.

**Tek ağ.** `HubBridge` tek bir directory tutar. Eski istemcilerin gönderdiği `network` alanı yok sayılır.

**Dashboard.**
- Uç noktalar: `/`, `/login`, `/logout`, `/tokens`, `/tokens/:id/revoke`, `/allowlist`. Sunucu tarafında çizilir.
- Oturum `HMAC(SESSION_SECRET)` imzalı cookie'dir: 12 saat, `HttpOnly`, `SameSite=Strict`, HTTPS'te `Secure`.
- POST'ta `Origin` kendi kökeni olmalıdır.
- Giriş akışı (`src/dashboard/oidc.ts`): yetkilendirme kodu + PKCE (S256), `state` + `nonce` 10 dk'lık imzalı cookie'de bekler.
  - Keşif önce `/.well-known/openid-configuration`'a, olmazsa RFC 8414 `/.well-known/oauth-authorization-server`'a bakar (unco-forge yalnız bunu açar).
  - `OIDC_CLIENT_ID` yoksa sunucu sağlayıcıya kendini kaydeder ve kaydı store'da tutar.
  - `id_token` sağlayıcının JWKS'iyle doğrulanır (issuer, audience = client_id, nonce). E-posta `email` claim'i, yoksa `sub`'dır.
  - `email` kapsamı yalnız sağlayıcı destekliyorsa istenir; unco-forge kapsamları otomatik onaylar, desteklenmeyen kapsam onay döngüsü riski taşır.
- Oturum cookie'si `SameSite=Lax`'tir (sağlayıcıdan dönüş siteler arası bir yönlendirme zinciri), POST'lar `Sec-Fetch-Site` / `Origin` ile korunur.
- İçerik: durum (bağlantı, çevrimiçi Mac, telefon, hub listesi), token yönetimi, allowlist.
- `OIDC_ISSUER` ya da izin listesi (`ALLOWED_EMAIL_DOMAINS` / `ALLOWED_EMAILS`) yoksa dashboard kapalıdır (`503`).

**Diğer.**
- `/health` kimlik doğrulamasız `{ok:true}` döner.
- Kalıcı durum yalnız yönetim verisidir: `relay_tokens`, `relay_settings`. Postgres (`DATABASE_URL`) yoksa bellekte tutulur. Oda/hub durumu bilerek bellektedir. Sunucu **tek kopya** çalışır.
- Env: `PORT`, `DATABASE_URL`, `SESSION_SECRET`, `OIDC_ISSUER`, `OIDC_PROVIDER_NAME`, `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` (isteğe bağlı), `ALLOWED_EMAIL_DOMAINS`, `ALLOWED_EMAILS`, `PUBLIC_URL`, `NETWORK_ALLOWLIST`, `NETWORK_ALLOWLIST_MODE`, `APNS_*`.
- Lumi'nin sunucusundaki değerler: `OIDC_ISSUER=https://sb.internal.rollic.io`, `OIDC_PROVIDER_NAME=Google`, `ALLOWED_EMAIL_DOMAINS=uncosoft.com,rollicgames.com`.

**Kapanış kodları.**

| Kod | Anlamı |
|---|---|
| 4000–4005 | Kanalların kendi kodları (08) |
| 4006 | IP allowlist dışı (`network_not_allowed`) |
| 4007 | Token iptal edildi (`token_revoked`) |

## Barındırma (Lumi'nin kendi sunucusu)

- Heroku `lumi-relay`: `uncosoft` team'i, `eu` bölgesi, Basic dyno, Postgres `essential-0`.
- Adres: `wss://lumi-relay-a261b62c34c2.herokuapp.com`.
- Deploy: `RelayServer/scripts/deploy-heroku.sh`. Klasörü geçici bir git deposuna kopyalayıp app'in remote'una iter; Lumi deposunda commit gerekmez.
- Railway sunucusu Faz 2–3 istemcileri dağıtılana kadar açık kalır, sonra kapatılır.

## Mac (Faz 2)

- **Config.** `remote.json`'a additive `serverToken` eklendi; `relayUrl` ile birlikte sunucuyu tanımlar (`RemoteConfig.endpoint` → `RelayEndpoint`, adres `ws://`/`wss://` ve boş olmayan, boşluksuz token değilse `nil`). Sunucu yoksa hiçbir kanal açılmaz.
  - Varsayılan adres boştur. Eski gömülü Railway adresi okunurken boşa çevrilir (`RemoteConfig.legacyRelayUrl`).
  - Eski `networkToken` okunmaz ama dosyada korunur (karar 9).
  - Token'lar dosyada düz durduğu için `remote.json` her yazımda `0600`'e çekilir. Keychain'e taşınmadı: QR'a gömülmesi gerekiyor ve oda token'ı zaten aynı dosyada.
- **Bağlantı.** `RelayConnecting.start(endpoint:hello:)` el sıkışmada `Authorization: Bearer` gönderir. 401 (yalnız el sıkışmada) ve 4007 kalıcı rettir (`RelayInbound.rejected(RemoteServerIssue)`, `isPermanent`); yeniden denenmez, adres/token değişince kanal yeniden kurulur.
  - 4006 (allowlist) ağa bağlıdır (karar 147): `RelayInbound.blocked(.networkNotAllowed)` yayınlanır, kanal durmaz ve 1…60 sn geri çekilmeyle denemeyi sürdürür. Kanal yeniden `connected` olunca uyarı kalkar.
  - Her bağlantı paylaşılan `NetworkPathSignal`'i (`NWPathMonitor`, yol `satisfied` olunca) dinler; geri çekilme beklemesindeyse beklemeyi kesip hemen bağlanır (`retryNowIfWaiting`). Kurulu ya da kurulmakta olan bağlantıya dokunmaz. Mac izinli ağa geçince bağlantı birkaç saniyede geri gelir.
- **Ret gösterimi.**
  - Telefon/hub kanallarının reddi `RemoteService.serverIssue`'da (`RemoteEvent.serverIssueChanged`) görünür.
  - Directory'nin reddi `RemoteControllerService.directoryIssue`'da görünür.
  - Hub bağlantısının kalıcı reddi `RemoteHubLinkState.rejected(reason: <issue.rawValue>)` olur; 4006'da bağlantı `.connecting`'de kalır ve nedeni directory'nin uyarısı söyler.
  - 4006 uyarısı yalnız onu bildiren kanal (telefon/hub; directory) yeniden bağlanınca kalkar; kalıcı ret onu ezer, tersi olmaz.
  - Üçü de `RemoteServerIssue.message` ile anlatılır.
- **Tek ağ.** Hub ve controller hello'larında `network` yok. `createNetwork`/`joinNetwork`/`leaveNetwork` ve `RemoteNetworkSection` kalktı; yerine `RemoteServicing.setServer(url:token:)` var.
- **Hub şifresi zorunlu.** Hub kanalı şifre olmadan açılmaz (`hubHelloIfReady`). Paylaşım anahtarı şifre yoksa önce şifre formunu açar.
- **Ortak bileşen.** `RemoteServerSection` (Server URL + Token, Connect/Save, Disconnect, doğrulama ve ret mesajı) hem `This Mac` sayfasında hem `RemoteMobilePane`'de (Remote ▸ Mobile ve Settings ▸ Remote) çizilir.
  - `This Mac`'te paylaşım ve hub listesi, `Mobile`'da QR, ancak sunucu tanımlıyken görünür.
- **QR.** `lumi-remote://pair?url=…&token=<oda>&stoken=<server token>`.

## Telefon (Faz 3)

- **Eşleşme.** `PairingInfo`'ya `serverToken` eklendi. `Pairing.parseResult` QR'daki `stoken`'ı okur.
  - `stoken` yoksa `PairingError.outdatedMac` döner ve kullanıcıya "Mac'te Lumi'yi güncelleyip sunucuya bağlayın" denir.
  - Tarayıcı böyle bir QR'da da durur (`Pairing.isPairingLink`) ki hata görünsün.
- **Keychain.** `com.lumi.LumiMobile.pairing`'e additive `serverToken` yazılır. Server token'ı olmayan eski eşleşme okunmaz; uygulama eşleştirme ekranına düşer, çünkü hiçbir sunucuyu açamaz.
- **Bağlantı.** `ConnectionFactory` artık `URLRequest` alır. `RelayClient` el sıkışmada `Authorization: Bearer <serverToken>` gönderir, hello aynıdır (`role:phone`, oda token'ı).
  - Kalıcı retler (`RelayRejection`) yeniden denenmez: hiç frame gelmeden 401 → `unauthorized`, 4007 → `tokenRevoked`. Telefon allowlist'e tabi olmadığı için 4006 almaz.
  - `AppModel` retti eşleşmeyi siler ve sebebi `pairingError` olarak eşleştirme ekranında gösterir.

## Kalan

- Railway sunucusu (`lumi-relay-production.up.railway.app`) bütün istemciler bu sürüme geçince kapatılır.
