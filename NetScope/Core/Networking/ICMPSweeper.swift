import Foundation
import Darwin

/// Batch ICMP echo sweeper.
///
/// Design notes — this is the hot path of the whole app:
/// * **One socket for the entire sweep.** `SOCK_DGRAM`/`IPPROTO_ICMP` needs no
///   root and no entitlement on Darwin. Opening one fd per host would burn
///   file descriptors and thread time for no benefit.
/// * **Non-blocking, single reader thread.** Echo requests are fired in a tight
///   loop with light pacing, then replies are drained with `poll(2)`. Sweeping
///   a /24 costs one thread and finishes in well under a second.
/// * **Replies are matched on source address**, not on the ICMP identifier: the
///   kernel rewrites the identifier for datagram sockets, so it is not ours to
///   rely on.
///
/// Everything here runs off the main actor; the type is a reference type only
/// so the socket has an owner with a deterministic lifetime.
final class ICMPSweeper: @unchecked Sendable {

    struct Reply: Sendable, Hashable {
        var address: IPv4
        var roundTripTime: TimeInterval
    }

    /// How many echo requests to push before pausing to drain the receive queue.
    private static let sendBurstSize = 48

    /// Pause between bursts. Prevents `ENOBUFS` on busy Wi-Fi radios.
    private static let burstPause: UInt32 = 1_500 // microseconds

    private let queue = DispatchQueue(label: "com.netscope.icmp-sweeper", qos: .userInitiated)

    // MARK: - Public API

    /// Pings every target and reports responders as they answer.
    ///
    /// - Returns: `false` when the ICMP socket could not be created at all, so
    ///   the caller can fall back to TCP probing.
    @discardableResult
    func sweep(
        targets: [IPv4],
        timeout: TimeInterval,
        attempts: Int,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: (@Sendable (Int) -> Void)? = nil,
        onReply: @escaping @Sendable (Reply) -> Void
    ) async -> Bool {
        guard !targets.isEmpty else { return true }

        return await withCheckedContinuation { continuation in
            queue.async {
                let succeeded = self.performSweep(
                    targets: targets,
                    timeout: max(timeout, 0.1),
                    attempts: max(attempts, 1),
                    isCancelled: isCancelled,
                    onProgress: onProgress,
                    onReply: onReply
                )
                continuation.resume(returning: succeeded)
            }
        }
    }

    // MARK: - Implementation

    private func performSweep(
        targets: [IPv4],
        timeout: TimeInterval,
        attempts: Int,
        isCancelled: @Sendable () -> Bool,
        onProgress: (@Sendable (Int) -> Void)?,
        onReply: @Sendable (Reply) -> Void
    ) -> Bool {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        configure(descriptor)

        let identifier = UInt16.random(in: 1...UInt16.max)
        var sendTimes: [UInt32: TimeInterval] = [:]
        var responded = Set<UInt32>()
        sendTimes.reserveCapacity(targets.count)
        responded.reserveCapacity(64)

        var sequence: UInt16 = 0
        var receiveBuffer = [UInt8](repeating: 0, count: 1500)

        for attempt in 0..<attempts {
            if isCancelled() { return true }

            var sentThisRound = 0
            for target in targets {
                if responded.contains(target.raw) { continue }
                if isCancelled() { return true }

                sequence &+= 1
                let packet = Self.makeEchoRequest(identifier: identifier, sequence: sequence)
                sendTimes[target.raw] = Self.monotonicNow()
                Self.send(packet, to: target, on: descriptor)
                sentThisRound += 1

                if sentThisRound % Self.sendBurstSize == 0 {
                    // Progress is reported on transmit: the send loop is the
                    // part with a knowable denominator, and it keeps the UI
                    // moving while replies trickle in.
                    if attempt == 0 { onProgress?(sentThisRound) }
                    usleep(Self.burstPause)
                    drain(
                        descriptor: descriptor,
                        buffer: &receiveBuffer,
                        until: Self.monotonicNow() + 0.004,
                        sendTimes: sendTimes,
                        responded: &responded,
                        onReply: onReply
                    )
                }
            }

            guard sentThisRound > 0 else { break }
            if attempt == 0 { onProgress?(sentThisRound) }

            // Final drain for this round: give slow hosts the full timeout.
            let isLastAttempt = attempt == attempts - 1
            let waitFor = isLastAttempt ? timeout : timeout * 0.75
            drain(
                descriptor: descriptor,
                buffer: &receiveBuffer,
                until: Self.monotonicNow() + waitFor,
                sendTimes: sendTimes,
                responded: &responded,
                onReply: onReply,
                isCancelled: isCancelled
            )

            if responded.count == targets.count { break }
        }

        return true
    }

    /// Reads and dispatches echo replies until `deadline`.
    private func drain(
        descriptor: Int32,
        buffer: inout [UInt8],
        until deadline: TimeInterval,
        sendTimes: [UInt32: TimeInterval],
        responded: inout Set<UInt32>,
        onReply: @Sendable (Reply) -> Void,
        isCancelled: @Sendable () -> Bool = { false }
    ) {
        while true {
            if isCancelled() { return }

            let remaining = deadline - Self.monotonicNow()
            guard remaining > 0 else { return }

            var descriptorSet = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptorSet, 1, Int32(min(remaining * 1000, 1000)))
            guard ready > 0, descriptorSet.revents & Int16(POLLIN) != 0 else {
                if ready < 0 && errno != EINTR { return }
                continue
            }

            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let byteCount = withUnsafeMutablePointer(to: &source) { pointer -> Int in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    buffer.withUnsafeMutableBytes { raw in
                        recvfrom(descriptor, raw.baseAddress, raw.count, 0, sockaddrPointer, &sourceLength)
                    }
                }
            }

            guard byteCount > 0 else {
                if byteCount < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { continue }
                return
            }

            let address = IPv4(networkOrder: source.sin_addr.s_addr)
            guard !responded.contains(address.raw),
                  let sentAt = sendTimes[address.raw],
                  Self.isEchoReply(buffer, length: byteCount)
            else { continue }

            responded.insert(address.raw)
            let rtt = max(Self.monotonicNow() - sentAt, 0)
            onReply(Reply(address: address, roundTripTime: rtt))
        }
    }

    private func configure(_ descriptor: Int32) {
        var flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 {
            flags |= O_NONBLOCK
            _ = fcntl(descriptor, F_SETFL, flags)
        }

        // A generous receive buffer keeps replies from being dropped while we
        // are still busy transmitting the rest of the sweep.
        var receiveBufferSize: Int32 = 256 * 1024
        setsockopt(
            descriptor, SOL_SOCKET, SO_RCVBUF,
            &receiveBufferSize, socklen_t(MemoryLayout<Int32>.size)
        )

        var noSignalPipe: Int32 = 1
        setsockopt(
            descriptor, SOL_SOCKET, SO_NOSIGPIPE,
            &noSignalPipe, socklen_t(MemoryLayout<Int32>.size)
        )
    }

    // MARK: - Packet helpers

    private static func send(_ packet: [UInt8], to address: IPv4, on descriptor: Int32) {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = 0
        destination.sin_addr = address.inAddr

        _ = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                packet.withUnsafeBytes { raw in
                    sendto(
                        descriptor,
                        raw.baseAddress,
                        raw.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    /// Builds an 8-byte ICMP header followed by a small identifiable payload.
    private static func makeEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + 16)
        packet[0] = 8 // ICMP echo request
        packet[1] = 0 // code
        packet[2] = 0 // checksum placeholder
        packet[3] = 0
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        for index in 8..<packet.count {
            packet[index] = UInt8(0x40 + (index % 16))
        }

        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Standard one's-complement Internet checksum (RFC 1071).
    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum &+= UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return UInt16(truncatingIfNeeded: ~sum)
    }

    /// Darwin hands datagram ICMP sockets the full IP packet, so the header has
    /// to be stepped over before the ICMP type can be read.
    private static func isEchoReply(_ buffer: [UInt8], length: Int) -> Bool {
        var offset = 0
        if length >= 20, (buffer[0] >> 4) == 4 {
            offset = Int(buffer[0] & 0x0F) * 4
        }
        guard length >= offset + 8 else { return false }
        return buffer[offset] == 0 // echo reply
    }

    private static func monotonicNow() -> TimeInterval {
        // `uptimeNanoseconds` is monotonic and unaffected by clock changes.
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// Minimal lock-protected box, used to hand a value back out of a `@Sendable`
/// callback without reaching for a full actor.
final class MutableBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storage) }
    }
}
