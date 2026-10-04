import Foundation

enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL, using fileManager: FileManager = .default) throws {
        try CoordinatedFileAccess.write(url) { coordinatedURL in
            try writeUncoordinated(data, to: coordinatedURL, using: fileManager)
        }
    }

    /// Performs the atomic replacement while the caller already owns a file
    /// coordinator access window. Keeping this separate avoids nested
    /// coordinators when a caller is doing an index read-modify-write.
    static func writeUncoordinated(_ data: Data, to url: URL, using fileManager: FileManager = .default) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let backupURL = url.appendingPathExtension("bak")
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            if fileManager.fileExists(atPath: url.path) {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: url, to: backupURL)
            }
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }

    /// Restores a previously decoded backup without first replacing the
    /// backup with the currently corrupt primary file.
    static func restore(_ data: Data, to url: URL, using fileManager: FileManager = .default) throws {
        try CoordinatedFileAccess.write(url) { coordinatedURL in
            try restoreUncoordinated(data, to: coordinatedURL, using: fileManager)
        }
    }

    static func restoreUncoordinated(_ data: Data, to url: URL, using fileManager: FileManager = .default) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).restore-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }
}
