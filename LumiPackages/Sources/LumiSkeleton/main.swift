import AppKit
import Darwin

// Harness çıktısı dosyaya yönlendirildiğinde de satır satır aksın
setvbuf(stdout, nil, _IOLBF, 0)

let app = NSApplication.shared
let delegate = SkeletonAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
