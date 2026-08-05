#!/bin/zsh
# Lumi.app bundle üretimi (design/04 faz 6).
#
# Kullanım:
#   Scripts/make-app.sh                          # release build + imza → dist/Lumi.app
#   Scripts/make-app.sh --install                # + /Applications/Lumi.app'e kur
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
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --notarize) NOTARIZE=1 ;;
    *) echo "Bilinmeyen parametre: $arg (desteklenen: --install, --notarize)" >&2; exit 1 ;;
  esac
done

if [ "$NOTARIZE" -eq 1 ] && [ -z "${IDENTITY:-}" ]; then
  echo "HATA: --notarize için IDENTITY (Developer ID Application sertifikası) gerekli." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/LumiPackages"
DIST="${DIST:-$ROOT/dist}"   # test için farklı çıktı dizini: DIST=/path Scripts/make-app.sh
APP="$DIST/Lumi.app"
VERSION="${VERSION:-0.6.1}"

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
xcodebuild -scheme Lumi -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ARCHS="$ARCH" CODE_SIGNING_ALLOWED=NO \
  -quiet build
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
ICON_SRC="$ROOT/Assets/icon.png"
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
    <string>com.lumi.app</string>
    <key>CFBundleName</key>
    <string>Lumi</string>
    <key>CFBundleDisplayName</key>
    <string>Lumi</string>
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
  if pgrep -xq Lumi; then
    echo "  HATA: Lumi çalışıyor — önce uygulamadan çık, sonra tekrar dene." >&2
    exit 1
  fi
  rm -rf /Applications/Lumi.app
  ditto "$APP" /Applications/Lumi.app
  echo "✓ /Applications/Lumi.app kuruldu"
fi
