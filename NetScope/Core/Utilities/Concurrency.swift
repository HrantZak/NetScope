import Foundation

/// Runs `operation` over `items` with a hard cap on concurrency, delivering
/// results to `onResult` as soon as each one lands.
///
/// A plain `TaskGroup` would launch every element at once; on a network sweep
/// that means thousands of simultaneous sockets, which the OS throttles and the
/// Wi-Fi radio hates. This keeps exactly `limit` probes in flight and refills
/// the window as tasks complete, so throughput stays high and memory flat.
/// The `isolation` parameter makes the function inherit the caller's actor.
/// Without it, a `onResult` closure that touches main-actor state (as the
/// device detail screen's does) would be an actor-isolated, non-`Sendable`
/// value being handed to a `nonisolated` function — which Swift 6 rejects.
/// Inheriting isolation keeps the result handler on the caller's actor while
/// the probes themselves still run on the concurrent pool.
func concurrentForEach<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    limit: Int,
    isolation: isolated (any Actor)? = #isolation,
    operation: @escaping @Sendable (Item) async -> Output,
    onResult: (Output) async -> Void
) async {
    guard !items.isEmpty else { return }
    let window = max(1, min(limit, items.count))

    await withTaskGroup(of: Output.self) { group in
        var index = 0

        while index < window {
            let item = items[index]
            group.addTask { await operation(item) }
            index += 1
        }

        while let output = await group.next() {
            await onResult(output)

            if Task.isCancelled {
                group.cancelAll()
                continue
            }

            if index < items.count {
                let item = items[index]
                group.addTask { await operation(item) }
                index += 1
            }
        }
    }
}

/// A reference-typed holder that lets non-`Sendable`-friendly framework objects
/// be captured by `@Sendable` closures.
///
/// Used for `NWConnection` / `NWBrowser`, whose own callbacks already serialise
/// onto a dispatch queue we control.
final class UncheckedBox<Wrapped>: @unchecked Sendable {
    let wrapped: Wrapped

    init(_ wrapped: Wrapped) {
        self.wrapped = wrapped
    }
}

/// One-shot latch: guarantees a continuation is resumed exactly once even when
/// several callbacks race (state handler, timeout, cancellation).
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFired = false

    /// Returns `true` only for the first caller.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasFired { return false }
        hasFired = true
        return true
    }
}
