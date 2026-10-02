import Foundation
import LumiKit

/// Test için: verilen satırları `lines`'a yayan, yazılan stdin'i biriktiren
/// sahte streaming süreç. `emitAll()` scripted satırları sırayla verir.
public final class FakeStreamingProcess: StreamingProcessSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private var _handles: [FakeStreamingHandle] = []
    public var handles: [FakeStreamingHandle] { lock.lock(); defer { lock.unlock() }; return _handles }
    private var _spawns: [(executable: String, arguments: [String], currentDirectory: String?)] = []
    /// Her spawn'ın binary'si, argümanları ve CWD'si (bayrak testleri).
    public var spawns: [(executable: String, arguments: [String], currentDirectory: String?)] {
        lock.lock(); defer { lock.unlock() }; return _spawns
    }
    private let scriptedLines: [String]
    public init(scriptedLines: [String] = []) { self.scriptedLines = scriptedLines }

    public func spawn(executable: String, arguments: [String],
                      currentDirectory: String?, environment: [String: String]) -> any StreamingProcessHandle {
        let h = FakeStreamingHandle(scriptedLines: scriptedLines)
        lock.lock()
        _handles.append(h)
        _spawns.append((executable, arguments, currentDirectory))
        lock.unlock()
        return h
    }
}

public final class FakeStreamingHandle: StreamingProcessHandle, @unchecked Sendable {
    public let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    public private(set) var written: [String] = []
    private let scriptedLines: [String]

    public init(scriptedLines: [String]) {
        self.scriptedLines = scriptedLines
        (lines, continuation) = AsyncStream.makeStream(of: String.self)
    }
    /// Scripted satırları yayınlar ve stream'i bitirir (test kontrollü).
    public func emitAll() { for l in scriptedLines { continuation.yield(l) }; continuation.finish() }
    public func emit(_ line: String) { continuation.yield(line) }
    public func finish() { continuation.finish() }
    public func write(_ text: String) { written.append(text) }
    public func terminate() { continuation.finish() }
}
