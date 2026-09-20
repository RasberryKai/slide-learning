import Foundation

private struct RecentProjectsFile: Codable, Sendable {
    var projects: [ProjectSummary]
}

actor ProjectStore {
    let rootURL: URL
    private let validator: any PDFValidating
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slide Learning", isDirectory: true),
        validator: any PDFValidating = PDFKitValidator(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
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

    var projectsURL: URL { rootURL.appendingPathComponent("Projects", isDirectory: true) }
    var recentIndexURL: URL { rootURL.appendingPathComponent("recent-projects.json") }

    func createProject(from sourceURL: URL) async throws -> Project {
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
            try fileManager.copyItem(at: sourceURL, to: copiedSourceURL)
            // Validate the managed copy as well as the caller's URL. This
            // protects against a truncated or otherwise incomplete copy
            // becoming the project's permanent source.
            let copiedValidation = try await validator.validate(copiedSourceURL)
            guard copiedValidation.pageCount == validation.pageCount else {
                throw ProjectError.invalidPDF
            }
            try writeProjectFile(project, in: stagingURL)
            try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
            try fileManager.moveItem(at: stagingURL, to: finalURL)
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
        var project = try await loadProject(id: id)
        project.lastOpenedAt = now()
        try save(project)
        return project
    }

    func loadProject(id: UUID) async throws -> Project {
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

    func save(_ project: Project) throws {
        _ = try project.validated()
        let directory = projectDirectoryURL(id: project.id)
        guard fileManager.fileExists(atPath: sourceURL(id: project.id).path) else {
            throw ProjectError.projectUnavailable(.missingSource)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeProjectFile(project, in: directory)
        try updateRecentIndex(with: ProjectSummary(project: project))
    }

    func listRecentProjects() async throws -> [ProjectSummary] {
        var index = try readRecentIndex()
        let indexedIDs = Set(index.projects.map(\.id))
        var changed = false
        if fileManager.fileExists(atPath: projectsURL.path),
           let directories = try? fileManager.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for directory in directories {
                guard !directory.lastPathComponent.hasPrefix(".staging-"),
                      let id = UUID(uuidString: directory.lastPathComponent),
                      !indexedIDs.contains(id) else { continue }
                guard let project = try? recoverProjectMetadata(id: id).project else { continue }
                var discovered = ProjectSummary(project: project)
                discovered.availability = await sourceAvailability(id: id, pageCount: project.pageCount)
                index.projects.append(discovered)
                changed = true
            }
        }

        var refreshed: [ProjectSummary] = []
        refreshed.reserveCapacity(index.projects.count)
        for record in index.projects {
            refreshed.append(await refreshSummary(record))
        }
        if changed || refreshed != index.projects {
            index.projects = refreshed
            try writeRecentIndex(index)
        }
        return refreshed.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func deleteProject(id: UUID) throws {
        let directory = projectDirectoryURL(id: id)
        if fileManager.fileExists(atPath: directory.path) {
            do { try fileManager.removeItem(at: directory) }
            catch { throw ProjectError.storageFailed("Could not delete the project: \(error.localizedDescription)") }
        }
        var index = try readRecentIndex()
        index.projects.removeAll { $0.id == id }
        try writeRecentIndex(index)
    }

    func sourceURL(id: UUID) -> URL { projectDirectoryURL(id: id).appendingPathComponent("source.pdf") }

    private func projectDirectoryURL(id: UUID) -> URL { projectsURL.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func metadataURL(id: UUID) -> URL { projectDirectoryURL(id: id).appendingPathComponent("project.json") }

    private func writeProjectFile(_ project: Project, in directory: URL) throws {
        let data = try encoder.encode(project)
        do { try AtomicFileWriter.write(data, to: directory.appendingPathComponent("project.json"), using: fileManager) }
        catch { throw ProjectError.storageFailed("Could not save project: \(error.localizedDescription)") }
    }

    private func readRecentIndex() throws -> RecentProjectsFile {
        guard fileManager.fileExists(atPath: recentIndexURL.path) else {
            if let backup = try? Data(contentsOf: recentIndexURL.appendingPathExtension("bak")),
               let recovered = try? decoder.decode(RecentProjectsFile.self, from: backup) {
                try? AtomicFileWriter.restore(backup, to: recentIndexURL, using: fileManager)
                return recovered
            }
            return RecentProjectsFile(projects: [])
        }
        do {
            return try decoder.decode(RecentProjectsFile.self, from: Data(contentsOf: recentIndexURL))
        } catch {
            let backupURL = recentIndexURL.appendingPathExtension("bak")
            if let backup = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(RecentProjectsFile.self, from: backup) {
                do { try AtomicFileWriter.restore(backup, to: recentIndexURL, using: fileManager) }
                catch { throw ProjectError.storageFailed("Could not restore recent projects: \(error.localizedDescription)") }
                return recovered
            }
            // A corrupt index should not hide otherwise valid project folders;
            // listRecentProjects() reconciles those folders below.
            return RecentProjectsFile(projects: [])
        }
    }

    private func recoverProjectMetadata(id: UUID) throws -> (project: Project, recovered: Bool) {
        let primaryURL = metadataURL(id: id)
        let backupURL = primaryURL.appendingPathExtension("bak")
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            if let backup = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(Project.self, from: backup).validated() {
                try? AtomicFileWriter.restore(backup, to: primaryURL, using: fileManager)
                return (recovered, true)
            }
            throw ProjectError.projectUnavailable(.unreadableMetadata)
        }
        if let project = try? decoder.decode(Project.self, from: Data(contentsOf: primaryURL)).validated() {
            return (project, false)
        }
        if let backup = try? Data(contentsOf: backupURL),
           let recovered = try? decoder.decode(Project.self, from: backup).validated() {
            do { try AtomicFileWriter.restore(backup, to: primaryURL, using: fileManager) }
            catch { throw ProjectError.projectUnavailable(.unreadableMetadata) }
            return (recovered, true)
        }
        throw ProjectError.projectUnavailable(.unreadableMetadata)
    }

    private func validateManagedSource(_ sourceURL: URL, expectedPageCount: Int) async throws {
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw ProjectError.projectUnavailable(.unreadableSource)
        }
        do {
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

    private func updateRecentIndex(with summary: ProjectSummary) throws {
        var index = try readRecentIndex()
        index.projects.removeAll { $0.id == summary.id }
        index.projects.append(summary)
        try writeRecentIndex(index)
    }

    private func writeRecentIndex(_ index: RecentProjectsFile) throws {
        do { try AtomicFileWriter.write(encoder.encode(index), to: recentIndexURL, using: fileManager) }
        catch { throw ProjectError.storageFailed("Could not save recent projects: \(error.localizedDescription)") }
    }

    private func cleanup(stagingURL: URL, finalURL: URL) {
        if fileManager.fileExists(atPath: stagingURL.path) { try? fileManager.removeItem(at: stagingURL) }
        if fileManager.fileExists(atPath: finalURL.path) { try? fileManager.removeItem(at: finalURL) }
    }
}
