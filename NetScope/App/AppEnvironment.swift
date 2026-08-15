import Foundation
import Observation
import SwiftUI

/// Composition root: owns the stores, the scan coordinator and the network
/// observer, and wires them together.
///
/// Injected once at the top of the view tree and read via `@Environment`.
@MainActor
@Observable
final class AppEnvironment {

    let settings: SettingsStore
    let repository: DeviceRepository
    let scanner: ScanCoordinator

    /// Current connection details, refreshed on every path change.
    private(set) var snapshot: NetworkSnapshot = .disconnected

    private(set) var permission: LocalNetworkPermission = .unknown
    private(set) var isRequestingPermission = false
    private(set) var isBootstrapped = false

    private let pathObserver = NetworkPathObserver()
    private var observerTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore()
        let repository = DeviceRepository()
        self.settings = settings
        self.repository = repository
        self.scanner = ScanCoordinator(repository: repository, settings: settings)
    }

    // MARK: - Lifecycle

    /// Loads cached data, works out the current network and asks for Local
    /// Network access. Safe to call repeatedly; only the first call does work.
    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        Haptics.prepare()

        await repository.load()

        let initial = await NetworkInfoProvider.currentSnapshot()
        applySnapshot(initial)

        observeNetworkChanges()

        // Requesting permission is also what shows the system prompt, so it is
        // done up front rather than in the middle of the first scan.
        await requestPermission()

        scanner.refreshAutoScan()

        // Cached results are shown instantly; a fresh scan starts behind them.
        if permission != .denied, scanner.canScan {
            scanner.startScan()
        }
    }

    private func observeNetworkChanges() {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in pathObserver.snapshots() {
                guard !Task.isCancelled else { return }
                self.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: NetworkSnapshot) {
        let didChangeNetwork = snapshot.networkID != self.snapshot.networkID
        self.snapshot = snapshot
        scanner.handleNetworkChange(to: snapshot)
        repository.setCurrentNetwork(snapshot.networkID)

        guard didChangeNetwork, isBootstrapped, snapshot.isConnected,
              permission == .granted, settings.configuration.autoScanEnabled
        else { return }

        scanner.rescanIfIdle()
    }

    // MARK: - Permission

    func requestPermission() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        permission = await LocalNetworkAuthorization.request()
    }

    /// Refreshes connection details without a full scan.
    func refreshNetworkInfo() async {
        let snapshot = await NetworkInfoProvider.currentSnapshot()
        applySnapshot(snapshot)
    }

    // MARK: - Scene events

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            scanner.refreshAutoScan()
            Task { await refreshNetworkInfo() }
        case .background:
            scanner.stopAutoScan()
            scanner.cancelScan()
            Task { await repository.flush() }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Preview support

    /// Environment pre-populated with plausible devices, for SwiftUI previews.
    static func preview() -> AppEnvironment {
        let environment = AppEnvironment()
        environment.snapshot = .previewSample
        environment.permission = .granted
        environment.scanner.snapshot = .previewSample
        environment.repository.setCurrentNetwork(NetworkSnapshot.previewSample.networkID)
        environment.repository.apply(Device.previewSamples)
        return environment
    }
}

// Injected with `.environment(appEnvironment)` at the root and read with
// `@Environment(AppEnvironment.self)`, which is the Observation-native path —
// no `EnvironmentKey` and no optional unwrapping at every call site.
