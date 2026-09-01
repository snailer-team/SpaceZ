# Security Policy

SpaceZ is a **debug-build-only** tool, but it opens a LAN port and serializes
UI state, so we treat security reports seriously.

## Supported versions

| Version | Supported |
|---|---|
| latest 1.x | ✅ |
| older | ❌ — upgrade to the latest release |

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, use
[GitHub private vulnerability reporting](https://github.com/snailer-team/SpaceZ/security/advisories/new)
on this repository. You should receive a response within 7 days.

Reports we consider in scope:

- Bypassing the session token on the HTTP or WebSocket endpoints
- Any path that sends unredacted user content off-device while
  `RedactionPolicy.strict` (the default) is active
- Escaping the `setProperty` allowlist (arbitrary mutation of a live app)
- Any way `SpaceZDebugger.start()` can activate capture, overlay, or the
  server in a non-DEBUG build

Out of scope:

- Attacks requiring the attacker to already have the session token URL
- Behavior of builds that explicitly opt out of protections
  (`RedactionPolicy.none`, custom allowlists)
- Denial of service against the debug server itself (it is a development tool
  on a trusted network; killing it does not affect the host app)

## Design-level guarantees

The invariants the codebase maintains — useful context when assessing a
report — are documented in [CONTRIBUTING.md](CONTRIBUTING.md#the-three-invariants)
and the [README security model](README.md#security-model).
