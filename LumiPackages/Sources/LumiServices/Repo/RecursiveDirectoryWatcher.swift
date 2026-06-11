import CoreServices
import Foundation

/// FSEvents tabanlı recursive dizin izleyicisi (spec/12 §12).
/// 500ms latency parametresi event fırtınalarını coalesce eder — Electron'daki
/// debounce'un FSEvents-doğal karşılığı (spec/12 Electron notu 2).
final class RecursiveDirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable () -> Void

    init?(
        path: String,
        latency: TimeInterval,
        queue: DispatchQueue,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.onChange = onChange

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RecursiveDirectoryWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
            watcher.onChange()
        }

        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return nil
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
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
