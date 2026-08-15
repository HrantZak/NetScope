import Foundation
import Darwin

/// Reads the kernel routing table and ARP neighbour cache via `sysctl(3)`.
///
/// `CTL_NET / PF_ROUTE` is documented BSD API available to sandboxed apps.
/// Both lookups are best effort: iOS may return an empty ARP cache, in which
/// case MAC addresses (and therefore vendors) are simply unavailable and the
/// UI shows what it has.
enum RouteTable {

    /// `RTF_LLINFO` is not surfaced in the iOS SDK headers; the value is stable
    /// across Darwin releases.
    private static let rtfLLInfo: Int32 = 0x400

    // MARK: - Public

    /// Address of the default gateway (`0.0.0.0/0` route), if present.
    static func defaultGateway() -> IPv4? {
        guard let buffer = dumpRoutes(flags: Int32(RTF_GATEWAY)) else { return nil }
        var fallback: IPv4?

        forEachMessage(in: buffer) { header, addresses in
            guard header.rtm_flags & Int32(RTF_GATEWAY) != 0 else { return }
            guard let destination = addresses[RTAX_DST], let gatewayBytes = addresses[RTAX_GATEWAY] else { return }
            guard let gateway = ipv4(from: gatewayBytes) else { return }

            // The default route has a 0.0.0.0 destination.
            if let dst = ipv4(from: destination), dst.raw == 0 {
                fallback = gateway
            } else if fallback == nil, gateway.isPrivate {
                fallback = gateway
            }
        }

        return fallback
    }

    /// Snapshot of the ARP cache: IPv4 address to `aa:bb:cc:dd:ee:ff`.
    static func arpTable() -> [IPv4: String] {
        guard let buffer = dumpRoutes(flags: rtfLLInfo) else { return [:] }
        var table: [IPv4: String] = [:]

        forEachMessage(in: buffer) { _, addresses in
            guard let destinationBytes = addresses[RTAX_DST],
                  let linkBytes = addresses[RTAX_GATEWAY],
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

    /// Walks the packed `rt_msghdr` stream, handing each message plus its
    /// sockaddr table to `body`.
    private static func forEachMessage(
        in buffer: [UInt8],
        _ body: (rt_msghdr, [Int32: [UInt8]]) -> Void
    ) {
        let headerSize = MemoryLayout<rt_msghdr>.size

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + headerSize <= raw.count {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let messageLength = Int(header.rtm_msglen)
                guard messageLength >= headerSize, offset + messageLength <= raw.count else { return }

                var addresses: [Int32: [UInt8]] = [:]
                var cursor = offset + headerSize
                let messageEnd = offset + messageLength

                for index in Int32(0)..<Int32(RTAX_MAX) {
                    guard header.rtm_addrs & (1 << index) != 0 else { continue }
                    guard cursor + 2 <= messageEnd else { break }

                    // Darwin sockaddrs are length-prefixed: first byte is sa_len.
                    let length = Int(raw[cursor])
                    let span = length == 0 ? MemoryLayout<UInt32>.size : (length + 3) & ~3
                    let usable = min(length == 0 ? span : length, messageEnd - cursor)
                    guard usable > 0 else { break }

                    addresses[index] = Array(
                        UnsafeRawBufferPointer(rebasing: raw[cursor..<(cursor + usable)])
                    )
                    cursor += span
                    if cursor > messageEnd { break }
                }

                body(header, addresses)
                offset += messageLength
            }
        }
    }

    // MARK: - sockaddr decoding

    /// Decodes a `sockaddr_in` blob. Also tolerates `sockaddr_inarp`, which
    /// shares the same first eight bytes.
    private static func ipv4(from bytes: [UInt8]) -> IPv4? {
        guard bytes.count >= 8 else { return nil }
        guard bytes[1] == UInt8(AF_INET) else { return nil }
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
