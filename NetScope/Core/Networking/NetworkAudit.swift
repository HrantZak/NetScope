import Foundation

/// Twenty lightweight, local-only checks that turn raw scan data into useful
/// next steps. No traffic is generated here; the audit is safe to recompute on
/// every repository update.
enum NetworkAudit {
    enum Level: Int, Sendable {
        case good, info, warning

        var symbolName: String {
            switch self {
            case .good: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }
    }

    struct Check: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let level: Level
    }

    static func checks(snapshot: NetworkSnapshot, devices: [Device]) -> [Check] {
        let online = devices.filter(\.isOnline)
        let ports = Set(online.flatMap(\.openPorts))
        let recentCutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        let highLatency = online.filter { ($0.latencyMilliseconds ?? 0) > 100 }
        let randomized = devices.filter { device in
            device.macAddress.map { VendorDatabase.isRandomized(mac: $0) } == true
        }

        return [
            check("connection", "Active connection", snapshot.isConnected, "Connected through \(snapshot.interfaceType.title)", "No usable local connection"),
            check("address", "Local IPv4", snapshot.localAddress != nil, snapshot.localAddress?.description ?? "Unavailable", "An IPv4 address is required for scanning"),
            check("subnet", "Subnet detected", snapshot.subnet != nil, snapshot.subnet?.description ?? "Unavailable", "Could not calculate the scan range"),
            check("gateway", "Gateway detected", snapshot.gateway != nil, snapshot.gateway?.description ?? "Unavailable", "Router address was not found"),
            check("dns", "DNS available", !snapshot.dnsServers.isEmpty, snapshot.dnsServers.map(\.description).joined(separator: ", "), "No DNS resolver was detected"),
            check("security", "Wi-Fi security", snapshot.isSecure != false, snapshot.isSecure == nil ? "Security status is hidden by iOS" : "Network reports encryption", "This Wi-Fi network appears to be open"),
            check("router", "Router identified", devices.contains(where: { $0.isGateway }), devices.first(where: { $0.isGateway })?.displayName ?? "Gateway is not in the device list", "Run another scan near the router"),
            countCheck("online", "Online devices", online.count, empty: "No remote device answered", suffix: "currently reachable"),
            countCheck("new", "New in the last 24 hours", devices.filter { $0.firstSeen >= recentCutoff && !$0.isLocalDevice }.count, empty: "No newly seen devices", suffix: "new devices to review"),
            warningCount("unknown", "Unknown device types", devices.filter { $0.kind == .unknown }.count, clear: "Every device has a likely type", suffix: "need classification"),
            warningCount("offline", "Offline records", devices.filter { !$0.isOnline }.count, clear: "All stored devices are online", suffix: "did not answer the latest scan"),
            warningCount("latency", "High latency", highLatency.count, clear: "No device is above 100 ms", suffix: "devices above 100 ms"),
            countCheck("services", "Devices with services", online.filter { !$0.services.isEmpty }.count, empty: "No open TCP services found", suffix: "expose reachable services"),
            portCheck("web", "Web dashboards", ports.intersection([80, 443, 8008, 8080, 8443]), "No web dashboards found"),
            portCheck("remote", "Remote administration", ports.intersection([22, 23, 3389, 5900]), "No common remote-admin ports found", warning: true),
            portCheck("shares", "File sharing", ports.intersection([139, 445, 548, 2049]), "No network file shares found"),
            portCheck("printing", "Network printing", ports.intersection([515, 631, 9100]), "No printer services found"),
            warningCount("identity", "Missing vendor identity", devices.filter { !$0.isLocalDevice && $0.vendor == nil }.count, clear: "Every device vendor is identified", suffix: "lack a visible hardware vendor"),
            warningCount("names", "Unnamed devices", devices.filter { !$0.isLocalDevice && $0.hostname == nil && $0.bonjourName == nil && $0.customName == nil }.count, clear: "Every device has a useful name", suffix: "can be renamed for easier tracking"),
            countCheck("privacy", "Private Wi-Fi addresses", randomized.count, empty: "No randomized MAC addresses visible", suffix: "use address randomization")
        ]
    }

    private static func check(_ id: String, _ title: String, _ success: Bool, _ successDetail: String, _ failureDetail: String) -> Check {
        Check(id: id, title: title, detail: success ? successDetail : failureDetail, level: success ? .good : .warning)
    }

    private static func countCheck(_ id: String, _ title: String, _ count: Int, empty: String, suffix: String) -> Check {
        Check(id: id, title: title, detail: count == 0 ? empty : "\(count) \(suffix)", level: count == 0 ? .info : .good)
    }

    private static func warningCount(_ id: String, _ title: String, _ count: Int, clear: String, suffix: String) -> Check {
        Check(id: id, title: title, detail: count == 0 ? clear : "\(count) \(suffix)", level: count == 0 ? .good : .warning)
    }

    private static func portCheck(_ id: String, _ title: String, _ ports: Set<UInt16>, _ empty: String, warning: Bool = false) -> Check {
        let list = ports.sorted().map(String.init).joined(separator: ", ")
        return Check(id: id, title: title, detail: ports.isEmpty ? empty : "Detected on ports \(list)", level: ports.isEmpty ? .good : (warning ? .warning : .info))
    }
}
