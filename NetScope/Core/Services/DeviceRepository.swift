import Foundation
import Observation

/// Single source of truth for discovered devices, history and events.
///
/// Main-actor isolated because the UI reads it directly; all the heavy lifting
/// (encoding, disk IO) is delegated to the `FileStore` actor so the main thread
/// only ever touches in-memory arrays.
@MainActor
@Observable
final class DeviceRepository {

    // MARK: - Published state

    /// Devices on the network we are currently attached to, sorted by address.
    private(set) var devices: [Device] = []

    /// Every device ever seen, newest activity first.
    private(set) var history: [Device] = []

    private(set) var events: [NetworkEvent] = []

    private(set) var samples: [ScanSample] = []

    private(set) var lastScanDate: Date?

    private(set) var currentNetworkID: String = ""

    // MARK: - Private state

    /// Authoritative map, keyed by `Device.id`.
    private var storage: [String: Device] = [:]

    /// IDs that were online before the running scan started, for diffing.
    private var previouslyOnline: Set<String> = []

    /// IDs reported by the running scan.
    private var seenInCurrentScan: Set<String> = []

    private var saveTask: Task<Void, Never>?
    private var isLoaded = false

    private enum FileName {
        static let devices = "devices"
        static let events = "events"
        static let samples = "samples"
    }

    // MARK: - Lifecycle

    /// Loads persisted state. Safe to call more than once.
    func load() async {
        guard !isLoaded else { return }
        isLoaded = true

        let store = FileStore.shared
        async let storedDevices = store.load([Device].self, from: FileName.devices)
        async let storedEvents = store.load([NetworkEvent].self, from: FileName.events)
        async let storedSamples = store.load([ScanSample].self, from: FileName.samples)

        let loadedDevices = await storedDevices ?? []
        events = await storedEvents ?? []
        samples = await storedSamples ?? []

        storage = Dictionary(loadedDevices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lastScanDate = loadedDevices.map(\.lastSeen).max()
        rebuildCaches()
    }

    /// Switches the active network; the visible device list follows.
    func setCurrentNetwork(_ networkID: String) {
        guard currentNetworkID != networkID else { return }
        currentNetworkID = networkID
        rebuildCaches()
    }

    // MARK: - Scan lifecycle

    func beginScan(networkID: String) {
        currentNetworkID = networkID
        previouslyOnline = Set(
            storage.values
                .filter { $0.networkID == networkID && $0.responded }
                .map(\.id)
        )
        seenInCurrentScan = []
    }

    /// Merges a batch of freshly scanned devices.
    ///
    /// Batching matters: during a scan hundreds of updates arrive in a burst,
    /// and re-sorting per device would be quadratic. Callers coalesce updates
    /// and hand them over in groups.
    func apply(_ scanned: [Device]) {
        guard !scanned.isEmpty else { return }

        for scannedDevice in scanned {
            var device = scannedDevice

            // Migrate identities written by builds that keyed a device only by
            // MAC (or by the older network|IP format). User names, notes and
            // favourites survive the upgrade, while the new key prevents
            // proxy-ARP clients from collapsing into one row.
            if storage[device.id] == nil {
                let legacyIDs = [
                    device.macAddress.map { "mac:\($0)" },
                    "\(device.networkID)|\(device.ipAddress)"
                ].compactMap { $0 }

                if let legacyID = legacyIDs.first(where: { storage[$0] != nil }),
                   let legacy = storage.removeValue(forKey: legacyID) {
                    device = legacy.merging(scanned: device, isNewSighting: false)
                    device.id = scannedDevice.id
                }
            }

            // A scan reports each host several times as details are filled in;
            // only the first report counts as a sighting.
            let isNewSighting = seenInCurrentScan.insert(device.id).inserted

            if let existing = storage[device.id] {
                storage[device.id] = existing.merging(scanned: device, isNewSighting: isNewSighting)
            } else {
                storage[device.id] = device
            }
        }

        rebuildCaches()
    }

    /// Result of reconciling a finished scan against the previous state.
    struct ScanDiff: Sendable {
        var appeared: [Device] = []
        var disappeared: [Device] = []
        var returned: [Device] = []
    }

    /// Marks unseen devices offline, records events and returns what changed.
    @discardableResult
    func completeScan(networkName: String, duration: TimeInterval) -> ScanDiff {
        var diff = ScanDiff()
        let networkID = currentNetworkID

        // Iterate a snapshot: the loop writes back into `storage`.
        for (id, device) in Array(storage) where device.networkID == networkID {
            if seenInCurrentScan.contains(id) {
                if !previouslyOnline.contains(id) {
                    if device.timesSeen <= 1 {
                        diff.appeared.append(device)
                    } else {
                        diff.returned.append(device)
                    }
                }
            } else if device.responded {
                var updated = device
                updated.responded = false
                updated.latency = nil
                storage[id] = updated
                diff.disappeared.append(updated)
            }
        }

        for device in diff.appeared {
            recordEvent(.init(
                kind: .deviceAppeared,
                message: "\(device.displayName) joined \(networkName)",
                deviceID: device.id,
                networkID: networkID
            ))
        }
        for device in diff.returned {
            recordEvent(.init(
                kind: .deviceReturned,
                message: "\(device.displayName) is back online",
                deviceID: device.id,
                networkID: networkID
            ))
        }
        for device in diff.disappeared {
            recordEvent(.init(
                kind: .deviceDisappeared,
                message: "\(device.displayName) left the network",
                deviceID: device.id,
                networkID: networkID
            ))
        }

        let current = storage.values.filter { $0.networkID == networkID }
        let responding = current.filter(\.responded)
        let latencies = responding.compactMap(\.latencyMilliseconds)

        samples.append(
            ScanSample(
                networkID: networkID,
                networkName: networkName,
                deviceCount: current.count,
                onlineCount: responding.count,
                newDeviceCount: diff.appeared.count,
                averageLatency: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
                scanDuration: duration
            )
        )
        if samples.count > 300 { samples.removeFirst(samples.count - 300) }

        lastScanDate = .now
        previouslyOnline = []
        seenInCurrentScan = []

        rebuildCaches()
        scheduleSave()
        return diff
    }

    // MARK: - Mutations

    func toggleFavorite(_ device: Device) {
        guard var stored = storage[device.id] else { return }
        stored.isFavorite.toggle()
        storage[device.id] = stored
        rebuildCaches()
        scheduleSave()
    }

    func rename(_ device: Device, to name: String) {
        guard var stored = storage[device.id] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        stored.customName = trimmed.isEmpty ? nil : trimmed
        storage[device.id] = stored
        rebuildCaches()
        scheduleSave()
    }

    func updateNotes(_ device: Device, notes: String) {
        guard var stored = storage[device.id] else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        stored.notes = trimmed.isEmpty ? nil : trimmed
        storage[device.id] = stored
        rebuildCaches()
        scheduleSave()
    }

    /// Writes back a device after an on-demand action (ping, port scan).
    func update(_ device: Device) {
        guard storage[device.id] != nil else { return }
        storage[device.id] = device
        rebuildCaches()
        scheduleSave()
    }

    func remove(_ device: Device) {
        storage.removeValue(forKey: device.id)
        rebuildCaches()
        scheduleSave()
    }

    func device(with id: String) -> Device? { storage[id] }

    // MARK: - History

    func clearHistory(keepingCurrentNetwork: Bool = true) {
        if keepingCurrentNetwork {
            storage = storage.filter { $0.value.networkID == currentNetworkID }
        } else {
            storage.removeAll()
        }
        events.removeAll()
        samples.removeAll()
        rebuildCaches()
        scheduleSave()
    }

    /// Drops records untouched for longer than the retention window.
    func pruneHistory(olderThanDays days: Int) {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let before = storage.count

        storage = storage.filter { _, device in
            device.isFavorite || device.lastSeen >= cutoff || device.networkID == currentNetworkID
        }
        events = events.filter { $0.timestamp >= cutoff }
        samples = samples.filter { $0.date >= cutoff }

        guard storage.count != before else { return }
        rebuildCaches()
        scheduleSave()
    }

    func recordEvent(_ event: NetworkEvent) {
        events.insert(event, at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
    }

    // MARK: - Derived

    var favorites: [Device] {
        history.filter(\.isFavorite)
    }

    var statistics: NetworkStatistics {
        NetworkStatistics.compute(from: devices)
    }

    var samplesForCurrentNetwork: [ScanSample] {
        samples.filter { $0.networkID == currentNetworkID }
    }

    // MARK: - Private

    /// Rebuilds the two sorted projections after any mutation.
    ///
    /// One pass over `storage`, then two sorts — cheap enough for the low
    /// thousands of devices this app can realistically see, and it keeps every
    /// read path O(1).
    private func rebuildCaches() {
        var current: [Device] = []
        var all: [Device] = []
        current.reserveCapacity(storage.count)
        all.reserveCapacity(storage.count)

        for device in storage.values {
            all.append(device)
            if device.networkID == currentNetworkID { current.append(device) }
        }

        current.sort { $0.ipAddress < $1.ipAddress }
        all.sort { $0.lastSeen > $1.lastSeen }

        devices = current
        history = all
    }

    /// Coalesces rapid mutations into one write a second later.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = Array(storage.values)
        let eventsSnapshot = events
        let samplesSnapshot = samples

        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, self != nil else { return }

            let store = FileStore.shared
            await store.save(snapshot, to: FileName.devices)
            await store.save(eventsSnapshot, to: FileName.events)
            await store.save(samplesSnapshot, to: FileName.samples)
        }
    }

    /// Flushes pending writes immediately — used when the app backgrounds.
    func flush() async {
        saveTask?.cancel()
        let snapshot = Array(storage.values)
        let store = FileStore.shared
        await store.save(snapshot, to: FileName.devices)
        await store.save(events, to: FileName.events)
        await store.save(samples, to: FileName.samples)
    }
}
