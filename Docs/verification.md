# SpaceZ v1.2.0 — Requirements Verification Report

Every functional and non-functional requirement from the original system
design, traced to measured evidence. Method: unit tests (55+), on-simulator
E2E against the **released package consumed as a real adopter** (remote SPM
dependency), abuse testing, and micro-benchmarks. Unverified paths are named
as such — a checkmark here means *measured*, not *believed*.

Environment: iPhone 15 Pro simulator, Xcode 26.4, demo app with planted bugs.
"Budget" refers to the design targets set in the README.

## Functional requirements

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| FR1 | Hierarchy capture (UIKit + SwiftUI + extensible) | ✅ | 58-node UIKit tree captured E2E; SwiftUI semantic tree renders source-like (`ProfileCard → VStack → Text/Button`, 10 nodes); custom descriptor registered through the public API in `CaptureEngineTests` |
| FR2 | Property inspection | ✅ | Web + overlay property panels verified on-screen; per-class extras (UILabel text/font, UIButton title, scroll offsets) asserted in export |
| FR3 | Device ↔ tool selection | ✅ / ⚠️ | Tool→device: browser click drew the on-device highlight (screenshot in README). Device→tool: `select` push covered by protocol test `testDeviceSelectionIsPushedToClients`; the physical tap gesture itself is code-reviewed but not machine-tested (no simulator tap automation) |
| FR4 | Search (`PayButton`, `alpha=0`, `accessibilityLabel=nil`) | ✅ | Unit tests + live E2E: `alpha=0.01 → [21]`, `PayButton → [15]` with strict redaction active (identifier survives redaction by design) |
| FR5 | Live update without full-tree streaming | ✅ | 1 Hz mutations → 1.1 pushes/s, **exactly 1 invalidated node per push, 86 B median** vs 85 KB full tree |
| FR6 | Snapshot with environment metadata | ✅ | `/snapshot.json` carries `SnapshotEnvironment` (app version+build, OS, device model, locale, Dynamic Type) + ISO-8601 timestamp — verified in live export and `testSnapshotExportCarriesEnvironmentMetadata` |
| FR7 | Automated diagnostics | ✅ | Planted bugs each caught exactly once: `invisible-interaction` (checkout overlay), `deep-hierarchy`, `massive-siblings`, `hidden-subtree` (stress screen); system-chrome false positives (UIVisualEffectView) excluded; custom rule registration tested |

## Non-functional requirements

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| NFR1 | Capture must not distort the app (p50 < 2 ms / p95 < 5 ms / hard 8 ms, 5,000 nodes) | ✅ p95·hard, ⚠️ p50 | 5,551 nodes, optimized `-O`: **p50 3.44 ms / p95 3.80 ms** — p95 and hard met; p50 misses its target by 1.7×. Debug `-Onone`: p50 ~10.5–14 ms (throttle keeps main-thread share ~4%). Over-budget captures log a runtime warning; CI gates p95 every run |
| NFR2 | Mutual failure isolation | ✅ | Port occupied (EADDRINUSE): app launches, logs cause + remediation, overlay works, **no dead URL printed** (bug found & fixed during this verification). Abuse suite: wrong token, pre-auth requests, malformed JSON, 1 MB garbage frame, 5 abrupt disconnects, raw TCP garbage — app alive, next session served 58 nodes cleanly |
| NFR3 | Bounded network usage | ✅ | Incremental protocol: ~93 B/s under 1 Hz mutations vs ~92 KB/s if full trees were re-sent — **989× reduction**; `getNodes` RTT p50 0.45 ms / p99 0.97 ms over 100 requests |
| NFR4 | Data protection | ✅ | Strict redaction on the wire (text → `[REDACTED]`, labels → `***`, nil-ness preserved); wrong-token and pre-auth connections closed with **zero bytes of tree data leaked** (including pre-auth `setProperty`); write API rejects non-allowlisted keys; release build: no server, no overlay, no logs (pixel-verified) |
| NFR5 | Framework extensibility | ✅ | Capture core imports no UI framework; UIKit and SwiftUI ship as `NodeDescriptor` adapters; test suite drives the engine through a third, framework-free adapter registered via the public API |

## Known gaps (tracked honestly)

1. **NFR1 p50**: 3.44 ms vs 2 ms target on optimized simulator builds.
   Re-examine if users report capture-time frame drops; planned fix is lazy
   property fetch (structure-only capture, properties on `getNodes`).
2. **FR3 physical tap path**: the long-press → tap-to-select gesture chain has
   no automated test (simulator tap injection unavailable in this toolchain);
   the protocol layer beneath it is tested.
3. All numbers are simulator numbers. Physical-device measurements will be
   added when device CI is available.
