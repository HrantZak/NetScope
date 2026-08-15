import Foundation

/// Serialises scan results to CSV or JSON and stages a file for the share sheet.
enum ExportService {

    enum Format: String, CaseIterable, Identifiable, Sendable {
        case csv
        case json

        var id: String { rawValue }

        var title: String {
            switch self {
            case .csv: "CSV"
            case .json: "JSON"
            }
        }

        var symbolName: String {
            switch self {
            case .csv: "tablecells"
            case .json: "curlybraces"
            }
        }

        var fileExtension: String { rawValue }
    }

    /// Envelope written for JSON exports: results plus the context they were
    /// captured in, so a file is meaningful on its own.
    private struct Export: Encodable {
        struct Network: Encodable {
            var name: String
            var interface: String?
            var localAddress: String?
            var subnet: String?
            var gateway: String?
            var dnsServers: [String]
            var ssid: String?
        }

        var generatedAt: Date
        var application: String
        var deviceCount: Int
        var network: Network
        var devices: [Device]
    }

    // MARK: - Public

    /// Builds the export payload for the given devices.
    static func makeData(
        devices: [Device],
        snapshot: NetworkSnapshot,
        format: Format
    ) throws -> Data {
        switch format {
        case .json:
            return try makeJSON(devices: devices, snapshot: snapshot)
        case .csv:
            return makeCSV(devices: devices)
        }
    }

    /// Writes the export to a temporary file and returns its URL.
    static func makeFile(
        devices: [Device],
        snapshot: NetworkSnapshot,
        format: Format
    ) async throws -> URL {
        let data = try makeData(devices: devices, snapshot: snapshot, format: format)

        let stamp = ISO8601DateFormatter.filenameFormatter.string(from: .now)
        let name = "NetScope-\(stamp).\(format.fileExtension)"

        await FileStore.shared.pruneExports()
        return try await FileStore.shared.writeExport(data, filename: name)
    }

    // MARK: - Formats

    private static func makeJSON(devices: [Device], snapshot: NetworkSnapshot) throws -> Data {
        let payload = Export(
            generatedAt: .now,
            application: "NetScope 1.0",
            deviceCount: devices.count,
            network: .init(
                name: snapshot.displayName,
                interface: snapshot.interfaceName,
                localAddress: snapshot.localAddress?.description,
                subnet: snapshot.subnet?.description,
                gateway: snapshot.gateway?.description,
                dnsServers: snapshot.dnsServers.map(\.description),
                ssid: snapshot.ssid
            ),
            devices: devices.sorted { $0.ipAddress < $1.ipAddress }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func makeCSV(devices: [Device]) -> Data {
        let columns = [
            "IP Address", "Name", "Hostname", "Bonjour Name", "MAC Address", "Vendor",
            "Type", "Status", "Latency (ms)", "Open Ports", "Services",
            "Discovery", "Gateway", "Favorite", "First Seen", "Last Seen", "Times Seen", "Notes"
        ]

        var rows: [String] = [columns.joined(separator: ",")]
        rows.reserveCapacity(devices.count + 1)

        let formatter = ISO8601DateFormatter()

        for device in devices.sorted(by: { $0.ipAddress < $1.ipAddress }) {
            let latency = device.latencyMilliseconds.map { String(format: "%.1f", $0) } ?? ""
            let services = device.services
                .map { "\($0.port)/\($0.displayName)" }
                .joined(separator: "; ")

            let fields = [
                device.ipAddress.description,
                device.displayName,
                device.hostname ?? "",
                device.bonjourName ?? "",
                device.macAddress ?? "",
                device.vendor ?? "",
                device.kind.title,
                device.isOnline ? "Online" : "Offline",
                latency,
                device.openPorts.map(String.init).joined(separator: " "),
                services,
                device.discoveryMethod.title,
                device.isGateway ? "yes" : "no",
                device.isFavorite ? "yes" : "no",
                formatter.string(from: device.firstSeen),
                formatter.string(from: device.lastSeen),
                String(device.timesSeen),
                device.notes ?? ""
            ]

            rows.append(fields.map(escapeCSV).joined(separator: ","))
        }

        // BOM keeps Excel from mangling non-ASCII device names.
        let bom = Data([0xEF, 0xBB, 0xBF])
        return bom + Data(rows.joined(separator: "\r\n").utf8)
    }

    /// Quotes a field when it contains a delimiter, quote or newline.
    private static func escapeCSV(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension ISO8601DateFormatter {
    /// Sortable and filename safe. `nonisolated(unsafe)` for the same reason as
    /// the formatters in `Formatters`: configured once, then read-only.
    nonisolated(unsafe) static let filenameFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        return formatter
    }()
}
