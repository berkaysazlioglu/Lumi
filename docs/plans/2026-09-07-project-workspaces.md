# Projects sidebar ve yerel workspace oluşturma

Durum: 2026-09-07 kullanıcı onayıyla uygulandı. Plan, entegrasyon ve doğrulama ana ajanda; servis, state ve UI ilk uygulamaları Luna ajanlarına ayrıldı.

## Kesinleşen gereksinimler

- Sol Projects panelinde her projenin yanında `+` bulunur; tıklayınca oluşturma popup'ı açılır.
- Popup Orca referansındaki form düzenini Lumi tema bileşenleriyle kullanır.
- Yalnız yerel çalışma: `Run on` alanı yoktur.
- `Create From` yerine kullanıcı tarafından doldurulan `Name` alanı vardır; Smart/GitHub/Branch modları yoktur.
- Git worktree ve Plastic SCM workspace oluşturma desteklenir.
- Plastic ve Unity algısı görünür biçimde belirtilir.
- Unity projesinde `Copy Library` toggle'ı ve üzerinde küçük açıklama bulunur.
- Workspace klasörleri kaynak projenin dışında oluşturulur; sidebar'daki proje/workspace ilişkisi diskte iç içe klasör anlamına gelmez.

## Önerilen ilk sürüm sınırı

- Project → Workspace listesi; mevcut proje klasörü `Original` satırı olarak gösterilir.
- Proje, mevcut `RepoStore` keşif kaynaklarından gelir. Yeni workspace yalnız sidebar'da kendi projesinin altında gösterilir; diskte ayrı workspace kökünde tutulur.
- Workspace seçimi terminal grid'i, Sessions, Explorer ve Agent History için aynı klasör bağlamını kullanır.
- Mevcut üst repo sekmeleri ilk sürümde korunur. Bunları kaldırmak önceki yanıttaki bir öneriydi; kabul edilmiş gereksinim değildir.
- Source Control'deki mevcut Git özellikleri korunur. Plastic check-in/diff/history bu oluşturma işinin kapsamına eklenmez.
- SSH, issue/PR eşleme, nested workspace, sparse checkout, otomatik setup script'i ve toplu silme yoktur.
- Düz klasörler açılmaya devam eder; SCM bulunmayan klasörde bağımsız checkout oluşturma sunulmaz.
- Kullanıcının istemediği ikinci bir Unity seçeneği eklenmez. Unity Hub/Editor başlatma sonraki işe bırakılır.

## Popup

```text
Create workspace                                  ×

Project          [MyGame                       ▾]
Plastic SCM repository · Unity project detected

Name             [inventory                     ]
Agent            [Claude                       ▾]

Unity
Copying Library may shorten the first Unity import
when preparing this workspace for CLI/MCP tools.
Copy Library                                  [off]

Advanced                                      [▾]
  Branch         [/main/inventory               ]
  Based on       /main · changeset 123
  Location       ~/lumi/workspaces/MyGame/inventory

                              [Cancel] [Create workspace]
```

- Proje yanındaki `+` ilgili projeyi seçili getirir; popup içinde proje değiştirilebilir.
- İsim zorunludur. Görünen isim korunur; klasör ve branch için provider'a uygun öneri üretilir ve önizlenir.
- Ajan seçimi mevcut Claude/Codex/Shell başlangıç akışını kullanır; workspace'i yalnız açma seçeneği de bulunur.
- `Advanced` varsayılan kapalıdır. Branch adı değiştirilebilir; başlangıç revision'ı ve hedef yol görünürdür.
- Varsayılan başlangıç, seçilen kaynak workspace'in mevcut commit/changeset'idir. Kaydedilmemiş kaynak değişiklikleri taşınmaz; bu formda kısa bir açıklamayla belirtilir.
- Yeni branch oluşturulur; mevcut bir branch'in üstüne yazılmaz. İsim/yol çakışması alanda gösterilir.
- Proje değişiminde eski algılama sonucu ve Unity seçeneği yeni projeye taşınmaz; geç gelen async yanıtlar göz ardı edilir.
- İşlem adımları: doğrulama → workspace oluşturma → isteğe bağlı Library kopyalama → kaydetme → açma/ajan başlatma.
- Oluşturma sırasında çift submit engellenir. İptal/kapatma davranışı servis işinin gerçek iptal kabiliyetine göre açıkça tanımlanır; yalnız popup'ı gizlemek iptal sayılmaz.
- Popup terminal girdisini bloklayan mevcut overlay sistemi üzerinden açılır.

## Algılama ve Unity Library

- SCM türü ve Unity algısı bağımsızdır. Plastic kullanımı tek başına Unity projesi olduğu anlamına gelmez.
- Unity algısı mevcut `Assets/` + `ProjectSettings/ProjectVersion.txt` kontrolünü kullanır.
- Git+Unity için de aynı Library seçeneği gösterilir; Plastic+Unity birleşiminde her iki algılama etiketi gösterilir.
- `.plastic` yalnız aday işaretidir; gerçek workspace/repository kimliği CLI ile doğrulanır. CLI bulunamazsa algılama ve oluşturma hatası anlaşılır biçimde gösterilir.
- Library toggle'ı varsayılan kapalıdır. Kaynakta Library yoksa seçenek açıklamayla pasif görünür.
- `Library şart` denmez: Unity bu önbelleği yeniden oluşturabilir. CLI/MCP hazır olma durumu kullanılan araca ve Editor/import durumuna bağlıdır.
- Kopya kaynak Library'den bağımsızdır; symlink veya hardlink ile ortak yazılabilir cache oluşturulmaz.
- Temp, Logs ve kaynak SCM metadata'sı Library kopyalama adımına dahil edilmez.
- Kopyalama UI thread'inde çalışmaz; büyük klasör belleğe bütünüyle alınmaz. Kaynak/hedef containment ve symlink denetimleri uygulanır.
- İlk uygulama için kaynak projede aktif Unity Editor varsa Library kopyası engellenir ve kopyasız devam seçeneği sunulur. Kullanılan kilit göstergesi uygulama öncesi doğrulanır; eski bir lock dosyası otomatik silinmez.
- Kopya checkout tamamlandıktan sonra, yeni workspace'te Editor/ajan başlatılmadan önce hazırlanır.
- Kopya başarısızsa hazır SCM workspace korunur; yarım Library yalnız bu işlemin oluşturduğu alan içinde temizlenir. Kullanıcı yeniden deneyebilir veya Library olmadan açabilir.
- Library kopyası import veya MCP bağlantısının başarılı olacağı garantisi olarak sunulmaz.

Kaynak: [Unity — Importing assets](https://docs.unity3d.com/cn/2023.1/Manual/ImportingAssets.html), Library'nin yeniden üretilebilir cache oluşunu açıklar.

## Model ve servis sınırları

- Mevcut path tabanlı terminal kimliği korunur; terminal servislerine workspace'in gerçek yolu verilir.
- Project kimliği ile workspace yolu ayrı tutulur. Proje adı veya branch adı kalıcı kimlik olarak kullanılmaz.
- Workspace kaydı: kaynak proje yolu, workspace yolu (kimlik), görünen isim, branch ve SCM türü. Original satırı projeden türetilir; kayıtlar yalnız Lumi tarafından oluşturulan workspace'lerdir.
- Mevcut `isGitRepo` uyumluluk yüzeyi kademeli korunabilir; yeni kod SCM türünü Git/Plastic/none olarak ele alır. Unity ayrı capability'dir.
- Dar `WorkspaceServicing` sözleşmesi: kaynağı inceleme, workspace oluşturma ve Library kopyasını yeniden deneme. Kayıtların uzlaştırılması store'dadır.
- Git ve Plastic komutları servis içinde SCM türüne göre ayrılır. Process I/O mevcut `ProcessRunning` ve `BinaryLocating` üzerinden enjekte edilir.
- Library kopyası ayrı dosya sistemi sınırında test edilebilir; provider'lar Unity UI tercihlerini yorumlamaz.
- Git worktree keşfinde `.git` dosyası desteklenir. Lumi tarafından oluşturulan worktree'ler ayrı proje olarak çoğaltılmaz; harici worktree import bu kapsamda değildir.
- Plastic workspace komutları repository ve server kimliğini açıkça kullanır; CLI varsayılan repository seçimine güvenilmez.
- Plastic branch tabanı seçilen changeset'e sabitlenir; Git başlangıcı commit'e çözülür. Oluşturma sırasında branch ilerlemesi tabanı değiştirmez.
- Varsayılan oluşturma yolu `~/lumi/workspaces/{project name}/{workspace name}` olur. Bu konum uygulama ayarlarının tutulduğu `~/.lumi` dizininden ayrıdır. Tam hedef yol kullanıcıya formda gösterilir.
- Aynı adlı farklı projeler aynı klasörü paylaşmaz; çakışmada proje klasörü adına kararlı proje kimliğinden kısa bir ek getirilir. Görünen proje adı değişmez.
- Oluşturma hedefi kaynak repository/workspace kökünün veya kayıtlı başka bir proje/workspace'in içinde olamaz. Kaynak yolu alt klasörse SCM'nin gerçek kökü esas alınır; `~`, `..` ve symlink'ler çözülerek containment doğrulanır. Geçersiz hedefte oluşturma başlamaz.
- Yönetilen workspace kökü, genel proje keşfinde yeni bağımsız projeler üretmez; workspace'ler kendi kataloglarından bağlı projeye yerleştirilir. Kaynak projenin Explorer ve watcher kapsamı harici workspace'leri kapsayacak şekilde genişletilmez.
- Yeni workspace yolları Explorer/reveal/dosya işlemlerindeki izinli kök doğrulamasına kayıtla dahil edilir; kontrol genel olarak gevşetilmez.
- Kaynak klasörü değiştirmek veya kaynak branch'i switch etmek oluşturma akışının parçası değildir.

## Kalıcılık ve kabuk entegrasyonu

- Yeni panel ve popup `FeatureAssembly` + panel/overlay descriptor'ları ile eklenir; RootView/PanelHostView/HeaderBarView/ContentRouterView'a iş mantığı eklenmez.
- Sol yerleşimde Sessions üstte, Projects altta kalır (karar 47 düzeltmesi; ilk taslak tersiydi). Mevcut panel sıralaması ve kullanıcı görünürlük tercihleri korunarak yeni panel için tek seferlik migration gerekir.
- `projects` hiçbir yuvada yoksa sol listenin başına eklenir; zaten varsa yeri değiştirilmez. Sol panel kullanıcı tarafından gizlenmişse zorla açılmaz. Yeni kurulum varsayılanı `[sessions, projects]` olur.
- Workspace kayıtları mevcut ConfigCodec deseninde additive alanlarla yazılır; eski config/ui-state anahtarlarının anlamı değiştirilmez.
- Bootstrap önce proje ve workspace kataloğunu yükler, sonra NavigationStore açık yolları geri yükler. Aksi hâlde projectsRoot dışındaki workspace sekmeleri açılışta düşer.
- Silinmiş/ulaşılamayan workspace kaydı kullanıcıya eksik olarak gösterilir; otomatik disk silme yapılmaz.
- Workspace değişimi çalışan PTY'leri durdurmaz. Watcher/cache abonelikleri seçili workspace yolunu izler.
- Uygulamaya başlanırken ilgili karar/tasarım kayıtları bu kapsamla güncellenir.

Luna incelemesindeki `AdditionalPath(.repo)` önerisi tek başına yeterli değildir: workspace yolunu geri bulabilir ama proje/workspace ilişkisini ve original/managed sahipliğini taşımaz. Bu ilişki ayrı additive metadata ile saklanır; keşfedilen proje listesi ikinci kez kalıcı bir liste olarak çoğaltılmaz. Library kopyası hatasında tüm workspace'i silme önerisi benimsenmedi; başarılı SCM oluşturma sonucu kurtarılabilir durumda korunur.

## Luna görev dağılımı ve sıra

| İş paketi | Sahip | Teslim |
|---|---|---|
| Plan, ortak sözleşmeler, kapsam kararları | Ana ajan | Model/protokol taslağı, kabul ölçütleri |
| Git/Plastic servisleri ve Library kopyası | Luna A | Provider'lar, hata/kurtarma akışı, servis testleri |
| Workspace store, katalog ve persistence | Luna B | State, codec, restore ve navigation testleri |
| Projects paneli ve oluşturma popup'ı | Luna C | Tema bileşenleriyle UI, form durumları ve preview'lar |
| Composition ve bütünleşik doğrulama | Ana ajan | Servis/store/UI bağlantıları, build/test/release build |

Ortak LumiKit tipleri ve dosya sahipliği önce sabitlenir; Luna uygulamaları sonra paralel başlar. Ortak registry/composition dosyalarını ana ajan düzenler. Her ajan diğer ajanın değişikliklerini geri almadan kendisine ayrılan dosyalarda çalışır.

## Kabul ölçütleri

- Proje yanındaki + doğru projeyle popup açar; formda Run on veya Create From modları bulunmaz.
- Git, Plastic, Git+Unity, Plastic+Unity ve düz klasör doğru ayrışır.
- Boş isim, geçersiz branch, mevcut hedef, aynı anda çift oluşturma ve CLI eksikliği görünür sonuç verir.
- Varsayılan hedefin `~/lumi/workspaces/...` olduğu; kaynak içine, kaynak alt klasörüne veya symlink üzerinden kaynak içine yönlenen hedeflerin reddedildiği doğrulanır. Oluşturulan workspace kaynak projenin dosya ağacına veya untracked dosya listesine girmez.
- İki workspace'in terminalleri ve dosya görünümü birbirine karışmaz; geçiş PTY'yi kapatmaz.
- Library açık/kapalı/yok/kopyalama hatası senaryoları kaynak klasöre yazmadan doğrulanır.
- Kısmi Plastic/Git başarısızlığı kalan kaynakları görünür kılar; kullanıcı branch'leri veya önceden var olan klasörler temizlenmez.
- Ajan başlatma hatası oluşturulmuş workspace'i kaybettirmez.
- Yeniden açılışta kayıtlı workspace'ler, aktif yol ve mevcut eski ayarlar korunur.
- Anlamlı servis/store/codec testleri; geçici repository ile gerçek Git testi; Plastic komut zinciri için izole process testleri.
- `swift build`, `swift test`, `swift build -c release --product Lumi`; popup, klavye odağı ve sidebar için görsel kontrol.

## Doğrulama sınırı

Git oluşturma gerçek geçici repository'lerle; Plastic metadata kurulu CLI'nin gerçek salt-okuma çıktısıyla doğrulanır. Plastic branch/workspace oluşturma ve kısmi hata zinciri fake process runner ile test edilir; gerçek Plastic sunucusunda yazma smoke testi bu çalışmada yapılmadı.

## Uygulama doğrulaması (2026-09-07)

- Tam paket: 1473 test, 0 hata. Native pencere ve loopback testleri normal macOS erişimiyle çalıştırıldı.
- Son UI açıklama değişikliği sonrası native render + tasarım token denetimi: 5 test, 0 hata.
- Debug ve release `Lumi` ürünü derlendi. Sidebar ve Plastic+Unity popup'ı native PNG render ile gözden geçirildi.
- Kullanıcının gerçek projelerinde SCM oluşturma/switch veya Library kopyalama çalıştırılmadı; Git yazma testleri geçici repository'lerdedir.

## Kullanıcı düzeltmeleri (2026-09-07, karar 47)

Önceki planın ilgili maddeleri güncellendi: Sessions önce, Projects sonra; Projects yalnız tek tek eklenen projelerden oluşur. Plastic varsayılan olarak mevcut branch ile yeni workspace oluşturur, yeni branch isteğe bağlıdır. Create popup'ı kapanır; süreç ve kurtarma sidebar'da sürer, tamamlanma kullanıcının odağını değiştirmez. Fiziksel hedef hâlâ kaynak proje dışındaki `~/lumi/workspaces/...` konumudur.

## Sidebar seçimi düzeltmesi (karar 48)

“Eklediğim projeler”, additional paths girdileri anlamına gelmez. Projects `+` topbar'ın aynı repo seçme popup'ını kullanır; kullanıcı keşfedilen repolardan kendi sidebar listesini oluşturur. Seçim `sidebarProjectPaths` olarak bağımsız saklanır; Finder açılmaz, topbar'da açık repo yeniden seçilebilir ve sidebar'a ekleme topbar tab'larını değiştirmez.

## Ek: ajan satırları, sağ tık ve silme (2026-09-07, karar 49)

Codex'in yarım bıraktığı Orca-sadelik işi tamamlandı: checkout satırlarının altında canlı ajanlar durum glifi + kimlik + başlık + kısa zaman ile listelenir; proje/workspace/ajan satırlarına sağ tık menüleri geldi; workspace silme (`Delete Workspace…` → onay → kirli worktree'de `Force Delete`) ve eksik kayıt için `Remove from List` eklendi. Karar 46'daki "silme kapsam dışı" maddesi bu ekle kullanıcı isteğiyle açıldı.

