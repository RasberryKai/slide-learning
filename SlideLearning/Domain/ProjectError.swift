import Foundation

enum ProjectError: LocalizedError, Equatable, Sendable {
    case invalidPDF
    case emptyPDF
    case encryptedPDF
    case unsupportedSchema(Int)
    case invalidMetadata(String)
    case projectUnavailable(ProjectAvailability)
    case importFailed(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPDF: "The selected file is not a valid PDF."
        case .emptyPDF: "The PDF contains no pages."
        case .encryptedPDF: "Password-protected PDFs are not supported."
        case .unsupportedSchema(let version): "This project uses an unsupported data version (\(version))."
        case .invalidMetadata(let message): message
        case .projectUnavailable(let availability):
            switch availability {
            case .missingProject: "The project folder is unavailable."
            case .missingSource: "The copied source PDF is unavailable."
            case .unreadableMetadata: "The project metadata cannot be read."
            case .unreadableSource: "The copied source PDF cannot be read."
            case .available: nil
            }
        case .importFailed(let message), .storageFailed(let message): message
        }
    }
}
