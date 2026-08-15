import Foundation

/// Everything we can legitimately learn about the connection we are sitting on.
///
/// Fields are optional on purpose: iOS restricts several of them (SSID needs an
/// entitlement, BSSID is usually redacted), so the UI degrades gracefully.
struct NetworkSnapshot: Hashable, Sendable, Codable {

    enum InterfaceType: String, Codable, Sendable {
        case wifi
        case cellular
        case wired
        case other
        case none

        var title: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .cellular: "Cellular"
            case .wired: "Wired"
            case .other: "Other"
            case .none: "Offline"
            }
        }

        var symbolName: String {
            switch self {
            case .wifi: "wifi"
            case .cellular: "antenna.radiowaves.left.and.right"
            case .wired: "cable.connector"
            case .other: "network"
            case .none: "wifi.slash"
            }
        }
    }

    /// BSD interface name, e.g. `en0`.
    var interfaceName: String?
    var interfaceType: InterfaceType = .none

    var localAddress: IPv4?
    var netmask: IPv4?
    var subnet: IPv4Subnet?
    var gateway: IPv4?
    var broadcast: IPv4?
    var dnsServers: [IPv4] = []

    /// Only populated when the Access Wi-Fi Information entitlement is present.
    var ssid: String?
    var bssid: String?
    var isSecure: Bool?

    var externalRouterVendor: String?

    var capturedAt: Date = .now

    var isConnected: Bool { localAddress != nil && interfaceType != .none }

    /// Stable key used to scope stored devices to a given network.
    var networkID: String {
        if let ssid, !ssid.isEmpty { return "ssid:\(ssid)" }
        if let subnet { return "net:\(subnet.description)" }
        if let gateway { return "gw:\(gateway.description)" }
        return "unknown"
    }

    var displayName: String {
        if let ssid, !ssid.isEmpty { return ssid }
        if let subnet { return subnet.description }
        return interfaceType.title
    }

    var hostCountEstimate: Int { subnet?.usableHostCount ?? 0 }

    static let disconnected = NetworkSnapshot()
}
