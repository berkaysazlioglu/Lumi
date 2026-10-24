#!/bin/zsh
# Makinedeki Lumi.app kopyalarını bulur, seçilenleri çöp kutusuna taşır.
#
# Kullanım:
#   Scripts/clean-apps.sh              # bul → listele → seç → çöp kutusuna taşı
#   Scripts/clean-apps.sh --list       # sadece listele, hiçbir şey silme
#   Scripts/clean-apps.sh --all        # onay sonrası hepsini taşı
#   Scripts/clean-apps.sh --purge      # çöp kutusu yerine kalıcı sil (rm -rf)
#
# Arama Spotlight (mdfind, bundle id: com.lumi.app) + yaygın dizinlerde find ile
# yapılır; Spotlight kapalı/indekssiz konumlar da yakalanır.
#
# Yalnızca .app bundle'ları silinir. Kullanıcı verisi (~/.lumi/config.json,
# ui-state.json, hooks/ ve ~/Library/Preferences/com.lumi.app.plist) bundle'ın
# DIŞINDA durur; bu script onlara dokunmaz.
# Script zsh sözdizimi kullanır (dizi indeksleme, ${(@u)}). `sh`/`bash` ile
# çağrıldığında parse hatası vermesin diye kendini zsh altında yeniden başlatır.
if [ -z "${ZSH_VERSION:-}" ]; then
  exec /bin/zsh "$0" "$@"
fi

set -euo pipefail

BUNDLE_ID="com.lumi.app"
# make-rework-app.sh'in yan yana kurulan build'i de aynı aileden sayılır.
typeset -a BUNDLE_IDS
BUNDLE_IDS=("$BUNDLE_ID" "com.lumi.rework")
LIST_ONLY=0
SELECT_ALL=0
PURGE=0

for arg in "$@"; do
  case "$arg" in
    --list) LIST_ONLY=1 ;;
    --all) SELECT_ALL=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Bilinmeyen parametre: $arg (desteklenen: --list, --all, --purge)" >&2; exit 1 ;;
  esac
done

# --- Arama ------------------------------------------------------------------
echo "▸ Lumi.app kopyaları aranıyor…"

typeset -a found
found=()

for id in "${BUNDLE_IDS[@]}"; do
  while IFS= read -r p; do
    [ -n "$p" ] && found+=("$p")
  done < <(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null || true)
done

# Spotlight'ın atladığı yerler (indekslenmeyen build çıktıları, gizli
# ~/.lumi/updates altında bekleyen güncelleme, harici diskler).
typeset -a roots
roots=(
  "/Applications"
  "$HOME/Applications"
  "$HOME/Desktop"
  "$HOME/Downloads"
  "$HOME/wkspaces"
  "$HOME/lumi"
  "$HOME/.lumi/updates"
  "/Volumes"
)
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] && found+=("$p")
  done < <(find "$root" -maxdepth 6 -name "Lumi*.app" -type d -prune 2>/dev/null || true)
done

# Tekilleştir + gerçekten Lumi bundle'ı olduğunu doğrula. /Volumes/Data altındaki
# firmlink kopyaları (aynı bundle'ın ikinci yolu) gerçek yola indirgenir.
typeset -a apps
apps=()
for p in "${(@u)found}"; do
  p="${p#/System/Volumes/Data}"
  [ -d "$p" ] || continue
  [[ "$p" == *.app ]] || continue
  id="$(defaults read "$p/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "")"
  (( ${BUNDLE_IDS[(Ie)$id]} )) || continue
  apps+=("$p")
done
apps=("${(@u)apps}")

if [ ${#apps[@]} -eq 0 ]; then
  echo "Hiç Lumi.app bulunamadı."
  exit 0
fi

# --- Listeleme --------------------------------------------------------------
echo ""
i=1
for p in "${apps[@]}"; do
  ver="$(defaults read "$p/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
  size="$(du -sh "$p" 2>/dev/null | cut -f1 || echo "?")"
  mtime="$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$p" 2>/dev/null || echo "?")"
  note=""
  [[ "$p" == "$HOME/.lumi/updates/"* ]] && note=" · bekleyen güncelleme"
  pgrep -f "$p/Contents/MacOS/" >/dev/null 2>&1 && note="$note · ÇALIŞIYOR"
  printf "  %2d) %s\n      v%s · %s · %s%s\n" "$i" "$p" "$ver" "$size" "$mtime" "$note"
  i=$((i + 1))
done
echo ""

[ "$LIST_ONLY" -eq 1 ] && exit 0

# --- Seçim ------------------------------------------------------------------
typeset -a targets
targets=()

if [ "$SELECT_ALL" -eq 1 ]; then
  targets=("${apps[@]}")
else
  echo "Silinecekleri seç (örn: 1 3 4 · 'all' · boş bırak = vazgeç):"
  printf "> "
  read -r reply || reply=""
  [ -z "$reply" ] && { echo "Vazgeçildi."; exit 0; }
  if [ "$reply" = "all" ]; then
    targets=("${apps[@]}")
  else
    for tok in ${=reply}; do
      case "$tok" in
        ''|*[!0-9]*) echo "Geçersiz seçim: $tok" >&2; exit 1 ;;
      esac
      if [ "$tok" -lt 1 ] || [ "$tok" -gt ${#apps[@]} ]; then
        echo "Aralık dışı seçim: $tok" >&2; exit 1
      fi
      targets+=("${apps[$tok]}")
    done
  fi
fi

targets=("${(@u)targets}")
[ ${#targets[@]} -eq 0 ] && { echo "Vazgeçildi."; exit 0; }

# --- Onay -------------------------------------------------------------------
if [ "$PURGE" -eq 1 ]; then
  action="KALICI OLARAK SİLİNECEK"
else
  action="çöp kutusuna taşınacak"
fi

echo ""
echo "Şunlar $action:"
for p in "${targets[@]}"; do
  if pgrep -f "$p/Contents/MacOS/" >/dev/null 2>&1; then
    echo "  • $p  ⚠ şu an çalışıyor — önce kapatman önerilir"
  else
    echo "  • $p"
  fi
done
echo "(Ayarlar ~/.lumi ve ~/Library/Preferences altında; bunlara dokunulmaz.)"
printf "Onaylıyor musun? [y/N] "
read -r confirm || confirm=""
case "$confirm" in
  y|Y|yes|YES) ;;
  *) echo "Vazgeçildi."; exit 0 ;;
esac

# --- Silme ------------------------------------------------------------------
failed=0
for p in "${targets[@]}"; do
  if [ "$PURGE" -eq 1 ]; then
    if rm -rf "$p" 2>/dev/null; then
      echo "✓ silindi: $p"
    elif sudo rm -rf "$p"; then
      echo "✓ silindi (sudo): $p"
    else
      echo "✗ silinemedi: $p" >&2; failed=1
    fi
  else
    # Finder üzerinden taşımak, geri alınabilir bir çöp kutusu kaydı bırakır.
    if osascript -e "tell application \"Finder\" to delete POSIX file \"$p\"" >/dev/null 2>&1; then
      echo "✓ çöp kutusuna taşındı: $p"
    else
      echo "✗ taşınamadı (Finder izni?): $p" >&2; failed=1
    fi
  fi
done

exit $failed
