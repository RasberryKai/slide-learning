# iPad implementation

The iPad app is a separate application target in the existing Xcode project. It shares the domain model, reducer, storage, view models, PDF validation, thumbnail worker, and vector PDF exporter with the Mac app. Platform-specific views and app lifecycle live in `SlideLearningIPad`.

## Delivery contract

| Requirement | Implementation | Verification |
| --- | --- | --- |
| Dark deck library; portrait and landscape | Adaptive SwiftUI library, native Files importer | Simulator UI checks |
| Independent focus and selection | Shared reducer; thumbnail and separate selection control | Shared reducer tests and UI checks |
| All / Selected and thumbnail size | Saved shared view preferences | Shared reducer tests and UI checks |
| Large slide with notes below | PDFKit preview and keyboard-aware notes editor | Simulator portrait/landscape checks |
| Notes auto-select; survive deselection | Shared reducer and autosave | Shared tests and UI checks |
| Relaunch restores edits and view preferences | Shared atomic project store; lifecycle flush | Shared persistence tests and UI checks |
| Source-quality selected PDF with notes | Shared Core Graphics exporter; native share sheet | Shared PDF tests and UI export check |
| Confirm deletion | Native confirmation before shared store deletion | Simulator UI check |
| Preserve Mac app | Separate target and conditional image type | Mac build and regression suite |

## Scope

- iPadOS 18+, iPad only, portrait and landscape, including resized windows.
- Local PDF import, curation, notes, autosave, and export.
- Native keyboard and share/Files interfaces; mockup keyboard keys are not custom UI.
- Plain-text notes only. No drawing or PDF annotations.
- Mac and iPad have independent local libraries. No cloud synchronization or project-transfer format.
- Device installation requires configuring signing in Xcode; simulator builds do not.

## Validation

The original shared core passed all 19 tests on both Mac and iPad on 2026-09-21. These cover reducer behavior, persistence/recovery, PDF validation, vector/selectable-text export, mixed page geometry, long notes, and thumbnail cache reload. After adding a failed-save recovery regression, all 20 Mac tests passed. Back navigation now keeps unsaved edits and the workspace open when the final save fails; retry is verified to persist the note to disk before closing.

The iPad preview now loads an independent single-page PDF representation into a fresh PDF view when focus changes. This avoids the copied-page backing lifetime implicated in the reproducible PDF accessibility crash. Accessibility remains enabled. Failed page loading clears the previous preview rather than showing it beside a different slide's notes. A rotated/cropped fixture retained its rotation, crop/media boxes, and text after page isolation.

Final expanded UI and visual-review results are pending below; the deployment target alone does not establish physical-device or iPadOS 18 runtime compatibility.

## Reproducing simulator UI checks

Build and run the iPad scheme once on your chosen simulator, then terminate the app. Add the generated, non-private 90-page fixture:

```sh
python3 scripts/seed-ipad-simulator.py --pages 90 <simulator-UDID>
```

The script adds only the fixed `Finance Review` QA project and refuses to overwrite an existing fixture unless `--reset` is supplied. Reset checks the project ID and name before replacing this disposable QA deck. Terminate the app before seeding or resetting, then relaunch to load it. The UI suite in `SlideLearningIPadUITests` uses that project and may alter its selections and notes. Use 90 pages for the full suite. Run the UI target with Product → Test, or add `-only-testing:SlideLearningIPadUITests` to the iPad test command. Fixture-dependent tests skip when the fixture is absent; missing controls or broken behavior must fail.

The generator and seeding script are development tools, not part of either application.
