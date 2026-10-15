import Foundation

/// Lumi kapandıktan sonra sahnelenmiş sürümü yerine kuran script ve onu
/// koşturan tek seferlik LaunchAgent (karar 118).
///
/// `Scripts/install-on-quit.sh`'ın (karar 64) uygulamaya taşınmış hâli. Oradan
/// gelen dersler aynen geçerli: süreç launchd'ye devredilir (Lumi'nin çocuğu
/// olarak kalan bir süreç kapanışta ölebilir), launchd ortamı dar olduğu için
/// yalnız mutlak yollar kullanılır ve stdout/stderr bir log dosyasına bağlanır.
///
/// Farkları:
/// - Lumi'yi `ps` ile aramaz, kendi PID'ini bekler.
/// - Kurulumdan hemen önce sahneyi Developer ID gereksinimiyle YENİDEN
///   doğrular: sahne kullanıcının yazabildiği `~/.lumi` altında saatlerce
///   bekleyebilir.
/// - Uygulama hiçbir anda yok kalmaz: uzun süren kopya önce yanına
///   (`.incoming-`) yapılır, değiş-tokuş iki `mv`'dir; kesilirse (`trap`) ya
///   da başarısız olursa eski sürüm geri konur.
/// - Plist `~/Library/LaunchAgents`'ta DEĞİL `~/.lumi/updates`'tedir: kesilen
///   bir kurulum bir sonraki login'de bayat argümanlarla yeniden koşmaz.
enum AppUpdateInstallScript {
    static let label = "com.lumi.app-update"

    /// Lumi'nin kapanmasını bekleme sınırı. Kapanış onaylanmış bir quit'in
    /// içinden planlandığı için saniyeler sürer; sınır asılı kalmış bir
    /// sürecin agent'ı sonsuza dek tutmasını engeller.
    static let maxWaitSeconds = 600

    /// Argümanlar: `PID SRC TARGET RELAUNCH(0|1) LABEL PLIST STAGING FAILURE
    /// REQUIREMENT`. `LABEL` boşsa agent kendini kaldırmaz, `REQUIREMENT`
    /// boşsa imza kontrolü atlanır — ikisi de yalnız testler içindir
    /// (launchd dışında, imzasız fixture'la koşarlar).
    static let source = """
    #!/bin/bash
    # Lumi güncelleme kurucusu (karar 118) — Lumi'nin LaunchAgent'ı olarak koşar.
    set -u
    PID="$1"; SRC="$2"; TARGET="$3"; RELAUNCH="$4"
    LABEL="$5"; PLIST="$6"; STAGING="$7"; FAILURE="$8"; REQUIREMENT="$9"
    MAX_TICKS=\(maxWaitSeconds * 2)
    INCOMING="${TARGET%.app}.incoming-$$.app"
    BACKUP="${TARGET%.app}.previous-$$.app"

    log() { echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*"; }
    fail() { log "FAILED: $1"; printf '%s\\n' "$1" > "$FAILURE"; }
    relaunch() {
      if [ "$RELAUNCH" = "1" ] && [ -e "$TARGET" ]; then
        /usr/bin/open "$TARGET" || log "could not reopen $TARGET"
      fi
    }
    finish() {
      /bin/rm -f "$PLIST"
      # Kendini launchd'den düşürmek bu süreci de bitirir — en son adım.
      if [ -n "$LABEL" ]; then
        /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$LABEL" >/dev/null 2>&1
      fi
      exit "$1"
    }
    # Değiş-tokuş ortasında kesilirse (logout/kapatma SIGTERM'i) eskisi geri gelir.
    restore() {
      if [ ! -e "$TARGET" ] && [ -e "$BACKUP" ]; then
        /bin/mv "$BACKUP" "$TARGET" || log "could not restore $BACKUP"
      fi
      /bin/rm -rf "$INCOMING"
    }
    interrupted() {
      restore
      fail "The update was interrupted; the previous version was kept"
      finish 1
    }

    log "waiting for Lumi (pid $PID) to quit"
    ticks=0
    while /bin/kill -0 "$PID" 2>/dev/null; do
      if [ "$ticks" -ge "$MAX_TICKS" ]; then
        fail "Lumi did not quit within \(maxWaitSeconds) seconds"
        finish 1
      fi
      /bin/sleep 0.5
      ticks=$((ticks + 1))
    done

    if [ ! -d "$SRC" ]; then
      fail "The downloaded update is missing ($SRC)"
      relaunch
      finish 1
    fi
    if [ -n "$REQUIREMENT" ] && ! /usr/bin/codesign --verify --deep --strict -R="$REQUIREMENT" "$SRC"; then
      fail "The downloaded update failed signature verification"
      relaunch
      finish 1
    fi

    trap interrupted TERM HUP INT
    if ! /usr/bin/ditto "$SRC" "$INCOMING"; then
      /bin/rm -rf "$INCOMING"
      fail "Copying the new version failed; Lumi was not changed"
    elif [ -e "$TARGET" ] && ! /bin/mv "$TARGET" "$BACKUP"; then
      /bin/rm -rf "$INCOMING"
      fail "Could not move the current Lumi aside ($TARGET)"
    elif /bin/mv "$INCOMING" "$TARGET"; then
      trap - TERM HUP INT
      /bin/rm -rf "$BACKUP" "$STAGING"
      /bin/rm -f "$FAILURE"
      log "installed $TARGET"
    else
      restore
      fail "Could not put the new version in place; the previous version was restored"
    fi
    trap - TERM HUP INT

    relaunch
    finish 0
    """

    static func plist(script: String, arguments: [String], logPath: String) -> Data {
        let dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", script] + arguments,
            "RunAtLoad": true,
            "KeepAlive": false,
            // Script'in kendi log satırları ve launchd'nin göremediği erken
            // ölümler (karar 64'te yaşandı) aynı dosyaya düşer.
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        // Sabit, geçerli bir sözlük — serileştirme başarısız olamaz.
        return (try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)) ?? Data()
    }
}
