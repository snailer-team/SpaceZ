# Changelog

All notable changes to SpaceZ are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

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

[Unreleased]: https://github.com/snailer-team/SpaceZ/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/snailer-team/SpaceZ/releases/tag/v1.0.0
