import Foundation

// MARK: - IPv4

/// A compact, value-type IPv4 address stored as a host-order `UInt32`.
///
/// Using an integer representation keeps sorting, subnet math and hashing
/// allocation-free, which matters when we hold thousands of candidate hosts.
///
/// Deliberately *not* named `IPv4Address`: the `Network` framework exports a
/// type with that name and the collision would force qualification everywhere.
struct IPv4: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {

    /// Host byte order representation (`192.168.1.1` -> `0xC0A80101`).
    let raw: UInt32

    init(raw: UInt32) {
        self.raw = raw
    }

    init?(_ string: String) {
        var addr = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        self.raw = UInt32(bigEndian: addr.s_addr)
    }

    init(networkOrder: UInt32) {
        self.raw = UInt32(bigEndian: networkOrder)
    }

    var networkOrder: UInt32 { raw.bigEndian }

    var inAddr: in_addr { in_addr(s_addr: raw.bigEndian) }

    var description: String {
        "\((raw >> 24) & 0xFF).\((raw >> 16) & 0xFF).\((raw >> 8) & 0xFF).\(raw & 0xFF)"
    }

    var isLoopback: Bool { (raw >> 24) == 127 }

    var isLinkLocal: Bool { (raw >> 16) == 0xA9FE }

    /// True for the RFC1918 / CGNAT ranges we consider "a LAN".
    var isPrivate: Bool {
        let a = (raw >> 24) & 0xFF
        let b = (raw >> 16) & 0xFF
        if a == 10 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 100 && (64...127).contains(b) { return true }
        return false
    }

    /// The `x.y.z.0/24` block this address belongs to — used for grouping.
    var classCBlock: String {
        "\((raw >> 24) & 0xFF).\((raw >> 16) & 0xFF).\((raw >> 8) & 0xFF).0/24"
    }

    static func < (lhs: IPv4, rhs: IPv4) -> Bool { lhs.raw < rhs.raw }

    // Encoded as a dotted string so exported JSON stays human readable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = IPv4(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid IPv4 address: \(text)")
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - IPv4Subnet

/// An IPv4 network described by an address inside it plus a prefix length.
struct IPv4Subnet: Hashable, Sendable, Codable, CustomStringConvertible {

    let address: IPv4
    let prefixLength: Int

    init(address: IPv4, prefixLength: Int) {
        self.address = address
        self.prefixLength = min(max(prefixLength, 0), 32)
    }

    /// Builds a subnet from an address and a dotted netmask (`255.255.255.0`).
    init(address: IPv4, netmask: IPv4) {
        self.init(address: address, prefixLength: netmask.raw.nonzeroBitCount)
    }

    var maskRaw: UInt32 {
        prefixLength == 0 ? 0 : (~UInt32(0)) << (32 - UInt32(prefixLength))
    }

    var netmask: IPv4 { IPv4(raw: maskRaw) }

    var networkAddress: IPv4 { IPv4(raw: address.raw & maskRaw) }

    var broadcastAddress: IPv4 { IPv4(raw: (address.raw & maskRaw) | ~maskRaw) }

    /// Number of assignable host addresses (network + broadcast excluded).
    var usableHostCount: Int {
        switch prefixLength {
        case 32: return 1
        case 31: return 2
        default:
            let total = UInt64(~maskRaw) + 1
            return Int(total) - 2
        }
    }

    var description: String { "\(networkAddress)/\(prefixLength)" }

    func contains(_ candidate: IPv4) -> Bool {
        (candidate.raw & maskRaw) == (address.raw & maskRaw)
    }

    /// Enumerates usable host addresses, capped at `limit` to stay responsive on
    /// unusually wide networks (a /16 would mean 65k probes).
    ///
    /// When the subnet is larger than `limit` the window stays centred on
    /// `anchor` (normally our own address) because neighbours cluster nearby.
    func hostAddresses(limit: Int, anchor: IPv4? = nil) -> [IPv4] {
        guard limit > 0 else { return [] }
        guard prefixLength < 31 else {
            return prefixLength == 32 ? [address] : [networkAddress, broadcastAddress]
        }

        let first = networkAddress.raw &+ 1
        let last = broadcastAddress.raw &- 1
        guard first <= last else { return [] }

        let total = Int(last - first) + 1
        if total <= limit {
            return (first...last).map(IPv4.init(raw:))
        }

        let centre = anchor.map { max(min($0.raw, last), first) } ?? first
        let half = UInt32(limit / 2)
        var start = centre > first &+ half ? centre &- half : first
        if start &+ UInt32(limit) &- 1 > last {
            start = last &- UInt32(limit) &+ 1
        }
        let end = start &+ UInt32(limit) &- 1
        return (start...end).map(IPv4.init(raw:))
    }
}
