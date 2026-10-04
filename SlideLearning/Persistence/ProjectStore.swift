import Foundation

private struct RecentProjectsFile: Codable, Sendable {
    var projects: [ProjectSummary]
}

private func defaultSlideLearningRootURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Slide Learning", isDirectory: true)
}

/// The durable project library. The actor serializes this process's work;
/// NSFileCoordinator calls additionally serialize access with iCloud Drive and
/// other processes using the selected folder.
actor ProjectStore {
    private let localRootURL: URL
    private var activeRootURL: URL
    private let bookmarkStore: SecurityScopedBookmarkStore
    private var startedScopedAccessURL: URL?
    private var storageBlocked = false
    private(set) var sharedLibraryStatus: SharedLibraryStatus = .local

    private let validator: any PDFValidating
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootURL: URL = defaultSlideLearningRootURL(),
        validator: any PDFValidating = PDFKitValidator(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        bookmarkURL: URL? = nil
    ) {
        self.localRootURL = rootURL
        self.activeRootURL = rootURL
        self.bookmarkStore = SecurityScopedBookmarkStore(
            bookmarkURL: bookmarkURL ?? rootURL.appendingPathComponent(".shared-library.bookmark"),
            fileManager: fileManager
        )
        self.validator = validator
        self.fileManager = fileManager
        self.now = now
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Kept source-compatible for PDF workers and tests. It always reflects
    /// the currently selected library root.
    var rootURL: URL { activeRootURL }
    var projectsURL: URL { activeRootURL.appendingPathComponent("Projects", isDirectory: true) }
    var recentIndexURL: URL { activeRootURL.appendingPathComponent("recent-projects.json") }

    func currentSharedLibraryStatus() -> SharedLibraryStatus { sharedLibraryStatus }

    /// Persists the user's selected folder bookmark and migrates the local
    /// library by copy. The source library is never moved or removed.
    func selectSharedLibrary(at url: URL) async throws -> SharedLibraryStatus {
        // Keep the picker URL itself: rebuilding it can discard its security scope.
        let selectedURL = url
        let didStartAccessing = selectedURL.startAccessingSecurityScopedResource()
        guard selectedURL.isFileURL,
              fileManager.fileExists(atPath: selectedURL.path),
              (try? selectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            if didStartAccessing { selectedURL.stopAccessingSecurityScopedResource() }
            throw ProjectError.storageFailed("The selected shared library folder is unavailable.")
        }

        do {
            if selectedURL.standardizedFileURL == activeRootURL.standardizedFileURL {
                try bookmarkStore.save(for: selectedURL)
                if didStartAccessing {
                    stopScopedAccess()
                    startedScopedAccessURL = selectedURL
                }
                activeRootURL = selectedURL
                storageBlocked = false
                sharedLibraryStatus = .shared(selectedURL)
                return sharedLibraryStatus
            }

            let migrationSource = activeRootURL
            try migrateLibrary(from: migrationSource, to: selectedURL)
            try bookmarkStore.save(for: selectedURL)

            stopScopedAccess()
            activeRootURL = selectedURL
            startedScopedAccessURL = didStartAccessing ? selectedURL : nil
            storageBlocked = false
            sharedLibraryStatus = .shared(selectedURL)
            return sharedLibraryStatus
        } catch let error as ProjectError {
            if didStartAccessing { selectedURL.stopAccessingSecurityScopedResource() }
            throw error
        } catch {
            if didStartAccessing { selectedURL.stopAccessingSecurityScopedResource() }
            throw ProjectError.storageFailed("Could not prepare the shared library: \(error.localizedDescription)")
        }
    }

    /// Restores the previously selected folder. A stale bookmark is refreshed
    /// against the resolved URL. If a saved bookmark cannot be restored, the
    /// store becomes blocked instead of silently showing local data.
    func restoreSharedLibrary() async -> SharedLibraryStatus {
        guard fileManager.fileExists(atPath: bookmarkStore.bookmarkURL.path) else {
            sharedLibraryStatus = .needsSelection
            storageBlocked = false
            return sharedLibraryStatus
        }

        do {
            let resolved = try bookmarkStore.resolve()
            // Preserve the security scope carried by the resolved bookmark URL.
            let selectedURL = resolved.url
            let didStartAccessing = selectedURL.startAccessingSecurityScopedResource()
            do {
                guard selectedURL.isFileURL,
                      fileManager.fileExists(atPath: selectedURL.path),
                      (try? selectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: selectedURL.path])
                }

                if resolved.isStale {
                    try bookmarkStore.save(for: selectedURL)
                }
                stopScopedAccess()
                activeRootURL = selectedURL
                startedScopedAccessURL = didStartAccessing ? selectedURL : nil
                storageBlocked = false
                sharedLibraryStatus = .shared(selectedURL)
            } catch {
                if didStartAccessing { selectedURL.stopAccessingSecurityScopedResource() }
                throw error
            }
        } catch {
            storageBlocked = true
            sharedLibraryStatus = .unavailable(
                "The shared Slide Learning folder could not be restored. Select it again to continue."
            )
        }
        return sharedLibraryStatus
    }

    /// Removes only this device's bookmark and returns to its retained local
    /// library. Shared files are intentionally left untouched.
    func clearSharedLibrary() async {
        stopScopedAccess()
        if fileManager.fileExists(atPath: bookmarkStore.bookmarkURL.path) {
            try? fileManager.removeItem(at: bookmarkStore.bookmarkURL)
        }
        activeRootURL = localRootURL
        storageBlocked = false
        sharedLibraryStatus = .local
    }

    func createProject(from sourceURL: URL) async throws -> Project {
        try ensureStorageAvailable()
        do {
            try CoordinatedFileAccess.materializeIfNeeded(sourceURL, using: fileManager)
        } catch {
            throw ProjectError.invalidPDF
        }

        let validation: PDFValidationResult
        do {
            validation = try await validator.validate(sourceURL)
        } catch let error as ProjectError {
            throw error
        } catch {
            throw ProjectError.invalidPDF
        }
        guard validation.pageCount > 0 else { throw ProjectError.emptyPDF }

        let id = UUID()
        let timestamp = now()
        let projectName = sourceURL.deletingPathExtension().lastPathComponent
        let project = Project(
            id: id,
            name: projectName.isEmpty ? "Untitled Project" : projectName,
            sourceFilename: sourceURL.lastPathComponent,
            pageCount: validation.pageCount,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastOpenedAt: timestamp,
            viewPreferences: ViewPreferences(
                focusedPageIndex: validation.pageCount > 0 ? 0 : nil,
                inspectorVisible: true,
                thumbnailSize: .regular,
                filter: .all
            )
        )
        _ = try project.validated()

        let stagingURL = projectsURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let finalURL = projectDirectoryURL(id: id)
        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            let copiedSourceURL = stagingURL.appendingPathComponent("source.pdf")
            try CoordinatedFileAccess.copy(from: sourceURL, to: copiedSourceURL, using: fileManager)
            // Validate the managed copy as well as the caller's URL. This
            // protects against a truncated provider transfer becoming the
            // project's permanent source.
            let copiedValidation = try await validator.validate(copiedSourceURL)
            guard copiedValidation.pageCount == validation.pageCount else {
                throw ProjectError.invalidPDF
            }
            try writeProjectFile(project, in: stagingURL)
            try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
            try CoordinatedFileAccess.write(finalURL) { _ in
                try fileManager.moveItem(at: stagingURL, to: finalURL)
            }
            try updateRecentIndex(with: ProjectSummary(project: project))
            return project
        } catch let error as ProjectError {
            cleanup(stagingURL: stagingURL, finalURL: finalURL)
            throw error
        } catch {
            cleanup(stagingURL: stagingURL, finalURL: finalURL)
            throw ProjectError.importFailed(error.localizedDescription)
        }
    }

    func openProject(id: UUID) async throws -> Project {
        let loaded = try await loadProject(id: id)
        var opened = loaded
        opened.lastOpenedAt = now()
        do {
            try save(opened, expectedProject: loaded)
            return opened
        } catch let error as ProjectError {
            // Another process may have edited the project. Show the newest
            // state instead of replacing its actual edits.
            if case .storageFailed(let message) = error,
               message.contains("changed since it was opened") {
                return try await loadProject(id: id)
            }
            throw error
        }
    }

    func loadProject(id: UUID) async throws -> Project {
        try ensureStorageAvailable()
        let directory = projectDirectoryURL(id: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw ProjectError.projectUnavailable(.missingProject)
        }
        let source = sourceURL(id: id)
        guard fileManager.fileExists(atPath: source.path) else {
            throw ProjectError.projectUnavailable(.missingSource)
        }
        let project = try recoverProjectMetadata(id: id).project
        try await validateManagedSource(source, expectedPageCount: project.pageCount)
        return project
    }

    /// `expectedProject` is the last project version observed by the caller.
    /// A mismatch means another device/process has edited the project. Dirty
    /// local state is written to a conflict sidecar before the error is
    /// returned, so the user's notes remain recoverable.
    func save(_ project: Project, expectedProject: Project? = nil) throws {
        try ensureStorageAvailable()
        _ = try project.validated()
        let directory = projectDirectoryURL(id: project.id)
        let source = sourceURL(id: project.id)
        guard fileManager.fileExists(atPath: source.path) else {
            throw ProjectError.projectUnavailable(.missingSource)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var projectToSave = project
        let metadata = directory.appendingPathComponent("project.json")
        do {
            try CoordinatedFileAccess.write(metadata) { coordinatedMetadata in
                let current = readProjectMetadataUncoordinated(
                    id: project.id,
                    primaryURL: coordinatedMetadata,
                    allowBackup: true
                )
                if let expectedProject,
                   let current,
                   differsInDurableContent(current, from: expectedProject),
                   differsInDurableContent(current, from: project) {
                    let localIsDirty = differsMeaningfully(project, from: expectedProject)
                    if localIsDirty {
                        try writeConflictCopy(project, in: directory)
                    }
                    let message = localIsDirty
                        ? "Your edits were preserved in a conflict copy."
                        : "Reload it before saving again."
                    throw ProjectError.storageFailed("Project changed since it was opened. \(message)")
                }

                if let current {
                    // Opening a project updates only lastOpenedAt. Preserve a
                    // newer value written by another device without treating
                    // it as an edit to notes, selections, or preferences.
                    projectToSave.lastOpenedAt = max(projectToSave.lastOpenedAt, current.lastOpenedAt)
                }
                let encoded = try encoder.encode(projectToSave)
                try AtomicFileWriter.writeUncoordinated(encoded, to: coordinatedMetadata, using: fileManager)
            }
        } catch let error as ProjectError {
            throw error
        } catch {
            throw ProjectError.storageFailed("Could not save project: \(error.localizedDescription)")
        }
        try updateRecentIndex(with: ProjectSummary(project: projectToSave))
    }

    func listRecentProjects() async throws -> [ProjectSummary] {
        try ensureStorageAvailable()
        _ = try modifyRecentIndexLocked { reconcileRecentIndex(RecentProjectsFile(projects: $0)) }

        let index = try readRecentIndex()
        var refreshed: [ProjectSummary] = []
        refreshed.reserveCapacity(index.projects.count)
        for record in index.projects {
            refreshed.append(await refreshSummary(record))
        }

        let final = try modifyRecentIndexLocked { current in
            var merged = reconcileRecentIndex(RecentProjectsFile(projects: current))
            var byID = Dictionary(uniqueKeysWithValues: merged.projects.map { ($0.id, $0) })
            for summary in refreshed { byID[summary.id] = summary }
            merged.projects = Array(byID.values)
            return merged
        }
        return final.projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func deleteProject(id: UUID) throws {
        try ensureStorageAvailable()
        let directory = projectDirectoryURL(id: id)
        if fileManager.fileExists(atPath: directory.path) {
            do {
                try CoordinatedFileAccess.write(directory, options: [.forDeleting]) { _ in
                    try fileManager.removeItem(at: directory)
                }
            } catch {
                throw ProjectError.storageFailed("Could not delete the project: \(error.localizedDescription)")
            }
        }
        _ = try modifyRecentIndexLocked { index in
            var projects = index
            projects.removeAll { $0.id == id }
            return RecentProjectsFile(projects: projects)
        }
    }

    func sourceURL(id: UUID) -> URL { projectDirectoryURL(id: id).appendingPathComponent("source.pdf") }

    // MARK: - Shared-library migration

    private func migrateLibrary(from sourceRoot: URL, to targetRoot: URL) throws {
        let sourceProjects = sourceRoot.appendingPathComponent("Projects", isDirectory: true)
        let targetProjects = targetRoot.appendingPathComponent("Projects", isDirectory: true)
        try fileManager.createDirectory(at: targetProjects, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: sourceProjects.path) else {
            try rebuildRecentIndex(at: targetRoot)
            return
        }

        let folders = try fileManager.contentsOfDirectory(
            at: sourceProjects,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for sourceFolder in folders {
            guard (try? sourceFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !sourceFolder.lastPathComponent.hasPrefix(".staging-"),
                  let id = UUID(uuidString: sourceFolder.lastPathComponent) else { continue }

            let targetFolder = targetProjects.appendingPathComponent(id.uuidString, isDirectory: true)
            if !fileManager.fileExists(atPath: targetFolder.path) {
                try copyProjectFolder(from: sourceFolder, to: targetFolder, in: targetProjects)
                continue
            }

            let localProject = try? readProjectMetadata(at: sourceFolder, id: id)
            let sharedProject = try? readProjectMetadata(at: targetFolder, id: id)
            let sameSource = fileManager.contentsEqual(
                atPath: sourceFolder.appendingPathComponent("source.pdf").path,
                andPath: targetFolder.appendingPathComponent("source.pdf").path
            )
            if let localProject, let sharedProject, localProject == sharedProject, sameSource {
                continue
            }

            // Never overwrite a divergent shared project. Preserve the local
            // copy under a fresh ID so both devices' notes remain available.
            guard let localProject else { continue }
            let cloneID = UUID()
            let clone = Project(
                id: cloneID,
                name: "\(localProject.name) (Local Copy)",
                sourceFilename: localProject.sourceFilename,
                pageCount: localProject.pageCount,
                createdAt: localProject.createdAt,
                updatedAt: localProject.updatedAt,
                lastOpenedAt: localProject.lastOpenedAt,
                slides: localProject.slides,
                viewPreferences: localProject.viewPreferences
            )
            try copyProjectFolder(
                from: sourceFolder,
                to: targetProjects.appendingPathComponent(cloneID.uuidString, isDirectory: true),
                in: targetProjects,
                replacingMetadataWith: clone
            )
        }
        try rebuildRecentIndex(at: targetRoot)
    }

    private func copyProjectFolder(
        from sourceFolder: URL,
        to targetFolder: URL,
        in targetProjects: URL,
        replacingMetadataWith project: Project? = nil
    ) throws {
        let staging = targetProjects.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let source = sourceFolder.appendingPathComponent("source.pdf")
            let destination = staging.appendingPathComponent("source.pdf")
            guard fileManager.fileExists(atPath: source.path) else {
                throw ProjectError.projectUnavailable(.missingSource)
            }
            try CoordinatedFileAccess.copy(from: source, to: destination, using: fileManager)

            let sourceID = UUID(uuidString: sourceFolder.lastPathComponent)!
            let metadataProject = try project ?? readProjectMetadata(at: sourceFolder, id: sourceID)
            try writeProjectFile(metadataProject, in: staging)
            try CoordinatedFileAccess.write(targetFolder) { _ in
                try fileManager.moveItem(at: staging, to: targetFolder)
            }
        } catch {
            if fileManager.fileExists(atPath: staging.path) { try? fileManager.removeItem(at: staging) }
            throw error
        }
    }

    private func rebuildRecentIndex(at root: URL) throws {
        let indexURL = root.appendingPathComponent("recent-projects.json")
        let projectsRoot = root.appendingPathComponent("Projects", isDirectory: true)
        let existing = readRecentIndexUncoordinated(at: indexURL) ?? RecentProjectsFile(projects: [])
        let merged = reconcileRecentIndex(existing, projectsRoot: projectsRoot)
        do {
            try AtomicFileWriter.write(encoder.encode(merged), to: indexURL, using: fileManager)
        } catch {
            throw ProjectError.storageFailed("Could not save recent projects: \(error.localizedDescription)")
        }
    }

    // MARK: - Metadata and recent index

    private func projectDirectoryURL(id: UUID) -> URL {
        projectsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func metadataURL(id: UUID) -> URL {
        projectDirectoryURL(id: id).appendingPathComponent("project.json")
    }

    private func writeProjectFile(_ project: Project, in directory: URL) throws {
        let data = try encoder.encode(project)
        do {
            try AtomicFileWriter.write(data, to: directory.appendingPathComponent("project.json"), using: fileManager)
        } catch {
            throw ProjectError.storageFailed("Could not save project: \(error.localizedDescription)")
        }
    }

    private func readRecentIndex() throws -> RecentProjectsFile {
        let indexURL = recentIndexURL
        guard fileManager.fileExists(atPath: indexURL.path) else {
            if let backup = try? CoordinatedFileAccess.read(indexURL.appendingPathExtension("bak"), { try Data(contentsOf: $0) }),
               let recovered = try? decoder.decode(RecentProjectsFile.self, from: backup) {
                try? AtomicFileWriter.restore(backup, to: indexURL, using: fileManager)
                return recovered
            }
            return RecentProjectsFile(projects: [])
        }
        if let data = try? CoordinatedFileAccess.read(indexURL, { try Data(contentsOf: $0) }),
           let decoded = try? decoder.decode(RecentProjectsFile.self, from: data) {
            return decoded
        }
        let backupURL = indexURL.appendingPathExtension("bak")
        if let backup = try? CoordinatedFileAccess.read(backupURL, { try Data(contentsOf: $0) }),
           let recovered = try? decoder.decode(RecentProjectsFile.self, from: backup) {
            do { try AtomicFileWriter.restore(backup, to: indexURL, using: fileManager) }
            catch { throw ProjectError.storageFailed("Could not restore recent projects: \(error.localizedDescription)") }
            return recovered
        }
        // A corrupt index must not hide otherwise valid project folders;
        // listRecentProjects() reconciles those folders below.
        return RecentProjectsFile(projects: [])
    }

    private func readRecentIndexUncoordinated(at indexURL: URL) -> RecentProjectsFile? {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode(RecentProjectsFile.self, from: data) {
            return decoded
        }
        let backupURL = indexURL.appendingPathExtension("bak")
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? decoder.decode(RecentProjectsFile.self, from: data)
    }

    private func recoverProjectMetadata(id: UUID) throws -> (project: Project, recovered: Bool) {
        let primaryURL = metadataURL(id: id)
        let backupURL = primaryURL.appendingPathExtension("bak")
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            if let backup = try? CoordinatedFileAccess.read(backupURL, { try Data(contentsOf: $0) }),
               let recovered = try? decoder.decode(Project.self, from: backup).validated() {
                try? AtomicFileWriter.restore(backup, to: primaryURL, using: fileManager)
                return (recovered, true)
            }
            throw ProjectError.projectUnavailable(.unreadableMetadata)
        }
        if let data = try? CoordinatedFileAccess.read(primaryURL, { try Data(contentsOf: $0) }),
           let project = try? decoder.decode(Project.self, from: data).validated() {
            return (project, false)
        }
        if let backup = try? CoordinatedFileAccess.read(backupURL, { try Data(contentsOf: $0) }),
           let recovered = try? decoder.decode(Project.self, from: backup).validated() {
            do { try AtomicFileWriter.restore(backup, to: primaryURL, using: fileManager) }
            catch { throw ProjectError.projectUnavailable(.unreadableMetadata) }
            return (recovered, true)
        }
        throw ProjectError.projectUnavailable(.unreadableMetadata)
    }

    private func readProjectMetadata(at folder: URL, id: UUID) throws -> Project {
        let metadata = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: metadata),
              let project = try? decoder.decode(Project.self, from: data).validated(),
              project.id == id else {
            throw ProjectError.projectUnavailable(.unreadableMetadata)
        }
        return project
    }

    private func readProjectMetadataUncoordinated(
        id: UUID,
        primaryURL: URL,
        allowBackup: Bool
    ) -> Project? {
        if let data = try? Data(contentsOf: primaryURL),
           let project = try? decoder.decode(Project.self, from: data).validated(),
           project.id == id {
            return project
        }
        guard allowBackup else { return nil }
        let backupURL = primaryURL.appendingPathExtension("bak")
        guard let data = try? Data(contentsOf: backupURL),
              let project = try? decoder.decode(Project.self, from: data).validated(),
              project.id == id else { return nil }
        return project
    }

    private func differsMeaningfully(_ lhs: Project, from rhs: Project) -> Bool {
        // Dates are derived metadata, not user-editable project state. The
        // ISO-8601 encoder persists whole seconds while Date can retain
        // fractional seconds in memory, so comparing these values directly
        // creates a false conflict after an otherwise successful save.
        return differsInDurableContent(lhs, from: rhs)
            || lhs.viewPreferences != rhs.viewPreferences
    }

    private func differsInDurableContent(_ lhs: Project, from rhs: Project) -> Bool {
        // View preferences such as focus and panel visibility can race during
        // ordinary use. Last writer wins for those; notes and selection must
        // still be protected by the conflict copy path.
        return lhs.schemaVersion != rhs.schemaVersion
            || lhs.id != rhs.id
            || lhs.name != rhs.name
            || lhs.sourceFilename != rhs.sourceFilename
            || lhs.pageCount != rhs.pageCount
            || lhs.slides != rhs.slides
    }

    private func writeConflictCopy(_ project: Project, in directory: URL) throws {
        let name = "project.conflict-\(Int(now().timeIntervalSince1970))-\(UUID().uuidString).json"
        let url = directory.appendingPathComponent(name)
        do {
            try AtomicFileWriter.write(encoder.encode(project), to: url, using: fileManager)
        } catch {
            throw ProjectError.storageFailed("Project changed since it was opened and the local conflict copy could not be saved.")
        }
    }

    private func modifyRecentIndexLocked(
        _ mutation: ([ProjectSummary]) throws -> RecentProjectsFile
    ) throws -> RecentProjectsFile {
        let indexURL = recentIndexURL
        try fileManager.createDirectory(at: activeRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        do {
            return try CoordinatedFileAccess.write(indexURL) { coordinatedURL in
                let current = readRecentIndexUncoordinated(at: coordinatedURL) ?? RecentProjectsFile(projects: [])
                let updated = try mutation(current.projects)
                try AtomicFileWriter.writeUncoordinated(encoder.encode(updated), to: coordinatedURL, using: fileManager)
                return updated
            }
        } catch let error as ProjectError {
            throw error
        } catch {
            throw ProjectError.storageFailed("Could not save recent projects: \(error.localizedDescription)")
        }
    }

    private func updateRecentIndex(with summary: ProjectSummary) throws {
        _ = try modifyRecentIndexLocked { projects in
            var reconciled = reconcileRecentIndex(RecentProjectsFile(projects: projects))
            reconciled.projects.removeAll { $0.id == summary.id }
            reconciled.projects.append(summary)
            return reconciled
        }
    }

    private func reconcileRecentIndex(
        _ index: RecentProjectsFile,
        projectsRoot: URL? = nil
    ) -> RecentProjectsFile {
        let root = projectsRoot ?? projectsURL
        var byID = Dictionary(uniqueKeysWithValues: index.projects.map { ($0.id, $0) })
        guard fileManager.fileExists(atPath: root.path),
              let folders = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return RecentProjectsFile(projects: Array(byID.values))
        }
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let project = try? readProjectMetadata(at: folder, id: id) else { continue }
            var summary = ProjectSummary(project: project)
            summary.availability = fileManager.fileExists(atPath: folder.appendingPathComponent("source.pdf").path)
                ? .available
                : .missingSource
            byID[id] = summary
        }
        return RecentProjectsFile(projects: Array(byID.values))
    }

    // MARK: - Source validation and availability

    private func validateManagedSource(_ sourceURL: URL, expectedPageCount: Int) async throws {
        do {
            try CoordinatedFileAccess.materializeIfNeeded(sourceURL, using: fileManager)
            let validation = try await validator.validate(sourceURL)
            guard validation.pageCount == expectedPageCount else {
                throw ProjectError.projectUnavailable(.unreadableSource)
            }
        } catch let error as ProjectError {
            if case .projectUnavailable(.unreadableSource) = error { throw error }
            throw ProjectError.projectUnavailable(.unreadableSource)
        } catch {
            throw ProjectError.projectUnavailable(.unreadableSource)
        }
    }

    private func sourceAvailability(id: UUID, pageCount: Int) async -> ProjectAvailability {
        let source = sourceURL(id: id)
        guard fileManager.fileExists(atPath: source.path) else { return .missingSource }
        do {
            try await validateManagedSource(source, expectedPageCount: pageCount)
            return .available
        } catch let error as ProjectError {
            if case .projectUnavailable(let availability) = error { return availability }
            return .unreadableSource
        } catch { return .unreadableSource }
    }

    private func refreshSummary(_ record: ProjectSummary) async -> ProjectSummary {
        var result = record
        let directory = projectDirectoryURL(id: record.id)
        guard fileManager.fileExists(atPath: directory.path) else {
            result.availability = .missingProject
            return result
        }
        guard fileManager.fileExists(atPath: sourceURL(id: record.id).path) else {
            result.availability = .missingSource
            return result
        }
        let project: Project
        do { project = try recoverProjectMetadata(id: record.id).project }
        catch { result.availability = .unreadableMetadata; return result }
        result = ProjectSummary(project: project)
        result.availability = await sourceAvailability(id: record.id, pageCount: project.pageCount)
        return result
    }

    private func ensureStorageAvailable() throws {
        if storageBlocked {
            throw ProjectError.storageFailed(
                "The shared Slide Learning folder is unavailable. Select it again before accessing projects."
            )
        }
    }

    private func stopScopedAccess() {
        guard let startedScopedAccessURL else { return }
        startedScopedAccessURL.stopAccessingSecurityScopedResource()
        self.startedScopedAccessURL = nil
    }

    private func cleanup(stagingURL: URL, finalURL: URL) {
        if fileManager.fileExists(atPath: stagingURL.path) { try? fileManager.removeItem(at: stagingURL) }
        if fileManager.fileExists(atPath: finalURL.path) { try? fileManager.removeItem(at: finalURL) }
    }
}
