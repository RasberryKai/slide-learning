import Foundation
import XCTest

final class IPadWorkflowUITests: XCTestCase {
    private let seededProjectID = "3D3D88B0-579C-4F94-8AB2-30544CC31276"
    private let reusableNoteSlideIndex = 0
    private let persistenceSlideIndex = 4
    private let longDeckLastSlideIndex = 89
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.kaikuppers.SlideLearning.ipad")
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testLibraryFilesPickerCanOpenAndCancel() throws {
        try waitForLibrary()

        let importButton = app.buttons["slideLearning.importPDF"]
        XCTAssertTrue(importButton.exists)
        importButton.tap()

        let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let pickerCancel = app.buttons["Cancel"]
        let documentsCancel = documents.buttons["Cancel"]
        let cancel = pickerCancel.waitForExistence(timeout: 3) ? pickerCancel : documentsCancel
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "The Files picker must expose a Cancel action.")
        attachScreenshot(named: "files-picker-open")
        cancel.tap()

        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        attachScreenshot(named: "library-after-picker-cancel")
    }

    func testDeckFocusSelectionNotesFilterAndCollapse() throws {
        try openSeededDeck()
        try focusSlideUsingKeyboard(1)

        let firstThumbnail = app.buttons["slideLearning.thumbnail.0"]
        let secondThumbnail = app.buttons["slideLearning.thumbnail.1"]
        XCTAssertTrue(firstThumbnail.waitForExistence(timeout: 8))
        XCTAssertTrue(secondThumbnail.waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["slideLearning.noteEditor"].waitForExistence(timeout: 8))

        let countBeforeFocus = try selectedCount()
        secondThumbnail.tap()
        XCTAssertTrue(app.staticTexts["Notes — Slide 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(try selectedCount(), countBeforeFocus, "Focusing a slide must not change its selection state.")
        attachScreenshot(named: "deck-focused-slide-two")

        // Reuse one fixed QA slide so repeated runs do not consume all empty note candidates.
        try resetSlideForQA(index: reusableNoteSlideIndex)
        let noteEditor = app.textViews["slideLearning.noteEditor"]
        let candidateSelection = app.buttons["slideLearning.selection.\(reusableNoteSlideIndex)"]
        let candidateIndex = reusableNoteSlideIndex

        let countBeforeNote = try selectedCount()
        noteEditor.tap()
        noteEditor.typeText(" UI QA spaces")
        let noteValue = noteEditor.value as? String ?? ""
        XCTAssertTrue(noteValue.contains(" UI QA spaces"), "Typed notes should preserve the leading space.")
        XCTAssertEqual(try selectedCount(), countBeforeNote + 1, "Typing the first nonblank note should select the slide.")
        XCTAssertTrue(candidateSelection.waitForExistence(timeout: 5))
        XCTAssertTrue(candidateSelection.label.localizedCaseInsensitiveContains("Deselect"), "A nonblank note should auto-select its slide.")
        // Keep this attachment while the editor still owns focus so reviewers can inspect the keyboard-open state.
        attachScreenshot(named: "notes-keyboard-open")
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        let selectedFilter = app.buttons["Selected"]
        guard selectedFilter.waitForExistence(timeout: 5) else {
            attachScreenshot(named: "selected-filter-missing")
            XCTFail("The segmented filter control must be accessible.")
            return
        }
        selectedFilter.tap()
        XCTAssertTrue(app.buttons["slideLearning.thumbnail.\(candidateIndex)"].waitForExistence(timeout: 5), "Selected filter must retain the auto-selected slide.")
        attachScreenshot(named: "selected-filter")

        let allFilter = app.buttons["All"]
        if allFilter.exists { allFilter.tap() }

        let hideNotes = app.buttons["Hide Notes"]
        XCTAssertTrue(hideNotes.waitForExistence(timeout: 5))
        hideNotes.tap()
        XCTAssertFalse(app.textViews["slideLearning.noteEditor"].waitForExistence(timeout: 2))
        attachScreenshot(named: "notes-collapsed")

        let showNotes = app.buttons["Show Notes"]
        XCTAssertTrue(showNotes.waitForExistence(timeout: 5))
        showNotes.tap()
        XCTAssertTrue(app.textViews["slideLearning.noteEditor"].waitForExistence(timeout: 5))
        attachScreenshot(named: "notes-expanded")
    }

    func testHardwareKeyboardControlsNotesAndSelection() throws {
        try openSeededDeck()
        try resetSlideForQA(index: reusableNoteSlideIndex)

        let noteEditor = app.textViews["slideLearning.noteEditor"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // Printable input while the workspace owns focus must create the first note character and auto-select the slide.
        let countBeforePrintable = try selectedCount()
        app.typeKey("q", modifierFlags: [])
        XCTAssertTrue(waitForNoteValue(noteEditor, equals: "q"), "A printable hardware key must become the first note character.")
        XCTAssertEqual(try selectedCount(), countBeforePrintable + 1)
        XCTAssertTrue(app.buttons["slideLearning.selection.\(reusableNoteSlideIndex)"].label.localizedCaseInsensitiveContains("Deselect"))
        attachScreenshot(named: "hardware-printable-notes-open")

        // Return must reopen a hidden notes inspector and transfer focus into the editor.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let hideNotes = app.buttons["Hide Notes"]
        XCTAssertTrue(hideNotes.waitForExistence(timeout: 5))
        hideNotes.tap()
        XCTAssertFalse(noteEditor.waitForExistence(timeout: 2))
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(noteHeader(for: reusableNoteSlideIndex).waitForExistence(timeout: 5))
        attachScreenshot(named: "hardware-return-restores-notes")

        // Arrows and Space inside the editor must stay inside text entry.
        let countBeforeEditorKeys = try selectedCount()
        noteEditor.tap()
        app.typeKey(XCUIKeyboardKey.end, modifierFlags: [])
        let noteBeforeEditorSpace = noteEditor.value as? String ?? ""
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        XCTAssertTrue(
            waitForNoteValue(noteEditor, equals: noteBeforeEditorSpace + " "),
            "Space inside notes must insert a literal space character."
        )
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: reusableNoteSlideIndex).exists, "Editor arrows must not move the focused slide.")
        XCTAssertEqual(try selectedCount(), countBeforeEditorKeys, "Space inside notes must not toggle slide selection.")

        // Escape returns to the workspace; all four arrows then move focus through the long deck.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: reusableNoteSlideIndex).exists)
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: 1).waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: 2).waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: 1).waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        XCTAssertTrue(noteHeader(for: reusableNoteSlideIndex).waitForExistence(timeout: 5))

        // Space outside notes toggles the focused slide and can be reversed without changing the fixture permanently.
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        let slideTwoSelection = app.buttons["slideLearning.selection.1"]
        XCTAssertTrue(slideTwoSelection.waitForExistence(timeout: 5))
        if slideTwoSelection.label.localizedCaseInsensitiveContains("Deselect") {
            slideTwoSelection.tap()
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
        XCTAssertTrue(slideTwoSelection.label.hasPrefix("Select "))
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        XCTAssertTrue(slideTwoSelection.label.localizedCaseInsensitiveContains("Deselect"), "Space outside notes must toggle selection.")
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        XCTAssertTrue(slideTwoSelection.label.hasPrefix("Select "))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    func testExportPresentsShareSheetAndSupportsRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        try openSeededDeck()

        let export = app.buttons["slideLearning.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 8), "The export control must be present in an open deck.")
        XCTAssertTrue(export.isEnabled, "The seeded project must have a selected slide available for export.")

        export.tap()
        let shareSheet = app.otherElements["ActivityListView"]
        let sharePresented = shareSheet.waitForExistence(timeout: 20)
            || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2)
        XCTAssertTrue(sharePresented, "Export must present the native share sheet.")
        attachScreenshot(named: "export-share-sheet")

        // Dismiss the share sheet without selecting an external destination.
        if app.buttons["header.closeButton"].exists { app.buttons["header.closeButton"].tap() }
        else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        else { app.typeKey(XCUIKeyboardKey.escape, modifierFlags: []) }
        XCTAssertTrue(app.buttons["slideLearning.back"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLayoutChange()
        attachScreenshot(named: "workspace-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForLayoutChange()
        attachScreenshot(named: "workspace-portrait")
    }

    func testNotesSurviveRelaunch() throws {
        try openSeededDeck()
        try resetSlideForQA(index: persistenceSlideIndex)

        let noteEditor = app.textViews["slideLearning.noteEditor"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 8))
        noteEditor.tap()
        noteEditor.typeText(" persistence check")
        let expectedFragment = " persistence check"
        XCTAssertTrue((noteEditor.value as? String ?? "").contains(expectedFragment))
        attachScreenshot(named: "persistence-notes-keyboard-open")
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        app.buttons["slideLearning.back"].tap()
        XCTAssertTrue(app.buttons["slideLearning.project.\(seededProjectID)"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        try waitForLibrary()
        try openSeededDeck()

        let restoredEditor = app.textViews["slideLearning.noteEditor"]
        XCTAssertTrue(restoredEditor.waitForExistence(timeout: 8))
        XCTAssertTrue(noteHeader(for: persistenceSlideIndex).waitForExistence(timeout: 8), "Relaunch must restore the last focused slide.")
        XCTAssertTrue((restoredEditor.value as? String ?? "").contains(expectedFragment))
        attachScreenshot(named: "notes-after-relaunch")
    }

    func testLongDeckScrollAndRestoresLastFocusedSlide() throws {
        try openSeededDeck()
        try focusSlideUsingKeyboard(longDeckLastSlideIndex)

        XCTAssertTrue(noteHeader(for: longDeckLastSlideIndex).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["slideLearning.thumbnail.\(longDeckLastSlideIndex)"].waitForExistence(timeout: 8), "Focusing the last page must scroll the 90-slide sidebar to it.")
        attachScreenshot(named: "long-deck-last-slide")

        app.buttons["slideLearning.back"].tap()
        XCTAssertTrue(app.buttons["slideLearning.project.\(seededProjectID)"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        try waitForLibrary()
        app.buttons["slideLearning.project.\(seededProjectID)"].tap()
        XCTAssertTrue(app.buttons["slideLearning.back"].waitForExistence(timeout: 12))
        XCTAssertTrue(noteHeader(for: longDeckLastSlideIndex).waitForExistence(timeout: 8), "Relaunch must restore focus on the last slide.")
        attachScreenshot(named: "long-deck-restored-focus")
    }

    func testDeleteConfirmationCancelKeepsProject() throws {
        try waitForLibrary()

        let project = app.buttons["slideLearning.project.\(seededProjectID)"]
        guard project.waitForExistence(timeout: 8) else {
            throw XCTSkip("The seeded project is not present in the simulator library.")
        }

        project.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "A project row swipe must expose Delete.")
        delete.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        attachScreenshot(named: "delete-confirmation")
        cancel.tap()
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        attachScreenshot(named: "delete-cancelled")
    }

    private func waitForLibrary() throws {
        let importButton = app.buttons["slideLearning.importPDF"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 12), "The iPad library must become ready within 12 seconds.")
        guard importButton.exists else { throw TestFlowError.libraryNotReady }
    }

    private func openSeededDeck() throws {
        try waitForLibrary()
        let project = app.buttons["slideLearning.project.\(seededProjectID)"]
        guard project.waitForExistence(timeout: 8) else {
            attachScreenshot(named: "seeded-project-missing")
            throw XCTSkip("Seeded project \(seededProjectID) is not present; fixture-dependent UI flow skipped.")
        }
        project.tap()
        XCTAssertTrue(app.buttons["slideLearning.back"].waitForExistence(timeout: 12), "The seeded project must open within 12 seconds.")
        guard app.buttons["slideLearning.back"].exists else { throw TestFlowError.deckOpenFailed }
    }

    private func ensureAllSlidesVisible() {
        let allFilter = app.buttons["All"]
        XCTAssertTrue(allFilter.waitForExistence(timeout: 5), "The All filter must be accessible.")
        if allFilter.exists { allFilter.tap() }
    }

    private func ensureNotesVisible() {
        let showNotes = app.buttons["Show Notes"]
        if showNotes.waitForExistence(timeout: 3) { showNotes.tap() }
        XCTAssertTrue(app.textViews["slideLearning.noteEditor"].waitForExistence(timeout: 5), "The notes editor must be visible for keyboard QA.")
    }

    private func focusSlideUsingKeyboard(_ index: Int) throws {
        ensureAllSlidesVisible()
        ensureNotesVisible()

        // SwiftUI's focusable container is not guaranteed to be the responder after
        // relaunch or after a previous TextEditor interaction. A visible thumbnail
        // tap explicitly activates the workspace before sending hardware keys.
        try activateWorkspaceWithVisibleThumbnail()
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // The fixture can retain focus from a previous run. Move to the first page first,
        // then advance to the requested page so the same path works from any saved state.
        for _ in 0...longDeckLastSlideIndex {
            app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        }
        for _ in 0..<index {
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        }
        XCTAssertTrue(noteHeader(for: index).waitForExistence(timeout: 8), "Keyboard focus must reach slide \(index + 1).")

        let targetThumbnail = app.buttons["slideLearning.thumbnail.\(index)"]
        XCTAssertTrue(targetThumbnail.waitForExistence(timeout: 8), "The focused thumbnail must remain accessible.")
        targetThumbnail.tap()
    }

    private func resetSlideForQA(index: Int) throws {
        try focusSlideUsingKeyboard(index)
        let editor = app.textViews["slideLearning.noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        if !(editor.value as? String ?? "").isEmpty {
            editor.tap()
            app.typeKey("a", modifierFlags: .command)
            app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            XCTAssertTrue(waitForNoteValue(editor, equals: ""), "The reusable QA note must be cleared before typing.")
        }
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        let selection = app.buttons["slideLearning.selection.\(index)"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        if selection.label.localizedCaseInsensitiveContains("Deselect") {
            selection.tap()
            XCTAssertTrue(selection.waitForExistence(timeout: 3))
        }
        XCTAssertTrue(selection.label.hasPrefix("Select "), "Reusable QA slide must start unselected.")
        try activateWorkspaceWithVisibleThumbnail()
    }

    private func activateWorkspaceWithVisibleThumbnail() throws {
        let visibleThumbnails = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'slideLearning.thumbnail.'")
        )
        let firstThumbnail = visibleThumbnails.firstMatch
        XCTAssertTrue(firstThumbnail.waitForExistence(timeout: 8), "At least one visible thumbnail must activate the workspace.")
        guard firstThumbnail.exists else { throw TestFlowError.workspaceNotActivated }
        firstThumbnail.tap()
    }

    private func noteHeader(for index: Int) -> XCUIElement {
        app.staticTexts["Notes — Slide \(index + 1)"]
    }

    private func waitForNoteValue(_ editor: XCUIElement, equals expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (editor.value as? String ?? "") == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return (editor.value as? String ?? "") == expected
    }

    private func selectedCount() throws -> Int {
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'selected'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The toolbar must expose the selected slide count.")
        guard let count = Int(summary.label.split(separator: " ").first ?? "") else {
            throw TestFlowError.selectionCountUnavailable
        }
        return count
    }

    private func waitForLayoutChange() {
        let expectation = expectation(description: "Allow SwiftUI layout to settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 3)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum TestFlowError: Error {
        case libraryNotReady
        case deckOpenFailed
        case selectionCountUnavailable
        case workspaceNotActivated
    }
}
