# Fire Project Context

Fire 10.8 starts from `v0.11.13-fire.10.7.3` on local branch
`codex/fire-10.8`. The abandoned Ignition integration remains preserved at
`v1.0.21` / `fire/main` for reference and must not be fixed forward wholesale.

Product source of truth is
`_bmad-output/planning-artifacts/prd.md`; architectural ownership is in
`_bmad-output/planning-artifacts/architecture.md`. Historical release details
remain data in `HANDOFF.md` and `docs/FIRE-1.0-IGNITION.md`, not current rollout
authority.

Guardians:

- Keep bundle id `com.jordanbaird.Ice` and product `Ice.app`.
- Keep live menu-item geometry live; never restore the fire.10.7 item cache.
- Keep MCP writes behind both explicit enablement and Fire-authored consent.
- Keep advanced features default-off and independently stoppable.
- Keep all candidates prerelease until signed E2E on the real Mac.
- Do not publish, promote Latest, or update the appcast without live scoped
  approval.

The 2026-07-31 FireLogic, SwiftLint, Bridge, and signed-build result was evidence
for the earlier rebuild, not for this branch. The 10.8 candidate
must earn fresh evidence after Fireline and unrelated menu-bar changes are
removed. Roadmap contracts are public issues #18 (10.8), #19 (10.9), #20
(10.10), and #21 (10.11).

Accepted into 10.8: the top-level optional-runtime gate, cancellation of quota,
trigger, and relay work when disabled, bounded XPC deadlines, the XPC-process AX
timeout, a full pull-request verification workflow, prerelease-only tag builds,
strict appcast idempotency, synchronized fallback item identities, and off-main
window enumeration in `temporarilyShow`. Fireline remains physically absent.

Fresh local candidate evidence (2026-08-14):

- FireLogic: 36 tests passed, 0 failures.
- Appcast verifier: 3 fixture tests passed (match, mismatch, duplicate).
- Bridge: clean SwiftPM build with the Xcode 26 toolchain.
- App: full unsigned Debug build succeeded for Ice, MCPBackend.xpc,
  MenuBarItemService.xpc, and the embedded IceMCPBridge.
- SwiftLint strict: 0 violations across 129 Swift files.
- Workflow YAML and appcast shell syntax parsed successfully.

This is repository and unsigned-build proof only. It is not signed desktop E2E,
not a GitHub prerelease, and not appcast promotion evidence.
