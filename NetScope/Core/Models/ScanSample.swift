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

        // Built step by step with explicit types: the chained
        // map/sorted/prefix/map form pushed the type-checker past its budget.
        var kindBuckets: [Bucket] = []
        for (kind, count) in kindCounts {
            kindBuckets.append(Bucket(label: kind.title, count: count, symbolName: kind.symbolName))
        }
        statistics.kindBuckets = rank(kindBuckets, limit: nil)

        var vendorBuckets: [Bucket] = []
        for (vendor, count) in vendorCounts {
            vendorBuckets.append(Bucket(label: vendor, count: count, symbolName: "building.2.fill"))
        }
        statistics.vendorBuckets = rank(vendorBuckets, limit: 8)

        var portBuckets: [Bucket] = []
        for (port, count) in portCounts {
            let name: String = PortCatalog.name(for: port) ?? "Unknown"
            let label: String = "\(port) · \(name)"
            portBuckets.append(Bucket(label: label, count: count, symbolName: PortCatalog.symbol(for: port)))
        }
        statistics.topPorts = rank(portBuckets, limit: 8)

        let bandLabels = ["< 10 ms", "10–50 ms", "50–200 ms", "> 200 ms"]
        var latencyBuckets: [Bucket] = []
        for (index, label) in bandLabels.enumerated() {
            latencyBuckets.append(Bucket(label: label, count: latencyBands[index], symbolName: "timer"))
        }
        statistics.latencyBuckets = latencyBuckets

        return statistics
    }

    /// Sorts buckets by descending count, breaking ties alphabetically, and
    /// optionally keeps only the leading `limit`.
    private static func rank(_ buckets: [Bucket], limit: Int?) -> [Bucket] {
        var sorted = buckets
        sorted.sort { lhs, rhs in
            if lhs.count == rhs.count { return lhs.label < rhs.label }
            return lhs.count > rhs.count
        }
        guard let limit, sorted.count > limit else { return sorted }
        return Array(sorted[0..<limit])
    }
}
