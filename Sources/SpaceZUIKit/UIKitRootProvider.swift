import SpaceZCore
import UIKit

/// Roots = every window of every connected scene, back to front.
/// Multi-window iPad apps produce multiple roots; the snapshot models that as
/// `rootIDs: [NodeID]` rather than inventing a fake super-root.
@MainActor
public final class UIKitRootProvider: RootProvider {
    public init() {}

    public func rootObjects() -> [AnyObject] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !($0 is SpaceZInternalWindow) }
            .sorted { $0.windowLevel < $1.windowLevel }
    }
}
