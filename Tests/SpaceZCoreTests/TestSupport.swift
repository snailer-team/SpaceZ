import CoreGraphics
import Foundation
@testable import SpaceZCore

/// Framework-free stand-in for a UI object tree — lets core tests (capture,
/// diff, IDs) run without UIKit.
@MainActor
final class TestElement {
    var name: String
    var frame: CGRect
    var alpha: Double
    var hidden: Bool
    var interactive: Bool
    var children: [TestElement]

    init(
        _ name: String,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        alpha: Double = 1,
        hidden: Bool = false,
        interactive: Bool = false,
        children: [TestElement] = []
    ) {
        self.name = name
        self.frame = frame
        self.alpha = alpha
        self.hidden = hidden
        self.interactive = interactive
        self.children = children
    }
}

@MainActor
final class TestDescriptor: NodeDescriptor {
    func supports(_ object: AnyObject) -> Bool { object is TestElement }

    func capture(_ object: AnyObject) -> CapturedNodeContent {
        guard let element = object as? TestElement else {
            return CapturedNodeContent(type: "?")
        }
        return CapturedNodeContent(
            type: element.name,
            frame: element.frame,
            alpha: element.alpha,
            isHidden: element.hidden,
            isUserInteractionEnabled: element.interactive,
            properties: ["name": .string(element.name)]
        )
    }

    func children(of object: AnyObject) -> [AnyObject] {
        (object as? TestElement)?.children ?? []
    }
}

@MainActor
final class TestRootProvider: RootProvider {
    var roots: [TestElement]

    init(roots: [TestElement]) {
        self.roots = roots
    }

    func rootObjects() -> [AnyObject] { roots }
}

@MainActor
func makeEngine(roots: [TestElement]) -> CaptureEngine {
    let engine = CaptureEngine()
    engine.descriptors.register(TestDescriptor())
    engine.addRootProvider(TestRootProvider(roots: roots))
    return engine
}
