import Foundation

/// Decides *when* to capture without instrumenting the host framework.
///
/// Strategy (hybrid, per design decision D3):
/// - A `CFRunLoopObserver` on `.beforeWaiting` fires after every main-thread
///   work item — any UI mutation wakes the run loop, so nothing is missed.
/// - A throttle (default 250 ms) collapses bursts: 50 layout passes inside one
///   scroll animation become at most 4 captures, not 50.
/// - The publisher upstream drops snapshots whose fingerprint didn't change,
///   so an idle-but-awake run loop (timers, network) costs one capture per
///   throttle window at worst, and nothing is sent downstream.
///
/// Swizzling-based dirty tracking is deliberately not the default: a debug
/// tool that rewrites `addSubview` on every app that links it trades host-app
/// stability for precision we don't need at 250 ms granularity.
@MainActor
public final class ChangeDetector {
    public var onCaptureNeeded: (() -> Void)?

    private var observer: CFRunLoopObserver?
    private var throttle: TimeInterval
    private var lastFire = ContinuousClock.now
    private var trailingScheduled = false

    public init(throttle: TimeInterval = 0.25) {
        self.throttle = throttle
    }

    public func start() {
        guard observer == nil else { return }
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            // The observer fires on the main run loop, which is the main actor.
            MainActor.assumeIsolated {
                self?.runLoopDidTick()
            }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    public func stop() {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil
    }

    /// Manual dirty signal for hosts that want captures outside run loop
    /// activity (e.g. after an off-screen render).
    public func markDirty() {
        runLoopDidTick()
    }

    private func runLoopDidTick() {
        let now = ContinuousClock.now
        let sinceLast = lastFire.duration(to: now)
        if sinceLast >= .seconds(throttle) {
            lastFire = now
            onCaptureNeeded?()
        } else if !trailingScheduled {
            // Trailing edge: guarantee one capture after the burst settles,
            // otherwise the last mutation in a burst would go unseen until
            // the next unrelated run loop tick.
            trailingScheduled = true
            let delay = throttle - Double(sinceLast.components.seconds)
                - Double(sinceLast.components.attoseconds) / 1e18
            DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.01)) { [weak self] in
                guard let self else { return }
                self.trailingScheduled = false
                self.lastFire = ContinuousClock.now
                self.onCaptureNeeded?()
            }
        }
    }
}
