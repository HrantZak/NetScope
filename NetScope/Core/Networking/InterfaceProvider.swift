import Foundation
import Darwin

/// Reads the device's own IPv4 interfaces through `getifaddrs(3)`.
///
/// Public BSD API — no entitlement required and no private symbols involved.
enum InterfaceProvider {

    struct Interface: Sendable, Hashable {
        var name: String
        var address: IPv4
        var netmask: IPv4
        var broadcast: IPv4?
        var isRunning: Bool

        var subnet: IPv4Subnet { IPv4Subnet(address: address, netmask: netmask) }

        /// `en0` is Wi-Fi on every shipping iPhone; `pdp_ip*` is cellular.
        var type: NetworkSnapshot.InterfaceType {
            if name.hasPrefix("en") { return .wifi }
            if name.hasPrefix("pdp_ip") { return .cellular }
            if name.hasPrefix("bridge") || name.hasPrefix("ap") { return .wired }
            return .other
        }
    }

    /// All up, non-loopback IPv4 interfaces, best candidate first.
    static func activeInterfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var interfaces: [Interface] = []

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0,
                  let addressPointer = pointer.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let name = String(cString: pointer.pointee.ifa_name)
            let address = readIPv4(from: addressPointer)
            guard !address.isLoopback, address.raw != 0 else { continue }

            let netmask = pointer.pointee.ifa_netmask.map(readIPv4(from:)) ?? IPv4(raw: 0xFFFFFF00)
            let broadcast = (flags & IFF_BROADCAST != 0)
                ? pointer.pointee.ifa_dstaddr.map(readIPv4(from:))
                : nil

            interfaces.append(
                Interface(
                    name: name,
                    address: address,
                    netmask: netmask.raw == 0 ? IPv4(raw: 0xFFFFFF00) : netmask,
                    broadcast: broadcast,
                    isRunning: flags & IFF_RUNNING != 0
                )
            )
        }

        // Prefer Wi-Fi with a private address — that is the LAN we can scan.
        return interfaces.sorted { lhs, rhs in
            func rank(_ item: Interface) -> Int {
                var score = 0
                if item.type == .wifi { score += 8 }
                if item.address.isPrivate { score += 4 }
                if item.isRunning { score += 2 }
                if item.name == "en0" { score += 1 }
                return score
            }
            return rank(lhs) > rank(rhs)
        }
    }

    /// The interface a LAN scan should run over, if any.
    static func primaryInterface() -> Interface? {
        activeInterfaces().first { $0.type != .cellular }
    }

    private static func readIPv4(from pointer: UnsafeMutablePointer<sockaddr>) -> IPv4 {
        pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            IPv4(networkOrder: $0.pointee.sin_addr.s_addr)
        }
    }
}
