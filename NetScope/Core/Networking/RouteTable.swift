import Foundation
import Darwin

/// Reads the kernel routing table and ARP neighbour cache via `sysctl(3)`.
///
/// `CTL_NET / PF_ROUTE` is documented BSD API available to sandboxed apps, but
/// the iOS SDK does not expose `<net/route.h>` to Swift — `rt_msghdr` and the
/// `RTF_*` / `RTAX_*` constants are missing from the Darwin module map. They are
/// therefore mirrored here. The routing-socket message layout is part of the
/// stable kernel/user ABI and has not changed in decades; only fixed-width
/// integer fields are involved, so the offsets are identical on 32- and 64-bit.
///
/// Both lookups are best effort: iOS may return an empty ARP cache, in which
/// case MAC addresses (and therefore vendors) are simply unavailable and the UI
/// shows what it has.
enum RouteTable {

    /// Mirror of the parts of `<net/route.h>` the SDK withholds.
    private enum RouteABI {
        static let flagGateway: Int32 = 0x0002
        static let flagLinkLayerInfo: Int32 = 0x0400

        static let addressIndexDestination: Int32 = 0
        static let addressIndexGateway: Int32 = 1
        static let addressIndexCount: Int32 = 8

        /// `sizeof(struct rt_msghdr)`: 36 bytes of header plus a 56-byte
        /// `rt_metrics` tail.
        static let headerSize = 92

        /// Byte offsets of the three fields we actually read.
        static let offsetMessageLength = 0   // u_short rtm_msglen
        static let offsetFlags = 8           // int     rtm_flags
        static let offsetAddressMask = 12    // int     rtm_addrs
    }

    /// One decoded routing-socket message.
    private struct RouteMessage {
        var flags: Int32
        /// Sockaddr blobs keyed by their `RTAX_*` index.
        var addresses: [Int32: [UInt8]]
    }

    // MARK: - Public

    /// Address of the default gateway (`0.0.0.0/0` route), if present.
    static func defaultGateway() -> IPv4? {
        guard let buffer = dumpRoutes(flags: RouteABI.flagGateway) else { return nil }
        var fallback: IPv4?

        forEachMessage(in: buffer) { message in
            guard message.flags & RouteABI.flagGateway != 0 else { return }
            guard let destinationBytes = message.addresses[RouteABI.addressIndexDestination],
                  let gatewayBytes = message.addresses[RouteABI.addressIndexGateway],
                  let gateway = ipv4(from: gatewayBytes)
            else { return }

            // The default route has a 0.0.0.0 destination.
            if let destination = ipv4(from: destinationBytes), destination.raw == 0 {
                fallback = gateway
            } else if fallback == nil, gateway.isPrivate {
                fallback = gateway
            }
        }

        return fallback
    }

    /// Snapshot of the ARP cache: IPv4 address to `aa:bb:cc:dd:ee:ff`.
    static func arpTable() -> [IPv4: String] {
        guard let buffer = dumpRoutes(flags: RouteABI.flagLinkLayerInfo) else { return [:] }
        var table: [IPv4: String] = [:]

        forEachMessage(in: buffer) { message in
            guard let destinationBytes = message.addresses[RouteABI.addressIndexDestination],
                  let linkBytes = message.addresses[RouteABI.addressIndexGateway],
                  let address = ipv4(from: destinationBytes),
                  let mac = macAddress(fromLinkLayer: linkBytes)
            else { return }
            table[address] = mac
        }

        return table
    }

    // MARK: - sysctl plumbing

    private static func dumpRoutes(flags: Int32) -> [UInt8]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, flags]
        var needed = 0

        guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else { return nil }

        // The table can grow between the sizing call and the read; pad a little
        // and retry once rather than failing the whole scan.
        for _ in 0..<2 {
            var capacity = needed + 1024
            var buffer = [UInt8](repeating: 0, count: capacity)
            let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
                sysctl(&mib, u_int(mib.count), raw.baseAddress, &capacity, nil, 0)
            }
            if status == 0 {
                return Array(buffer.prefix(capacity))
            }
            if errno != ENOMEM { return nil }
            needed = capacity
        }
        return nil
    }

    /// Walks the packed stream of routing messages, handing each decoded one to
    /// `body`.
    private static func forEachMessage(in buffer: [UInt8], _ body: (RouteMessage) -> Void) {
        buffer.withUnsafeBytes { raw in
            var offset = 0

            while offset + RouteABI.headerSize <= raw.count {
                let messageLength = Int(raw.loadUnaligned(
                    fromByteOffset: offset + RouteABI.offsetMessageLength,
                    as: UInt16.self
                ))
                guard messageLength >= RouteABI.headerSize, offset + messageLength <= raw.count else { return }

                let flags = raw.loadUnaligned(
                    fromByteOffset: offset + RouteABI.offsetFlags,
                    as: Int32.self
                )
                let addressMask = raw.loadUnaligned(
                    fromByteOffset: offset + RouteABI.offsetAddressMask,
                    as: Int32.self
                )

                var addresses: [Int32: [UInt8]] = [:]
                var cursor = offset + RouteABI.headerSize
                let messageEnd = offset + messageLength

                for index in Int32(0)..<RouteABI.addressIndexCount {
                    guard addressMask & (1 << index) != 0 else { continue }
                    guard cursor + 2 <= messageEnd else { break }

                    // Darwin sockaddrs are length-prefixed: first byte is sa_len.
                    let length = Int(raw[cursor])
                    let stride = length == 0 ? MemoryLayout<UInt32>.size : (length + 3) & ~3
                    let usable = min(length == 0 ? stride : length, messageEnd - cursor)
                    guard usable > 0 else { break }

                    addresses[index] = Array(
                        UnsafeRawBufferPointer(rebasing: raw[cursor..<(cursor + usable)])
                    )

                    cursor += stride
                    if cursor > messageEnd { break }
                }

                body(RouteMessage(flags: flags, addresses: addresses))
                offset += messageLength
            }
        }
    }

    // MARK: - sockaddr decoding

    /// Decodes a `sockaddr_in` blob. Also tolerates `sockaddr_inarp`, which
    /// shares the same first eight bytes.
    private static func ipv4(from bytes: [UInt8]) -> IPv4? {
        guard bytes.count >= 8, bytes[1] == UInt8(AF_INET) else { return nil }
        let value = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        return IPv4(raw: value)
    }

    /// Decodes the hardware address out of a `sockaddr_dl` blob.
    ///
    /// Layout: len, family, index(2), type, nlen, alen, slen, data…
    private static func macAddress(fromLinkLayer bytes: [UInt8]) -> String? {
        guard bytes.count >= 8, bytes[1] == UInt8(AF_LINK) else { return nil }
        let nameLength = Int(bytes[5])
        let addressLength = Int(bytes[6])
        guard addressLength == 6 else { return nil }

        let start = 8 + nameLength
        guard start + addressLength <= bytes.count else { return nil }

        let octets = bytes[start..<(start + addressLength)]
        guard octets.contains(where: { $0 != 0 }) else { return nil }

        return octets.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
