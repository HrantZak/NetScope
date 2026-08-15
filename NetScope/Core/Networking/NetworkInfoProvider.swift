import Foundation
import Network
#if canImport(NetworkExtension)
import NetworkExtension
#endif

/// Assembles a `NetworkSnapshot` from every source iOS allows.
enum NetworkInfoProvider {

    /// Wi-Fi details that require an entitlement; all fields may be `nil`.
    struct WiFiInfo: Sendable {
        var ssid: String?
        var bssid: String?
        var isSecure: Bool?

        static let unavailable = WiFiInfo()
    }

    /// Builds a full picture of the current connection.
    static func currentSnapshot(includeWiFiDetails: Bool = true) async -> NetworkSnapshot {
        var snapshot = NetworkSnapshot()

        guard let interface = InterfaceProvider.primaryInterface() else {
            snapshot.interfaceType = .none
            return snapshot
        }

        snapshot.interfaceName = interface.name
        snapshot.interfaceType = interface.type
        snapshot.localAddress = interface.address
        snapshot.netmask = interface.netmask
        snapshot.subnet = interface.subnet
        snapshot.broadcast = interface.broadcast ?? interface.subnet.broadcastAddress
        snapshot.gateway = RouteTable.defaultGateway()

        var resolvers = DNSResolver.systemResolvers()
        if resolvers.isEmpty, let gateway = snapshot.gateway {
            // Home routers almost always proxy DNS; showing the gateway is more
            // useful than showing nothing.
            resolvers = [gateway]
        }
        snapshot.dnsServers = resolvers

        if let gateway = snapshot.gateway,
           let mac = RouteTable.arpTable()[gateway] {
            snapshot.externalRouterVendor = VendorDatabase.vendor(forMAC: mac)
        }

        if includeWiFiDetails, interface.type == .wifi {
            let wifi = await currentWiFiInfo()
            snapshot.ssid = wifi.ssid
            snapshot.bssid = wifi.bssid
            snapshot.isSecure = wifi.isSecure
        }

        snapshot.capturedAt = .now
        return snapshot
    }

    /// Reads SSID/BSSID via `NEHotspotNetwork`.
    ///
    /// This needs the *Access Wi-Fi Information* capability. Without it the API
    /// simply hands back `nil` — no crash, no prompt — and the UI falls back to
    /// showing the subnet as the network's name.
    static func currentWiFiInfo() async -> WiFiInfo {
        #if canImport(NetworkExtension)
        return await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                continuation.resume(
                    returning: WiFiInfo(
                        ssid: network.ssid.isEmpty ? nil : network.ssid,
                        bssid: network.bssid.isEmpty ? nil : network.bssid,
                        isSecure: network.isSecure
                    )
                )
            }
        }
        #else
        return .unavailable
        #endif
    }
}

/// Watches for connectivity changes with `NWPathMonitor` and republishes them
/// as an async stream of snapshots.
final class NetworkPathObserver: @unchecked Sendable {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.netscope.path-monitor", qos: .utility)
    private var isStarted = false
    private let lock = NSLock()

    /// Emits once immediately, then on every path change.
    ///
    /// Consumers get a fully built `NetworkSnapshot`, not a raw `NWPath`, so the
    /// UI layer never has to know about the Network framework.
    func snapshots() -> AsyncStream<NetworkSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { path in
                // Only the status is carried across the task boundary: `NWPath`
                // itself is not `Sendable`, and nothing else here needs it.
                let isSatisfied = path.status == .satisfied

                Task.detached(priority: .utility) {
                    guard isSatisfied else {
                        continuation.yield(.disconnected)
                        return
                    }
                    // A path change can land before the interface table catches
                    // up, so give the stack a moment to settle.
                    try? await Task.sleep(for: .milliseconds(250))
                    continuation.yield(await NetworkInfoProvider.currentSnapshot())
                }
            }

            start()

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }

            Task.detached(priority: .userInitiated) {
                continuation.yield(await NetworkInfoProvider.currentSnapshot())
            }
        }
    }

    func start() {
        lock.withLock {
            guard !isStarted else { return }
            isStarted = true
            monitor.start(queue: queue)
        }
    }

    func stop() {
        lock.withLock {
            guard isStarted else { return }
            isStarted = false
            monitor.cancel()
        }
    }
}
