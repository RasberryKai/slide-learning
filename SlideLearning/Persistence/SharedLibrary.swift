import Foundation

/// Describes which project library is currently active.
///
/// A shared location is deliberately reported as unavailable when its
/// security-scoped bookmark cannot be restored. Falling back to the local
/// library in that situation would make it look as if shared projects had
/// disappeared.
enum SharedLibraryStatus: Equatable, Sendable {
    case local
    case shared(URL)
    case needsSelection
    case unavailable(String)

    var sharedURL: URL? {
        guard case .shared(let url) = self else { return nil }
        return url
    }

    var isShared: Bool { sharedURL != nil }
}

enum CoordinatedFileAccess {
    /// Performs a synchronous coordinated read. The accessor must finish all
    /// file I/O before it returns; this is required for iCloud/File Provider
    /// URLs because the coordinator owns the access window.
    static func read<T>(
        _ url: URL,
        options: NSFileCoordinator.ReadingOptions = [],
        _ accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do {
                result = .success(try accessor(coordinatedURL))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "The coordinated read did not receive access to the file."
            ])
        }
        return try result.get()
    }

    /// Performs a synchronous coordinated write. AtomicFileWriter is used
    /// inside this accessor so a failed write leaves the last good metadata
    /// file and its backup in place.
    static func write<T>(
        _ url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            do {
                result = .success(try accessor(coordinatedURL))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "The coordinated write did not receive access to the file."
            ])
        }
        return try result.get()
    }

    /// Coordinates a copy between a source and destination. This is used for
    /// imports and migration so a provider can move the source into memory
    /// before the destination is committed.
    static func copy(
        from sourceURL: URL,
        to destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessorError: NSError?
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
            options: [],
            error: &coordinationError
        ) { coordinatedSourceURL, coordinatedDestinationURL in
            do {
                try fileManager.copyItem(at: coordinatedSourceURL, to: coordinatedDestinationURL)
            } catch {
                accessorError = error as NSError
            }
        }
        if let coordinationError { throw coordinationError }
        if let accessorError { throw accessorError }
    }

    /// Gives iCloud Drive/File Provider a chance to materialize a placeholder
    /// before a validator or PDF worker opens it. A coordinated read is also
    /// useful here because the provider owns the transfer window.
    static func materializeIfNeeded(
        _ url: URL,
        using fileManager: FileManager = .default
    ) throws {
        if let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]), values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }

        try read(url) { coordinatedURL in
            guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: coordinatedURL.path])
            }
            return ()
        }
    }
}

struct SecurityScopedBookmarkStore {
    let bookmarkURL: URL
    private let fileManager: FileManager

    init(bookmarkURL: URL, fileManager: FileManager = .default) {
        self.bookmarkURL = bookmarkURL
        self.fileManager = fileManager
    }

    func save(for url: URL) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        // iOS picker URLs carry an implicit security scope in their bookmark.
        // A minimal bookmark may omit the information needed to restore it.
        let options: URL.BookmarkCreationOptions = []
        #endif
        let data = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try AtomicFileWriter.write(data, to: bookmarkURL, using: fileManager)
    }

    func resolve() throws -> (url: URL, isStale: Bool) {
        guard fileManager.fileExists(atPath: bookmarkURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: bookmarkURL.path])
        }
        let data = try CoordinatedFileAccess.read(bookmarkURL) { try Data(contentsOf: $0) }
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}
