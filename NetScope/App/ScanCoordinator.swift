import Foundation
import Observation

/// Drives scans and translates engine events into UI state.
///
/// Two things make this fast enough to stay smooth with hundreds of devices:
///
/// 1. Engine events arrive through an `AsyncStream` consumed on the main actor,
///    rather than one `Task { @MainActor }` hop per event.
/// 2. Device updates are **coalesced**: they accumulate in a buffer that is
///    flushed to the repository at ~8 fps, so the list re-sorts a handful of
///    times per scan instead of once per discovered host.
@MainActor
@Observable
final class ScanCoordinator {

    // MARK: - Published state

    private(set) var progress: ScanProgress = .idle
    private(set) var lastError: String?
    private(set) var lastCompletedAt: Date?
    private(set) var lastScanDuration: TimeInterval?

    /// Snapshot of the network the next scan will run against.
    var snapshot: NetworkSnapshot = .disconnected

    var isScanning: Bool { progress.isRunning }

    var canScan: Bool { snapshot.isConnected && snapshot.subnet != nil }

    // MARK: - Dependencies

    private let engine = ScanEngine()
    private let notifications = NotificationService()
    private let repository: DeviceRepository
    private let settings: SettingsStore

    // MARK: - Task state

    private var scanTask: Task<Void, Never>?
    private var autoScanTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?

    /// Devices waiting to be handed to the repository.
    private var pendingDevices: [String: Device] = [:]

    /// How long updates may sit in the buffer before being applied.
    private static let flushInterval: Duration = .milliseconds(120)

    init(repository: DeviceRepository, settings: SettingsStore) {
        self.repository = repository
        self.settings = settings
    }

    // MARK: - Scanning

    func startScan() {
        guard !isScanning else { return }
        guard canScan else {
            lastError = "Not connected to a scannable network."
            return
        }

        lastError = nil

        // A just-cancelled scan may still be unwinding inside the engine, which
        // refuses to start a second one. Waiting for it here makes a rapid
        // stop-then-scan sequence behave predictably instead of silently
        // dropping the new request.
        let previous = scanTask
        scanTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.runScan()
        }
    }

    func cancelScan() {
        // The reference is kept on purpose — `startScan` awaits it so the
        // engine finishes unwinding before the next scan begins.
        scanTask?.cancel()
        flushPending()
        progress.phase = .idle
        progress.finishedAt = .now
    }

    func rescanIfIdle() {
        guard !isScanning else { return }
        startScan()
    }

    private func runScan() async {
        let configuration = settings.configuration
        let target = snapshot
        let startedAt = Date.now

        repository.beginScan(networkID: target.networkID)

        progress = ScanProgress(
            phase: .preparing,
            scannedHosts: 0,
            totalHosts: 0,
            foundDevices: 0,
            startedAt: startedAt,
            finishedAt: nil
        )

        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream(
            bufferingPolicy: .unbounded
        )

        let scanEngine = engine
        let producer = Task.detached(priority: .userInitiated) {
            await scanEngine.scan(configuration: configuration, snapshot: target) { event in
                continuation.yield(event)
            }
            continuation.finish()
        }

        await withTaskCancellationHandler {
            for await event in stream {
                handle(event)
            }
        } onCancel: {
            producer.cancel()
            continuation.finish()
        }

        _ = await producer.value

        flushPending()

        let duration = Date.now.timeIntervalSince(startedAt)
        lastScanDuration = duration
        lastCompletedAt = .now
        progress.finishedAt = .now
        progress.phase = .idle

        guard !Task.isCancelled else { return }

        // Reconcile against the network the scan actually ran on, which may no
        // longer be the one we are attached to.
        let diff = repository.completeScan(networkName: target.displayName, duration: duration)
        repository.pruneHistory(olderThanDays: configuration.keepHistoryDays)

        await announce(diff: diff, networkName: target.displayName, configuration: configuration)
    }

    /// Applies one engine event. Kept branch-light: this runs hundreds of times
    /// per scan.
    private func handle(_ event: ScanEvent) {
        switch event {
        case .started(let totalHosts):
            progress.totalHosts = totalHosts
            progress.scannedHosts = 0
            progress.phase = .sweeping

        case .phase(let phase):
            progress.phase = phase
            progress.scannedHosts = 0

        case .progress(let scanned, let total):
            progress.scannedHosts = scanned
            progress.totalHosts = total

        case .discovered(let device):
            pendingDevices[device.id] = device
            progress.foundDevices = max(progress.foundDevices, pendingDevices.count)
            scheduleFlush()

        case .updated(let device):
            pendingDevices[device.id] = device
            scheduleFlush()

        case .finished(let deviceCount):
            progress.foundDevices = deviceCount
            progress.phase = .finishing

        case .failed(let message):
            lastError = message
            progress.phase = .idle
            progress.finishedAt = .now
            repository.recordEvent(
                NetworkEvent(kind: .scanFailed, message: message, networkID: snapshot.networkID)
            )
            Haptics.error()
        }
    }

    // MARK: - Buffering

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushPending()
        }
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingDevices.isEmpty else { return }

        let batch = Array(pendingDevices.values)
        pendingDevices.removeAll(keepingCapacity: true)
        repository.apply(batch)
        progress.foundDevices = repository.devices.count
    }

    // MARK: - Notifications

    private func announce(
        diff: DeviceRepository.ScanDiff,
        networkName: String,
        configuration: ScanConfiguration
    ) async {
        if !diff.appeared.isEmpty { Haptics.success() }

        let appeared = configuration.notifyOnNewDevice ? diff.appeared : []
        let left = configuration.notifyOnDeviceLeft ? diff.disappeared : []
        guard !appeared.isEmpty || !left.isEmpty else { return }

        await notifications.notifyDeviceChanges(
            appeared: appeared,
            disappeared: left,
            networkName: networkName
        )
    }

    // MARK: - Automatic scanning

    /// Restarts the auto-scan loop to match current settings.
    func refreshAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = nil

        let configuration = settings.configuration
        guard configuration.autoScanEnabled else { return }

        autoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(configuration.autoScanInterval))
                guard let self, !Task.isCancelled else { return }
                guard self.settings.configuration.autoScanEnabled else { return }
                self.rescanIfIdle()
            }
        }
    }

    func stopAutoScan() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    /// Called when the network itself changed underneath us.
    func handleNetworkChange(to snapshot: NetworkSnapshot) {
        let previousID = self.snapshot.networkID
        self.snapshot = snapshot

        guard previousID != snapshot.networkID else { return }

        cancelScan()
        repository.setCurrentNetwork(snapshot.networkID)

        if snapshot.isConnected {
            repository.recordEvent(
                NetworkEvent(
                    kind: .networkChanged,
                    message: "Now on \(snapshot.displayName)",
                    networkID: snapshot.networkID
                )
            )
        }
    }
}
