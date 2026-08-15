import Foundation
import Observation

/// One point on the live latency chart.
struct PingSample: Identifiable, Hashable, Sendable {
    var id: Int
    var timestamp: Date
    /// `nil` means the probe timed out — plotted as a gap, not as zero.
    var milliseconds: Double?
}

/// Drives the on-demand diagnostics on the device detail screen: continuous
/// ping, port scan and HTTP fingerprinting.
@MainActor
@Observable
final class DeviceDetailViewModel {

    // MARK: - Ping

    private(set) var pingSamples: [PingSample] = []
    private(set) var isPinging = false
    private(set) var packetsSent = 0
    private(set) var packetsLost = 0

    var packetLossPercentage: Double {
        guard packetsSent > 0 else { return 0 }
        return Double(packetsLost) / Double(packetsSent) * 100
    }

    var minimumLatency: Double? { pingSamples.compactMap(\.milliseconds).min() }
    var maximumLatency: Double? { pingSamples.compactMap(\.milliseconds).max() }

    var averageLatency: Double? {
        let values = pingSamples.compactMap(\.milliseconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean absolute difference between consecutive samples.
    var jitter: Double? {
        let values = pingSamples.compactMap(\.milliseconds)
        guard values.count > 1 else { return nil }
        let deltas = zip(values.dropFirst(), values).map { abs($0 - $1) }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    // MARK: - Port scan

    private(set) var isScanningPorts = false
    private(set) var scannedPortCount = 0
    private(set) var totalPortCount = 0
    private(set) var liveServices: [ServiceInfo] = []

    var portScanFraction: Double {
        totalPortCount > 0 ? Double(scannedPortCount) / Double(totalPortCount) : 0
    }

    // MARK: - HTTP

    private(set) var fingerprint: HTTPFingerprinter.Fingerprint?
    private(set) var isFingerprinting = false

    // MARK: - Reachability

    private(set) var isCheckingReachability = false
    private(set) var lastReachabilityResult: Bool?
    private(set) var lastReachabilityCheck: Date?

    // MARK: - Private

    private let sweeper = ICMPSweeper()
    private var pingTask: Task<Void, Never>?
    private var portScanTask: Task<Void, Never>?

    /// Keeps the chart bounded; older points scroll off.
    private static let maximumSamples = 60

    // MARK: - Ping control

    func togglePing(for device: Device, timeout: TimeInterval) {
        if isPinging {
            stopPing()
        } else {
            startPing(for: device, timeout: timeout)
        }
    }

    func startPing(for device: Device, timeout: TimeInterval) {
        guard !isPinging else { return }
        isPinging = true
        pingSamples.removeAll(keepingCapacity: true)
        packetsSent = 0
        packetsLost = 0

        let address = device.ipAddress
        let sweeper = sweeper

        pingTask = Task { [weak self] in
            var index = 0

            while !Task.isCancelled {
                let box = MutableBox<TimeInterval?>(nil)

                // `onReply` is labelled explicitly: an unlabelled trailing
                // closure would forward-scan onto `isCancelled`, which also
                // takes a closure.
                await sweeper.sweep(
                    targets: [address],
                    timeout: timeout,
                    attempts: 1,
                    onReply: { reply in box.value = reply.roundTripTime }
                )

                guard !Task.isCancelled, let self else { return }

                self.appendSample(
                    PingSample(
                        id: index,
                        timestamp: .now,
                        milliseconds: box.value.map { $0 * 1000 }
                    )
                )
                index += 1

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        isPinging = false
    }

    private func appendSample(_ sample: PingSample) {
        packetsSent += 1
        if sample.milliseconds == nil { packetsLost += 1 }

        pingSamples.append(sample)
        if pingSamples.count > Self.maximumSamples {
            pingSamples.removeFirst(pingSamples.count - Self.maximumSamples)
        }
    }

    // MARK: - Reachability

    /// Confirms the host is up using ICMP first, then a TCP knock — some hosts
    /// answer only one of the two.
    func checkReachability(for device: Device) async {
        guard !isCheckingReachability else { return }
        isCheckingReachability = true
        defer {
            isCheckingReachability = false
            lastReachabilityCheck = .now
        }

        let address = device.ipAddress
        let box = MutableBox<TimeInterval?>(nil)

        await sweeper.sweep(
            targets: [address],
            timeout: 1.0,
            attempts: 2,
            onReply: { reply in box.value = reply.roundTripTime }
        )

        if box.value != nil {
            lastReachabilityResult = true
            return
        }

        let fallbackPorts = device.openPorts.isEmpty
            ? [80, 443, 22, 445]
            : Array(device.openPorts.prefix(4))

        let result = await PortScanner.quickLivenessProbe(
            address: address,
            ports: fallbackPorts,
            timeout: 1.0
        )
        lastReachabilityResult = result.provesHostAlive
    }

    // MARK: - Port scan

    func startPortScan(for device: Device, configuration: ScanConfiguration) {
        guard !isScanningPorts else { return }

        let ports = configuration.profile.ports
        isScanningPorts = true
        scannedPortCount = 0
        totalPortCount = ports.count
        liveServices = device.services.filter(\.discoveredViaBonjour)

        let address = device.ipAddress
        let timeout = configuration.portTimeout

        // `Task` inherits this view model's main-actor isolation, so the
        // bookkeeping below is already on the main actor; only the probes
        // themselves run on the concurrent pool inside `concurrentForEach`.
        portScanTask = Task { [weak self] in
            await concurrentForEach(ports, limit: configuration.portConcurrency) { port -> ServiceInfo? in
                let result = await TCPProbe.probe(address: address, port: port, timeout: timeout)
                guard case .open(let duration) = result else { return nil }
                return ServiceInfo(
                    port: port,
                    name: PortCatalog.name(for: port),
                    detail: nil,
                    connectTime: duration
                )
            } onResult: { service in
                guard let self else { return }
                self.scannedPortCount += 1
                if let service { self.mergeLiveServices([service]) }
            }

            guard !Task.isCancelled else { return }
            self?.isScanningPorts = false
        }
    }

    func stopPortScan() {
        portScanTask?.cancel()
        portScanTask = nil
        isScanningPorts = false
    }

    private func mergeLiveServices(_ services: [ServiceInfo]) {
        var byPort: [UInt16: ServiceInfo] = [:]
        for service in liveServices { byPort[service.port] = service }
        for service in services where byPort[service.port] == nil {
            byPort[service.port] = service
        }
        liveServices = byPort.values.sorted { $0.port < $1.port }
    }

    // MARK: - HTTP fingerprint

    func fingerprintWebService(for device: Device) async {
        guard !isFingerprinting else { return }

        let httpsPort = device.openPorts.first { $0 == 443 || $0 == 8443 }
        let httpPort = device.openPorts.first { [80, 8080, 8000, 8081, 8888, 5000, 81].contains($0) }

        guard let port = httpsPort ?? httpPort else { return }

        isFingerprinting = true
        defer { isFingerprinting = false }

        fingerprint = await HTTPFingerprinter.fingerprint(
            address: device.ipAddress,
            port: port,
            useTLS: httpsPort != nil
        )
    }

    /// The URL the "Open in browser" action should use, if any.
    func webURL(for device: Device) -> URL? {
        if device.openPorts.contains(443) {
            return URL(string: "https://\(device.ipAddress)")
        }
        if device.openPorts.contains(8443) {
            return URL(string: "https://\(device.ipAddress):8443")
        }
        for port in [80, 8080, 8000, 8081, 8888, 5000, 81] where device.openPorts.contains(UInt16(port)) {
            return URL(string: port == 80 ? "http://\(device.ipAddress)" : "http://\(device.ipAddress):\(port)")
        }
        return nil
    }

    func cancelAll() {
        stopPing()
        stopPortScan()
    }
}
