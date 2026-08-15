import Foundation

/// User-tunable scan behaviour, persisted via `SettingsStore`.
struct ScanConfiguration: Hashable, Sendable, Codable {

    // MARK: Profile

    enum Profile: String, Codable, Sendable, CaseIterable, Identifiable {
        case fast
        case balanced
        case thorough

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fast: "Fast"
            case .balanced: "Balanced"
            case .thorough: "Thorough"
            }
        }

        var detail: String {
            switch self {
            case .fast: "Sweep only, minimal port probing. Finishes in seconds."
            case .balanced: "Sweep plus ~80 common ports per host."
            case .thorough: "Sweep plus 1024 ports per host. Slowest, most complete."
            }
        }

        var symbolName: String {
            switch self {
            case .fast: "bolt.fill"
            case .balanced: "dial.medium.fill"
            case .thorough: "magnifyingglass.circle.fill"
            }
        }

        var ports: [UInt16] {
            switch self {
            case .fast: PortCatalog.quickPorts
            case .balanced: PortCatalog.commonPorts
            case .thorough: PortCatalog.thoroughPorts
            }
        }
    }

    // MARK: Stored settings

    var profile: Profile = .balanced

    /// Concurrent host probes. Higher is faster but heavier on the radio.
    var hostConcurrency: Int = 96

    /// Concurrent port probes per host.
    var portConcurrency: Int = 24

    /// Per-host ping timeout in seconds.
    var pingTimeout: TimeInterval = 0.8

    /// Per-port TCP connect timeout in seconds.
    var portTimeout: TimeInterval = 0.6

    /// Number of ICMP echoes per host during discovery.
    var pingAttempts: Int = 2

    /// Upper bound on probed addresses, protecting against huge subnets.
    var maxHosts: Int = 1024

    var resolveHostnames: Bool = true
    var useBonjour: Bool = true
    var scanPorts: Bool = true

    /// Fall back to TCP SYN-style connects when ICMP is filtered.
    var useTCPFallback: Bool = true

    var autoScanEnabled: Bool = false
    /// Seconds between automatic scans.
    var autoScanInterval: TimeInterval = 120

    var notifyOnNewDevice: Bool = true
    var notifyOnDeviceLeft: Bool = false

    var keepHistoryDays: Int = 30

    static let `default` = ScanConfiguration()

    // MARK: Derived

    var portsToProbe: [UInt16] { scanPorts ? profile.ports : [] }

    /// Clamped values, applied before the engine consumes the configuration.
    var sanitized: ScanConfiguration {
        var copy = self
        copy.hostConcurrency = min(max(hostConcurrency, 8), 256)
        copy.portConcurrency = min(max(portConcurrency, 4), 64)
        copy.pingTimeout = min(max(pingTimeout, 0.15), 5)
        copy.portTimeout = min(max(portTimeout, 0.15), 5)
        copy.pingAttempts = min(max(pingAttempts, 1), 5)
        copy.maxHosts = min(max(maxHosts, 32), 8192)
        copy.autoScanInterval = min(max(autoScanInterval, 15), 3600)
        copy.keepHistoryDays = min(max(keepHistoryDays, 1), 365)
        return copy
    }
}

// MARK: - Presentation preferences

/// How the device list is arranged. Persisted separately from scan settings
/// because it changes far more often.
struct BrowsePreferences: Hashable, Sendable, Codable {

    enum LayoutMode: String, Codable, Sendable, CaseIterable, Identifiable {
        case comfortable
        case compact
        case grid
        case table

        var id: String { rawValue }

        var title: String {
            switch self {
            case .comfortable: "Cards"
            case .compact: "Compact"
            case .grid: "Grid"
            case .table: "Table"
            }
        }

        var symbolName: String {
            switch self {
            case .comfortable: "rectangle.grid.1x2"
            case .compact: "list.bullet"
            case .grid: "square.grid.2x2"
            case .table: "tablecells"
            }
        }
    }

    enum SortField: String, Codable, Sendable, CaseIterable, Identifiable {
        case ipAddress
        case name
        case latency
        case lastSeen
        case openPorts
        case vendor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ipAddress: "IP address"
            case .name: "Name"
            case .latency: "Latency"
            case .lastSeen: "Last seen"
            case .openPorts: "Open ports"
            case .vendor: "Vendor"
            }
        }

        var symbolName: String {
            switch self {
            case .ipAddress: "number"
            case .name: "textformat"
            case .latency: "timer"
            case .lastSeen: "clock"
            case .openPorts: "bolt.horizontal"
            case .vendor: "building.2"
            }
        }
    }

    enum GroupField: String, Codable, Sendable, CaseIterable, Identifiable {
        case none
        case kind
        case vendor
        case status
        case subnetBlock

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .kind: "Device type"
            case .vendor: "Vendor"
            case .status: "Status"
            case .subnetBlock: "Address block"
            }
        }
    }

    enum StatusFilter: String, Codable, Sendable, CaseIterable, Identifiable {
        case all
        case online
        case offline
        case favorites
        case withServices

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .online: "Online"
            case .offline: "Offline"
            case .favorites: "Favorites"
            case .withServices: "With services"
            }
        }

        var symbolName: String {
            switch self {
            case .all: "square.stack.3d.up"
            case .online: "checkmark.circle"
            case .offline: "moon.zzz"
            case .favorites: "star"
            case .withServices: "bolt.horizontal.circle"
            }
        }
    }

    var layout: LayoutMode = .comfortable
    var sortField: SortField = .ipAddress
    var sortAscending: Bool = true
    var group: GroupField = .none
    var statusFilter: StatusFilter = .all
    var kindFilter: Set<DeviceKind> = []

    static let `default` = BrowsePreferences()

    var hasActiveFilters: Bool {
        statusFilter != .all || !kindFilter.isEmpty
    }
}
