import Foundation
import XCTest
#if os(iOS)
@testable import SlideLearningIPad
#else
@testable import SlideLearning
#endif

final class ProjectFoundationTests: XCTestCase {
    func testFocusAndSelectionAreIndependent() {
        var project = Project(name: "Deck", sourceFilename: "deck.pdf", pageCount: 3)
        ProjectReducer.reduce(&project, action: .focus(pageIndex: 1))
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 1)
        XCTAssertFalse(project.slides[1].isSelected)

        ProjectReducer.reduce(&project, action: .toggleFocusedSelection)
        XCTAssertTrue(project.slides[1].isSelected)
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 1)
    }

    func testNoteSelectsOnlyWhenMeaningfulAndClearingPreservesSelection() {
        var project = Project(name: "Deck", sourceFilename: "deck.pdf", pageCount: 2)
        ProjectReducer.reduce(&project, action: .updateNote(pageIndex: 0, text: "  \n"))
        XCTAssertFalse(project.slides[0].isSelected)
        ProjectReducer.reduce(&project, action: .updateNote(pageIndex: 0, text: "Context"))
        XCTAssertTrue(project.slides[0].isSelected)
        ProjectReducer.reduce(&project, action: .updateNote(pageIndex: 0, text: ""))
        XCTAssertTrue(project.slides[0].note.isEmpty)
        XCTAssertTrue(project.slides[0].isSelected)
    }

    func testSelectedFilterDeselectsFocusedSlideToNextThenPrevious() {
        var project = Project(
            name: "Deck",
            sourceFilename: "deck.pdf",
            pageCount: 4,
            slides: (0..<4).map { SlideState(pageIndex: $0, isSelected: $0 != 3, note: "") },
            viewPreferences: ViewPreferences(focusedPageIndex: 1, inspectorVisible: true, thumbnailSize: .regular, filter: .selected)
        )
        ProjectReducer.reduce(&project, action: .setSelection(pageIndex: 1, selected: false))
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 2)
        ProjectReducer.reduce(&project, action: .setSelection(pageIndex: 2, selected: false))
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 0)
        ProjectReducer.reduce(&project, action: .setSelection(pageIndex: 0, selected: false))
        XCTAssertNil(project.viewPreferences.focusedPageIndex)
    }

    func testArrowFocusUsesSourceOrderInSelectedFilter() {
        var project = Project(
            name: "Deck", sourceFilename: "deck.pdf", pageCount: 5,
            slides: (0..<5).map { SlideState(pageIndex: $0, isSelected: $0 % 2 == 0, note: "") },
            viewPreferences: ViewPreferences(focusedPageIndex: 0, inspectorVisible: true, thumbnailSize: .regular, filter: .selected)
        )
        ProjectReducer.reduce(&project, action: .moveFocus(.next))
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 2)
        ProjectReducer.reduce(&project, action: .moveFocus(.next))
        XCTAssertEqual(project.viewPreferences.focusedPageIndex, 4)
    }
}

final class ProjectStoreTests: XCTestCase {
    private final class Validator: PDFValidating, @unchecked Sendable {
        let pages: Int
        init(pages: Int) { self.pages = pages }
        func validate(_ url: URL) async throws -> PDFValidationResult {
            guard pages > 0 else { throw ProjectError.emptyPDF }
            return PDFValidationResult(pageCount: pages)
        }
    }

    private func makeStore(
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> (ProjectStore, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("lecture.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        return (
            ProjectStore(
                rootURL: root.appendingPathComponent("library"),
                validator: Validator(pages: 3),
                now: { timestamp }
            ),
            root,
            source
        )
    }

    func testFractionalTimestampDoesNotCreateFalseConflictOnConsecutiveSaves() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.987_654)
        let (store, root, source) = try makeStore(timestamp: timestamp)
        let original = try await store.createProject(from: source)

        var firstEdit = original
        firstEdit.slides[0].note = "First edit"
        firstEdit.updatedAt = timestamp.addingTimeInterval(0.1)
        try await store.save(firstEdit, expectedProject: original)

        var secondEdit = firstEdit
        secondEdit.slides[1].note = "Second edit"
        secondEdit.updatedAt = timestamp.addingTimeInterval(0.2)
        try await store.save(secondEdit, expectedProject: firstEdit)

        let saved = try await store.loadProject(id: original.id)
        XCTAssertEqual(saved.slides[0].note, "First edit")
        XCTAssertEqual(saved.slides[1].note, "Second edit")

        let projectFolder = root
            .appendingPathComponent("library/Projects")
            .appendingPathComponent(original.id.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: projectFolder.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("project.conflict-") })
    }

    func testRepeatingAnAlreadySavedStateDoesNotCreateAConflict() async throws {
        let (store, root, source) = try makeStore()
        let original = try await store.createProject(from: source)
        var edited = original
        edited.slides[0].note = "Saved note"

        try await store.save(edited, expectedProject: original)
        try await store.save(edited, expectedProject: original)

        let saved = try await store.loadProject(id: original.id)
        XCTAssertEqual(saved.slides[0].note, "Saved note")
        let folder = root.appendingPathComponent("library/Projects/\(original.id.uuidString)")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("project.conflict-") })
    }

    func testStaleViewPreferencesDoNotCreateAConflictCopy() async throws {
        let (store, root, source) = try makeStore()
        let original = try await store.createProject(from: source)
        var first = original
        first.viewPreferences.inspectorVisible = false
        try await store.save(first, expectedProject: original)

        var second = original
        second.viewPreferences.sidebarVisible = false
        try await store.save(second, expectedProject: original)

        let saved = try await store.loadProject(id: original.id)
        XCTAssertFalse(saved.viewPreferences.sidebarVisible)
        let folder = root.appendingPathComponent("library/Projects/\(original.id.uuidString)")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("project.conflict-") })
    }

    func testSharedMigrationPreservesLocalAndRejectsStaleSave() async throws {
        let (store, root, source) = try makeStore()
        let original = try await store.createProject(from: source)
        let localSource = await store.sourceURL(id: original.id)
        let shared = root.appendingPathComponent("Slide Learning")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        _ = try await store.selectSharedLibrary(at: shared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localSource.path))
        let migrated = try await store.loadProject(id: original.id)
        XCTAssertEqual(migrated, original)
        var remote = original
        remote.slides[0].note = "Newer device note"
        try await store.save(remote, expectedProject: original)
        var stale = original
        stale.slides[1].note = "Other device note"
        do {
            try await store.save(stale, expectedProject: original)
            XCTFail("A stale save must not overwrite remote notes")
        } catch { }
        let current = try await store.loadProject(id: original.id)
        XCTAssertEqual(current.slides[0].note, "Newer device note")
        let folder = shared.appendingPathComponent("Projects").appendingPathComponent(original.id.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("project.conflict-") })
    }

    func testImportCopiesSourceAndSurvivesOriginalDeletion() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        try FileManager.default.removeItem(at: source)
        let loaded = try await store.loadProject(id: project.id)
        XCTAssertEqual(loaded, project)
        try? FileManager.default.removeItem(at: root)
    }

    func testInvalidImportCreatesNoRecentProject() async throws {
        let (_, root, source) = try makeStore()
        let invalidStore = ProjectStore(rootURL: root.appendingPathComponent("invalid"), validator: Validator(pages: 0))
        do {
            _ = try await invalidStore.createProject(from: source)
            XCTFail("Expected empty PDF rejection")
        } catch { }
        let recent = try await invalidStore.listRecentProjects()
        XCTAssertEqual(recent, [])
    }

    func testAtomicSaveCreatesBackupAndRoundTripsPreferences() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        var edited = project
        edited.slides[1].isSelected = true
        edited.slides[1].note = "Keep this context"
        edited.viewPreferences = ViewPreferences(focusedPageIndex: 1, inspectorVisible: false, thumbnailSize: .large, filter: .selected)
        edited.updatedAt = Date(timeIntervalSince1970: 100)
        try await store.save(edited)
        let loaded = try await store.loadProject(id: project.id)
        XCTAssertEqual(loaded, edited)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("library/Projects/\(project.id.uuidString)/project.json.bak").path))
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingProjectRemainsInRecentIndexAndCanBeDeleted() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        try FileManager.default.removeItem(at: root.appendingPathComponent("library/Projects/\(project.id.uuidString)"))
        let summaries = try await store.listRecentProjects()
        XCTAssertEqual(summaries.first?.availability, .missingProject)
        try await store.deleteProject(id: project.id)
        let recent = try await store.listRecentProjects()
        XCTAssertTrue(recent.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func testDeletingProjectDoesNotDeleteExternalExport() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        let export = root.appendingPathComponent("Selected Slides.pdf")
        try Data("export".utf8).write(to: export)
        try await store.deleteProject(id: project.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testCorruptMetadataRecoversBackupAndRepairsPrimary() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        var edited = project
        edited.name = "Edited"
        try await store.save(edited)
        let metadata = root.appendingPathComponent("library/Projects/\(project.id.uuidString)/project.json")
        try Data("corrupt".utf8).write(to: metadata)

        let recovered = try await store.loadProject(id: project.id)
        XCTAssertEqual(recovered, project)
        XCTAssertNotEqual(try Data(contentsOf: metadata), Data("corrupt".utf8))
        try? FileManager.default.removeItem(at: root)
    }

    func testCorruptRecentIndexRecoversBackup() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        var edited = project
        edited.name = "Edited"
        try await store.save(edited)
        let index = root.appendingPathComponent("library/recent-projects.json")
        try Data("corrupt".utf8).write(to: index)

        let summaries = try await store.listRecentProjects()
        XCTAssertEqual(summaries.first?.id, project.id)
        XCTAssertEqual(summaries.first?.name, edited.name)
        try? FileManager.default.removeItem(at: root)
    }

    func testProjectFolderMissingFromIndexIsReconciled() async throws {
        let (store, root, source) = try makeStore()
        let project = try await store.createProject(from: source)
        let index = root.appendingPathComponent("library/recent-projects.json")
        try FileManager.default.removeItem(at: index)

        let summaries = try await store.listRecentProjects()
        XCTAssertEqual(summaries.first?.id, project.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testCloseProjectKeepsEditsWhenFinalFlushFailsAndRecovers() async throws {
        let (store, root, source) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = AppViewModel(
            store: store,
            thumbnailProvider: PDFThumbnailProvider(
                cacheDirectory: root.appendingPathComponent("thumbnail-cache")
            )
        )
        await app.importProject(from: source)
        let active = try XCTUnwrap(app.activeProject)
        let projectID = active.project.id
        let managedSource = await store.sourceURL(id: projectID)
        let movedSource = managedSource.deletingLastPathComponent()
            .appendingPathComponent("source.pdf.moved")
        try FileManager.default.moveItem(at: managedSource, to: movedSource)
        defer {
            if !FileManager.default.fileExists(atPath: managedSource.path),
               FileManager.default.fileExists(atPath: movedSource.path) {
                try? FileManager.default.moveItem(at: movedSource, to: managedSource)
            }
        }

        active.dispatch(.updateNote(pageIndex: 1, text: "Unsaved context"))
        app.closeProject()
        await app.flushActiveProject()

        XCTAssertEqual(app.screen, .project(projectID))
        XCTAssertTrue(app.activeProject === active)
        XCTAssertEqual(active.project.slides[1].note, "Unsaved context")
        XCTAssertEqual(active.error, .projectUnavailable(.missingSource))

        try FileManager.default.moveItem(at: movedSource, to: managedSource)
        app.closeProject()
        await app.flushActiveProject()

        XCTAssertEqual(app.screen, .recentProjects)
        XCTAssertNil(app.activeProject)

        let recovered = try await store.loadProject(id: projectID)
        XCTAssertEqual(recovered.slides[1].note, "Unsaved context")
    }
}
