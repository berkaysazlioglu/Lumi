# 09 — Relay Server: kendi sunucunu bağla (token + IP allowlist + dashboard)

Durum: Faz 1 (sunucu) tamam, 2026-11-09. Faz 2 (Mac) ve Faz 3 (telefon) bekliyor. 08-mac-remote.md'nin ağ token'ı modelinin yerini alır.

## Kullanıcı kararları (2026-11-06 / 09)

1. **Herkes kendi sunucusunu bağlar.** Uygulamaya relay adresi gömülmez. Kullanıcı **Server URL + Server Token** girer. Adresi bilmek tek başına bağlanmaya yetmez.
2. **Sunucu tek ağdır.** `Create network` / ağ token'ı kalkar. Token'ı olan herkes o sunucudaki hub listesini görür.
3. **Hub şifresi zorunludur.** Şifresi olmayan Mac hub olarak paylaşılamaz. Bunu Mac uygular; şifreyi relay değil hub doğrular (08'deki gibi).
4. **IP allowlist yalnız hub/controller içindir.** Telefon odası (`mac`/`phone` rolleri) her ağdan bağlanır. Başlangıç listesi unco-forge'un varsayılanlarıdır, mod `enforce`.
5. **Telefon QR ile eşleşir.** Mac, server token'ıyla bağlanır ve bugünkü oda token'ını üretir. QR'a URL + server token + oda token'ı gömülür; telefon ikisiyle bağlanır.
6. **Dashboard kullanıcı adı + şifreyle girilir** (`ADMIN_USERNAME` / `ADMIN_PASSWORD`). Token girişi yoktur.
7. **Ortak bağlantı bileşeni.** Remote route'undaki `This Mac` ve `Mobile` ekranları aynı Server URL + Token bileşenini kullanır. Telefonda giriş alanı yoktur, yalnız QR okunur.
8. **Google login yok.** Bu modelde Google/unco-forge OAuth kullanılmaz.

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
- Giriş: IP başına 15 dk'da 5 yanlış denemeden sonra `429`.
- İçerik: durum (bağlantı, çevrimiçi Mac, telefon, hub listesi), token yönetimi, allowlist.
- `ADMIN_USERNAME` / `ADMIN_PASSWORD` yoksa dashboard kapalıdır (`503`).

**Diğer.**
- `/health` kimlik doğrulamasız `{ok:true}` döner.
- Kalıcı durum yalnız yönetim verisidir: `relay_tokens`, `relay_settings`. Postgres (`DATABASE_URL`) yoksa bellekte tutulur. Oda/hub durumu bilerek bellektedir. Sunucu **tek kopya** çalışır.
- Env: `PORT`, `DATABASE_URL`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `SESSION_SECRET`, `NETWORK_ALLOWLIST`, `NETWORK_ALLOWLIST_MODE`, `APNS_*`.

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

## Sonraki fazlar

- **Faz 2 — Mac.**
  - Ortak `Server URL + Token` bileşeni `This Mac` ve `Mobile` ekranlarında kullanılır. `remote.json`'da tek kaynak olur: `relayUrl` + additive `serverToken`; token Keychain'de.
  - Bütün kanallar el sıkışmada Bearer gönderir.
  - `Create/Join/Leave Network` ve `networkToken` kalkar.
  - Hub şifresi zorunlu olur.
  - `RemoteModels`'teki Railway varsayılanı kalkar, adres boş başlar.
  - QR'a `stoken` eklenir.
  - `4006` / `4007` / `401` için kullanıcıya anlaşılır hata gösterilir.
- **Faz 3 — Telefon.** `Pairing` QR'daki server token'ını okur, Keychain'deki eşleşmeye ekler ve el sıkışmada Bearer gönderir. Eski (token'sız) QR'lar "Mac'te Lumi'yi güncelleyin" uyarısıyla reddedilir.
