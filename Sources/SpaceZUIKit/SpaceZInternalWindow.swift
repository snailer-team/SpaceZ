import UIKit

/// Marker for windows the debugger itself creates (overlay, highlight).
/// The root provider skips them so the inspector never inspects itself —
/// otherwise every capture would differ (the overlay reacts to snapshots,
/// which would trigger captures, forever).
public protocol SpaceZInternalWindow: AnyObject {}
