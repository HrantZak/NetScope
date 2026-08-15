import Foundation

/// Discovers which TCP ports a host is listening on.
struct PortScanner: Sendable {

    var timeout: TimeInterval
    var concurrency: Int

    init(timeout: TimeInterval = 0.6, concurrency: Int = 24) {
        self.timeout = timeout
        self.concurrency = concurrency
    }

    /// Probes `ports` on `address` and returns the open ones, sorted.
    ///
    /// Results stream through `onFound` too, so a detail screen can populate
    /// its list while the rest of the range is still being scanned.
    func scan(
        address: IPv4,
        ports: [UInt16],
        onFound: (@Sendable (ServiceInfo) -> Void)? = nil
    ) async -> [ServiceInfo] {
        guard !ports.isEmpty else { return [] }

        let collected = MutableBox<[ServiceInfo]>([])
        let timeout = timeout

        await concurrentForEach(ports, limit: concurrency) { port -> ServiceInfo? in
            let result = await TCPProbe.probe(address: address, port: port, timeout: timeout)
            guard case .open(let duration) = result else { return nil }
            return ServiceInfo(
                port: port,
                name: PortCatalog.name(for: port),
                detail: nil,
                connectTime: duration
            )
        } onResult: { service in
            guard let service else { return }
            collected.mutate { $0.append(service) }
            onFound?(service)
        }

        return collected.value.sorted { $0.port < $1.port }
    }

    /// Fast liveness check: races a handful of very common ports and stops at
    /// the first sign of life. Used as the ICMP fallback during discovery.
    static func quickLivenessProbe(
        address: IPv4,
        ports: [UInt16] = [80, 443, 22, 445, 62078, 8080],
        timeout: TimeInterval
    ) async -> TCPProbeResult {
        await withTaskGroup(of: TCPProbeResult.self) { group in
            for port in ports {
                group.addTask { await TCPProbe.probe(address: address, port: port, timeout: timeout) }
            }

            var best: TCPProbeResult = .timedOut
            for await result in group where result.provesHostAlive {
                best = result
                group.cancelAll()
                break
            }
            return best
        }
    }
}
