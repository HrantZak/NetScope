import Foundation
import Network

/// A Bonjour service instance found on the LAN.
struct BonjourService: Sendable, Hashable {
    var name: String
    var type: String
    var domain: String
    var address: IPv4?
    var port: UInt16?
    var txtRecord: [String: String] = [:]

    var label: String { PortCatalog.bonjourLabel(for: type) }

    /// Apple devices advertise a hardware identifier in TXT (`model=J305AP`).
    var advertisedModel: String? {
        txtRecord["model"] ?? txtRecord["md"] ?? txtRecord["am"] ?? txtRecord["ty"]
    }
}

/// Browses Bonjour for the service types declared in `NSBonjourServices`.
///
/// iOS only permits browsing types listed in the app's Info.plist, so the list
/// below and the plist must stay in sync.
enum BonjourDiscovery {

    static let serviceTypes: [String] = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_nfs._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp", "_scanner._tcp",
        "_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_hap._tcp", "_homekit._tcp",
        "_googlecast._tcp", "_spotify-connect._tcp", "_sonos._tcp",
        "_rdlink._tcp", "_device-info._tcp", "_workstation._tcp", "_rfb._tcp",
        "_daap._tcp", "_dacp._tcp", "_touch-able._tcp",
        "_mqtt._tcp", "_secure-mqtt._tcp", "_rtsp._tcp", "_ftp._tcp",
        "_telnet._tcp", "_http-alt._tcp", "_webdav._tcp", "_webdavs._tcp",
        "_uscans._tcp", "_uscan._tcp", "_scanner._udp", "_sleep-proxy._udp",
        "_matter._tcp", "_matter._udp", "_meshcop._udp", "_miio._udp",
        "_adb._tcp", "_nvstream._tcp", "_steamlocal._tcp", "_xbox._tcp",
        "_amzn-wplay._tcp", "_airplay._udp", "_raop._udp", "_companion-link._udp"
    ]

    private static let queue = DispatchQueue(label: "com.netscope.bonjour", qos: .userInitiated)

    /// A browse hit before its address has been resolved. Deliberately holds
    /// only strings so it can cross actor boundaries.
    private struct BrowseHit: Sendable, Hashable {
        var name: String
        var type: String
        var domain: String
        var txtRecord: [String: String]
    }

    // MARK: - Public API

    /// Browses every declared service type in parallel, then resolves each
    /// instance to an IPv4 address.
    static func discover(
        browseTimeout: TimeInterval = 2.5,
        resolveTimeout: TimeInterval = 1.5,
        resolveConcurrency: Int = 16
    ) async -> [BonjourService] {
        let hits = MutableBox<Set<BrowseHit>>([])

        await withTaskGroup(of: Void.self) { group in
            for type in serviceTypes {
                group.addTask {
                    let found = await browse(type: type, duration: browseTimeout)
                    hits.mutate { $0.formUnion(found) }
                }
            }
        }

        let unique = Array(hits.value)
        guard !unique.isEmpty else { return [] }

        let resolved = MutableBox<[BonjourService]>([])
        await concurrentForEach(unique, limit: resolveConcurrency) { hit -> BonjourService in
            let endpoint = await resolve(hit: hit, timeout: resolveTimeout)
            return BonjourService(
                name: hit.name,
                type: hit.type,
                domain: hit.domain,
                address: endpoint?.address,
                port: endpoint?.port,
                txtRecord: hit.txtRecord
            )
        } onResult: { service in
            resolved.mutate { $0.append(service) }
        }

        return resolved.value
    }

    // MARK: - Browsing

    private static func browse(type: String, duration: TimeInterval) async -> Set<BrowseHit> {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: type, domain: nil),
            using: parameters
        )
        let box = UncheckedBox(browser)
        let collected = MutableBox<Set<BrowseHit>>([])
        let latch = ResumeOnce()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Set<BrowseHit>, Never>) in
                @Sendable func finish() {
                    guard latch.claim() else { return }
                    box.wrapped.browseResultsChangedHandler = nil
                    box.wrapped.stateUpdateHandler = nil
                    box.wrapped.cancel()
                    continuation.resume(returning: collected.value)
                }

                box.wrapped.browseResultsChangedHandler = { results, _ in
                    var hits: Set<BrowseHit> = []
                    for result in results {
                        guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
                        var txt: [String: String] = [:]
                        if case .bonjour(let record) = result.metadata {
                            txt = record.dictionary
                        }
                        hits.insert(BrowseHit(name: name, type: type, domain: domain, txtRecord: txt))
                    }
                    collected.mutate { $0.formUnion(hits) }
                }

                box.wrapped.stateUpdateHandler = { state in
                    switch state {
                    case .failed, .cancelled:
                        // Most commonly a denied Local Network permission.
                        finish()
                    default:
                        break
                    }
                }

                box.wrapped.start(queue: queue)
                queue.asyncAfter(deadline: .now() + duration) { finish() }
            }
        } onCancel: {
            box.wrapped.cancel()
        }
    }

    // MARK: - Resolving

    /// Resolves a Bonjour instance to an address.
    ///
    /// A **UDP** connection is used on purpose: it reaches `.ready` as soon as
    /// DNS-SD resolution succeeds, without needing the peer to accept anything.
    /// A TCP probe would fail against services that refuse our connection, and
    /// no datagram is ever actually sent.
    private static func resolve(
        hit: BrowseHit,
        timeout: TimeInterval
    ) async -> (address: IPv4, port: UInt16)? {
        let endpoint = NWEndpoint.service(
            name: hit.name,
            type: hit.type,
            domain: hit.domain,
            interface: nil
        )

        let parameters = NWParameters.udp
        parameters.prohibitedInterfaceTypes = [.cellular]
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }

        let connection = NWConnection(to: endpoint, using: parameters)
        let box = UncheckedBox(connection)
        let latch = ResumeOnce()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<(address: IPv4, port: UInt16)?, Never>) in
                @Sendable func finish(_ value: (address: IPv4, port: UInt16)?) {
                    guard latch.claim() else { return }
                    box.wrapped.stateUpdateHandler = nil
                    box.wrapped.cancel()
                    continuation.resume(returning: value)
                }

                box.wrapped.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(remoteIPv4(of: box.wrapped))
                    case .failed, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }

                box.wrapped.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
            }
        } onCancel: {
            box.wrapped.cancel()
        }
    }

    private static func remoteIPv4(of connection: NWConnection) -> (address: IPv4, port: UInt16)? {
        guard let remote = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, let port) = remote
        else { return nil }

        switch host {
        case .ipv4(let value):
            let bytes = [UInt8](value.rawValue)
            guard bytes.count == 4 else { return nil }
            let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return (IPv4(raw: raw), port.rawValue)
        case .name(let name, _):
            guard let parsed = IPv4(name) else { return nil }
            return (parsed, port.rawValue)
        default:
            return nil
        }
    }
}
