#!/bin/zsh
# Lumi.app bundle üretimi (design/04 faz 6).
#
# Kullanım:
#   Scripts/make-app.sh                          # release build + imza → dist/Lumi.app
#   Scripts/make-app.sh --install                # + /Applications/Lumi.app'e kur
#   IDENTITY="Developer ID Application: ..." Scripts/make-app.sh   # gerçek imza + hardened runtime
#
# İmza sırası: IDENTITY → keychain'deki ilk geçerli "Apple Development" → ad-hoc.
# TCC (Downloads/Photos/Calendar/mikrofon izinleri) imza kimliğine bağlıdır: ad-hoc
# imzada kimlik build'e özgü CDHash olduğundan her kurulumda izinler sıfırlanır ve
# macOS yeniden sorar. Sertifikayla imza kimliği sabit kalır → izinler bir kez verilir.
#
# Notarization (Developer ID imzası sonrası):
#   ditto -c -k --keepParent dist/Lumi.app dist/Lumi.zip
#   xcrun notarytool submit dist/Lumi.zip --keychain-profile <profil> --wait
#   xcrun stapler staple dist/Lumi.app
set -euo pipefail

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "Bilinmeyen parametre: $arg (desteklenen: --install)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/LumiPackages"
DIST="$ROOT/dist"
APP="$DIST/Lumi.app"
VERSION="${VERSION:-0.6.0}"

echo "▸ Release build…"
cd "$PKG"
swift build -c release --product Lumi

echo "▸ Bundle iskeleti…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PKG/.build/release/Lumi" "$APP/Contents/MacOS/Lumi"

# SPM resource bundle'ları (default YAML'lar, fontlar) Bundle.module'ün
# araması için Resources altına kopyalanır
for bundle in "$PKG"/.build/release/*.bundle; do
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
  echo "  Notarization için script başındaki komutlara bak."
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
