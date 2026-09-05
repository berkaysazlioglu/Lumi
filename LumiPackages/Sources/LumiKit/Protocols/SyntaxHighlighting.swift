import AppKit
import Foundation

/// Sözdizimi vurgulama dikişi (design/03 §6): FileViewer yalnız bu protokole
/// bağlanır — Highlightr yetersiz kalırsa tree-sitter'a view'a dokunmadan geçilir.
///
/// Refactor 7.5: protokol LumiKit'te, tek implementasyonu (`HighlightrEngine`,
/// JSCore + DispatchQueue) LumiServices'te durur. View modülü artık ne
/// Highlightr paketini ne de bir arka plan kuyruğunu tanır.
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString
}
