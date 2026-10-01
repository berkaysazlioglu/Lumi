#!/bin/zsh
# LumiMobile → TestFlight otomasyonu (make-app.sh mobil karşılığı).
#
# Tek komutla: xcodegen generate → xcodebuild archive → export .ipa → TestFlight upload.
#
# Kullanım:
#   Scripts/make-mobile.sh                 # tam pipeline (archive + export + upload)
#   Scripts/make-mobile.sh --no-upload     # sadece .ipa üret (build/export/), yükleme yapma
#   VERSION=1.1 Scripts/make-mobile.sh     # marketing sürümünü ez (varsayılan 1.0)
#
# Build numarası (CFBundleVersion) otomatik = `git rev-list --count HEAD` — her commit'te
# artar, TestFlight'ın istediği benzersiz/artıcı build numarasını garanti eder.
#
# İmza: keychain'de dağıtım sertifikası GEREKMEZ. `-allowProvisioningUpdates` + App Store
# Connect API anahtarı ile Xcode dağıtım cert/profilini otomatik oluşturur/çeker.
#
# App Store Connect API sırları ~/.lumi/mobile-tf.env'den okunur (repo DIŞI — git'e giremez):
#   ASC_ISSUER_ID="69a6de7f-...-..."                  # ASC ▸ Users and Access ▸ Integrations
#   ASC_KEY_ID="7ZM9LV2BVJ"                            # anahtar kimliği
#   ASC_KEY_PATH="$HOME/Downloads/AuthKey_7ZM9LV2BVJ.p8"
# (Aynı üç değer ortam değişkeni olarak da verilebilir; env dosyası onları ezer.
#  Geriye-uyum: Scripts/make-mobile.local.sh varsa o da yüklenir, env dosyası son sözü söyler.)
set -euo pipefail

NO_UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --no-upload) NO_UPLOAD=1 ;;
    *) echo "Bilinmeyen parametre: $arg (desteklenen: --no-upload)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE="$ROOT/LumiMobile"
PROJECT="$MOBILE/LumiMobile.xcodeproj"
SCHEME="LumiMobile"
ARCHIVE="$MOBILE/build/LumiMobile.xcarchive"
EXPORT_DIR="$MOBILE/build/export"
EXPORT_PLIST="$MOBILE/ExportOptions.plist"

# Kişisel, commit'lenmeyen ayarlar (ASC sırları burada tutulur).
# Önce geriye-uyum için repo-içi local.sh (varsa), sonra repo-dışı ~/.lumi/mobile-tf.env
# (tercih edilen; son sözü söyler). set -a → dosyadaki atamalar bu kabuğa export edilir.
LEGACY_OVERRIDES="$ROOT/Scripts/make-mobile.local.sh"
if [ -f "$LEGACY_OVERRIDES" ]; then
  echo "▸ Yerel ayarlar (legacy): Scripts/make-mobile.local.sh"
  set -a; source "$LEGACY_OVERRIDES"; set +a
fi
ENV_OVERRIDES="$HOME/.lumi/mobile-tf.env"
if [ -f "$ENV_OVERRIDES" ]; then
  echo "▸ Yerel ayarlar: ~/.lumi/mobile-tf.env"
  set -a; source "$ENV_OVERRIDES"; set +a
fi

# Sürüm/build.
VERSION="${VERSION:-1.0}"
BUILD="$(cd "$ROOT" && git rev-list --count HEAD)"
echo "▸ Sürüm: $VERSION ($BUILD)"

# Upload auth modu: (1) ASC API key (.p8) varsa onu kullan; (2) yoksa Apple ID +
# app-specific password (o build-makinesi Fastfile'ının yaptığı gibi, .p8 GEREKMEZ).
UPLOAD_MODE=""
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ] && [ -f "${ASC_KEY_PATH:-/nonexistent}" ]; then
  UPLOAD_MODE="apikey"
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  UPLOAD_MODE="appleid"
fi

if [ "$NO_UPLOAD" -eq 0 ] && [ -z "$UPLOAD_MODE" ]; then
  echo "HATA: Yükleme için ya ASC API key (ASC_KEY_ID+ASC_ISSUER_ID+ASC_KEY_PATH)" >&2
  echo "      ya da Apple ID (APPLE_ID+APPLE_APP_SPECIFIC_PASSWORD) gerekli." >&2
  echo "      Sırlar: ~/.lumi/mobile-tf.env. Sadece .ipa için --no-upload." >&2
  exit 1
fi
[ -n "$UPLOAD_MODE" ] && echo "▸ Upload modu: $UPLOAD_MODE"

# Otomatik provisioning için API anahtarı archive/export'a da geçilir (varsa).
AUTH_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ] && [ -f "${ASC_KEY_PATH:-/nonexistent}" ]; then
  AUTH_ARGS=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
else
  # Anahtar yoksa yalnızca otomatik güncellemeyi dene (--no-upload senaryosu).
  AUTH_ARGS=(-allowProvisioningUpdates)
fi

echo "▸ xcodegen generate…"
(cd "$MOBILE" && xcodegen generate >/dev/null)

echo "▸ Temiz build/ dizini…"
rm -rf "$MOBILE/build"

echo "▸ Archive…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  "${AUTH_ARGS[@]}"

echo "▸ Export .ipa…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  "${AUTH_ARGS[@]}"

# .ipa adı CFBundleName'e göre değişebilir → otomatik bul.
IPA="$(/bin/ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1 || true)"
if [ -z "$IPA" ]; then
  echo "HATA: Export sonrası .ipa bulunamadı ($EXPORT_DIR)." >&2
  exit 1
fi
echo "▸ .ipa: $IPA"

if [ "$NO_UPLOAD" -eq 1 ]; then
  echo "✓ Bitti (yükleme atlandı). .ipa: $IPA"
  exit 0
fi

echo "▸ TestFlight'a yükleniyor ($UPLOAD_MODE)…"
if [ "$UPLOAD_MODE" = "apikey" ]; then
  # altool anahtarı path'ten değil, AuthKey_<KEYID>.p8 adıyla bilinen dizinlerden arar.
  KEY_DIR="$HOME/.appstoreconnect/private_keys"
  mkdir -p "$KEY_DIR"
  cp -f "$ASC_KEY_PATH" "$KEY_DIR/AuthKey_$ASC_KEY_ID.p8"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  # Apple ID + app-specific password (Transporter yolu). Apple ID birden çok
  # takımdaysa provider kısaltması şart (`xcrun altool --list-providers -u … -p …`).
  PROVIDER_ARGS=()
  [ -n "${ASC_PROVIDER:-}" ] && PROVIDER_ARGS=(--asc-provider "$ASC_PROVIDER")
  xcrun altool --upload-app -f "$IPA" -t ios \
    -u "$APPLE_ID" -p "$APPLE_APP_SPECIFIC_PASSWORD" "${PROVIDER_ARGS[@]}"
fi

echo "✓ Yüklendi. TestFlight'ta işlenmesi birkaç dakika sürer → build $VERSION ($BUILD)."
