import Darwin
import Foundation

/// Tek dizinlik, debounce'lu dosya sistemi izleyicisi (spec/12 §watcher).
/// Non-recursive: dizinin kendi girdi listesi değişince tetiklenir
/// (kök dizin izleme için yeterli — repo ekleme/silme).
final class DirectoryWatcher: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject
    private let queue: DispatchQueue
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private var pending: DispatchWorkItem? // queue-confined

    init?(
        path: String,
        queue: DispatchQueue,
        debounce: TimeInterval,
        onChange: @escaping @Sendable () -> Void
    ) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        self.fileDescriptor = descriptor
        self.queue = queue
        self.debounce = debounce
        self.onChange = onChange
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleCallback()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.activate()
    }

    private func scheduleCallback() {
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in
            onChange()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    func cancel() {
        source.cancel()
    }

    deinit {
        if !source.isCancelled {
            source.cancel()
        }
    }
}
