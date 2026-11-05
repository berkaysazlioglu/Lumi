#!/bin/zsh
# Lumi.app bundle üretimi (design/04 faz 6).
#
# Kullanım:
#   Scripts/make-app.sh                          # release build + imza → dist/Lumi.app
#   Scripts/make-app.sh --install                # + /Applications/Lumi.app'e kur
#   Scripts/make-app.sh --slot 2 [--open]        # ayrı kimlikli test kopyası → dist/slot-2/Lumi 2.app
#       # (bundle id com.lumi.app.slot2, config ~/.lumi-slot2, numaralı ikon — slot 1–2 kendi
#       #  karakteri: Assets/icon-variants/icon-a|b.png, sonrakiler tonu kaydırılmış Lumi).
#       # Aynı Mac'te birbirine ve gerçek Lumi'ye karışmayan birden çok Lumi koşturmak içindir
#       # (örn. Mac'ten Mac'e remote'u hub + controller olarak denemek, karar 143).
#   --open                                        # build bitince uygulamayı aç
#
# Applications'a kurulmayan ve notarize edilmeyen build'lerin ikonu farklıdır (rozet:
# slot numarası ya da "dev") — Dock'ta gerçek Lumi ile karışmasın.
#   IDENTITY="Developer ID Application: ..." Scripts/make-app.sh   # gerçek imza + hardened runtime
#   IDENTITY="Developer ID Application: ..." Scripts/make-app.sh --notarize
#       # + notarize + staple + dağıtım paketleri:
#       #   dist/Lumi-<VERSION>-<arch>-mac.zip, .dmg, SHA256SUMS-<VERSION>.txt
#
# İmza sırası: IDENTITY → keychain'deki ilk geçerli "Apple Development" → ad-hoc.
# TCC (Downloads/Photos/Calendar/mikrofon izinleri) imza kimliğine bağlıdır: ad-hoc
# imzada kimlik build'e özgü CDHash olduğundan her kurulumda izinler sıfırlanır ve
# macOS yeniden sorar. Sertifikayla imza kimliği sabit kalır → izinler bir kez verilir.
#
# --notarize, keychain'de kayıtlı bir notarytool profili ister (varsayılan ad:
# lumi-notary, NOTARY_PROFILE ile değiştirilebilir). Bir kez kaydetmek için:
#   xcrun notarytool store-credentials lumi-notary \
#     --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
set -euo pipefail

INSTALL=0
NOTARIZE=0
OPEN=0
SLOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --notarize) NOTARIZE=1 ;;
    --open) OPEN=1 ;;
    --slot) shift; SLOT="${1:-}" ;;
    --slot=*) SLOT="${1#--slot=}" ;;
    *) echo "Bilinmeyen parametre: $1 (desteklenen: --install, --notarize, --slot N, --open)" >&2; exit 1 ;;
  esac
  shift
done

if [ -n "$SLOT" ]; then
  if ! [[ "$SLOT" =~ ^[1-9][0-9]?$ ]]; then
    echo "HATA: --slot 1–99 arası bir sayı ister (verilen: '$SLOT')." >&2
    exit 1
  fi
  if [ "$INSTALL" -eq 1 ] || [ "$NOTARIZE" -eq 1 ]; then
    echo "HATA: --slot test kopyası içindir; --install / --notarize ile birlikte kullanılmaz." >&2
    exit 1
  fi
fi

if [ "$NOTARIZE" -eq 1 ] && [ -z "${IDENTITY:-}" ]; then
  echo "HATA: --notarize için IDENTITY (Developer ID Application sertifikası) gerekli." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/LumiPackages"
DIST="${DIST:-$ROOT/dist}"   # test için farklı çıktı dizini: DIST=/path Scripts/make-app.sh
VERSION="${VERSION:-0.9.6}"
GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Kişisel, commit'lenmeyen ayarlar: varsa burada source edilir (.gitignore'da).
# Değişkenler (IDENTITY / VERSION / DIST / NOTARY_PROFILE) burada ezilebilir,
# kurulum sonrası ek adımlar `post_install` fonksiyonuyla tanımlanabilir.
# Dosya yoksa script aynen davranır — CI etkilenmez.
LOCAL_OVERRIDES="$ROOT/Scripts/make-app.local.sh"
if [ -f "$LOCAL_OVERRIDES" ]; then
  echo "▸ Yerel ayarlar: Scripts/make-app.local.sh"
  source "$LOCAL_OVERRIDES"
fi

# --install (notarize'sız): bundle geçici dizinde üretilir, yalnız /Applications'a
# kurulur — dist/ dokunulmaz. --notarize ile dağıtım paketleri için dist/ kullanılır.
if [ "$INSTALL" -eq 1 ] && [ "$NOTARIZE" -eq 0 ]; then
  DIST="$(mktemp -d -t lumi-build)"
  trap 'rm -rf "$DIST"' EXIT
fi
# Kimlik: gerçek Lumi ya da ayrı bir test kopyası (--slot). Rozet yalnız
# Applications'a kurulmayan ve notarize edilmeyen build'lere basılır.
APP_NAME="Lumi"
BUNDLE_ID="com.lumi.app"
CONFIG_DIR=""
BADGE=""
HUE=0
BASE_ICON="$ROOT/Assets/icon.png"
if [ -n "$SLOT" ]; then
  DIST="$DIST/slot-$SLOT"
  APP_NAME="Lumi $SLOT"
  BUNDLE_ID="com.lumi.app.slot$SLOT"
  CONFIG_DIR="$HOME/.lumi-slot$SLOT"
  BADGE="$SLOT"
  # Slot 1–2 kendi karakterini taşır (Assets/icon-variants: hayalet, küp); sonrakiler
  # mor Lumi ikonunun tonu kaydırılarak ayrışır: yeşil, turuncu, pembe, mavi…
  VARIANTS=("$ROOT/Assets/icon-variants/icon-a.png" "$ROOT/Assets/icon-variants/icon-b.png")
  if [ "$SLOT" -le ${#VARIANTS[@]} ] && [ -f "${VARIANTS[$SLOT]}" ]; then
    BASE_ICON="${VARIANTS[$SLOT]}"
  else
    HUES=(250 150 60 200 320 100)
    HUE="${HUES[$(( (SLOT - 1) % ${#HUES[@]} + 1 ))]}"
  fi
elif [ "$INSTALL" -eq 0 ] && [ "$NOTARIZE" -eq 0 ]; then
  BADGE="dev"
  HUE=100
fi
APP="$DIST/$APP_NAME.app"

echo "▸ Release build…"
# NEDEN xcodebuild (swift build DEĞİL): `swift build`'in ürettiği Bundle.module
# accessor'ı bundle'ı yalnız app kökünde ve build makinesindeki mutlak .build
# yolunda arar — Contents/Resources'a bakmaz. Böyle bir binary başka makinede
# (örn. CI build'i kullanıcı makinesinde) açılışta fatalError ile çöker.
# Xcode'un build sistemi ise Bundle.main.resourceURL'i (Contents/Resources)
# arayan bir accessor üretir; bizim modüller + Highlightr/SwiftTerm dahil
# tüm resource bundle çözümlemesi app içinde çalışır.
ARCH="$(uname -m)"
DERIVED="$PKG/.build/xcode"
cd "$PKG"
# SPM paketi şemasında xcodebuild iki zararsız gürültü basar: boş "supported
# platforms" IDE logu ve "Any Mac" / "Any Mac (Mac Catalyst)" belirsizliği
# (ilki, yani native macOS seçilir; Catalyst'i dışlayan bir -destination yazımı
# yok). Yalnız bu satırlar süzülür; çıkış kodu pipefail ile xcodebuild'inkidir.
XCODEBUILD_NOISE='IDERunDestination: Supported platforms for the buildables|^--- xcodebuild: WARNING: Using the first of multiple matching destinations:|^\{ platform:macOS(, variant:Mac Catalyst)?, name:Any Mac \}$'
# SwiftTerm 1.20 `Apple/Metal/Shaders.metal`'i resource olarak derler; Xcode 26+
# Metal derleyicisini ayrı indirilen bir bileşen yapar ("missing Metal Toolchain").
# Yerelde ve CI runner'ında eksikse bir kez indirilir.
if ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
  echo "▸ Metal Toolchain indiriliyor…"
  xcodebuild -downloadComponent MetalToolchain
fi
# -skipPackagePluginValidation: SwiftTerm 1.20'nin build-tool eklentisi
# (SwiftTermBuildInfoPlugin — yalnız git dal/commit bilgisini Swift dosyasına
# yazar) etkileşimsiz xcodebuild'de "Validate plug-in" onayında takılıyordu.
xcodebuild -scheme Lumi -configuration Release \
  -skipPackagePluginValidation \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ARCHS="$ARCH" CODE_SIGNING_ALLOWED=NO \
  -quiet build 2>&1 | { grep -Ev "$XCODEBUILD_NOISE" || true; }
PRODUCTS="$DERIVED/Build/Products/Release"

echo "▸ Bundle iskeleti…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PRODUCTS/Lumi" "$APP/Contents/MacOS/Lumi"

# SPM resource bundle'ları (default YAML'lar, fontlar) Bundle.module'ün
# araması için Resources altına kopyalanır
for bundle in "$PRODUCTS"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "▸ App icon (.icns)…"
ICON_SRC="$BASE_ICON"
if [ -n "$BADGE" ]; then
  BADGED="$DIST/icon-$BADGE.png"
  swift "$ROOT/Scripts/badge-icon.swift" "$ICON_SRC" "$BADGED" "$BADGE" "$HUE"
  ICON_SRC="$BADGED"
  echo "  Rozetli ikon: $BADGE"
fi
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z $retina $retina "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>Lumi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LumiGitCommit</key>
    <string>${GIT_COMMIT}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Lumi needs microphone access for Claude Code voice mode.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Claude Code sessions running inside Lumi may read or write files here.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Claude Code sessions running inside Lumi may read or write files here.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Claude Code sessions running inside Lumi may read or write files here.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>A command run by a Claude Code session touched the Photos library. Lumi itself does not use your photos.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>A command run by a Claude Code session touched calendar data. Lumi itself does not use your calendar.</string>
    <key>NSRemindersUsageDescription</key>
    <string>A command run by a Claude Code session touched reminders data. Lumi itself does not use your reminders.</string>
    <key>NSContactsUsageDescription</key>
    <string>A command run by a Claude Code session touched contacts data. Lumi itself does not use your contacts.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claude Code sessions may use AppleScript (e.g. notifications) via commands you run.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Claude Code sessions running inside Lumi may read or write files on network volumes.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Claude Code sessions running inside Lumi may read or write files on removable volumes.</string>
</dict>
</plist>
PLIST
if [ -n "$CONFIG_DIR" ]; then
  # Test kopyası kendi config dizinini kullanır (LumiPaths.configDirectoryVariable).
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" \
    -c "Add :LSEnvironment:LUMI_CONFIG_DIR string $CONFIG_DIR" "$APP/Contents/Info.plist"
  echo "  Config dizini: $CONFIG_DIR"
fi

# Entitlements (spec/30): yalnız audio-input — V8'e özgü JIT/unsigned-memory/
# dyld/library-validation entitlement'ları bilinçli olarak YOK; App Sandbox yok.
ENTITLEMENTS="$DIST/Lumi.entitlements"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

echo "▸ İmzalama…"
if [ -n "${IDENTITY:-}" ]; then
  # Developer ID + hardened runtime (notarization ön koşulu)
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
  echo "  Developer ID ile imzalandı: $IDENTITY"
  [ "$NOTARIZE" -eq 0 ] && echo "  Notarization için --notarize parametresini kullan."
else
  # Kararlı TCC kimliği için keychain'deki geçerli bir geliştirme sertifikası
  # tercih edilir; yoksa ad-hoc'a düşülür (izinler her build'de sıfırlanır).
  DEV_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')"
  if [ -n "$DEV_IDENTITY" ]; then
    codesign --force --entitlements "$ENTITLEMENTS" --sign "$DEV_IDENTITY" "$APP"
    echo "  Geliştirme sertifikasıyla imzalandı: $DEV_IDENTITY"
    echo "  (TCC izinleri build'ler arası kalıcı — dağıtım için IDENTITY ver.)"
  else
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
    echo "  UYARI: Ad-hoc imzalandı — TCC izinleri her build'de yeniden sorulur."
    echo "  Kalıcı izin için bir Apple Development sertifikası kur ya da IDENTITY ver."
  fi
fi

echo "▸ Doğrulama…"
codesign --verify --verbose=2 "$APP"
echo "✓ $APP hazır"

if [ "$NOTARIZE" -eq 1 ]; then
  PROFILE="${NOTARY_PROFILE:-lumi-notary}"
  ZIP="$DIST/Lumi-${VERSION}-${ARCH}-mac.zip"
  DMG="$DIST/Lumi-${VERSION}-${ARCH}-mac.dmg"

  echo "▸ Notarization — app (profil: $PROFILE)…"
  NOTARIZE_ZIP="$DIST/Lumi-notarize-upload.zip"
  ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$PROFILE" --wait
  rm -f "$NOTARIZE_ZIP"
  xcrun stapler staple "$APP"

  echo "▸ Dağıtım zip'i…"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  echo "▸ DMG…"
  STAGE="$DIST/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Lumi.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "Lumi" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  codesign --force --sign "$IDENTITY" "$DMG"

  echo "▸ Notarization — dmg…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"

  echo "▸ SHA256 checksum…"
  (cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "SHA256SUMS-${VERSION}.txt")
  echo "✓ Dağıtım paketleri hazır:"
  echo "  $ZIP"
  echo "  $DMG"
  echo "  $DIST/SHA256SUMS-${VERSION}.txt"
fi

if [ "$INSTALL" -eq 1 ]; then
  echo "▸ /Applications'a kurulum…"
  # `pgrep` KULLANILMAZ: `-x Lumi` hiç eşleşmez (macOS'ta süreç adı tam yoldur)
  # ve `-f` de bazı bağlamlarda uygulamayı göremiyor.
  #
  # `ps … | grep -q` DA KULLANILMAZ: bu dosyadaki `set -o pipefail` ile BOZUKTU.
  # `grep -q` eşleşmeyi bulur bulmaz çıkıyor, `ps` SIGPIPE alıyor ve pipefail
  # pipeline'ı 141 yapıyordu — yani Lumi ÇALIŞIRKEN koşul "bulunamadı"ya düşüp
  # koruma hiç tetiklenmiyor, çalışan uygulamanın bundle'ı siliniyordu (süreç
  # eski inode'u tuttuğu için kullanıcı eski sürümü kullanmaya devam ederdi).
  # `ps -eo args=` çıktısı ~150 KB, pipe buffer 64 KB — kaçınılmazdı.
  #
  # Pipe hiç kurulmaz: çıktı tamamen okunur, eşleşme kabukta yapılır.
  RUNNING_PROCS="$(ps -eo args= 2>/dev/null || true)"
  case "$RUNNING_PROCS" in
    *"Lumi.app/Contents/MacOS/Lumi"*)
      echo "  HATA: Lumi çalışıyor — önce uygulamadan çık, sonra tekrar dene." >&2
      exit 1
      ;;
  esac
  rm -rf /Applications/Lumi.app
  ditto "$APP" /Applications/Lumi.app
  echo "✓ /Applications/Lumi.app kuruldu"
  # Yerel ayarlar dosyası tanımladıysa kurulum sonrası kancası
  if typeset -f post_install >/dev/null 2>&1; then post_install; fi
fi

if [ "$OPEN" -eq 1 ]; then
  if [ "$INSTALL" -eq 1 ]; then
    open /Applications/Lumi.app
  else
    open "$APP"
  fi
fi
