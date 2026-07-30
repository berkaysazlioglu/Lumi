# 06 — Remote Dashboard (yerel ağ)

**Amaç:** Kullanıcının telefonundan (aynı yerel ağ) aktif terminalleri listeleyip
ekran içeriklerini canlı izleyebilmesi ve Claude'a girdi gönderebilmesi.
Kapsam bilinçli olarak dar (v1): terminal açma/kapama YOK, yalnız izleme + girdi.

## 1. Mimari

Yeni SPM hedefi **LumiRemote** (`LumiKit` + [FlyingFox](https://github.com/swhitty/FlyingFox)
0.27+, kullanıcı onayıyla eklendi 2026-07-20). Katman yerleşimi mevcut deseni izler:

```
LumiKit      RemoteDashboardServing (protokol) + TerminalServicing.screenText(id:)
LumiRemote   RemoteDashboardServer (FlyingFox HTTP+WS) ← RemoteTerminalProviding
             TerminalServiceRemoteAdapter (TerminalServicing → provider köprüsü)
             TerminalSocketSession (bağlantı-başına durum makinesi, ağdan bağımsız)
LumiState    RemoteDashboardStore (@Observable; start/stop + url/isRunning)
LumiUI       HeaderBarView ikonu + RemoteDashboardPopover (start/stop, URL, QR)
LumiApp      AppContainer: adapter + server + store kompozisyonu
```

- **`RemoteTerminalProviding`** sunucu/soket mantığının terminal alt sistemine
  bakan tek yüzüdür; MainActor sıçramaları adapter'da kalır. Soket mantığı
  sahte provider'la ağsız test edilir (27 test, `LumiRemoteTests`).
- **Ekran görüntüsü:** `TerminalServicing.screenSnapshot(id:)` iki parça döner
  (2026-07-20 revizyonu — kullanıcı geri bildirimi: boşluk kaybı + renksizlik):
  **scrollback kuyruğu** düz metin (`getBufferAsData`, NUL hücreler boşluğa
  çevrilir — TUI'ler kelime aralarını cursor hareketiyle atladığından şart),
  **görünür ekran** ise `TerminalScreenRenderer` ile hücre özniteliklerinden
  stilli koşulara (`TerminalScreenRun`: renk + bold/italik/underline/dim)
  çevrilir. Renk çözümü SwiftTerm `mapColor` semantiğinin aynısıdır: tema ANSI
  paleti (bold 0-6'yı parlak varyanta terfi ettirir), xterm 256 küpü/gri rampası,
  truecolor; inverse/invisible sunucuda çözülür. Browser-side emülatör YOK —
  client yalnız span'lere düz CSS uygular.

## 2. Protokol

- `GET /` → gömülü `dashboard.html` (tek dosya, vanilla JS, mobile-first, koyu tema).
- `GET /api/terminals` → `{"terminals":[RemoteTerminalSummary]}` (liste görünümü 3 sn'de bir poll eder).
- `GET /ws` → WebSocket. Tek endpoint; bağlantı ilk `{"type":"attach","id":…}`
  mesajıyla terminale bağlanır. Client → server: `attach` / `input` (ham tuş
  bayt'ları; escape dizilerini client kodlar) / `prompt` (sunucu `PromptInjection`
  ile bracketed-paste sarar — UI'daki kuyruk enjeksiyonuyla aynı funnel).
  Server → client: `snapshot` (tam ekran metni + terminal özeti) / `exited` / `error`.

**Snapshot yayını:** çıktı stream'i (`outputStream(id:)`) yalnız *kirli-bayrak*
sinyalidir; 500 ms tick'te bayrak kalkıksa VEYA status değiştiyse buffer'dan
taze tam-snapshot çekilir (çıktı seli coalesce olur, TUI redraw'ları sorunsuz).
Scrollback payload'ı son 400 satırla sınırlıdır; stilli ekran bölümü ekran
boyutundadır (~30-40 satır) ve sınıra dahil değildir. Terminal listeden düşünce `exited` yayınlanır
ve soket kapatılır.

## 3. Yaşam döngüsü ve güvenlik

- Sunucu **otomatik başlamaz**; topbar'daki antenna ikonu → popover → Start/Stop
  (kullanıcı kararı 2026-07-20). Popover çalışırken URL + QR kod gösterir
  (CoreImage `CIQRCodeGenerator`, harici bağımlılık yok).
- Kapanışta `AppContainer.shutdown()` sunucuyu `terminal.killAll()`'dan ÖNCE durdurur.
- **FD izolasyonu (2026-07-20 düzeltmesi):** PTY çocukları exec'ten önce 3+ tüm
  tanıtıcıları kapatır (`PTYProcess`). Aksi halde forkpty çocukları sunucunun
  dinleme/bağlantı soketlerini miras alıp portu rehin alıyordu: sunucu durunca
  istekler kimsenin accept etmediği zombi sokete düşüyor, telefonda "bağlı ama
  bomboş" ekran görülüyordu. Regresyon bekçisi: `PTYFDInheritanceTests`.
- Port sabit **8484**; çakışmada `LumiError.remoteDashboardFailed` toast'u (karar 5).
- **v1 güvenlik modeli:** kimlik doğrulama yok — sunucu yalnız kullanıcı
  başlattığı sürece ve yerel ağa açık çalışır. Güvenilmeyen ağda açık bırakılmamalı;
  token/pairing ileriye dönük iş.

## 4. Bilinçli sınırlar (v1)

- Renk/stil yalnız görünür ekranda; scrollback kuyruğu düz metindir.
- Terminal spawn/kill, repo/git görünümleri yok.
- Snapshot diff'i yok (her yayın tam metin); LAN için yeterli, WAN hedeflenmez.
