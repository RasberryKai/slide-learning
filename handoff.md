# Slide Learning iPad — handoff

Updated 2026-09-21. User explicitly requested an immediate handoff. Stop implementation here; do not treat this as finished or production-ready.

## User request

Build a native iPad version in the existing repository, using the five supplied dark mockups as design references. Preserve the Mac app. Mockups show a deck library, PDF import, confirmation deletion, thumbnail sidebar, large active slide, independent selection, All/Selected filters, thumbnail sizing, notes beneath the slide, keyboard-aware layout, export, and portrait/landscape support.

Reference images live on Desktop:

- `CleanShot 2026-09-21 at 17.47.10@2x.png`
- `CleanShot 2026-09-21 at 17.47.19@2x.png`
- `CleanShot 2026-09-21 at 17.47.25@2x.png`
- `CleanShot 2026-09-21 at 17.47.32@2x.png`
- `CleanShot 2026-09-21 at 17.47.34@2x.png`

Repository: `/Users/kaikuppers/Documents/Projects/slide-learning`.

## Current implementation

All changes are uncommitted. Worktree was clean before this task. No commits, pushes, PRs, device installation, or distribution have been performed.

- New `SlideLearningIPad` iOS application target, iPad only, minimum iPadOS 18, separate bundle ID `com.kaikuppers.SlideLearning.ipad`.
- Existing Mac target retained.
- Shared domain/reducer, atomic project persistence, view models, PDF validation, vector PDF export, and thumbnail worker.
- `PlatformImage` conditionally maps to NSImage or UIImage; PNG cache supports both.
- Dark SwiftUI iPad library, Files picker import, PDF drop, progress/busy guards, local recent projects, swipe/context-menu deletion with an alert confirmation.
- Workspace has adaptive sidebar width, separate focus/selection controls with 44-point targets, All/Selected, thumbnail size, notes visibility, count, and export.
- PDFKit active page preview uses a coordinator retaining the source PDF and creates a single-page document from a copied source page. This prevents PDF gestures navigating independently of the notes focus, BUT see the blocking crash below.
- Notes use a single optional focus enum after a real focus-stealing bug was found with two Boolean FocusStates. Explicit tap focus added. Arrow/Space/Return/Escape handlers plus printable hardware-keyboard input to notes are implemented; direct hardware typing is not yet runtime verified.
- Export snapshots the project, writes into a UUID temporary directory with the clean filename `<source stem> – Selected Slides.pdf`, and presents native share UI. Temporary directory cleanup occurs on completion/dismissal.
- Root handles background flush and keys workspace identity by project ID. Back navigation uses AppViewModel.closeProject().
- Mac and iPad libraries remain independent and local. No sync, drawings, or annotations.

## Files

New:

- `SlideLearningIPad/SlideLearningIPadApp.swift`
- `SlideLearningIPad/IPadRootView.swift`
- `SlideLearningIPad/IPadRecentProjectsView.swift`
- `SlideLearningIPad/IPadProjectWorkspaceView.swift`
- `SlideLearningIPad/Info.plist`, `Assets.xcassets` (reuses existing app icon image)
- `SlideLearningIPadUITests/IPadWorkflowUITests.swift`
- `SlideLearning.xcodeproj/xcshareddata/xcschemes/SlideLearningIPad.xcscheme`
- `scripts/GenerateIPadTestPDF.swift`
- `scripts/seed-ipad-simulator.py`
- `IPAD_IMPLEMENTATION.md`

Modified:

- `project.yml` and generated `SlideLearning.xcodeproj/project.pbxproj`
- `SlideLearning/Features/MediaProtocols.swift`
- `SlideLearning/PDF/PDFThumbnailProvider.swift`
- Both files in `SlideLearningTests` (conditional test imports; new thumbnail cache test)
- `README.md`

`project.yml` is authoritative; regenerate with `xcodegen generate` after configuration changes. Fixed preexisting missing generated Info.plist setting for Mac test bundle while adding iPad tests.

## Verified results

- Mac build succeeded.
- All **19 Mac unit tests passed**.
- iPad simulator build succeeded after marking PDF preview Coordinator `@MainActor`.
- All **19 shared unit tests passed on iPad**: reducer, persistence/recovery, validation, vector/selectable-text export, mixed page geometry, long notes, thumbnail render/cache reload.
- Latest UI run: **4 of 5 UI tests passed**, one reproducible app crash remains.
  - Passed: delete confirmation cancel retains deck.
  - Passed: native share sheet and orientation test.
  - Passed: Files picker open/cancel.
  - Passed: notes survive back navigation and app relaunch.
  - Failed: focus/selection/notes/filter/collapse workflow crashes while switching slides, before completing the whole workflow.
- Initial share-sheet test failures were selector errors, not failed export. Accessibility tree exposes `ActivityListView`, navigation bar `UIActivityContentView`, close button `header.closeButton`, and `Save to Files` cell. Tests now use the observed identifiers.
- Initial deletion test failure came from native iPad confirmation popover lacking the expected explicit Cancel. Changed to an alert; now passes.
- Initial note editor failure was actual keyboard focus stealing. Single focus enum fixed the persistence test.
- `git diff --check` passed before latest test run; run again before completion.

## BLOCKER: reproducible PDF accessibility crash

Latest UI run crashes after opening the seeded deck, focusing slide 2, then focusing slide 1. The next accessibility snapshot loses the app connection. This reproduced twice, so do not dismiss it as flaky automation.

Crash report:

`/Users/kaikuppers/Library/Logs/DiagnosticReports/SlideLearningIPad-2026-09-21-181315.ips`

Earlier equivalent report:

`/Users/kaikuppers/Library/Logs/DiagnosticReports/SlideLearningIPad-2026-09-21-181147.ips`

Exception: `EXC_BAD_ACCESS`, `SIGSEGV`, `KERN_INVALID_ADDRESS at 0x10`.

Triggered stack starts with:

1. `CGPDFContentStreamCreate`
2. `CGPDFPageCopyPageLayoutWithCTLD`
3. `CGPDFTaggedNodeGetStringRange`
4. `CGPDFTaggedNodeApplyTextDecorationType` / child enumeration
5. `CGPDFTaggedNodeCreateAttributedString`
6. `-[UICGPDFNodeAccessibilityElement _attributedAccessibilityLabelForNode:]`
7. Accessibility label / UI testing snapshot traversal

Likely investigation seam: `IPadPDFPreview.Coordinator.displayPage(at:in:)` currently swaps a newly created single-page PDFDocument into a reused PDFView using `sourcePage.copy()`. PDFKit accessibility objects may retain stale page backing data after document replacement. This is a hypothesis, not yet proven. Consider a lifecycle-safe preview implementation that retains document/page backing, or recreates the PDFView on page changes while keeping source caching; preserve accessibility and source-page correspondence. Do not simply hide all PDF accessibility to make the test pass without assessing the product impact.

The failing test is `IPadWorkflowUITests.testDeckFocusSelectionNotesFilterAndCollapse()` around line 62. Latest log:

`/tmp/slide-learning-ipad-ui3.log`

Latest result bundle:

`/tmp/slide-learning-ipad/Logs/Test/Test-SlideLearningIPad-2026.09.21_18-12-55-+0200.xcresult`

## Exact next steps

1. Fix the PDF preview crash above. Read the full crash report and current preview implementation first.
2. Rerun the failing UI test only; then rerun all five after the fix.
3. Export final test screenshot attachments and visually inspect portrait, landscape, keyboard-open notes, collapsed notes, and share sheet. Do not treat orientation changes alone as layout validation.
4. Add/execute runtime hardware-keyboard checks for printable-first-character, Return when notes hidden, Escape, arrows, and Space inside/outside text entry.
5. Check long-deck scrolling/restored focus and a narrow iPad window; sidebar has adaptive width but those cases are not proven by current tests.
6. Actual Files import of a picked document, final Save to Files destination, deletion confirmation acceptance, iPadOS 18 runtime, and physical iPad are not yet verified. Shared core import/export/deletion tests pass; UI picker cancellation/share presentation are the current UI evidence.
7. Update `IPAD_IMPLEMENTATION.md`: its acceptance table currently lists planned verification, and its validation section still says results will be recorded. Replace with accurate final results/limits.
8. Re-run appropriate Mac checks only if shared files change; existing Mac 19-test pass is valid for current shared implementation.
9. Final response should give Xcode scheme `SlideLearningIPad`, mention local-only independent libraries, verification results, and any genuine remaining limits.

## Simulator and commands

Booted simulator:

- iPad Pro 13-inch (M5), iOS 26.5
- UDID `C0491D0C-51E9-4C78-843F-0D2E33F14B1E`
- App container observed: `/Users/kaikuppers/Library/Developer/CoreSimulator/Devices/C0491D0C-51E9-4C78-843F-0D2E33F14B1E/data/Containers/Data/Application/F84C0B64-279F-4D0C-A21E-8110A2035BF3` (query again; can change)

Seeded generated fixture:

- Finance Review, 30 slides
- Project ID `3D3D88B0-579C-4F94-8AB2-30544CC31276`
- Already present; test runs have modified notes/focus/selections.
- Source generated PDF: `/tmp/ipad-review-deck.pdf`
- Reproducible seed script refuses to overwrite an existing fixture. Delete only the QA deck through the simulator app before reseeding if needed.

```sh
xcodegen generate
xcodebuild -project SlideLearning.xcodeproj \
  -scheme SlideLearningIPad \
  -destination 'platform=iOS Simulator,id=C0491D0C-51E9-4C78-843F-0D2E33F14B1E' \
  -derivedDataPath /tmp/slide-learning-ipad \
  -parallel-testing-enabled NO \
  -only-testing:SlideLearningIPadUITests test
```

Use `-only-testing:SlideLearningIPadUITests/IPadWorkflowUITests/testDeckFocusSelectionNotesFilterAndCollapse` for the failing test. Keep tests serial on the seeded device; cloned simulators do not contain the fixture.

Shell sandbox requires escalation for Xcode build/test and simulator access. Existing calls were authorized. Regular workspace edits are allowed. No need to ask user again for these reversible development checks.

Other evidence:

- `/tmp/slide-learning-mac-build.log`
- `/tmp/slide-learning-mac-test.log`
- `/tmp/slide-learning-ipad-test.log` (initial shared iPad test success)
- `/tmp/slide-learning-ipad-final.log` (first UI run, historical failures)
- `/tmp/slide-learning-ipad-ui2.log` (second run, historical failures)
- `/tmp/ipad-qa-attachments/manifest.json` and attachments from first UI run

Export attachments with `xcrun xcresulttool export attachments --path <xcresult> --output-path <directory>` (needs escalation on this machine).

## Review/delegation state

Used `orchestrate-feature-development` and `delegation-guide` skills. Subagents:

- `ipad_ui`: implemented iPad source, then hit workspace spend cap; parent completed final fixes.
- `ipad_review`: resumed and completed independent source review; no other blocking findings. Flagged missing direct printable typing; parent added it, runtime verification pending.
- `ipad_ui_qa`: resumed for independent screenshot review; may still be active at handoff. Do not continue it automatically after this explicit stop/handoff request.

No agent may be assumed to have approved the current runtime behavior. The crash is blocking. The user requested handoff NOW; stop after writing this file.
