import Foundation

/// One completed scan, reduced to the numbers the charts need.
///
/// Kept deliberately tiny: a year of scans is still only a few hundred KB, and
/// the statistics screen can render straight from these without touching the
/// full device records.
struct ScanSample: Identifiable, Hashable, Sendable, Codable {
    var id: UUID = UUID()
    var date: Date = .now
    var networkID: String
    var networkName: String
    var deviceCount: Int
    var onlineCount: Int
    var newDeviceCount: Int
    /// Mean round-trip time across responding hosts, in milliseconds.
    var averageLatency: Double?
    var scanDuration: TimeInterval
}

/// Aggregated statistics derived from the current device list.
struct NetworkStatistics: Sendable, Hashable {

    struct Bucket: Identifiable, Hashable, Sendable {
        var id: String { label }
        var label: String
        var count: Int
        var symbolName: String
    }

    var totalDevices: Int = 0
    var onlineDevices: Int = 0
    var favoriteDevices: Int = 0
    var devicesWithServices: Int = 0
    var identifiedVendors: Int = 0
    var averageLatency: Double?
    var fastestDevice: Device?
    var slowestDevice: Device?
    var kindBuckets: [Bucket] = []
    var vendorBuckets: [Bucket] = []
    var latencyBuckets: [Bucket] = []
    var topPorts: [Bucket] = []

    var offlineDevices: Int { max(totalDevices - onlineDevices, 0) }

    /// Builds every aggregate in a single pass over the devices.
    static func compute(from devices: [Device]) -> NetworkStatistics {
        var statistics = NetworkStatistics()
        guard !devices.isEmpty else { return statistics }

        statistics.totalDevices = devices.count

        var kindCounts: [DeviceKind: Int] = [:]
        var vendorCounts: [String: Int] = [:]
        var portCounts: [UInt16: Int] = [:]
        var latencySum: Double = 0
        var latencyCount = 0
        var fastest: Device?
        var slowest: Device?
        var latencyBands = [0, 0, 0, 0] // <10ms, 10-50, 50-200, >200

        for device in devices {
            if device.isOnline { statistics.onlineDevices += 1 }
            if device.isFavorite { statistics.favoriteDevices += 1 }
            if !device.services.isEmpty { statistics.devicesWithServices += 1 }
            if device.vendor != nil { statistics.identifiedVendors += 1 }

            kindCounts[device.kind, default: 0] += 1
            if let vendor = device.vendor {
                vendorCounts[vendor, default: 0] += 1
            }
            for service in device.services {
                portCounts[service.port, default: 0] += 1
            }

            if let milliseconds = device.latencyMilliseconds {
                latencySum += milliseconds
                latencyCount += 1

                switch milliseconds {
                case ..<10: latencyBands[0] += 1
                case ..<50: latencyBands[1] += 1
                case ..<200: latencyBands[2] += 1
                default: latencyBands[3] += 1
                }

                if fastest == nil || milliseconds < (fastest?.latencyMilliseconds ?? .infinity) {
                    fastest = device
                }
                if slowest == nil || milliseconds > (slowest?.latencyMilliseconds ?? 0) {
                    slowest = device
                }
            }
        }

        statistics.averageLatency = latencyCount > 0 ? latencySum / Double(latencyCount) : nil
        statistics.fastestDevice = fastest
        statistics.slowestDevice = slowest

        statistics.kindBuckets = kindCounts
            .map { Bucket(label: $0.key.title, count: $0.value, symbolName: $0.key.symbolName) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }

        statistics.vendorBuckets = vendorCounts
            .map { Bucket(label: $0.key, count: $0.value, symbolName: "building.2.fill") }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
            .prefix(8)
            .map { $0 }

        statistics.topPorts = portCounts
            .map { entry in
                Bucket(
                    label: "\(entry.key) · \(PortCatalog.name(for: entry.key) ?? "Unknown")",
                    count: entry.value,
                    symbolName: PortCatalog.symbol(for: entry.key)
                )
            }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
            .prefix(8)
            .map { $0 }

        let bandLabels = ["< 10 ms", "10–50 ms", "50–200 ms", "> 200 ms"]
        statistics.latencyBuckets = zip(bandLabels, latencyBands).map {
            Bucket(label: $0.0, count: $0.1, symbolName: "timer")
        }

        return statistics
    }
}
