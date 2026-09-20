# Slide Learning — macOS App Feature Specification

## Status

Implementation-ready product specification for the first personal-use version.

Working title: **Slide Learning**. The final product name and icon may be changed without affecting the feature scope.

## Problem and desired outcome

Lecture slide decks often contain far more material than is useful for exam-focused flashcard generation. The user needs a fast way to review a PDF visually, keep roughly half of its slides, attach short contextual notes to relevant slides, and export a clean PDF that can be handed to an AI agent.

The app should optimize for quick curation rather than PDF editing. It must feel at home on a MacBook screen and remain efficient for typical decks of 30–90 pages.

The successful outcome is a local macOS app in which the user can:

1. Import one slide-deck PDF as a project.
2. Review slides in a left thumbnail sidebar with a large active slide on the right.
3. Focus, select, and deselect slides quickly, especially with the keyboard.
4. Add plain-text context to individual slides.
5. Close and reopen the app without losing work.
6. Export the selected slides and their notes as one high-quality PDF in original slide order.

## Product principles

- **Slide review first.** A single-column thumbnail sidebar supports navigation; the active slide fills the main workspace with notes beneath it.
- **Selection and focus are different states.** Looking at a slide must not silently change whether it will be exported.
- **No lost work.** Projects and edits save automatically and survive app restarts.
- **Source fidelity matters.** Exported slides should retain the quality and selectable text of the source PDF where possible; they must not become blurry screenshots.
- **Keep the app narrow.** It prepares source material. It does not generate flashcards or own the downstream AI prompt.
- **Local and private.** The app does not require accounts, cloud services, analytics, or network access.

## Target environment

- Native macOS desktop app.
- Optimized for a MacBook-sized display.
- Typical source document: 30–90 PDF pages, usually presentation slides.
- Personal-use v1, built and run on the user's own Mac.
- No App Store release, updater, onboarding funnel, or broad backward-compatibility requirement in v1.
- Target the macOS version currently used for development. If a specific deployment target is needed, choose the newest target supported by the user's Mac rather than adding compatibility work speculatively.

## Core user flow

### 1. Open or create a project

On launch, show a lightweight Recent Projects screen.

- Projects are ordered by most recently opened.
- Each item shows the project name, source PDF name, page count, selected count, and last-updated time.
- The primary action is **Import PDF**.
- PDF import is available through both a file picker and drag and drop.
- One PDF creates one project.
- The project name defaults to the PDF filename without its extension.
- Importing copies the PDF into the app-managed project library. The project must continue working if the original file is moved, renamed, or deleted.
- Opening a recent project restores its selections, notes, last-focused slide, thumbnail size, notes visibility, and current filter.

### 2. Review and curate the deck

The project screen uses a PowerPoint-style layout:

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Back   Project name   All | Selected   Selected count   Export      │
├───────────────┬─────────────────────────────────────────────────────┤
│ Thumbnails    │                                                     │
│ [1]           │                 Active slide                        │
│ [2]           │                                                     │
│ [3]           │                                                     │
│ ...           ├─────────────────────────────────────────────────────┤
│               │ Notes for the active slide                          │
│               │ [editable text area]                                │
└───────────────┴─────────────────────────────────────────────────────┘
```

Thumbnails stay in one scrollable column on the left. The active slide uses the remaining space on the right while preserving its aspect ratio. Notes sit beneath the active slide and may be hidden with the toolbar notes toggle; the active slide remains visible. The existing stored `inspectorVisible` preference controls notes visibility for compatibility with saved projects.

#### Focus behavior

- Clicking a thumbnail focuses it and updates the active slide and notes.
- Clicking a thumbnail does not, by itself, select or deselect it.
- The focused state is visually distinct from the selected state.
- Left/Right or Up/Down arrow keys move focus through slides in source order.
- Focus movement should scroll the newly focused thumbnail into view when needed.

#### Selection behavior

- Pressing Space toggles selection for the focused slide.
- Each thumbnail also has a directly clickable selection control.
- Space inserts a normal space while the note editor has keyboard focus; it must not toggle slide selection in that context.
- Selected slides use a strong border plus a checkmark badge. Selection must not be communicated through color alone.
- The toolbar always displays `<selected count> of <total count> selected`.
- The sidebar can show either **All** slides or **Selected** slides.
- In the Selected filter, deselecting the focused slide removes it from the filtered sidebar and moves focus predictably to the next remaining slide, or the previous slide when there is no next slide.
- Deselecting a slide never deletes its note. Reselecting it restores the existing note.
- Export order is always the source PDF order. Reordering selected slides is not supported in v1.

#### Notes behavior

- Notes are plain text associated with one source slide.
- The editor is optimized for one or two sentences but expands or scrolls comfortably for occasional longer lecturer context.
- There is no arbitrary character limit.
- Typing non-whitespace content into an unselected slide's empty note automatically selects that slide.
- Clearing a note does not automatically deselect the slide.
- Slides with a non-empty note display a small note badge in the sidebar.
- Line breaks are preserved in the project and export.
- Notes save automatically as the user types. A manual Save action is not required.
- Escape releases keyboard focus from the note editor, restoring arrow-key navigation and Space selection without losing notes.

#### Sidebar behavior

- The sidebar always shows a single column of thumbnails.
- A thumbnail-size control lets the user adjust the sidebar and thumbnail width.
- Page numbers reflect the source PDF's one-based page order.
- Thumbnail rendering is lazy and must not block interaction with already available thumbnails.
- The UI remains responsive while thumbnails are generated.

### 3. Export the curated deck

- Export is disabled when zero slides are selected.
- Export opens the standard macOS Save dialog.
- The suggested filename is `<original filename> – Selected Slides.pdf`.
- The output is one PDF containing selected slides only, in original source order.
- Every exported slide is identified by its original one-based source slide number.
- The original slide is reproduced at full available width without changing its aspect ratio.
- Source vector content and selectable text should remain intact where the PDF framework permits. Do not rasterize whole pages as thumbnail images for export.
- A slide without a note gets only the minimal source-slide label/footer; it must not receive a large empty notes area.
- A slide with a note gets a clearly labeled notes area directly beneath the slide on the same output page.
- The page may be taller than the original slide so the slide itself does not need to be shrunk unnecessarily.
- If a note cannot fit legibly beneath its slide, continue it on an immediately following page labeled `Notes for source slide <number>`.
- Note text is rendered as real, searchable/selectable PDF text where possible.
- Existing files are handled through normal macOS overwrite confirmation.
- Build the export in a temporary location and place it at the chosen destination only after successful completion, so a failed export does not leave a misleading partial PDF.
- After success, show the saved filename and offer **Show in Finder**.
- A failed export leaves the project unchanged and shows a useful error with a retry path.

## Project storage and privacy

The user must not have to choose or manage a project directory.

- Store projects in an app-managed location under macOS Application Support.
- Each project has a stable internal identifier and contains:
  - A private copy of the imported source PDF.
  - Project metadata, including name, source filename, page count, created time, and updated time.
  - Per-page selection state and note text.
  - Last-focused page and relevant view preferences.
- Save state continuously and atomically so an interrupted write does not corrupt the last good project state.
- No project data is uploaded or transmitted.
- The export destination is independent from internal project storage.
- Deleting a project requires confirmation and removes the app-managed PDF copy, selections, and notes.
- Deleting a project does not remove PDFs previously exported elsewhere.

An implementation may use a simple JSON metadata file alongside the copied PDF for v1. A database is unnecessary for this scope.

## Error handling and recovery

- Reject files that are not valid PDFs with a clear explanation; do not create an empty recent project.
- Reject corrupt, empty, or password-protected PDFs in v1 with a clear explanation. Password entry and decryption are out of scope.
- If import copying fails, remove any incomplete project data and leave the source file untouched.
- If an internal project file becomes unavailable or unreadable, keep the recent-project entry long enough to explain the problem and let the user delete it. Do not crash or silently discard project metadata.
- Restore the most recent successfully saved project state after an app crash or forced quit.
- Selection changes are immediately reversible by toggling the same slide again.
- Notes remain stored even while their slides are deselected, protecting against accidental selection changes.
- If a project is open when the app quits normally, reopening the project returns to the last-focused slide and saved view state.

## Explicit non-goals for v1

- Drawing, highlighting, arrows, shapes, spatial text boxes, or other on-slide markup.
- Multiple PDFs in one project.
- Slide reordering.
- Editing the source slide content.
- OCR or correction of text inside the PDF.
- Flashcard generation, AI prompts, AI-provider integration, or automatic upload.
- A deck-level “Instructions for AI” page.
- Markdown, JSON, or other sidecar exports.
- Cloud sync, shared projects, collaboration, accounts, analytics, or network features.
- Password-protected PDF support.
- App Store packaging, automatic updates, or public distribution work.

## Recommended implementation direction

This section is guidance, not a behavioral requirement.

- Prefer a native SwiftUI app with PDFKit/Core Graphics for PDF viewing, thumbnail generation, and page composition.
- Use AppKit bridging only where SwiftUI or PDFKit does not expose reliable macOS behavior, such as specific Save-panel or first-responder interactions.
- Keep the project model independent from views so autosaving and export can be tested without UI automation.
- Cache generated thumbnails inside the project cache or an app cache keyed by the copied PDF and page index. Cached thumbnails are disposable and are not the source for export.
- Perform PDF copying, thumbnail rendering, metadata saving, and export off the main thread while publishing UI state safely.
- Preserve original PDF page content by drawing PDF pages into the output PDF context rather than rendering them to bitmap images.
- No database, server, authentication layer, or third-party PDF service is warranted.

## Acceptance criteria

### Project creation and persistence

- Given a valid 30–90-page PDF, importing it creates one project and opens the slide-review workspace.
- The imported project still works after the original PDF is moved or deleted.
- Closing and reopening the app preserves every selection and note.
- Reopening a project restores the last-focused slide and saved view settings.
- Recent projects appear in most-recently-opened order.
- Deleting a project requires confirmation and does not affect an exported PDF.

### Review interaction

- Clicking a thumbnail changes focus without changing selection.
- Pressing Space outside the note editor toggles only the focused slide.
- Pressing Space inside the note editor types a space and does not change selection.
- Pressing Escape while editing notes releases text focus; arrows and Space immediately work on slides.
- Thumbnails appear in a single left column, with the active slide on the right and notes below it.
- Hiding notes leaves the active slide visible.
- Selected thumbnails show a checkmark and a strong non-color-only visual state.
- Focus remains distinguishable whether or not the focused slide is selected.
- Typing a non-empty note for an unselected slide selects it automatically.
- Deselecting and reselecting a noted slide preserves the note.
- The selected count updates immediately and accurately.
- All and Selected filters show the correct slides.
- Arrow-key navigation and automatic scrolling work in both filters.
- Thumbnail loading never freezes already available controls or text editing.

### Export

- Export cannot start with no selected slides.
- Export includes every selected slide exactly once and excludes every unselected slide.
- Exported slides follow original source order regardless of selection order.
- Each exported slide is labeled with its original source slide number.
- Notes appear beneath the correct slide; long notes continue on a correctly labeled following page.
- A selected slide without notes does not receive a large blank notes region.
- Exported slides remain sharp at normal zoom, and source text remains selectable where supported by the source PDF.
- The suggested filename follows the agreed naming rule.
- Canceling the Save dialog changes nothing.
- A failed export does not leave a partial destination file or alter project data.
- A successful export can be revealed in Finder.

### Privacy and scope

- The core workflow operates with networking disabled.
- The app makes no requests to an AI service and contains no flashcard prompt editor.
- A project accepts exactly one source PDF.
- The UI contains no spatial annotation or slide-reordering tools.

## Verification checklist for implementation handoff

Test with representative PDFs that include:

- 30 pages and approximately 90 pages.
- Landscape and portrait pages.
- Mixed page sizes or orientations in one file.
- Selectable text, vector diagrams, and high-resolution images.
- Slides with no notes, short notes, multiline notes, and text long enough to require continuation.
- A corrupt file, an empty PDF, and a password-protected PDF.

Also verify:

- Rapid Space-key selection while moving focus with arrow keys.
- Typing spaces and multiline text in the note editor.
- Deselecting a slide while the Selected filter is active.
- Quitting immediately after editing and recovering the latest saved state.
- Moving or deleting the originally imported PDF.
- Canceling and failing an export without leaving partial files.
- Deleting a project while exported documents remain intact.

## Decisions intentionally left to the implementation agent

- Exact visual styling, colors, typography, app icon, and final product name.
- Exact internal serialization format, provided storage remains local, atomic, and migration-friendly.
- Exact thumbnail-cache eviction policy.
- Exact implementation of PDF page composition, provided the export behavior and source-fidelity requirements are met.

