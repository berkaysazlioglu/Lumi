public struct ExplorerContentMatch: Sendable, Equatable, Identifiable {
    public var id: String { "\(path):\(line)" }
    public let path: String
    public let line: Int
    public let text: String

    public init(path: String, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }
}

public struct ExplorerContentResult: Sendable, Equatable {
    public let matches: [ExplorerContentMatch]
    public let isLimited: Bool

    public init(matches: [ExplorerContentMatch] = [], isLimited: Bool = false) {
        self.matches = matches
        self.isLimited = isLimited
    }
}
