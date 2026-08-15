import Foundation
import Network

/// Local Network permission state.
///
/// iOS exposes no API to query this directly, so the check is behavioural:
/// the app advertises a private Bonjour service and then browses for it. Only
/// an authorised app can see its own advertisement.
enum LocalNetworkPermission: String, Sendable {
    case unknown
    case granted
    case denied

    var title: String {
        switch self {
        case .unknown: "Not determined"
        case .granted: "Granted"
        case .denied: "Denied"
        }
    }
}

/// Requests and verifies Local Network access.
///
/// Starting the browser is also what triggers the system prompt, so calling
/// `request()` doubles as "ask the user".
enum LocalNetworkAuthorization {

    private static let serviceType = "_netscope._tcp"
    private static let queue = DispatchQueue(label: "com.netscope.local-network-auth", qos: .userInitiated)

    /// Advertises and browses for a private service.
    ///
    /// - Parameter timeout: how long to wait for our own advertisement to show
    ///   up before concluding the permission was refused.
    static func request(timeout: TimeInterval = 3.5) async -> LocalNetworkPermission {
        let instanceName = "NetScope-\(UInt32.random(in: 100_000...999_999))"

        let listenerParameters = NWParameters.tcp
        listenerParameters.includePeerToPeer = false

        guard let listener = try? NWListener(using: listenerParameters) else {
            return .unknown
        }
        listener.service = NWListener.Service(name: instanceName, type: serviceType)
        listener.newConnectionHandler = { connection in
            // Nothing ever connects; refuse politely just in case.
            connection.cancel()
        }

        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: NWParameters()
        )

        let listenerBox = UncheckedBox(listener)
        let browserBox = UncheckedBox(browser)
        let latch = ResumeOnce()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LocalNetworkPermission, Never>) in
                @Sendable func finish(_ permission: LocalNetworkPermission) {
                    guard latch.claim() else { return }
                    browserBox.wrapped.browseResultsChangedHandler = nil
                    browserBox.wrapped.stateUpdateHandler = nil
                    listenerBox.wrapped.stateUpdateHandler = nil
                    browserBox.wrapped.cancel()
                    listenerBox.wrapped.cancel()
                    continuation.resume(returning: permission)
                }

                browserBox.wrapped.browseResultsChangedHandler = { results, _ in
                    // Seeing any instance of our own service type proves access.
                    let sawOurService = results.contains { result in
                        guard case .service(let name, _, _, _) = result.endpoint else { return false }
                        return name == instanceName
                    }
                    if sawOurService { finish(.granted) }
                }

                browserBox.wrapped.stateUpdateHandler = { state in
                    if case .failed(let error) = state {
                        finish(isPolicyDenial(error) ? .denied : .unknown)
                    }
                }

                listenerBox.wrapped.stateUpdateHandler = { state in
                    if case .failed = state { finish(.unknown) }
                }

                listenerBox.wrapped.start(queue: queue)
                browserBox.wrapped.start(queue: queue)

                queue.asyncAfter(deadline: .now() + timeout) {
                    // The prompt may still be on screen; "denied" is the safe
                    // assumption and the UI offers a retry either way.
                    finish(.denied)
                }
            }
        } onCancel: {
            browserBox.wrapped.cancel()
            listenerBox.wrapped.cancel()
        }
    }

    /// `kDNSServiceErr_PolicyDenied` (-65570) is what mDNSResponder returns when
    /// the user has refused Local Network access.
    private static func isPolicyDenial(_ error: NWError) -> Bool {
        if case .dns(let code) = error {
            return code == -65570
        }
        return false
    }
}
