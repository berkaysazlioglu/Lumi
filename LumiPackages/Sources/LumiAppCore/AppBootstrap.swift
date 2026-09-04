import AppKit
import Darwin

/// Executable'ın TEK giriş noktası (`Sources/LumiApp/main.swift` yalnız bunu
/// çağırır). Uygulama kabuğu library target'ta (`LumiAppCore`) yaşar ki
/// `LumiAppTests` `@testable import` edebilsin — SPM executable target'ları
/// test target'ından import edilemez.
public enum AppBootstrap {
    /// `NSApplication.delegate` weak'tir; delegate'i process ömrü boyunca
    /// burada tutuyoruz (eski main.swift'te top-level `let` bu işi görüyordu).
    @MainActor private static var retainedDelegate: AppDelegate?

    @MainActor
    public static func run() {
        // Harness çıktısı dosyaya yönlendirildiğinde de satır satır aksın
        setvbuf(stdout, nil, _IOLBF, 0)

        // Font smoothing'i kapat (v1 paritesi): SwiftTerm draw'da macOS'a özgü
        // setShouldSmoothFonts(true) hardcoded — koyu zeminde yazıyı kalınlaştırıp
        // "glow" hissi veriyor. CoreGraphics bu process-default'u okuyup per-context
        // çağrıyı geçersiz kılar; Electron'un grayscale AA'sına denk gelir. Herhangi
        // bir çizimden ÖNCE ayarlanmalı.
        UserDefaults.standard.set(true, forKey: "CGFontRenderingFontSmoothingDisabled")

        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
