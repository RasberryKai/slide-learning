import Foundation

enum SlideFilter: String, Codable, CaseIterable, Sendable {
    case all
    case selected
}

enum FocusDirection: Sendable {
    case previous
    case next
}

enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case compact
    case regular
    case large

    var width: Double {
        switch self {
        case .compact: 150
        case .regular: 220
        case .large: 300
        }
    }
}
