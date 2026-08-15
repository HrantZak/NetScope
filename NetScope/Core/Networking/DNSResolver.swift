import Foundation
import Darwin

/// Name resolution helpers built on `getnameinfo(3)` and `libresolv`.
enum DNSResolver {

    /// Reverse-resolves an IPv4 address to a hostname.
    ///
    /// On a LAN this usually answers from mDNS (`.local` names) or the router's
    /// DHCP-backed DNS. Returns `nil` when nothing answers before `timeout`.
    ///
    /// `getnameinfo` blocks, so the call runs on a background executor and is
    /// wrapped in a timeout race — an unresponsive resolver must never stall a
    /// scan.
    static func reverseLookup(_ address: IPv4, timeout: TimeInterval = 1.2) async -> String? {
        await withTaskGroupTimeout(seconds: timeout) {
            await Self.blockingReverseLookup(address)
        }
    }

    private static func blockingReverseLookup(_ address: IPv4) async -> String? {
        await withCheckedContinuation { continuation in
            resolverQueue.async {
                var storage = sockaddr_in()
                storage.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                storage.sin_family = sa_family_t(AF_INET)
                storage.sin_port = 0
                storage.sin_addr = address.inAddr

                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = withUnsafePointer(to: &storage) { pointer -> Int32 in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        getnameinfo(
                            sa,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostBuffer,
                            socklen_t(hostBuffer.count),
                            nil,
                            0,
                            NI_NAMEREQD
                        )
                    }
                }

                guard status == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let name = String(cString: hostBuffer)
                // Some resolvers echo the address back instead of failing.
                continuation.resume(returning: name.isEmpty || name == address.description ? nil : name)
            }
        }
    }

    /// IPv4 DNS servers currently configured for the active interface.
    ///
    /// `res_ninit` is public libresolv API (linked via `-lresolv`); when it is
    /// unavailable or returns nothing, callers fall back to showing the gateway.
    static func systemResolvers() -> [IPv4] {
        var state = __res_state()
        guard res_9_ninit(&state) == 0 else { return [] }
        defer { res_9_ndestroy(&state) }

        let count = Int(state.nscount)
        guard count > 0 else { return [] }

        var servers: [IPv4] = []
        withUnsafeBytes(of: &state.nsaddr_list) { raw in
            let stride = MemoryLayout<sockaddr_in>.size
            let available = min(count, raw.count / stride)
            for index in 0..<available {
                let sa = raw.loadUnaligned(fromByteOffset: index * stride, as: sockaddr_in.self)
                guard sa.sin_family == sa_family_t(AF_INET) else { continue }
                let address = IPv4(networkOrder: sa.sin_addr.s_addr)
                guard address.raw != 0, !servers.contains(address) else { continue }
                servers.append(address)
            }
        }
        return servers
    }

    // MARK: - Private

    /// Dedicated concurrent queue: resolution is blocking but short-lived, and
    /// keeping it off the cooperative pool avoids starving Swift Concurrency.
    private static let resolverQueue = DispatchQueue(
        label: "com.netscope.dns-resolver",
        qos: .userInitiated,
        attributes: .concurrent
    )
}

/// Races `operation` against a sleep, returning `nil` if the sleep wins.
///
/// Note the losing child task is cancelled but a blocking `getnameinfo` cannot
/// be interrupted; it finishes on its own thread and its result is discarded.
func withTaskGroupTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
