import SpaceZCore
import SpaceZUIKit
import SwiftUI
import UIKit

/// Best-effort SwiftUI semantic tree, exposed *alongside* the UIKit render
/// tree.
///
/// SwiftUI's declaration tree (`VStack { Text; Button }`) and the UIView tree
/// under `UIHostingController` are different abstractions; pretending one is
/// the other produces nonsense. So the hosting view keeps its real UIView
/// children, and additionally gets synthetic `SwiftUI:*` children extracted by
/// reflecting the hosted root value with `Mirror`.
///
/// Reflection over SwiftUI internals is inherently version-fragile. The
/// contract here is graceful degradation, treated as a normal state, not an
/// error: when extraction fails on some OS release, the UIKit subtree is still
/// complete and a `swiftUISemantics: unavailable` property says why. No
/// private symbols are linked — `Mirror` only.
@MainActor
public final class SwiftUIHostingDescriptor: NodeDescriptor {
    /// Caps keep a pathological SwiftUI value graph from blowing up capture
    /// time; 400 semantic nodes ≫ anything a single screen legitimately shows.
    private let maxElements = 400
    private let maxDepth = 40

    private let uikit = UIKitViewDescriptor()

    /// Wrapper identity cache: hosting view → (semantic path → wrapper).
    /// Reusing the wrapper object for the same path keeps NodeIDs stable
    /// across captures, which keeps remote invalidation quiet while the
    /// SwiftUI structure is unchanged.
    private let wrapperCache = NSMapTable<UIView, NSMutableDictionary>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )

    public init() {}

    public func supports(_ object: AnyObject) -> Bool {
        if object is SwiftUISemanticElement { return true }
        guard let view = object as? UIView else { return false }
        return String(describing: type(of: view)).contains("HostingView")
    }

    public func capture(_ object: AnyObject) -> CapturedNodeContent {
        if let element = object as? SwiftUISemanticElement {
            var properties: [String: InspectorValue] = [
                "source": .string("SwiftUI semantic tree (best-effort reflection)"),
            ]
            if !element.modifierNames.isEmpty {
                properties["modifiers"] = .string(element.modifierNames.joined(separator: ", "))
            }
            return CapturedNodeContent(
                type: "SwiftUI:\(element.displayType)",
                label: element.detail,
                properties: properties
            )
        }

        var content = uikit.capture(object)
        guard let view = object as? UIView else { return content }
        // Cheap availability probe only — the actual extraction happens once,
        // in children(of:), not twice per capture pass.
        content.properties["swiftUISemantics"] = hostedRootValue(of: view) == nil
            ? .string("unavailable on this OS version")
            : .string("attached as SwiftUI:* children")
        return content
    }

    public func children(of object: AnyObject) -> [AnyObject] {
        if let element = object as? SwiftUISemanticElement {
            return element.children
        }
        guard let view = object as? UIView else { return [] }
        let semantic = semanticRoots(for: view) ?? []
        return uikit.children(of: view) + semantic
    }

    public func setProperty(
        _ key: String, to value: InspectorValue, on object: AnyObject
    ) -> Bool {
        // Semantic nodes are value reflections — there is nothing to mutate.
        guard object is UIView else { return false }
        return uikit.setProperty(key, to: value, on: object)
    }

    // MARK: - Reflection

    private func semanticRoots(for view: UIView) -> [SwiftUISemanticElement]? {
        guard let rootValue = hostedRootValue(of: view) else { return nil }
        let cache = cacheDictionary(for: view)
        var budget = maxElements
        let roots = buildElements(
            from: rootValue,
            path: "root",
            depth: 0,
            cache: cache,
            budget: &budget
        )
        return roots.isEmpty ? nil : roots
    }

    /// Finds the hosted SwiftUI root value by walking the hosting view's
    /// Mirror (including superclasses) for a `_rootView`-shaped field.
    private func hostedRootValue(of view: UIView) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: view)
        while let current = mirror {
            for child in current.children {
                if child.label == "_rootView" || child.label == "rootView" {
                    return child.value
                }
                // Newer OS versions hang the root view off an intermediate
                // content storage box.
                if child.label == "_base" || child.label == "content" {
                    let inner = Mirror(reflecting: child.value)
                    for innerChild in inner.children
                    where innerChild.label == "_rootView" || innerChild.label == "rootView" {
                        return innerChild.value
                    }
                }
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private func cacheDictionary(for view: UIView) -> NSMutableDictionary {
        if let existing = wrapperCache.object(forKey: view) { return existing }
        let created = NSMutableDictionary()
        wrapperCache.setObject(created, forKey: view)
        return created
    }

    /// SwiftUI plumbing types that carry structure but no meaning to the
    /// reader — flattened away so `VStack → Text` reads like the source, not
    /// like the runtime's wrapper soup.
    private static let transparentTypes: Set<String> = [
        "TupleView", "Tree", "Group", "_ConditionalContent", "AnyView",
        "ResolvedButtonStyle", "_VariadicView",
    ]

    /// Builds semantic elements for one value. Returns a *list* because
    /// transparent containers and tuples dissolve into their children.
    private func buildElements(
        from value: Any,
        path: String,
        depth: Int,
        cache: NSMutableDictionary,
        budget: inout Int
    ) -> [SwiftUISemanticElement] {
        guard budget > 0, depth < maxDepth else { return [] }

        var current = value
        var modifiers: [String] = []
        // Unwrap ModifiedContent chains: `Text("x").padding().opacity(...)`
        // is ModifiedContent<ModifiedContent<Text, _Padding>, _Opacity>. The
        // interesting node is the innermost content; modifiers become a note.
        var unwrapIterations = 0
        while Self.fullTypeName(of: current).hasPrefix("SwiftUI.ModifiedContent<"),
              unwrapIterations < 32 {
            unwrapIterations += 1
            let mirror = Mirror(reflecting: current)
            guard let content = mirror.children.first(where: { $0.label == "content" })
            else { break }
            if let modifier = mirror.children.first(where: { $0.label == "modifier" }) {
                let name = Self.simplifiedTypeName(of: modifier.value)
                // Internal bookkeeping modifiers add noise, not information.
                if !name.hasPrefix("Static"), !name.hasPrefix("_") || name.contains("Padding")
                    || name.contains("Background") || name.contains("Foreground") {
                    modifiers.append(name)
                }
            }
            current = content.value
        }

        let mirror = Mirror(reflecting: current)
        let isView = current is any View
        let displayType = Self.simplifiedTypeName(of: current)

        // Tuples, transparent wrappers, and non-view storage boxes dissolve.
        if mirror.displayStyle == .tuple
            || (isView && Self.transparentTypes.contains(displayType))
            || (!isView && Self.containsViews(mirror)) {
            var flattened: [SwiftUISemanticElement] = []
            var index = 0
            for child in mirror.children {
                let built = buildElements(
                    from: child.value,
                    path: "\(path)/\(displayType)[\(index)]",
                    depth: depth + 1,
                    cache: cache,
                    budget: &budget
                )
                if !built.isEmpty {
                    flattened.append(contentsOf: built)
                    index += 1
                }
            }
            return flattened
        }

        guard isView, !(current is EmptyView) else { return [] }

        budget -= 1
        let elementPath = "\(path)/\(displayType)"
        let element: SwiftUISemanticElement
        if let cached = cache[elementPath] as? SwiftUISemanticElement {
            element = cached
        } else {
            element = SwiftUISemanticElement()
            cache[elementPath] = element
        }
        element.displayType = displayType
        element.modifierNames = modifiers
        element.detail = Self.detailText(of: current)

        // An app-defined `View` declares its children in `body`, not in
        // stored properties — Mirror alone would only show its @State. SwiftUI's
        // own types are never body-expanded (their bodies recurse into style
        // resolution wrappers forever); their children live in storage, which
        // Mirror reaches.
        let childValues: [Any]
        if !Self.isSwiftUIType(current), let body = Self.expandBody(of: current) {
            childValues = [body]
        } else {
            childValues = mirror.children.map(\.value)
        }

        var children: [SwiftUISemanticElement] = []
        var index = 0
        for child in childValues {
            let built = buildElements(
                from: child,
                path: "\(elementPath)[\(index)]",
                depth: depth + 1,
                cache: cache,
                budget: &budget
            )
            if !built.isEmpty {
                children.append(contentsOf: built)
                index += 1
            }
        }
        element.children = children
        return [element]
    }

    /// Calls `body` on a view with a real body. Best-effort by construction:
    /// outside SwiftUI's render context, @Environment yields defaults and
    /// @State yields its current storage — good enough for structure.
    private static func expandBody(of value: Any) -> Any? {
        func open<V: View>(_ view: V) -> Any? {
            guard V.Body.self != Never.self else { return nil }
            return view.body
        }
        guard let view = value as? any View else { return nil }
        return open(view)
    }

    /// One-level probe: does this non-view container hold views (directly or
    /// inside a tuple)? Storage boxes that do are made transparent; everything
    /// else (Ints, Strings, closures, app model values) is data and must not
    /// be walked — both for signal and for privacy.
    private static func containsViews(_ mirror: Mirror) -> Bool {
        mirror.children.contains { child in
            if child.value is any View { return true }
            let inner = Mirror(reflecting: child.value)
            if inner.displayStyle == .tuple || inner.displayStyle == .struct {
                return inner.children.contains { $0.value is any View }
            }
            return false
        }
    }

    private static func isSwiftUIType(_ value: Any) -> Bool {
        String(reflecting: type(of: value)).hasPrefix("SwiftUI.")
    }

    private static func fullTypeName(of value: Any) -> String {
        String(reflecting: type(of: value))
    }

    private static func simplifiedTypeName(of value: Any) -> String {
        let full = String(describing: type(of: value))
        // `VStack<TupleView<(Text, Button<...>)>>` → `VStack`
        if let angleBracket = full.firstIndex(of: "<") {
            return String(full[..<angleBracket])
        }
        return full
    }

    /// Tiny, safe payload preview: only `Text` storage, truncated. Anything
    /// deeper risks reflecting app model data into the snapshot.
    private static func detailText(of value: Any) -> String? {
        guard simplifiedTypeName(of: value) == "Text" else { return nil }
        // Text storage nests the literal a few mirrors deep; look for a String.
        var queue: [Any] = [value]
        var hops = 0
        while !queue.isEmpty, hops < 24 {
            hops += 1
            let current = queue.removeFirst()
            if let string = current as? String {
                return "\"\(string.spacezTruncated(40))\""
            }
            queue.append(contentsOf: Mirror(reflecting: current).children.map(\.value))
        }
        return nil
    }
}

/// Identity anchor for one SwiftUI semantic node. Class (not struct) because
/// the ``NodeIDRegistry`` keys IDs off object identity; the cache in the
/// descriptor keeps the same instance alive for the same semantic path.
@MainActor
public final class SwiftUISemanticElement {
    var displayType: String = ""
    var detail: String?
    var modifierNames: [String] = []
    var children: [SwiftUISemanticElement] = []
}
