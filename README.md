# Slide Learning

A native macOS and iPad app for studying PDF slides. Browse a thumbnail overview, select slides, and write plain-text notes next to each slide. Projects autosave locally by default, or in one user-selected shared folder so work can continue between a Mac and iPad.

Built with SwiftUI and PDFKit. No account or third-party dependencies required.

## Requirements

- macOS 26 or later, or iPadOS 18 or later.
- Xcode 26 or later (build verified with Xcode 26.6).

The Xcode project is included. You do **not** need XcodeGen to build or install the app.

## Build and run

1. Clone the repository:

   ```sh
   git clone https://github.com/RasberryKai/slide-learning.git
   cd slide-learning
   open SlideLearning.xcodeproj
   ```

   Alternatively, download and unzip the repository using GitHub's **Code → Download ZIP**, then open `SlideLearning.xcodeproj`.

2. Select the **SlideLearning** scheme and **My Mac** as the run destination in Xcode.
3. Choose **Product → Run** (`⌘R`) to build and launch the app.

For a local build, no paid Apple Developer membership is needed. If Xcode asks for signing settings, select the **SlideLearning** target, open **Signing & Capabilities**, and use **Sign to Run Locally** as the signing certificate for the local build.

## Install in Applications

To create an app you can launch without Xcode:

1. Open `SlideLearning.xcodeproj` and select **SlideLearning → My Mac**.
2. Choose **Product → Archive** and wait for the build to finish.
3. In the Organizer window, select the new archive. If the window does not open automatically, choose **Window → Organizer → Archives**.
4. Click **Distribute App → Custom → Copy App** and continue through the export dialog.
5. Choose a folder for the exported app.
6. In Finder, move the exported **SlideLearning.app** into your **Applications** folder.
7. Open **SlideLearning** from Applications or Spotlight.

This is a local installation workflow. **Copy App** does not notarize the app for distribution; friends can follow these steps to build and install it on their own Macs. See Apple's [distribution methods](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html) for how Copy App differs from Developer ID distribution.

## Using the app

- Import a PDF to create a project.
- Browse slides in the thumbnail sidebar and select the ones you want to export.
- Focus a slide and start typing to add notes. Press **Escape** to return to navigating slides.
- Use the **arrow keys** to move between slides and **Space** to toggle selection when you are not editing text.
- On Mac, press **⇧⌘C** (or choose **Edit → Copy Slide**) to copy the current slide as a high-resolution image, without notes. **⌘C** still copies selected text normally.
- Export selected slides and their notes to a new PDF.

Notes are separate from the source PDF; the app does not draw on or annotate the original file.

### Shared library setup

The app has no server and does not silently move a local library into the cloud. To continue work between devices:

1. Create or locate `iCloud Drive/Slide Learning` in Finder or Files.
2. On each device, choose **Choose iCloud Folder** and select that same folder. The app stores a security-scoped bookmark, so the choice survives relaunches.
3. The first selection copies existing local projects into the selected folder. Local originals remain in the device's Application Support library as a backup.
4. The library card shows whether the app is using its local library or the selected shared path. A selected path is not proof that the folder is in iCloud Drive; choose the folder from iCloud Drive on both devices.
5. iCloud may take time to upload or download PDFs and metadata. Use **Refresh** on the library screen after switching devices or when a project has not arrived yet.

If another device has changed a project since it was opened, saving refuses to overwrite it and preserves your edits in a `project.conflict-*.json` file alongside `project.json`. Conflict recovery currently requires inspecting those files; simultaneous editing is not merged automatically.

Deleting a project while a shared folder is selected removes its PDF, notes, and metadata from that shared folder for every device using it. Exported PDFs remain where they were saved.

On Mac, the default local project storage is:

```text
~/Library/Application Support/Slide Learning/
```

## Development

Build from Terminal:

```sh
xcodebuild -project SlideLearning.xcodeproj \
  -scheme SlideLearning -configuration Debug \
  -destination 'platform=macOS' build
```

Run tests using **Product → Test** (`⌘U`) in Xcode, or:

```sh
xcodebuild -project SlideLearning.xcodeproj \
  -scheme SlideLearning -destination 'platform=macOS' test
```

`project.yml` is the source of truth for the project configuration. If you change it, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and regenerate the checked-in project:

```sh
brew install xcodegen
xcodegen generate
```

See [FEATURE_SPEC.md](FEATURE_SPEC.md) for the detailed product specification.

## iPad version

Select the **SlideLearningIPad** scheme in the same Xcode project, then choose an iPad simulator and run. To install on your own iPad, select that device and choose your signing team under the iPad target's **Signing & Capabilities**.

The iPad interface supports portrait and landscape, Files PDF import, slide selection, plain-text notes, local or selected-folder autosave, and PDF sharing (including Save to Files). Tap a thumbnail to focus it; use its checkmark control to include or exclude it. Notes automatically select a slide when non-whitespace text is first entered. The notes toggle makes more room for the PDF.

Each device starts with a private local Application Support library. Selecting the same folder inside iCloud Drive on both devices makes the project library shared; no paid provisioning or app-specific iCloud entitlement is required. The app uses security-scoped folder access and coordinated file writes. iCloud availability, conflict resolution by the file provider, and upload/download timing remain outside the app's control.

Builds and automated tests do not prove that a physical Mac and iPad are signed into the same iCloud account or that a cloud file has finished downloading. Verify the folder choice, cross-device arrival, and cloud delay behavior on the devices you intend to use.

Run the shared persistence, selection, PDF validation, export, and thumbnail tests on an iPad simulator:

```sh
xcodebuild -project SlideLearning.xcodeproj \
  -scheme SlideLearningIPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

See [IPAD_IMPLEMENTATION.md](IPAD_IMPLEMENTATION.md) for scope and verification evidence.
