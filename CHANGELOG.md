# Changelog

All notable changes to SpaceZ are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.2.0] - 2026-09-01

### Added

- `SnapshotEnvironment`: `/snapshot.json` exports now carry the capture
  environment (app version/build, OS version, device model, locale, Dynamic
  Type category), turning a saved snapshot into a complete field report for
  device-specific bugs.

### Changed

- README performance table now reports measured optimized-build numbers
  (5,551 nodes: p50 3.44 ms / p95 3.80 ms on simulator) alongside debug-build
  numbers.

## [1.1.0] - 2026-09-01

### Added

- `SpaceZDebugger.presentInspector()` — open the on-device inspector panel
  programmatically (debug menu, shake gesture, UI-test launch argument).
- README screenshots (web inspector, in-app panel, remote highlight) captured
  from the live demo app.

### Fixed

- The remote server now waits for both listeners to reach `.ready` before
  advertising the inspector URL. Previously a bind failure (port already in
  use) surfaced asynchronously, so the console printed a URL that could never
  work; now the failure is logged with the cause and a remediation hint, and
  the app keeps running with the overlay intact.

## [1.0.0] - 2026-08-31

Initial release.

### Added

- **Capture engine** (`SpaceZCore`): main-thread value-copy capture into an
  immutable, normalized node store (`NodeID → InspectorNode`, children as
  `[NodeID]`), iterative traversal safe for 10,000-deep hierarchies,
  session-stable identity IDs via a weak-keyed registry.
- **Live updates**: run-loop-observer change detection with throttling and
  trailing-edge capture, fingerprint-based no-op suppression, latest-state-wins
  backpressure, subtree diffing to invalidation sets.
- **UIKit adapter** (`SpaceZUIKit`): full `UIView` tree with per-class extras
  (labels, buttons, text fields, scroll/stack views), window-coordinate frames,
  on-device highlight overlay.
- **SwiftUI semantic tree** (`SpaceZSwiftUI`): best-effort Mirror reflection of
  hosted SwiftUI values — `ProfileCard → VStack → Text/Button` style trees with
  modifier notes, graceful fallback to the UIKit subtree when reflection fails.
- **Rule engine** (`SpaceZRules`): 6 built-in diagnostics
  (invisible-interaction, missing-accessibility-label, deep-hierarchy,
  massive-siblings, clipped-child, hidden-subtree) plus a public `UIRule`
  extension point.
- **In-app overlay** (`SpaceZOverlay`): floating entry button, tree browser
  with search, property inspector, issues list, tap-to-select, all in a
  touch-passthrough window excluded from capture.
- **Remote inspector** (`SpaceZRemote`): zero-dependency HTTP + WebSocket
  server (Network.framework), token-gated, Bonjour-advertised; embedded
  single-file web client with live tree, canvas view, search, property editing
  (allowlisted keys only), and issues; invalidation-based partial-fetch
  protocol; strict redaction of user content by default.
- **DemoApp** example project with intentionally planted bugs for each
  built-in rule.
- CI (lint + tests + perf gate + example build), release workflow, contribution
  guide, PR/issue templates.

[Unreleased]: https://github.com/snailer-team/SpaceZ/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/snailer-team/SpaceZ/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/snailer-team/SpaceZ/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/snailer-team/SpaceZ/releases/tag/v1.0.0
