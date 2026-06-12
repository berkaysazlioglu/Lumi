import AppKit
import Darwin

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
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
