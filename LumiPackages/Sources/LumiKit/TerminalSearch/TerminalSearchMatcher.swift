import Foundation

/// Terminal aramasının saf eşleştiricisi (karar 144). Mantıksal bir satırın
/// metninde sorgunun geçtiği yerleri UTF-16 aralıkları olarak döndürür;
/// aralıkların hücrelere eşlenmesi `LumiTerminal`'dedir.
public enum TerminalSearchMatcher {
    /// xterm `addon-search`'ün vurgu sınırı (Orca sayaçta `1000+` gösterir):
    /// sınır aşılınca tarama durur, toplam "en az" olarak raporlanır.
    public static let matchLimit = 1000

    /// Derlenmiş sorgu — her satırda yeniden derlenmesin diye bir kez kurulur.
    /// Geçersiz regex `nil` döner: Orca'da olduğu gibi "eşleşme yok" sayılır.
    public struct Compiled {
        fileprivate enum Kind {
            case literal(String, NSString.CompareOptions)
            case regex(NSRegularExpression)
        }

        fileprivate let kind: Kind
    }

    public static func compile(_ query: TerminalSearchQuery) -> Compiled? {
        guard let text = query.requestText else { return nil }
        guard query.isRegex else {
            let options: NSString.CompareOptions = query.isCaseSensitive ? [] : [.caseInsensitive]
            return Compiled(kind: .literal(text, options))
        }
        let options: NSRegularExpression.Options = query.isCaseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: text, options: options) else { return nil }
        return Compiled(kind: .regex(regex))
    }

    /// `line` içindeki eşleşmeler, soldan sağa, çakışmasız. Sıfır uzunluklu
    /// regex eşleşmeleri (`a*`, `^`) atlanır — vurgulanacak hücresi yoktur.
    /// `limit` dolunca durur.
    public static func ranges(in line: String, compiled: Compiled, limit: Int = matchLimit) -> [Range<Int>] {
        guard limit > 0, !line.isEmpty else { return [] }
        let nsLine = line as NSString
        let whole = NSRange(location: 0, length: nsLine.length)
        switch compiled.kind {
        case let .literal(text, options):
            return literalRanges(of: text, in: nsLine, whole: whole, options: options, limit: limit)
        case let .regex(regex):
            var result: [Range<Int>] = []
            regex.enumerateMatches(in: line, range: whole) { match, _, stop in
                guard let range = match?.range, range.location != NSNotFound, range.length > 0 else { return }
                result.append(range.location ..< range.location + range.length)
                if result.count >= limit { stop.pointee = true }
            }
            return result
        }
    }

    private static func literalRanges(
        of text: String,
        in line: NSString,
        whole: NSRange,
        options: NSString.CompareOptions,
        limit: Int
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var searchRange = whole
        while result.count < limit, searchRange.length > 0 {
            let found = line.range(of: text, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            result.append(found.location ..< found.location + found.length)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: whole.length - next)
        }
        return result
    }
}
