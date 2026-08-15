import Foundation

// MARK: - DeviceKind

/// Best-effort classification of a host, inferred from vendor, Bonjour records
/// and open ports. Never authoritative — iOS gives us no privileged access.
enum DeviceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case router
    case computer
    case phone
    case tablet
    case wearable
    case tv
    case speaker
    case printer
    case camera
    case storage
    case console
    case iot
    case server
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .router: "Router"
        case .computer: "Computer"
        case .phone: "Phone"
        case .tablet: "Tablet"
        case .wearable: "Wearable"
        case .tv: "TV / Media"
        case .speaker: "Speaker"
        case .printer: "Printer"
        case .camera: "Camera"
        case .storage: "Storage / NAS"
        case .console: "Game Console"
        case .iot: "Smart Home"
        case .server: "Server"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .router: "wifi.router.fill"
        case .computer: "desktopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .wearable: "applewatch"
        case .tv: "tv.fill"
        case .speaker: "hifispeaker.fill"
        case .printer: "printer.fill"
        case .camera: "video.fill"
        case .storage: "externaldrive.fill"
        case .console: "gamecontroller.fill"
        case .iot: "sensor.fill"
        case .server: "server.rack"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

// MARK: - Device

/// A host discovered on the local network.
///
/// Value type + `Sendable` so it can cross actor boundaries freely; the scan
/// engine produces these off the main actor and hands them to the repository.
struct Device: Identifiable, Hashable, Sendable, Codable {

    /// Stable identity. Prefers the MAC address (survives DHCP lease changes);
    /// falls back to network-scoped IP when the ARP entry is unavailable.
    var id: String

    var ipAddress: IPv4

    /// Reverse-DNS / mDNS hostname, when resolvable.
    var hostname: String?

    /// Friendly name advertised over Bonjour (`Living Room Apple TV`).
    var bonjourName: String?

    /// Name the user typed on the detail screen. Always wins for display.
    var customName: String?

    /// Hardware address from the ARP neighbour table. Frequently `nil` on iOS:
    /// the entry only exists after recent L2 traffic with that host.
    var macAddress: String?

    /// OUI vendor derived from `macAddress`.
    var vendor: String?

    var kind: DeviceKind = .unknown

    var services: [ServiceInfo] = []

    /// Bonjour service types advertised by the host.
    var bonjourServiceTypes: [String] = []

    /// Latest measured round-trip time in seconds.
    var latency: TimeInterval?

    /// Rolling window of recent RTT samples (seconds), oldest first.
    var latencySamples: [Double] = []

    /// How the host answered during the last probe.
    var responded: Bool = true

    /// Probe technique that proved the host is alive.
    var discoveryMethod: DiscoveryMethod = .icmp

    var isGateway: Bool = false

    /// True for the device running the app.
    var isLocalDevice: Bool = false

    var isFavorite: Bool = false

    var notes: String?

    var firstSeen: Date = .now
    var lastSeen: Date = .now

    /// Number of scans this device has appeared in. Drives "regular" badges.
    var timesSeen: Int = 1

    /// Identifier of the network the device was seen on (SSID or gateway MAC).
    var networkID: String = ""

    // MARK: Derived

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let bonjourName, !bonjourName.isEmpty { return bonjourName }
        if let hostname, !hostname.isEmpty { return Self.prettifyHostname(hostname) }
        if let vendor, !vendor.isEmpty { return vendor }
        return ipAddress.description
    }

    /// Secondary line: whichever identifying detail the name did not use.
    var subtitle: String {
        var parts: [String] = [ipAddress.description]
        if let vendor, !vendor.isEmpty, displayName != vendor { parts.append(vendor) }
        else if let hostname, !hostname.isEmpty, displayName != Self.prettifyHostname(hostname) {
            parts.append(Self.prettifyHostname(hostname))
        }
        return parts.joined(separator: " · ")
    }

    var latencyMilliseconds: Double? {
        latency.map { $0 * 1000 }
    }

    var averageLatencyMilliseconds: Double? {
        guard !latencySamples.isEmpty else { return nil }
        return latencySamples.reduce(0, +) / Double(latencySamples.count) * 1000
    }

    /// Sample-to-sample variation, a cheap stand-in for jitter.
    var jitterMilliseconds: Double? {
        guard latencySamples.count > 1 else { return nil }
        let deltas = zip(latencySamples.dropFirst(), latencySamples).map { abs($0 - $1) }
        return deltas.reduce(0, +) / Double(deltas.count) * 1000
    }

    var openPorts: [UInt16] { services.map(\.port).sorted() }

    var isOnline: Bool { responded }

    /// Merges a freshly scanned record into the stored one, preserving
    /// user-owned fields (name, notes, favourite) and long-lived history.
    ///
    /// - Parameter isNewSighting: `false` when this is a refinement of a device
    ///   already merged during the current scan (a hostname or port result
    ///   arriving after the initial discovery). Sighting counts and the latency
    ///   history must not advance for those, or a single scan would look like
    ///   three.
    func merging(scanned: Device, isNewSighting: Bool = true, latencyWindow: Int = 60) -> Device {
        var result = scanned
        result.id = id
        result.customName = customName
        result.notes = notes
        result.isFavorite = isFavorite
        result.firstSeen = min(firstSeen, scanned.firstSeen)
        result.timesSeen = timesSeen + (isNewSighting ? 1 : 0)

        // Keep previously learned facts when the new scan came up empty.
        result.hostname = scanned.hostname ?? hostname
        result.bonjourName = scanned.bonjourName ?? bonjourName
        result.macAddress = scanned.macAddress ?? macAddress
        result.vendor = scanned.vendor ?? vendor
        if scanned.kind == .unknown { result.kind = kind }
        if scanned.services.isEmpty { result.services = services }
        if scanned.bonjourServiceTypes.isEmpty { result.bonjourServiceTypes = bonjourServiceTypes }

        var samples = latencySamples
        if isNewSighting, let latency = scanned.latency {
            samples.append(latency)
            if samples.count > latencyWindow { samples.removeFirst(samples.count - latencyWindow) }
        }
        result.latencySamples = samples
        result.latency = scanned.latency ?? latency
        return result
    }

    /// Trims trailing `.local.`/`.lan` noise and shouty all-caps NetBIOS names.
    static func prettifyHostname(_ raw: String) -> String {
        var name = raw
        for suffix in [".local.", ".local", ".lan.", ".lan", ".home.", ".home", "."] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        name = name.replacingOccurrences(of: "-", with: " ")
        if name == name.uppercased(), name.count > 3 {
            name = name.capitalized
        }
        return name.isEmpty ? raw : name
    }
}

// MARK: - DiscoveryMethod

enum DiscoveryMethod: String, Codable, Sendable {
    case icmp
    case tcp
    case bonjour
    case arp
    case local

    var title: String {
        switch self {
        case .icmp: "ICMP echo"
        case .tcp: "TCP probe"
        case .bonjour: "Bonjour"
        case .arp: "ARP cache"
        case .local: "This device"
        }
    }
}
