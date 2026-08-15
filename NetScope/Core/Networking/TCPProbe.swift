import Foundation
import Network

/// Outcome of a single TCP connect attempt.
enum TCPProbeResult: Sendable, Equatable {
    /// Handshake completed — the port is open.
    case open(TimeInterval)
    /// The host answered with RST: it is alive, but nothing listens there.
    case refused(TimeInterval)
    /// Routing said the host is not reachable.
    case unreachable
    /// Nothing came back before the deadline.
    case timedOut

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }

    /// Both `open` and `refused` prove the host exists — that is what makes TCP
    /// a viable discovery fallback when ICMP is filtered.
    var provesHostAlive: Bool {
        switch self {
        case .open, .refused: true
        case .unreachable, .timedOut: false
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .open(let value), .refused(let value): value
        case .unreachable, .timedOut: nil
        }
    }
}

/// Connect-scan primitive built on `NWConnection`.
enum TCPProbe {

    private static let queue = DispatchQueue(
        label: "com.netscope.tcp-probe",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Attempts a TCP handshake and reports what happened.
    ///
    /// The connection is always cancelled before returning, including on task
    /// cancellation, so no socket is left dangling.
    static func probe(
        address: IPv4,
        port: UInt16,
        timeout: TimeInterval
    ) async -> TCPProbeResult {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return .timedOut }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = max(Int(timeout.rounded(.up)), 1)
            tcp.noDelay = true
            tcp.enableKeepalive = false
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(address.description),
            port: endpointPort,
            using: parameters
        )
        let box = UncheckedBox(connection)
        let latch = ResumeOnce()
        let startedAt = DispatchTime.now()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<TCPProbeResult, Never>) in
                @Sendable func finish(_ result: TCPProbeResult) {
                    guard latch.claim() else { return }
                    box.wrapped.stateUpdateHandler = nil
                    box.wrapped.cancel()
                    continuation.resume(returning: result)
                }

                @Sendable func elapsed() -> TimeInterval {
                    Double(DispatchTime.now().uptimeNanoseconds &- startedAt.uptimeNanoseconds) / 1_000_000_000
                }

                box.wrapped.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(.open(elapsed()))
                    case .failed(let error):
                        finish(classify(error, elapsed: elapsed()))
                    case .cancelled:
                        finish(.timedOut)
                    case .waiting(let error):
                        // `waiting` means the stack will retry. For a LAN probe a
                        // refusal or unreachable route is already the final word.
                        let classified = classify(error, elapsed: elapsed())
                        if classified != .timedOut { finish(classified) }
                    case .setup, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }

                box.wrapped.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) {
                    finish(.timedOut)
                }
            }
        } onCancel: {
            box.wrapped.cancel()
        }
    }

    /// Convenience wrapper used by reachability checks.
    static func isReachable(address: IPv4, port: UInt16, timeout: TimeInterval) async -> Bool {
        await probe(address: address, port: port, timeout: timeout).provesHostAlive
    }

    private static func classify(_ error: NWError, elapsed: TimeInterval) -> TCPProbeResult {
        guard case .posix(let code) = error else { return .timedOut }
        switch code {
        case .ECONNREFUSED, .ECONNRESET:
            return .refused(elapsed)
        case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN:
            return .unreachable
        default:
            return .timedOut
        }
    }
}
