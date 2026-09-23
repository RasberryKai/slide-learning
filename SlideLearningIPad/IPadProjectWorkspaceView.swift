import PDFKit
import SwiftUI
import UIKit

enum IPadWorkspaceFocus: Hashable { case workspace, notes }

private enum IPadSlideNavigationSide {
    case left
    case right
}

private enum IPadWorkspaceKey {
    case previous
    case next
    case toggleSelection
    case notes
    case escape
    case printable(String)
}

struct IPadProjectWorkspaceView: View {
    @ObservedObject var model: ProjectViewModel
    let thumbnailProvider: any SlideThumbnailProviding
    let exporter: any SlideExporting
    let onBack: () -> Void

    @FocusState private var keyboardFocus: IPadWorkspaceFocus?
    @State private var sourceURL: URL?
    @State private var exportState: ExportState = .idle
    @State private var shareItem: IPadShareItem?
    @State private var isCopyingSlide = false
    @State private var copyError: String?
    @State private var workspaceFocusRequest = 0

    enum ExportState: Equatable {
        case idle
        case exporting
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            workspace
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .background {
            IPadWorkspaceKeyCapture(
                isActive: keyboardFocus != .notes && shareItem == nil,
                focusRequest: workspaceFocusRequest,
                onKey: handleWorkspaceKey
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .task(id: model.project.id) {
            sourceURL = await model.sourceURL()
        }
        .onAppear { requestWorkspaceFocus() }
        .onChange(of: model.project.viewPreferences.focusedPageIndex) { _, _ in
            if keyboardFocus == .notes {
                requestWorkspaceFocus()
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { if case .failure = exportState { return true }; return false },
            set: { if !$0 { exportState = .idle } }
        )) {
            Button("Retry") { beginExport() }
            Button("Cancel", role: .cancel) { exportState = .idle }
        } message: {
            if case .failure(let message) = exportState { Text(message) }
        }
        .alert("Could not copy slide", isPresented: Binding(
            get: { copyError != nil },
            set: { if !$0 { copyError = nil } }
        )) {
            Button("OK", role: .cancel) { copyError = nil }
        } message: {
            Text(copyError ?? "")
        }
        .sheet(item: $shareItem) { item in
            IPadShareSheet(activityItems: [item.url]) {
                finishSharing(item)
            }
            .ignoresSafeArea()
            .onDisappear { finishSharing(item) }
        }
        .alert("Could not save project", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        ), presenting: model.error) { _ in
            Button("OK") { model.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    guard exportState != .exporting else { return }
                    onBack()
                } label: {
                    Label("Library", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(exportState == .exporting)
                .accessibilityIdentifier("slideLearning.back")

                Text(model.project.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Picker("Show", selection: Binding(
                        get: { model.project.viewPreferences.filter },
                        set: { model.dispatch(.setFilter($0)) }
                    )) {
                        Text("All").tag(SlideFilter.all)
                        Text("Selected").tag(SlideFilter.selected)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)

                    Picker("Thumbnail size", selection: Binding(
                        get: { model.project.viewPreferences.thumbnailSize },
                        set: { model.dispatch(.setThumbnailSize($0)) }
                    )) {
                        Text("Compact").tag(ThumbnailSize.compact)
                        Text("Regular").tag(ThumbnailSize.regular)
                        Text("Large").tag(ThumbnailSize.large)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 118)

                    Text("\(model.selectedCount) of \(model.totalCount) selected")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    Button {
                        beginExport()
                    } label: {
                        if exportState == .exporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedCount == 0 || exportState == .exporting)
                    .accessibilityIdentifier("slideLearning.export")

                    copySlideButton
                    notesVisibilityButton
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var notesVisibilityButton: some View {
        if model.project.viewPreferences.inspectorVisible {
            notesButton
        } else {
            notesButton
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var notesButton: some View {
        Button {
            toggleNotesVisibility()
        } label: {
            Label(
                model.project.viewPreferences.inspectorVisible ? "Hide Notes" : "Show Notes",
                systemImage: model.project.viewPreferences.inspectorVisible ? "note.text" : "note.text.badge.plus"
            )
        }
        .buttonStyle(.bordered)
    }

    private var copySlideButton: some View {
        Button {
            copyCurrentSlide()
        } label: {
            if isCopyingSlide {
                ProgressView().controlSize(.small)
            } else {
                Label("Copy Slide", systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.bordered)
        .disabled(model.project.viewPreferences.focusedPageIndex == nil || isCopyingSlide)
        .accessibilityIdentifier("slideLearning.copySlide")
    }

    private func toggleNotesVisibility() {
        if model.project.viewPreferences.inspectorVisible {
            requestWorkspaceFocus()
            model.dispatch(.setInspectorVisible(false))
        } else {
            let shouldFocusNotes = focusedNoteIsEmpty
            model.dispatch(.setInspectorVisible(true))
            if shouldFocusNotes {
                DispatchQueue.main.async {
                    DispatchQueue.main.async {
                        keyboardFocus = .notes
                    }
                }
            } else {
                requestWorkspaceFocus()
            }
        }
    }

    private var focusedNoteIsEmpty: Bool {
        guard let pageIndex = model.project.viewPreferences.focusedPageIndex,
              model.project.slides.indices.contains(pageIndex) else { return false }
        return model.project.slides[pageIndex].note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func copyCurrentSlide() {
        guard !isCopyingSlide,
              let pageIndex = model.project.viewPreferences.focusedPageIndex else { return }
        let project = model.project
        isCopyingSlide = true
        Task { @MainActor in
            defer { isCopyingSlide = false }
            guard let image = await thumbnailProvider.thumbnail(for: project, pageIndex: pageIndex, width: 2000) else {
                copyError = "The slide image could not be rendered. Please try again."
                return
            }
            UIPasteboard.general.image = image
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let requestedSidebar = CGFloat(model.project.viewPreferences.thumbnailSize.width + 34)
            let maximumSidebar = min(360, max(180, geometry.size.width - 320))
            let sidebarWidth = max(90, min(requestedSidebar, maximumSidebar))
            let thumbnailWidth = max(64, sidebarWidth - 28)

            HStack(spacing: 0) {
                IPadThumbnailSidebar(
                    model: model,
                    thumbnailProvider: thumbnailProvider,
                    thumbnailWidth: thumbnailWidth,
                    setWorkspaceFocus: requestWorkspaceFocus
                )
                .frame(width: sidebarWidth)

                Divider()

                IPadSlideInspector(
                    model: model,
                    sourceURL: sourceURL,
                    keyboardFocus: $keyboardFocus,
                    setWorkspaceFocus: requestWorkspaceFocus
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func requestWorkspaceFocus() {
        keyboardFocus = nil
        workspaceFocusRequest &+= 1
        DispatchQueue.main.async {
            keyboardFocus = .workspace
        }
    }

    private func handleWorkspaceKey(_ key: IPadWorkspaceKey) {
        switch key {
        case .escape:
            requestWorkspaceFocus()
        case .previous:
            guard keyboardFocus != .notes else { return }
            model.dispatch(.moveFocus(.previous))
        case .next:
            guard keyboardFocus != .notes else { return }
            model.dispatch(.moveFocus(.next))
        case .toggleSelection:
            guard keyboardFocus != .notes else { return }
            model.dispatch(.toggleFocusedSelection)
        case .notes:
            guard keyboardFocus != .notes else { return }
            if !model.project.viewPreferences.inspectorVisible {
                model.dispatch(.setInspectorVisible(true))
            }
            DispatchQueue.main.async {
                keyboardFocus = .notes
            }
        case .printable(let characters):
            guard keyboardFocus != .notes,
                  let index = model.project.viewPreferences.focusedPageIndex,
                  !characters.isEmpty else { return }
            model.dispatch(.setInspectorVisible(true))
            model.dispatch(.updateNote(pageIndex: index, text: model.project.slides[index].note + characters))
            DispatchQueue.main.async {
                keyboardFocus = .notes
            }
        }
    }

    private func beginExport() {
        guard model.selectedCount > 0, exportState != .exporting else { return }
        let project = model.project
        exportState = .exporting
        Task { @MainActor in
            let source = await model.sourceURL()
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SlideLearningExport-\(UUID().uuidString)", isDirectory: true)
            let stem = URL(fileURLWithPath: project.sourceFilename)
                .deletingPathExtension().lastPathComponent
            let filename = "\(stem) – Selected Slides.pdf"
            let temporary = temporaryDirectory.appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                try await exporter.export(
                    ExportRequest(
                        project: project,
                        sourceURL: source,
                        destinationURL: temporary,
                        managedProjectsRootURL: await model.managedProjectsRootURL()
                    ),
                    progress: { _ in }
                )
                exportState = .idle
                shareItem = IPadShareItem(url: temporary, directoryURL: temporaryDirectory)
            } catch let error as ProjectError {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                exportState = .failure(error.localizedDescription)
            } catch {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                exportState = .failure(error.localizedDescription)
            }
        }
    }

    private func finishSharing(_ item: IPadShareItem) {
        try? FileManager.default.removeItem(at: item.directoryURL)
        if shareItem?.id == item.id {
            shareItem = nil
        }
    }
}

private struct IPadWorkspaceKeyCapture: UIViewRepresentable {
    let isActive: Bool
    let focusRequest: Int
    let onKey: (IPadWorkspaceKey) -> Void

    final class Coordinator {
        var lastFocusRequest: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKey = onKey
        return view
    }

    func updateUIView(_ view: KeyView, context: Context) {
        view.onKey = onKey
        view.shouldBeFirstResponder = isActive
        if isActive {
            if context.coordinator.lastFocusRequest != focusRequest || !view.isFirstResponder {
                context.coordinator.lastFocusRequest = focusRequest
                DispatchQueue.main.async {
                    guard view.window != nil, view.shouldBeFirstResponder else { return }
                    if !view.isFirstResponder {
                        view.becomeFirstResponder()
                    }
                }
            }
        } else if view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ view: KeyView, coordinator: Coordinator) {
        view.resignFirstResponder()
        view.onKey = nil
    }

    final class KeyView: UIView {
        var onKey: ((IPadWorkspaceKey) -> Void)?
        var shouldBeFirstResponder = false

        override var canBecomeFirstResponder: Bool { true }

        override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(returnKeyCommand)),
                UIKeyCommand(input: "\n", modifierFlags: [], action: #selector(returnKeyCommand))
            ].map { command in
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }

        @objc private func returnKeyCommand(_ command: UIKeyCommand) {
            guard self.shouldBeFirstResponder else { return }
            onKey?(.notes)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, shouldBeFirstResponder else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.shouldBeFirstResponder else { return }
                self.becomeFirstResponder()
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key else { continue }
                guard key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else {
                    continue
                }

                switch key.keyCode {
                case .keyboardLeftArrow, .keyboardUpArrow:
                    onKey?(.previous)
                    handled = true
                case .keyboardRightArrow, .keyboardDownArrow:
                    onKey?(.next)
                    handled = true
                case .keyboardSpacebar:
                    onKey?(.toggleSelection)
                    handled = true
                case .keyboardReturnOrEnter, .keypadEnter, .keyboardReturn:
                    onKey?(.notes)
                    handled = true
                case .keyboardEscape:
                    onKey?(.escape)
                    handled = true
                default:
                    let characters = key.characters
                    guard !characters.isEmpty,
                          characters.unicodeScalars.allSatisfy({
                              !CharacterSet.controlCharacters.contains($0)
                                  && !(0xF700...0xF8FF).contains($0.value)
                          }) else { continue }
                    onKey?(.printable(characters))
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }
    }
}

private struct IPadThumbnailSidebar: View {
    @ObservedObject var model: ProjectViewModel
    let thumbnailProvider: any SlideThumbnailProviding
    let thumbnailWidth: CGFloat
    let setWorkspaceFocus: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(model.visibleSlides) { slide in
                        IPadThumbnailCell(
                            slide: slide,
                            pageCount: model.totalCount,
                            project: model.project,
                            width: thumbnailWidth,
                            isFocused: model.project.viewPreferences.focusedPageIndex == slide.pageIndex,
                            provider: thumbnailProvider,
                            focus: {
                                setWorkspaceFocus()
                                model.dispatch(.focus(pageIndex: slide.pageIndex))
                            },
                            setSelected: {
                                setWorkspaceFocus()
                                model.dispatch(.setSelection(pageIndex: slide.pageIndex, selected: $0))
                            }
                )
                        .id(slide.pageIndex)
                    }
                }
                .padding(14)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                if model.visibleSlides.isEmpty {
                    ContentUnavailableView("No selected slides", systemImage: "checkmark.circle", description: Text("Select slides in All view to see them here."))
                        .padding(10)
                }
            }
            .onChange(of: model.project.viewPreferences.focusedPageIndex) { _, pageIndex in
                guard let pageIndex else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(pageIndex, anchor: .center)
                }
            }
            .onAppear {
                guard let pageIndex = model.project.viewPreferences.focusedPageIndex else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(pageIndex, anchor: .center)
                }
            }
        }
    }
}

private struct IPadThumbnailCell: View {
    let slide: SlideState
    let pageCount: Int
    let project: Project
    let width: CGFloat
    let isFocused: Bool
    let provider: any SlideThumbnailProviding
    let focus: () -> Void
    let setSelected: (Bool) -> Void
    @State private var thumbnail: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button(action: focus) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .overlay {
                                    ProgressView().controlSize(.small)
                                }
                        }
                    }
                    .frame(width: width, height: width * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("slideLearning.thumbnail.\(slide.pageIndex)")
                .accessibilityLabel("Focus slide \(slide.pageIndex + 1)")
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            isFocused ? Color.blue : (slide.isSelected ? Color.primary : Color.secondary.opacity(0.25)),
                            lineWidth: isFocused || slide.isSelected ? 3 : 1
                        )
                }
                HStack(spacing: 5) {
                    Button { setSelected(!slide.isSelected) } label: {
                        Image(systemName: slide.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(slide.isSelected ? Color.blue : Color.secondary, Color(uiColor: .systemBackground))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("slideLearning.selection.\(slide.pageIndex)")
                    .accessibilityLabel(slide.isSelected ? "Deselect slide \(slide.pageIndex + 1)" : "Select slide \(slide.pageIndex + 1)")
                    if !slide.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "note.text")
                            .foregroundStyle(Color.blue)
                    }
                    }
                    .padding(7)
                }
            Text("Slide \(slide.pageIndex + 1) of \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: "\(project.id)-\(slide.pageIndex)-\(Int(width))") {
            thumbnail = await provider.thumbnail(for: project, pageIndex: slide.pageIndex, width: Double(width))
        }
    }
}

private struct IPadSlideInspector: View {
    @ObservedObject var model: ProjectViewModel
    let sourceURL: URL?
    var keyboardFocus: FocusState<IPadWorkspaceFocus?>.Binding
    let setWorkspaceFocus: () -> Void

    private var focusedSlide: SlideState? {
        guard let index = model.project.viewPreferences.focusedPageIndex else { return nil }
        return model.project.slides.first { $0.pageIndex == index }
    }

    var body: some View {
        if let focusedSlide, let sourceURL {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    IPadPDFPreview(
                        sourceURL: sourceURL,
                        pageIndex: focusedSlide.pageIndex,
                        onNavigationTap: { side in
                            setWorkspaceFocus()
                            model.dispatch(.moveFocus(side == .left ? .previous : .next))
                        },
                        onSelectionTap: {
                            setWorkspaceFocus()
                            model.dispatch(.toggleFocusedSelection)
                        }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(18)

                    if model.project.viewPreferences.inspectorVisible {
                        Divider()
                        notesEditor(for: focusedSlide)
                            .frame(height: min(190, max(150, geometry.size.height * 0.27)))
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
        } else {
            ContentUnavailableView(
                focusedSlide == nil ? "No slide focused" : "Loading deck",
                systemImage: focusedSlide == nil ? "sidebar.right" : "doc.richtext",
                description: Text(focusedSlide == nil ? "Select a slide to inspect it." : "Preparing the active slide…")
            )
        }
    }

    private func notesEditor(for slide: SlideState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes — Slide \(slide.pageIndex + 1)")
                    .font(.headline)
                Spacer()
                Text("Esc to return to slides")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(
                get: { model.project.slides[slide.pageIndex].note },
                set: { model.dispatch(.updateNote(pageIndex: slide.pageIndex, text: $0)) }
            ))
            .focused(keyboardFocus, equals: .notes)
            .simultaneousGesture(TapGesture().onEnded { keyboardFocus.wrappedValue = .notes })
            .onKeyPress(.escape) {
                setWorkspaceFocus()
                return .handled
            }
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 60, maxHeight: 180)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2))
            }
            .accessibilityLabel("Notes for slide \(slide.pageIndex + 1)")
            .accessibilityIdentifier("slideLearning.noteEditor")
        }
        .padding(18)
    }
}

private struct IPadPDFPreview: UIViewRepresentable {
    let sourceURL: URL
    let pageIndex: Int
    let onNavigationTap: (IPadSlideNavigationSide) -> Void
    let onSelectionTap: () -> Void

    @MainActor
    final class PreviewContainer: UIView, UIGestureRecognizerDelegate {
        private(set) var pdfView: PDFView?
        var onNavigationTap: ((IPadSlideNavigationSide) -> Void)?
        var onSelectionTap: (() -> Void)?

        private lazy var navigationTapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleNavigationTap(_:)))
            gesture.numberOfTapsRequired = 1
            gesture.numberOfTouchesRequired = 1
            gesture.cancelsTouchesInView = false
            return gesture
        }()

        private lazy var selectionTapGesture: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap))
            gesture.numberOfTapsRequired = 1
            gesture.numberOfTouchesRequired = 2
            gesture.cancelsTouchesInView = false
            return gesture
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .systemBackground
            clipsToBounds = true
            navigationTapGesture.delegate = self
            selectionTapGesture.delegate = self
            addGestureRecognizer(navigationTapGesture)
            addGestureRecognizer(selectionTapGesture)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func install(_ view: PDFView) {
            removePDFView()
            pdfView = view
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            suppressPDFKitDoubleTapZoom()
        }

        func removePDFView() {
            guard let pdfView else { return }
            pdfView.document = nil
            pdfView.removeFromSuperview()
            self.pdfView = nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            suppressPDFKitDoubleTapZoom()
        }

        @objc private func handleNavigationTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let location = gesture.location(in: self)
            onNavigationTap?(location.x < bounds.midX ? .left : .right)
        }

        @objc private func handleSelectionTap() {
            onSelectionTap?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if (gestureRecognizer === navigationTapGesture && isNavigationBlockingGesture(otherGestureRecognizer))
                || (otherGestureRecognizer === navigationTapGesture && isNavigationBlockingGesture(gestureRecognizer)) {
                return false
            }
            return true
        }

        private func isNavigationBlockingGesture(_ gesture: UIGestureRecognizer) -> Bool {
            gesture === selectionTapGesture || gesture is UILongPressGestureRecognizer
        }

        private func suppressPDFKitDoubleTapZoom() {
            guard pdfView != nil else { return }
            disableDoubleTapZoomGestures(in: self)
        }

        private func disableDoubleTapZoomGestures(in view: UIView) {
            view.gestureRecognizers?.forEach { recognizer in
                guard recognizer !== navigationTapGesture,
                      recognizer !== selectionTapGesture,
                      let tap = recognizer as? UITapGestureRecognizer,
                      tap.numberOfTapsRequired > 1,
                      view is UIScrollView else { return }
                tap.isEnabled = false
            }
            view.subviews.forEach { disableDoubleTapZoomGestures(in: $0) }
        }
    }

    @MainActor
    final class Coordinator {
        var sourceURL: URL?
        var sourceDocument: PDFDocument?
        var displayedPageIndex: Int?

        func document(for url: URL) -> PDFDocument? {
            if sourceURL != url {
                sourceURL = url
                sourceDocument = PDFDocument(url: url)
                displayedPageIndex = nil
            }
            return sourceDocument
        }

        @discardableResult
        func displayPage(at index: Int, in container: PreviewContainer) -> Bool {
            if displayedPageIndex == index, container.pdfView != nil { return false }
            guard let sourceDocument,
                  let sourcePage = sourceDocument.page(at: index) else {
                container.removePDFView()
                displayedPageIndex = nil
                return false
            }

            guard let singlePageDocument = makeIndependentDocument(for: sourcePage) else {
                container.removePDFView()
                displayedPageIndex = nil
                return false
            }
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(false)
            view.displaysPageBreaks = false
            view.backgroundColor = .systemBackground
            view.document = singlePageDocument
            if let page = singlePageDocument.page(at: 0) {
                view.go(to: page)
            }
            container.install(view)
            displayedPageIndex = index
            return true
        }

        private func makeIndependentDocument(for page: PDFPage) -> PDFDocument? {
            guard let data = page.dataRepresentation else { return nil }
            return PDFDocument(data: data)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.onNavigationTap = onNavigationTap
        view.onSelectionTap = onSelectionTap
        _ = context.coordinator.document(for: sourceURL)
        _ = context.coordinator.displayPage(at: pageIndex, in: view)
        return view
    }

    func updateUIView(_ view: PreviewContainer, context: Context) {
        view.onNavigationTap = onNavigationTap
        view.onSelectionTap = onSelectionTap
        _ = context.coordinator.document(for: sourceURL)
        if context.coordinator.displayPage(at: pageIndex, in: view) {
            view.pdfView?.autoScales = true
        }
    }

    static func dismantleUIView(_ view: PreviewContainer, coordinator: Coordinator) {
        view.removePDFView()
        coordinator.sourceDocument = nil
        coordinator.sourceURL = nil
        coordinator.displayedPageIndex = nil
    }
}

private struct IPadShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private struct IPadShareItem: Identifiable {
    let url: URL
    let directoryURL: URL
    var id: URL { url }
}
