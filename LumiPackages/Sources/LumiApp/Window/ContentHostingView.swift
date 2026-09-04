import AppKit
import SwiftUI

/// Kök SwiftUI içeriğinin NSHostingView'ı. AppKit'in "titlebar bölgesinde
/// mouseDownCanMoveWindow = true olan view pencereyi sürükler" kuralını header
/// üstündeki content için kapatır. NOT: SwiftUI'nin kendi titlebar sürükleme
/// davranışı bundan bağımsızdır ve hosting içindeki her basışı kapsar — bu
/// yüzden tab etkileşimi hosting DIŞINDA (`TabStripInteractionView`).
final class ContentHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}
