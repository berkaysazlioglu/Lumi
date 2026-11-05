import AppKit
import Darwin
import LumiKit
import os

/// Executable'ın TEK giriş noktası (`Sources/LumiApp/main.swift` yalnız bunu
/// çağırır). Uygulama kabuğu library target'ta (`LumiAppCore`) yaşar ki
/// `LumiAppTests` `@testable import` edebilsin — SPM executable target'ları
/// test target'ından import edilemez.
public enum AppBootstrap {
    /// `NSApplication.delegate` weak'tir; delegate'i process ömrü boyunca
    /// burada tutuyoruz (eski main.swift'te top-level `let` bu işi görüyordu).
    @MainActor private static var retainedDelegate: AppDelegate?

    /// `LumiPaths.Mode` seçimi refactor 3.2'de `AppContainer`'dan buraya taşındı:
    /// composition root artık modu PARAMETRE olarak alır, `#if DEBUG` yalnız
    /// executable'ın girişinde kalır (test edilebilir bir değer olur).
    public static var defaultPathsMode: LumiPaths.Mode {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    @MainActor
    public static func run() {
        // Harness çıktısı dosyaya yönlendirildiğinde de satır satır aksın
        setvbuf(stdout, nil, _IOLBF, 0)
        redirectStandardErrorIfDetached(paths: LumiPaths.app(mode: defaultPathsMode))

        // Font smoothing'i kapat (v1 paritesi): SwiftTerm draw'da macOS'a özgü
        // setShouldSmoothFonts(true) hardcoded — koyu zeminde yazıyı kalınlaştırıp
        // "glow" hissi veriyor. CoreGraphics bu process-default'u okuyup per-context
        // çağrıyı geçersiz kılar; Electron'un grayscale AA'sına denk gelir. Herhangi
        // bir çizimden ÖNCE ayarlanmalı.
        UserDefaults.standard.set(true, forKey: "CGFontRenderingFontSmoothingDisabled")

        let app = NSApplication.shared
        let delegate = AppDelegate(pathsMode: defaultPathsMode)
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    /// Karar 83: Finder/`open` ile başlatılan bundle'ın stderr'i /dev/null'dur;
    /// AppKit'in YUTTUĞU ObjC exception raporları (NSLog → stderr) orada
    /// kaybolur. stderr bir TTY değilse `<configDir>/logs/stderr.log`'a
    /// yönlendirilir (append; 5 MB üstünde bir önceki dosya `stderr.1.log`
    /// olarak döndürülür). `swift run` gibi TTY'li başlatmalar dokunulmaz.
    static func redirectStandardErrorIfDetached(paths: LumiPaths) {
        guard isatty(STDERR_FILENO) == 0 else { return }
        let logger = LumiLog.logger("lifecycle")
        let fileManager = FileManager.default
        let logsDir = paths.configDir.appendingPathComponent("logs")
        do {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            logger.log("stderr redirect skipped: \(error.localizedDescription, privacy: .public)")
            return
        }
        let target = logsDir.appendingPathComponent("stderr.log")
        let rotateThreshold: UInt64 = 5_000_000
        if let size = (try? fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.uint64Value,
           size > rotateThreshold {
            let rotated = logsDir.appendingPathComponent("stderr.1.log")
            try? fileManager.removeItem(at: rotated)
            try? fileManager.moveItem(at: target, to: rotated)
        }
        let fd = open(target.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else {
            logger.log("stderr redirect skipped: open failed errno \(errno)")
            return
        }
        dup2(fd, STDERR_FILENO)
        close(fd)
        fputs("\n=== Lumi started \(Date()) pid \(getpid()) ===\n", stderr)
        logger.log("stderr → \(target.path, privacy: .public)")
    }
}
