# Contributing to SpaceZ

Thanks for your interest! SpaceZ is a runtime UI debugger, which means
contributions are held to two unusual standards: **the debugger must never
distort the app it observes**, and **UI data must never leak off-device by
accident**. This document explains how to work within those constraints.

## Development setup

- Xcode 16 or newer (CI runs the latest stable Xcode on `macos-latest`)
- iOS 16+ simulator
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

```bash
git clone https://github.com/snailer-team/SpaceZ.git
cd SpaceZ

# Run the full test suite (auto-picks a simulator):
bash Scripts/ci_test.sh

# Lint:
swiftlint --strict

# Try your change live:
open Examples/DemoApp/DemoApp.xcodeproj   # run, then open the printed inspector URL
```

## Architecture in five sentences

1. **`SpaceZCore`** captures the UI on the main thread into an immutable,
   normalized `Snapshot` (`NodeID → InspectorNode`, children as IDs) and hands
   it to a background pipeline (`latest state wins`).
2. **Descriptors** (`SpaceZUIKit`, `SpaceZSwiftUI`, or yours) teach the engine
   one framework each; the core never imports UIKit.
3. **`SpaceZRules`** evaluates diagnostics over snapshots, decoupled from
   capture.
4. **`SpaceZRemote`** redacts, diffs, and serves snapshots over an
   invalidation-based WebSocket protocol plus an embedded web client.
5. **`SpaceZOverlay`** is the on-device inspector UI; **`SpaceZ`** wires it all
   together behind `SpaceZDebugger.start()`.

A full walkthrough lives in [README.md](README.md#architecture).

## The three invariants

PRs that violate these will be asked to change, regardless of the feature:

1. **Main-thread budget.** One capture pass over 5,000 nodes targets
   p50 < 2 ms / p95 < 5 ms, hard ceiling 8 ms (release build, device-class
   hardware). Only value copying happens on the main thread — diffing,
   encoding, rule evaluation, and transport stay off it. If you touch the
   capture path, your PR must include before/after numbers from the
   `CapturePerformanceTests` output (the PR template shows how).
2. **Redaction by default.** Anything crossing the process boundary goes
   through `Redactor` first. New captured properties that may contain user
   content must be added to `RedactionPolicy.defaultSensitiveKeys` or redacted
   structurally. The on-device overlay may show raw values; the network may not.
3. **Zero dependencies, DEBUG only.** SpaceZ ships with no third-party
   dependencies, and nothing may start the server or overlay in a release
   build (`SpaceZDebugger.start()` is compiled to a no-op outside DEBUG).

## Adding support for a new UI framework

This is the extension point the architecture is built around — no core changes
needed:

```swift
final class MyFrameworkDescriptor: NodeDescriptor {
    func supports(_ object: AnyObject) -> Bool { object is MyComponent }
    func capture(_ object: AnyObject) -> CapturedNodeContent { ... }
    func children(of object: AnyObject) -> [AnyObject] { ... }
}

SpaceZDebugger.register(descriptor: MyFrameworkDescriptor())
```

Rules for descriptors:
- `capture` copies primitive values only — never retain the object or return
  anything that references it.
- Children must come back in z-order (back to front).
- Synthetic nodes (like the SwiftUI semantic tree) need stable object identity
  across captures, or every capture will churn NodeIDs and spam invalidations.
  See `SwiftUISemanticElement`'s path-keyed cache for the pattern.

## Adding a diagnostic rule

```swift
struct MyRule: UIRule {
    let id = "my-rule"
    func inspect(node: InspectorNode, context: InspectionContext) -> [Issue] { ... }
}
```

- Use `InspectionContext`'s precomputed `depths`/`parents` indexes; a rule must
  not walk the whole tree per node (keeps evaluation O(nodes × rules)).
- Report a problem **once**, at the node where it's actionable, not for every
  descendant (see `DeepHierarchyRule`).
- Include a `suggestion` when there's a concrete fix.
- Built-ins must have zero false positives on a plain UIKit template app;
  noisy rules get reverted.

## Protocol changes

The wire protocol (`InspectorMessage.swift` ↔ `inspector.html`) is versioned
by snapshot, not by message schema. When you add a message:
- Add it to both the Swift codec and the web client.
- Unknown message types must remain non-fatal on both sides.
- Add a round-trip test in `InspectorProtocolTests`.

## Style

- `swiftlint --strict` must pass; configuration is in `.swiftlint.yml`.
- Comments explain *why*, not *what*. Numbers in comments need a source or a
  calculation.
- Public API requires doc comments.

## Commits & PRs

- Branch from `main`; one logical change per PR.
- Fill in every section of the PR template — especially **Performance impact**
  when relevant. PRs with an empty template are returned unreviewed.
- CI must be green (lint, tests incl. the perf gate, DemoApp build).

## Releases (maintainers)

1. Update `CHANGELOG.md` with a `## [X.Y.Z]` section.
2. Tag: `git tag vX.Y.Z && git push --tags`.
3. The release workflow re-runs tests and publishes the GitHub Release.
   SemVer: breaking public API → major, features → minor, fixes → patch.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
