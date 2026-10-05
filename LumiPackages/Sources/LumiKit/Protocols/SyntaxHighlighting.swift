import AppKit
import Foundation

/// Sözdizimi vurgulama dikişi (design/03 §6): FileViewer yalnız bu protokole
/// bağlanır — highlight.js yetersiz kalırsa tree-sitter'a view'a dokunmadan geçilir.
///
/// Refactor 7.5: protokol LumiKit'te, tek implementasyonu (`HighlightJSEngine`,
/// JSCore + DispatchQueue) LumiServices'te durur. View modülü artık ne
/// JSCore'u ne de bir arka plan kuyruğunu tanır (karar 111: Highlightr sarmalayıcısı bırakıldı).
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString
}
