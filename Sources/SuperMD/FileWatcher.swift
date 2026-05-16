import Foundation
import Combine
import Darwin
import CoreServices

/// Watches a single file path for external changes (writes, atomic-save
/// replaces, deletes). Editors commonly save by writing to a temp file and
/// renaming over the original, which unlinks the watched inode — so we
/// treat `.delete` / `.rename` as "re-open the path and keep watching."
///
/// Emits on the `changed` publisher (main queue) for each detected change.
@MainActor
final class FileWatcher: ObservableObject {
    let changed = PassthroughSubject<URL, Never>()

    private var source: DispatchSourceFileSystemObject?
    private var currentURL: URL?

    func watch(_ url: URL?) {
        stop()
        guard let url else { return }
        currentURL = url
        start(url: url)
    }

    func stop() {
        currentURL = nil
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }

    private func start(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .link],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            // Atomic save: editor swapped the file out from under us. Reopen
            // on the path so subsequent saves still fire.
            if mask.contains(.delete) || mask.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, let url = self.currentURL else { return }
                    self.source?.cancel()
                    self.source = nil
                    self.start(url: url)
                    self.changed.send(url)
                }
                return
            }
            self.changed.send(url)
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        src.resume()
        source = src
    }
}

/// Watches a set of directory roots (recursively) via FSEvents and emits on
/// `changed` whenever anything inside them is added, removed, or renamed. The
/// FileBrowser uses this to live-refresh its tree when files appear from
/// outside the app (or another window).
@MainActor
final class FolderWatcher: ObservableObject {
    let changed = PassthroughSubject<Void, Never>()

    private var stream: FSEventStreamRef?

    func watch(_ urls: [URL]) {
        stop()
        let paths = urls.map(\.path)
        guard !paths.isEmpty else { return }

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                watcher.changed.send()
            }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
