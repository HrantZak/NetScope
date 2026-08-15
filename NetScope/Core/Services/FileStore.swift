import Foundation
import OSLog

/// Small JSON-file persistence layer.
///
/// An `actor` so writes are serialised and never touch the main thread — the
/// device list can hold thousands of records and encoding it must not stutter
/// scrolling.
actor FileStore {

    static let shared = FileStore()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryName: String = "NetScopeData") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory

        directory = base.appendingPathComponent(directoryName, isDirectory: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// Loads and decodes a value, returning `nil` for anything unreadable.
    ///
    /// A corrupt cache is never fatal: it is discarded and rebuilt on the next
    /// scan rather than blocking launch.
    func load<Value: Decodable & Sendable>(_ type: Value.Type, from name: String) -> Value? {
        let fileURL = url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(Value.self, from: data)
        } catch {
            Log.storage.error("Failed to load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Encodes and writes atomically.
    @discardableResult
    func save<Value: Encodable & Sendable>(_ value: Value, to name: String) -> Bool {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(for: name), options: [.atomic])
            return true
        } catch {
            Log.storage.error("Failed to save \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Writes arbitrary data (used by CSV/JSON export) into a temporary file
    /// suitable for the share sheet.
    func writeExport(_ data: Data, filename: String) throws -> URL {
        let exportDirectory = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let fileURL = exportDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    /// Removes export files older than an hour so the container stays tidy.
    func pruneExports() {
        let exportDirectory = directory.appendingPathComponent("Exports", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date.now.addingTimeInterval(-3600)
        for fileURL in contents {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

/// Namespaced loggers. `OSLog` is free, structured and stripped in release.
enum Log {
    static let scan = Logger(subsystem: "com.netscope.NetScope", category: "scan")
    static let network = Logger(subsystem: "com.netscope.NetScope", category: "network")
    static let storage = Logger(subsystem: "com.netscope.NetScope", category: "storage")
    static let ui = Logger(subsystem: "com.netscope.NetScope", category: "ui")
}
