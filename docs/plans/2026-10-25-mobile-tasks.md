# Telefonda Tasks (plan)

Durum: **plan, onay bekliyor** (2026-10-25). Karar 137'nin Faz 4'ünden yalnız telefon kısmı (kullanıcı isteği). Onaylanınca karar 137'ye ek olarak girer.

## İlke: Mac tek doğruluk kaynağı, telefon onun penceresi

Telefon kullanıcının task sunucusuyla **hiç konuşmaz**. Token'lar Mac'in Keychain'inde kalır; telefon Mac'teki `TasksStore`'u relay üzerinden görür ve komut gönderir — Projects ağacındaki düzenin aynısı (karar 91). Böylece:

- token telefona, relay'e ya da TestFlight build'ine hiç girmez;
- adapter'lar (custom, ileride GitHub/Linear) telefonda yeniden yazılmaz;
- birleşik yazım, hata kaydı, ajan koşucusu tek yerde kalır.

## Tazeleme: "kimse bakmıyorsa istek yok" kuralı korunur

Mac yalnız Tasks route'u görünürken sunucuya istek atıyor (kullanıcı kararı 6). Telefon da bir **izleyicidir**: Tasks ekranı açılınca `tasks_subscribe` gönderir, açık kaldıkça 30 sn'de bir yeniler, kapanınca bırakır (chat'teki 30 sn ertelemeli `unsubscribe` deseni, karar 130). Mac'in tazeleme döngüsü "Mac route'u görünür **ya da** canlı bir telefon izleyicisi var" iken koşar. Uygulama öne gelince eldeki son liste relay önbelleğinden anında görünür ("updated 3 min ago"), sonra tazelenir.

## Protokol (hepsi additive)

**Mac → telefon `tasks` anlık görüntüsü** (relay oda başına önbelleğe alır, `welcome`'a iliştirir — `projects`/`usage` gibi):

```
{ sources: [{ id, name, kind, phase, phaseMessage?, capabilities, fields, me? }],
  tasks:   [{ source, id, title, status, priority?, labels, assignee?, project?,
              updatedAt, needsAttention, imageCount,
              agent?: { state, model?, terminalId?, summary? } }],
  users:   { <sourceId>: [{ id, name }] },
  generatedAt }
```

- `body` ve görsel adresleri anlık görüntüde **yok** (boyut; relay frame sınırı ~1 MB, karar 130). Detay açılınca istenir.
- Görüntü `ChatFrameBudget` gibi bir bütçeye oturtulur: sığmazsa önce en eski Done'lar kırpılır (`truncatedDone: N`).
- Mac tarafında `RemoteTasksBridge` (`RemoteUsageBridge` deseni): `TasksStore` değiştikçe 300 ms debounce ile yayınlar.

**Telefon → Mac komutları** (`RemoteCommandHandler`'a yeni case'ler, sonuç `command_result`):

| Komut | Ne yapar |
|---|---|
| `tasks_subscribe` / `tasks_unsubscribe` | izleyici kirası (yukarıda) |
| `task_detail {source,id}` | `body` (markdown) + görsel sayısı |
| `task_move {source,id,status}` | Mac'in birleşik yazımıyla (2 sn) gider |
| `task_assign {source,id,userId\|null}` | `You` en üstte |
| `task_create {source,title,status?}` | yalnız `create` beyan eden kaynakta |
| `task_start {source,id,model?,checkout?}` | Mac'in Start'ı: eşleşen proje, varsayılan yeni workspace, **kaynağın prompt şablonu** — telefon yalnız modeli/checkout'u değiştirebilir |

Hatalar `command_result` ile ve Mac'teki `TaskRequestFailure.summary` metniyle döner; telefon toast gösterir. Kaynak sorunlarında (offline / failing / reconnect) telefon bandı "Fix on your Mac" der — token'ı telefondan değiştirmek bilinçli olarak yok.

## Telefon arayüzü

- **Ana ekranda `Projects | Tasks` anahtarı** (başlık bloğunun altında; karar 132 tek liste düzenine dokunmaz).
- **Tasks listesi:** üstte kaynak seçici (birden çok kaynak varsa) ve durum filtresi (varsayılan açık olanlar: Todo / In Progress / In Review; Done ayrı çip). Durum başına bölümler; satırda kimlik, başlık, öncelik ikonu, atanan baş harfleri, varsa ajan glifi (`AgentActivityGlyph` — Projects ile aynı dil).
- **Kaydırma eylemleri:** sağa → bir sonraki durum; uzun basış menüsü → `Move to ▸`, `Assign to Me`, `Start with Claude`.
- **Detay sheet'i:** markdown gövde (telefonun mevcut chat markdown çizicisi), özellikler, ajan bölümü. **`Open Chat`** — ajanın terminali telefonda zaten bir chat (karar 88/89): task'i telefondan başlat → ajanın sohbetini telefondan izle/yanıtla → ajan `submit_for_review` deyince task In Review'a geçer.
- **Start sheet'i:** model (Default / Fable / Opus / Sonnet / Haiku — karar 133'teki `+` menüsüyle aynı), yer (yeni workspace / mevcut checkout), prompt önizlemesi salt okunur (şablon Mac'te düzenlenir).
- Demo modu (`DEMO=1`) örnek task'lerle.

## Fazlar

1. **Mac + relay:** `RemoteTasksBridge`, izleyici kirası (`TasksStore` tazeleme kapısı Mac route'u ∨ telefon izleyicisi), komutlar, boyut bütçesi, relay önbelleği + `welcome`. Testler: köprü, kira süresi, her komut, bütçe kırpması, relay (TS) testleri.
2. **Telefon:** `LumiMobileKit` modelleri + çözümleme + `AppModel` (abonelik, komutlar, iyimser taşıma), demo verisi; UI (anahtar, liste, detay, Start, Open Chat). Testler `LumiMobileKitTests`.
3. **Cila + dağıtım:** ajan teslim edince push bildirimi ("DEMO-1 is ready for review" — mevcut push altyapısı), gerçek cihazda deneme, `ios-v*` tag'iyle TestFlight.

## Kapsam dışı (v1)

Görseller (yetkili adresler Mac üzerinden vekillenmeli — v2), filtre/arama ayrıntıları, task düzenleme (başlık/öncelik), kaynak bağlama/yeniden bağlama, prompt şablonu düzenleme.
