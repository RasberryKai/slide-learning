import Foundation

struct SlideState: Codable, Equatable, Sendable, Identifiable {
    let pageIndex: Int
    var isSelected: Bool
    var note: String

    var id: Int { pageIndex }
}

struct ViewPreferences: Codable, Equatable, Sendable {
    var focusedPageIndex: Int?
    var inspectorVisible: Bool
    var thumbnailSize: ThumbnailSize
    var filter: SlideFilter

    static let `default` = ViewPreferences(
        focusedPageIndex: nil,
        inspectorVisible: true,
        thumbnailSize: .regular,
        filter: .all
    )
}

struct Project: Codable, Equatable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Project.currentSchemaVersion
    let id: UUID
    var name: String
    let sourceFilename: String
    let pageCount: Int
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var slides: [SlideState]
    var viewPreferences: ViewPreferences

    var selectedCount: Int {
        slides.reduce(into: 0) { count, slide in
            if slide.isSelected { count += 1 }
        }
    }

    var visiblePageIndices: [Int] {
        switch viewPreferences.filter {
        case .all: slides.map(\.pageIndex)
        case .selected: slides.filter(\.isSelected).map(\.pageIndex)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        sourceFilename: String,
        pageCount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        slides: [SlideState]? = nil,
        viewPreferences: ViewPreferences = .default
    ) {
        let now = createdAt
        self.id = id
        self.name = name
        self.sourceFilename = sourceFilename
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? now
        self.lastOpenedAt = lastOpenedAt ?? now
        self.slides = slides ?? (0..<max(0, pageCount)).map {
            SlideState(pageIndex: $0, isSelected: false, note: "")
        }
        self.viewPreferences = viewPreferences
    }

    func validated() throws -> Project {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ProjectError.unsupportedSchema(schemaVersion)
        }
        guard pageCount > 0,
              slides.count == pageCount,
              slides.enumerated().allSatisfy({ $0.element.pageIndex == $0.offset }) else {
            throw ProjectError.invalidMetadata("Slide state does not match the source page count")
        }
        if let focused = viewPreferences.focusedPageIndex,
           !(0..<pageCount).contains(focused) {
            throw ProjectError.invalidMetadata("Focused page is outside the source document")
        }
        return self
    }
}

struct ProjectSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var sourceFilename: String
    var pageCount: Int
    var selectedCount: Int
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var availability: ProjectAvailability

    init(project: Project, availability: ProjectAvailability = .available) {
        id = project.id
        name = project.name
        sourceFilename = project.sourceFilename
        pageCount = project.pageCount
        selectedCount = project.selectedCount
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        lastOpenedAt = project.lastOpenedAt
        self.availability = availability
    }
}

enum ProjectAvailability: String, Codable, Sendable {
    case available
    case missingProject
    case missingSource
    case unreadableMetadata
    case unreadableSource
}
