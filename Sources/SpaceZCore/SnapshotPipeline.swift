import Foundation

/// Fan-out hub between the capture engine and its consumers (overlay, rules,
/// remote server), with backpressure built in.
///
/// Policy: **latest state wins**. Consumers subscribe with
/// `AsyncStream(bufferingNewest: 1)` — if a consumer is slower than the UI
/// mutates, intermediate snapshots are dropped and it always resumes at the
/// current state. A debugger wants "what does the UI look like now", not a
/// replay of every frame (recording mode is a different consistency policy,
/// out of scope for v1).
public actor SnapshotPipeline {
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]
    private var latest: Snapshot?
    private var lastPublishedFingerprint: UInt64?

    /// Count of snapshots dropped because their fingerprint matched the
    /// previous publish. Exported for observability ("is the detector firing
    /// without real changes?").
    public private(set) var suppressedNoOpCount = 0

    public init() {}

    public var latestSnapshot: Snapshot? { latest }

    /// Publishes a snapshot to every subscriber, unless nothing changed.
    /// Returns whether the snapshot was actually forwarded.
    @discardableResult
    public func publish(_ snapshot: Snapshot) -> Bool {
        latest = snapshot
        let fingerprint = snapshot.fingerprint
        if fingerprint == lastPublishedFingerprint {
            suppressedNoOpCount += 1
            return false
        }
        lastPublishedFingerprint = fingerprint
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
        return true
    }

    /// Subscribe. The stream immediately yields the latest snapshot (if any),
    /// then only meaningful updates, keeping at most the newest one buffered.
    public func subscribe() -> AsyncStream<Snapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Snapshot.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeSubscriber(id)
            }
        }
        if let latest {
            continuation.yield(latest)
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        continuations[id] = nil
    }

    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
