<!--
Thanks for contributing to SpaceZ! Every section below is required unless
marked optional — reviewers use them to review quickly and to keep the
library's performance and privacy guarantees intact.
-->

## What & Why

<!-- What does this PR do, and what problem does it solve?
     Link the issue: Fixes #123 -->

## How

<!-- Key design decisions. If you considered another approach and rejected it,
     say why — that context is worth more than the diff. -->

## Performance impact (required if you touched the capture path)

<!--
SpaceZ's core guarantee is that capture stays within its main-thread budget
(p50 < 2 ms / p95 < 5 ms / hard 8 ms for 5,000 nodes, release build).

If this PR touches CaptureEngine, NodeIDRegistry, any NodeDescriptor, or
anything else on the main-thread capture path, paste before/after numbers from:

    xcodebuild -scheme SpaceZ-Package \
      -destination 'platform=iOS Simulator,name=<device>' test \
      2>&1 | grep "SpaceZ perf"

Before: [SpaceZ perf] …
After:  [SpaceZ perf] …

If untouched, write "Not applicable — no capture-path changes."
-->

## Breaking changes

<!-- Public API added/changed/removed? SemVer implications?
     "None" if not applicable. -->

## How was this tested?

<!-- Unit tests added/updated, DemoApp scenario verified on simulator/device,
     web inspector checked, etc. -->

## Checklist

- [ ] Tests added or updated for the change
- [ ] `swiftlint --strict` passes
- [ ] All tests pass locally (`bash Scripts/ci_test.sh`)
- [ ] Public API has doc comments
- [ ] No new third-party dependencies (SpaceZ ships dependency-free)
- [ ] DEBUG-only guarantees preserved (nothing starts the server or overlay in release builds)
- [ ] Redaction is not weakened (no new path sends raw text/user content off-device by default)
