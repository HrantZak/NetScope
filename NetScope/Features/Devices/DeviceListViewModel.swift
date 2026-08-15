import Foundation
import Observation

/// A titled group of devices, ready for rendering.
struct DeviceSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var symbolName: String?
    var devices: [Device]

    var count: Int { devices.count }
}

/// Owns the search / filter / sort / group pipeline for the device list.
///
/// The result is computed once per input change and cached in `sections`,
/// rather than recomputed inside `body`. During a scan the device array is
/// republished several times a second, and the view also re-renders for
/// unrelated reasons; recomputing a thousand-row sort on every pass is exactly
/// the kind of thing that makes a list feel sticky.
@MainActor
@Observable
final class DeviceListViewModel {

    /// Mutated through `updateSearch(_:)` rather than directly: the
    /// `@Observable` macro does not allow property observers, so the rebuild is
    /// triggered explicitly instead of from a `didSet`.
    private(set) var searchText: String = ""

    private(set) var sections: [DeviceSection] = []
    private(set) var visibleCount: Int = 0
    private(set) var totalCount: Int = 0

    private var devices: [Device] = []
    private var preferences: BrowsePreferences = .default

    var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || preferences.hasActiveFilters
    }

    var isGrouped: Bool { preferences.group != .none }

    /// Updates the query and refreshes the sections.
    func updateSearch(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        rebuild()
    }

    /// Feeds new inputs in. No-ops when nothing actually changed.
    func sync(devices: [Device], preferences: BrowsePreferences) {
        let devicesChanged = devices != self.devices
        let preferencesChanged = preferences != self.preferences
        guard devicesChanged || preferencesChanged else { return }

        self.devices = devices
        self.preferences = preferences
        rebuild()
    }

    // MARK: - Pipeline

    private func rebuild() {
        totalCount = devices.count

        let filtered = applyFilters(to: devices)
        let sorted = applySort(to: filtered)
        visibleCount = sorted.count
        sections = applyGrouping(to: sorted)
    }

    private func applyFilters(to devices: [Device]) -> [Device] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let statusFilter = preferences.statusFilter
        let kindFilter = preferences.kindFilter

        return devices.filter { device in
            switch statusFilter {
            case .all: break
            case .online: if !device.isOnline { return false }
            case .offline: if device.isOnline { return false }
            case .favorites: if !device.isFavorite { return false }
            case .withServices: if device.services.isEmpty { return false }
            }

            if !kindFilter.isEmpty, !kindFilter.contains(device.kind) { return false }
            if query.isEmpty { return true }

            return matches(device: device, query: query)
        }
    }

    /// Matches across every identifying field, plus port numbers so "443"
    /// finds every host with HTTPS open.
    private func matches(device: Device, query: String) -> Bool {
        if device.ipAddress.description.contains(query) { return true }
        if device.displayName.lowercased().contains(query) { return true }
        if device.hostname?.lowercased().contains(query) == true { return true }
        if device.bonjourName?.lowercased().contains(query) == true { return true }
        if device.vendor?.lowercased().contains(query) == true { return true }
        if device.macAddress?.lowercased().contains(query) == true { return true }
        if device.notes?.lowercased().contains(query) == true { return true }
        if device.kind.title.lowercased().contains(query) { return true }

        for service in device.services {
            if String(service.port).contains(query) { return true }
            if service.displayName.lowercased().contains(query) { return true }
        }

        return false
    }

    private func applySort(to devices: [Device]) -> [Device] {
        let ascending = preferences.sortAscending

        return devices.sorted { lhs, rhs in
            let result: Bool
            switch preferences.sortField {
            case .ipAddress:
                result = lhs.ipAddress < rhs.ipAddress
            case .name:
                result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .latency:
                // Unreachable hosts always sink to the bottom, regardless of
                // sort direction — a missing value is not "fast".
                let left = lhs.latencyMilliseconds ?? .greatestFiniteMagnitude
                let right = rhs.latencyMilliseconds ?? .greatestFiniteMagnitude
                if left == right { return lhs.ipAddress < rhs.ipAddress }
                result = left < right
            case .lastSeen:
                result = lhs.lastSeen > rhs.lastSeen
            case .openPorts:
                if lhs.services.count == rhs.services.count { return lhs.ipAddress < rhs.ipAddress }
                result = lhs.services.count > rhs.services.count
            case .vendor:
                let left = lhs.vendor ?? "\u{10FFFF}"
                let right = rhs.vendor ?? "\u{10FFFF}"
                if left == right { return lhs.ipAddress < rhs.ipAddress }
                result = left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            return ascending ? result : !result
        }
    }

    private func applyGrouping(to devices: [Device]) -> [DeviceSection] {
        guard !devices.isEmpty else { return [] }

        switch preferences.group {
        case .none:
            return [DeviceSection(id: "all", title: "Devices", symbolName: nil, devices: devices)]

        case .kind:
            return group(devices, by: { $0.kind.title }) { device in
                (device.kind.title, device.kind.symbolName, device.kind.rawValue)
            }

        case .vendor:
            return group(devices, by: { $0.vendor ?? "Unknown vendor" }) { device in
                (device.vendor ?? "Unknown vendor", "building.2.fill", device.vendor ?? "zzz")
            }

        case .status:
            return group(devices, by: { $0.isOnline ? "Online" : "Offline" }) { device in
                (
                    device.isOnline ? "Online" : "Offline",
                    device.isOnline ? "checkmark.circle.fill" : "moon.zzz.fill",
                    device.isOnline ? "0" : "1"
                )
            }

        case .subnetBlock:
            return group(devices, by: { $0.ipAddress.classCBlock }) { device in
                (device.ipAddress.classCBlock, "point.3.connected.trianglepath.dotted", device.ipAddress.classCBlock)
            }
        }
    }

    /// Groups while preserving the sorted order inside each bucket.
    private func group(
        _ devices: [Device],
        by key: (Device) -> String,
        descriptor: (Device) -> (title: String, symbol: String, sortKey: String)
    ) -> [DeviceSection] {
        var buckets: [String: [Device]] = [:]
        var descriptors: [String: (title: String, symbol: String, sortKey: String)] = [:]
        var order: [String] = []

        for device in devices {
            let bucketKey = key(device)
            if buckets[bucketKey] == nil {
                buckets[bucketKey] = []
                descriptors[bucketKey] = descriptor(device)
                order.append(bucketKey)
            }
            buckets[bucketKey]?.append(device)
        }

        return order
            .compactMap { bucketKey -> DeviceSection? in
                guard let members = buckets[bucketKey], let info = descriptors[bucketKey] else { return nil }
                return DeviceSection(
                    id: bucketKey,
                    title: info.title,
                    symbolName: info.symbol,
                    devices: members
                )
            }
            .sorted { lhs, rhs in
                let leftKey = descriptors[lhs.id]?.sortKey ?? lhs.title
                let rightKey = descriptors[rhs.id]?.sortKey ?? rhs.title
                return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
            }
    }
}
