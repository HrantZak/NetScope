import Foundation

/// Orchestrates a full LAN scan.
///
/// Pipeline, with everything that can overlap overlapping:
///
/// ```
///  ┌ Bonjour browse ─────────────────────────┐   (runs for the whole scan)
///  ├ ICMP sweep ─┬ ARP harvest ─┬ TCP fallback┤
///  └─────────────┴──────────────┴─────────────┴─ reverse DNS ─ port probes
/// ```
///
/// Hosts are emitted the moment they answer, so the list fills in live instead
/// of appearing all at once when the scan ends. The engine is an `actor`: it
/// owns the mutable scan state and can only be driven from one place at a time,
/// which makes "tap Scan twice quickly" a non-event.
actor ScanEngine {

    private let sweeper = ICMPSweeper()

    /// Guards against overlapping scans.
    private var isScanning = false

    var isBusy: Bool { isScanning }

    // MARK: - Entry point

    /// Runs a complete scan, reporting progress through `emit`.
    ///
    /// Honours task cancellation at every stage; a cancelled scan leaves no
    /// sockets or background work behind.
    func scan(
        configuration: ScanConfiguration,
        snapshot: NetworkSnapshot,
        emit: @escaping @Sendable (ScanEvent) -> Void
    ) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let config = configuration.sanitized

        guard let subnet = snapshot.subnet, let localAddress = snapshot.localAddress else {
            emit(.failed("No local IPv4 network found. Join a Wi-Fi network and try again."))
            return
        }

        guard subnet.prefixLength >= 8 else {
            emit(.failed("The current network is too large to scan safely."))
            return
        }

        let targets = subnet.hostAddresses(limit: config.maxHosts, anchor: localAddress)
        guard !targets.isEmpty else {
            emit(.failed("This network has no scannable host addresses."))
            return
        }

        emit(.started(totalHosts: targets.count))

        // Publish this iPhone immediately. Network-path notifications can
        // cancel a scan while the active sweep is still unwinding; previously
        // that race could leave the router as the only visible row even though
        // the local address was known from the start.
        let localHost = LiveHost(address: localAddress, latency: 0, method: .local)
        emit(.discovered(makeDevice(
            host: localHost,
            snapshot: snapshot,
            mac: nil,
            bonjour: [],
            hostname: nil,
            services: []
        )))

        // Bonjour runs for the duration of the sweep rather than after it.
        async let bonjourServices: [BonjourService] = Self.browseBonjour(enabled: config.useBonjour)

        // Capture neighbours both before and after the active sweep. Some
        // routers age their ARP entries very quickly, while others already
        // have useful entries before our first packet is sent.
        let arpBeforeSweep = RouteTable.arpTable()

        // 1. Liveness ------------------------------------------------------
        emit(.phase(.sweeping))
        let liveness = await discoverLiveHosts(
            targets: targets,
            config: config,
            emit: emit
        )

        if Task.isCancelled {
            _ = await bonjourServices
            emit(.finished(deviceCount: 0))
            return
        }

        // 2. Enrich with layer-2 facts -------------------------------------
        let arpAfterSweep = RouteTable.arpTable()
        let arpTable = arpBeforeSweep.merging(arpAfterSweep) { _, fresh in fresh }
        var aliveHosts = liveness

        // Sending probes populates the ARP cache even for hosts that drop ICMP,
        // so the neighbour table is a second, free discovery channel.
        for (address, _) in arpTable where subnet.contains(address) && aliveHosts[address] == nil {
            guard address != localAddress else { continue }
            aliveHosts[address] = LiveHost(address: address, latency: nil, method: .arp)
        }

        // A gateway can legitimately ignore ICMP and have no administration
        // port open. It is nevertheless known to be present because the
        // system route points at it. Previously such networks often showed
        // only "This iPhone", which looked like a broken scan.
        if let gateway = snapshot.gateway,
           subnet.contains(gateway),
           gateway != localAddress,
           aliveHosts[gateway] == nil {
            aliveHosts[gateway] = LiveHost(address: gateway, latency: nil, method: .route)
        }

        let services = await bonjourServices
        var bonjourByAddress: [IPv4: [BonjourService]] = [:]
        for service in services {
            guard let address = service.address else { continue }
            bonjourByAddress[address, default: []].append(service)
        }

        // Bonjour can reveal hosts that answered neither ICMP nor ARP.
        for (address, _) in bonjourByAddress where subnet.contains(address) && aliveHosts[address] == nil {
            aliveHosts[address] = LiveHost(address: address, latency: nil, method: .bonjour)
        }

        // Always include ourselves — we are unambiguously on the network.
        aliveHosts[localAddress] = localHost

        // 3. Build preliminary records and publish them immediately ---------
        var devices: [IPv4: Device] = [:]
        devices.reserveCapacity(aliveHosts.count)

        for host in aliveHosts.values.sorted(by: { $0.address < $1.address }) {
            let device = makeDevice(
                host: host,
                snapshot: snapshot,
                mac: arpTable[host.address],
                bonjour: bonjourByAddress[host.address] ?? [],
                hostname: nil,
                services: []
            )
            devices[host.address] = device
            emit(.discovered(device))
        }

        emit(.progress(scanned: targets.count, total: targets.count))

        guard !Task.isCancelled else {
            emit(.finished(deviceCount: devices.count))
            return
        }

        // 4. Reverse DNS ----------------------------------------------------
        if config.resolveHostnames {
            emit(.phase(.resolving))
            await resolveHostnames(for: &devices, config: config, emit: emit)
        }

        guard !Task.isCancelled else {
            emit(.finished(deviceCount: devices.count))
            return
        }

        // 5. Port probing ---------------------------------------------------
        if config.scanPorts {
            emit(.phase(.probingPorts))
            await probeServices(for: &devices, config: config, snapshot: snapshot, emit: emit)
        }

        emit(.phase(.finishing))
        emit(.finished(deviceCount: devices.count))
    }

    /// Wrapper so the `async let` above has a single async expression to bind.
    private static func browseBonjour(enabled: Bool) async -> [BonjourService] {
        guard enabled else { return [] }
        return await BonjourDiscovery.discover(browseTimeout: 2.5)
    }

    // MARK: - Stage 1: liveness

    private struct LiveHost: Sendable {
        var address: IPv4
        var latency: TimeInterval?
        var method: DiscoveryMethod
    }

    /// Named result types instead of tuples: Swift closures cannot destructure
    /// a tuple parameter, and these read better at the call site anyway.
    private struct ProbeOutcome: Sendable {
        var address: IPv4
        var result: TCPProbeResult
    }

    private struct HostnameOutcome: Sendable {
        var address: IPv4
        var hostname: String?
    }

    private struct ServiceOutcome: Sendable {
        var address: IPv4
        var services: [ServiceInfo]
    }

    private func discoverLiveHosts(
        targets: [IPv4],
        config: ScanConfiguration,
        emit: @escaping @Sendable (ScanEvent) -> Void
    ) async -> [IPv4: LiveHost] {
        let found = MutableBox<[IPv4: LiveHost]>([:])
        let cancelled = MutableBox(false)
        let total = targets.count

        _ = await withTaskCancellationHandler {
            await sweeper.sweep(
                targets: targets,
                timeout: config.pingTimeout,
                attempts: config.pingAttempts,
                isCancelled: { cancelled.value },
                onProgress: { sent in
                    emit(.progress(scanned: min(sent, total), total: total))
                },
                onReply: { reply in
                    found.mutate { $0[reply.address] = LiveHost(
                        address: reply.address,
                        latency: reply.roundTripTime,
                        method: .icmp
                    ) }
                }
            )
        } onCancel: {
            cancelled.value = true
        }

        // Always probe addresses that stayed silent when deep discovery is
        // enabled. Earlier builds stopped after ICMP found three hosts, which
        // systematically missed phones, TVs and IoT devices that block ping.
        // The bounded pool below keeps this exhaustive pass safe for iOS.
        let shouldFallBack = config.useTCPFallback
        guard shouldFallBack, !Task.isCancelled else { return found.value }

        emit(.phase(.sweeping))
        let silent = targets.filter { found.value[$0] == nil }
        let probed = MutableBox(0)
        let timeout = config.portTimeout

        // Each host races several ports internally, so cap host-level
        // parallelism to avoid hundreds of simultaneous NWConnections. That
        // used to overwhelm iOS on larger subnets and turn real replies into
        // apparent timeouts.
        let fallbackConcurrency = min(config.hostConcurrency, 12)
        await concurrentForEach(silent, limit: fallbackConcurrency) { address -> ProbeOutcome in
            let result = await PortScanner.quickLivenessProbe(
                address: address,
                // A deliberately diverse set: routers, computers, printers,
                // TVs and Apple devices rarely expose the same three ports.
                ports: [21, 22, 23, 53, 80, 135, 139, 443, 445, 515, 548, 554, 631, 1883, 3389, 5900, 7000, 8008, 8080, 8443, 8883, 9100, 62078],
                timeout: timeout
            )
            return ProbeOutcome(address: address, result: result)
        } onResult: { outcome in
            probed.mutate { $0 += 1 }
            emit(.progress(scanned: probed.value, total: silent.count))
            guard outcome.result.provesHostAlive else { return }
            found.mutate {
                $0[outcome.address] = LiveHost(
                    address: outcome.address,
                    latency: outcome.result.duration,
                    method: .tcp
                )
            }
        }

        return found.value
    }

    // MARK: - Stage 2: hostnames

    private func resolveHostnames(
        for devices: inout [IPv4: Device],
        config: ScanConfiguration,
        emit: @escaping @Sendable (ScanEvent) -> Void
    ) async {
        let addresses = Array(devices.keys)
        guard !addresses.isEmpty else { return }

        let resolved = MutableBox<[IPv4: String]>([:])
        let done = MutableBox(0)
        let total = addresses.count

        await concurrentForEach(addresses, limit: min(config.hostConcurrency, 32)) { address -> HostnameOutcome in
            HostnameOutcome(address: address, hostname: await DNSResolver.reverseLookup(address))
        } onResult: { outcome in
            done.mutate { $0 += 1 }
            emit(.progress(scanned: done.value, total: total))
            guard let hostname = outcome.hostname else { return }
            resolved.mutate { $0[outcome.address] = hostname }
        }

        for (address, hostname) in resolved.value {
            guard var device = devices[address] else { continue }
            device.hostname = hostname
            device.kind = reclassify(device)
            devices[address] = device
            emit(.updated(device))
        }
    }

    // MARK: - Stage 3: services

    private func probeServices(
        for devices: inout [IPv4: Device],
        config: ScanConfiguration,
        snapshot: NetworkSnapshot,
        emit: @escaping @Sendable (ScanEvent) -> Void
    ) async {
        let ports = config.portsToProbe
        let hosts = devices.keys.filter { $0 != snapshot.localAddress }.sorted()
        guard !ports.isEmpty, !hosts.isEmpty else { return }

        let scanner = PortScanner(timeout: config.portTimeout, concurrency: config.portConcurrency)
        let results = MutableBox<[IPv4: [ServiceInfo]]>([:])
        let done = MutableBox(0)
        let total = hosts.count

        // Hosts are walked a few at a time; each host internally fans out over
        // its port list. Two nested bounded pools keep total sockets in check.
        let hostParallelism = max(2, min(config.hostConcurrency / config.portConcurrency, 8))

        await concurrentForEach(hosts, limit: hostParallelism) { address -> ServiceOutcome in
            ServiceOutcome(address: address, services: await scanner.scan(address: address, ports: ports))
        } onResult: { outcome in
            done.mutate { $0 += 1 }
            emit(.progress(scanned: done.value, total: total))
            guard !outcome.services.isEmpty else { return }
            results.mutate { $0[outcome.address] = outcome.services }
        }

        for (address, found) in results.value {
            guard var device = devices[address] else { continue }
            device.services = mergeServices(existing: device.services, discovered: found)
            device.kind = reclassify(device)
            devices[address] = device
            emit(.updated(device))
        }
    }

    // MARK: - Record building

    private func makeDevice(
        host: LiveHost,
        snapshot: NetworkSnapshot,
        mac: String?,
        bonjour: [BonjourService],
        hostname: String?,
        services: [ServiceInfo]
    ) -> Device {
        let networkID = snapshot.networkID
        let isGateway = snapshot.gateway == host.address
        let isLocal = snapshot.localAddress == host.address
        // The neighbour table can contain a proxy-ARP MAC for our own address
        // (and sometimes the same proxy MAC for several clients). Treating
        // that value as a globally unique ID collapsed multiple IP addresses
        // into one row. The local device has no meaningful ARP MAC at all.
        let effectiveMAC = isLocal ? nil : mac

        let bonjourName = bonjour
            .map(\.name)
            .sorted { $0.count > $1.count }
            .first

        let bonjourTypes = Array(Set(bonjour.map(\.type))).sorted()
        let advertisedModel = bonjour.compactMap(\.advertisedModel).first
        let vendor = effectiveMAC.flatMap(VendorDatabase.vendor(forMAC:))

        var bonjourServices = bonjour.compactMap { service -> ServiceInfo? in
            guard let port = service.port else { return nil }
            return ServiceInfo(
                port: port,
                name: service.label,
                detail: service.advertisedModel,
                connectTime: nil,
                discoveredViaBonjour: true
            )
        }
        bonjourServices = mergeServices(existing: bonjourServices, discovered: services)

        let kind = DeviceClassifier.classify(
            vendor: vendor,
            hostname: hostname,
            bonjourName: bonjourName,
            bonjourTypes: bonjourTypes,
            advertisedModel: advertisedModel,
            openPorts: bonjourServices.map(\.port),
            isGateway: isGateway
        )

        // IP is intentionally part of the key even when a MAC is visible.
        // Proxy ARP, mesh systems and repeaters may expose one MAC for several
        // real hosts; distinct LAN addresses must always remain distinct rows.
        let identity = effectiveMAC.map {
            "\(networkID)|mac:\($0)|ip:\(host.address)"
        } ?? "\(networkID)|ip:\(host.address)"

        var device = Device(id: identity, ipAddress: host.address)
        device.hostname = hostname
        device.bonjourName = bonjourName
        device.macAddress = effectiveMAC
        device.vendor = vendor
        device.kind = isLocal && kind == .unknown ? .phone : kind
        device.services = bonjourServices
        device.bonjourServiceTypes = bonjourTypes
        device.latency = host.latency
        device.latencySamples = host.latency.map { [$0] } ?? []
        device.responded = true
        device.discoveryMethod = host.method
        device.isGateway = isGateway
        device.isLocalDevice = isLocal
        device.networkID = networkID
        device.firstSeen = .now
        device.lastSeen = .now
        return device
    }

    /// Re-runs classification after new evidence (hostname, ports) arrived.
    private func reclassify(_ device: Device) -> DeviceKind {
        DeviceClassifier.classify(
            vendor: device.vendor,
            hostname: device.hostname,
            bonjourName: device.bonjourName,
            bonjourTypes: device.bonjourServiceTypes,
            advertisedModel: device.services.compactMap(\.detail).first,
            openPorts: device.services.map(\.port),
            isGateway: device.isGateway
        )
    }

    /// Union by port, preferring the entry that carries more information.
    private func mergeServices(existing: [ServiceInfo], discovered: [ServiceInfo]) -> [ServiceInfo] {
        var byPort: [UInt16: ServiceInfo] = [:]
        for service in existing { byPort[service.port] = service }

        for service in discovered {
            if var current = byPort[service.port] {
                current.connectTime = service.connectTime ?? current.connectTime
                current.detail = current.detail ?? service.detail
                if current.name == nil { current.name = service.name }
                byPort[service.port] = current
            } else {
                byPort[service.port] = service
            }
        }

        return byPort.values.sorted { $0.port < $1.port }
    }
}
