import CoreServices
import Foundation

/// FSEvents tabanlı recursive dizin izleyicisi (spec/12 §12).
/// 500ms latency parametresi event fırtınalarını coalesce eder — Electron'daki
/// debounce'un FSEvents-doğal karşılığı (spec/12 Electron notu 2).
///
/// Path filtresi (karar 28): yalnız exclude'lu dizinlere (Unity `Library/`,
/// `node_modules/` …) düşen event batch'leri `onChange` tetiklemez; `.git`
/// hariç tutulmaz çünkü git panellerinin canlılığı ona bağlıdır.
final class RecursiveDirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let root: String
    private let excludedNames: Set<String>
    private let onChange: @Sendable () -> Void

    init?(
        path: String,
        latency: TimeInterval,
        queue: DispatchQueue,
        excludedNames: Set<String> = [],
        onChange: @escaping @Sendable () -> Void
    ) {
        self.root = path
        self.excludedNames = excludedNames
        self.onChange = onChange

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RecursiveDirectoryWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
            watcher.handle(eventPaths: eventPaths, count: count)
        }

        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            return nil
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    private func handle(eventPaths: UnsafeMutableRawPointer, count: Int) {
        // kFSEventStreamCreateFlagUseCFTypes → eventPaths bir CFArray<CFString>
        let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
        let paths = array.compactMap { $0 as? String }
        guard paths.count == count else {
            onChange() // beklenmedik biçim: güvenli taraf, tazele
            return
        }
        if Self.containsRelevantEvent(paths: paths, root: root, excludedNames: excludedNames) {
            onChange()
        }
    }

    static func containsRelevantEvent(paths: [String], root: String, excludedNames: Set<String>) -> Bool {
        paths.contains { isRelevantEvent(path: $0, root: root, excludedNames: excludedNames) }
    }

    /// Köke göre relative bileşenlerden herhangi biri exclude listesindeyse gürültü.
    /// Kökün kendisi veya kök dışı bir path (FSEvents kök bayrakları) daima ilgili.
    static func isRelevantEvent(path: String, root: String, excludedNames: Set<String>) -> Bool {
        guard !excludedNames.isEmpty else { return true }
        let normalizedRoot = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(normalizedRoot) else { return true }
        let relative = path.dropFirst(normalizedRoot.count)
        return !relative.split(separator: "/").contains { excludedNames.contains(String($0)) }
    }

    func cancel() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        cancel()
    }
}
