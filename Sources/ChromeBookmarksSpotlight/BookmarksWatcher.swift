import Foundation

/// Watches the Chrome profile directories and fires `onChange` (debounced) when
/// a `Bookmarks` file is rewritten. Chrome writes atomically via a temp file and
/// rename, so we watch the containing directory rather than the file inode.
final class BookmarksWatcher {

    private let queue = DispatchQueue(label: "com.rlm.ChromeBookmarksSpotlight.watcher")
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingWork: DispatchWorkItem?

    init(debounce: TimeInterval = 1.5, onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Starts watching the parent directories of the given `Bookmarks` files.
    func start(files: [URL]) {
        stop()
        let directories = Set(files.map { $0.deletingLastPathComponent().path })
        for directory in directories {
            let fd = open(directory, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.scheduleChange() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
