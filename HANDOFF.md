# HANDOFF — Fire fork + ClaudeBar PR + CodexBar issue + AuditLM

This is for me (Claude) after session compression strips context.
Owner (pdurlej) will tell me to read this in a fresh session.

## 🚧 IN-FLIGHT - fire.7.1 tagged but blocked on GitHub outage (2026-05-26 ~12:30)

**`v0.11.13-fire.7.1`** tag pushed (build 1130). Adds `list_layouts` MCP tool - W4 of the fire.8 plan that ships independently because it's a read-only addition. AI can now ask "what layouts has the user saved?" and get the list without trial-and-error apply_layout calls.

**Blocked by GitHub-wide outage**: GitHub Status reports a critical/minor incident affecting Actions auth + codeload.github.com since ~10:57 UTC. CI runs for v0.11.13-fire.7.1 failed 4 times - each on a different infra component (setup-xcode download, action-gh-release download, checkout 403 auth). I hardened the workflow to be more outage-resilient (replaced `maxim-lobanov/setup-xcode@v1` with native `xcode-select`, replaced `softprops/action-gh-release@v3` with `gh release create` CLI), but checkout's git auth still fails because that's GitHub's core infra not actions.

**Next session ship action** (assuming GitHub is healthy):
```bash
gh run rerun <latest-failed-run-id> -R pdurlej/Ice
# or manually:
gh workflow run "Build macOS and Create DMG" -R pdurlej/Ice --ref v0.11.13-fire.7.1
```

Then: download the DMG, `sign_update`, append to appcast.xml at `pdurlej/fire-releases`.

**Why this matters**: fire.7.1 unblocks the cross-MCP demo concept. Once shipped, AI assistants connected to Fire can both list and inspect saved layouts. The Fantastical-style auto-switching (apply_layout from calendar context) still needs fire.8 W1-W3 (write ops via embedded MCPBackend.xpc), but list_layouts is the read-side foundation.

## 🌱 IN-FLIGHT - fire.8 W1 scaffold on feature branch (2026-05-26 ~12:50)

Branch: `feature/fire-8-mcpbackend` (pushed). Contains the source files for a new embedded MCPBackend.xpc service that will own write operations once W2 ports the lean CGEvent drag logic in.

**Files added under MCPBackend/**:
- `main.swift` - entry point, activates listener, RunLoop
- `Listener.swift` - XPCListener for `com.jordanbaird.Ice.MCPBackend` with handlers for all 7 MCP cases (listItems / moveItem / hideItem / showItem / applyLayout / saveLayout / listLayouts)
- `MCPBackendStateManager.swift` - state manager. listItems / saveLayout / listLayouts are REAL (ported from fire.7's MenuBarStateManager). moveItem / hideItem / showItem / applyLayout are W2 stubs.
- `Resources/Info.plist` - XPC service config (same shape as MenuBarItemService.xpc).

**Next steps to land fire.8 W1**:
1. **pbxproj surgery**: clone MenuBarItemService.xpc Xcode target structure with new UUIDs for MCPBackend.xpc. ~12 edits in Ice.xcodeproj/project.pbxproj:
   - New PBXNativeTarget for MCPBackend
   - 3 build phases (Sources, Frameworks, Resources)
   - PBXFileSystemSynchronizedRootGroup for MCPBackend/ + Shared/ exception set for Resources/Info.plist
   - PBXFileReference for built .xpc product
   - XCConfigurationList + Debug/Release configs with PRODUCT_BUNDLE_IDENTIFIER=com.jordanbaird.Ice.MCPBackend
   - Add MCPBackend to project's targets array + root PBXGroup children + Products group children
   - Add MCPBackend.xpc to Ice target's "Embed XPC Services" build phase
2. **Decide on SourcePIDCache**: MCPBackend's listItems uses `ownerPID` (not source PID) so on macOS 26 with Control Center reparenting, bundleIDs may all resolve to "com.apple.controlcenter". Two options for W1:
   - (a) Add MenuBarItemService/SourcePIDCache.swift to MCPBackend target's source compilation (same file compiled into both targets)
   - (b) Accept ownerPID-only for now, document the limitation, fix in W2 if needed
3. **Bridge re-target**: update `Bridge/Sources/IceMCPBridge/main.swift` service name from `MenuBarItemService.name` to `com.jordanbaird.Ice.MCPBackend`. Keep MenuBarItemService.xpc for legacy sourcePID handshake from Ice main app.
4. **Build + smoke test**: confirm MCPBackend.xpc spawns as subprocess of Ice.app, bridge can connect, listItems returns real data.

**Then W2** (~4-5h): port lean CGEvent drag logic from Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift into MCPBackend/Mover.swift (new file). The 600-800 lines of helpers needed: `permitLocalEvents`, `getTargetPoints`, `postMoveEvents`, retry loop. HIDEventManager interaction may need to be skipped or simplified - test empirically.

**Then W3+**: bridge re-target + smoke test + W5 starter presets + W6 settings UI + W7 ship.

Estimated remaining for fire.8: 7-8h (depending on whether SourcePIDCache sharing is needed).

## 🔥 SHIPPED fire.7 - multi-display read-only MCP (2026-05-26 ~12:10)

**Tagged `v0.11.13-fire.7`** (build 1129). CI built + signed + notarized; DMG at https://github.com/pdurlej/Ice/releases/tag/v0.11.13-fire.7. Sparkle appcast updated with EdDSA-signed entry (`pdurlej/fire-releases` commit `7dbebdd`) so fire.6 users will receive auto-update notification.

**What fire.7 adds:**
- `list_items` now iterates ALL active displays via `CGGetActiveDisplayList`, not just the primary
- Per-display section detection - secondary monitors with collapsed Ice sections fall back gracefully instead of polluting primary display's section boundaries
- Main display leads ordering even when CGS returns it second (some users have an external as their main with the MBP display IDed first)
- Better diagnostic logging when section detection degrades on any particular display
- Wire contract unchanged - fire.6 bridges still work transparently with fire.7 servers

## 🎯 fire.8 plan - write ops + Fantastical-style "layout sets" (~8-10h, multi-session)

**Vision from this morning's brainstorm:** Menu bar layouts behave like Fantastical's calendar sets. User (or AI) flips between named layouts ("Focus", "Meeting", "Default") and Fire auto-arranges the menu bar accordingly. The AI-native part is genuinely novel: a calendar MCP (e.g. Fantastical's) tells an AI agent what context the user is in, the agent calls Fire's `apply_layout` to match. Cross-MCP orchestration with no app-to-app code integration needed.

**Architecture decision locked**: Path 1 from the morning's analysis - new embedded `MCPBackend.xpc` bundle alongside the existing `MenuBarItemService.xpc`. Self-contained move logic in the new .xpc target. Reasons:
- Path 2 (move MenuBar* to Shared/) was rejected: AppState + HIDEventManager cascade is unbounded, 6-8h optimistic
- Path 3 (defer writes indefinitely) was rejected: sets without writes is read-only fantasy, not the actual product
- Option D (in-process Mach service in Ice main app) was rejected: macOS launchd refuses non-LaunchAgent processes registering arbitrary Mach services (verified empirically this morning, see DISCOVERY section below)

**Wave breakdown for fire.8:**

| Wave | What | Effort | Blocker for next? |
|---|---|---|---|
| **W1** | Create `MCPBackend.xpc` Xcode target. Copy MenuBarItemService.xpc structure with new bundle ID `com.jordanbaird.Ice.MCPBackend`. Empty `Listener.swift` that responds to `start` only. Verify it spawns as XPC subprocess of Ice.app and bridge can connect to it. | ~1h | Yes - everything below depends on this scaffold |
| **W2** | Move logic in the new .xpc target: extract just the CGEvent posting + position math from `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` into a leaner standalone file. Helpers needed: `permitLocalEvents()`, `getTargetPoints()`, `postMoveEvents()`, retry loop. Total ~600-800 lines of careful porting. HIDEventManager interaction may need to be skipped or simplified - test empirically. | ~4-5h | Yes |
| **W3** | Wire MCPBackendStateManager.swift (resurrected from commit `f455335`, Worker B's logic adapted) into the new target. Bridge re-target service name in `Bridge/Sources/IceMCPBridge/main.swift` from `MenuBarItemService.name` to `com.jordanbaird.Ice.MCPBackend`. Build + smoke test write ops end-to-end. | ~1h | No |
| **W4** | `list_layouts` MCP tool: add to wire contract, implement in MCPBackendStateManager (reads from `MCPLayouts` dict), expose in bridge. Small wire-contract addition; backwards compatible. | ~30min | No |
| **W5** | Three built-in starter presets shipped with Fire as default layouts: "Focus" (minimal - clock/battery/wifi only), "Meeting" (essentials hidden - hide stream deck etc.), "Default" (everything visible). Stored in same `MCPLayouts` dict, seeded on first launch via MigrationManager. | ~1h | No |
| **W6** | Settings UI: new "Layouts" subpane under Menu Bar Layout. Browse / rename / delete / apply / preview. Hotkey assignment per layout (use existing `HotkeyManager` infrastructure). | ~2-3h | No |
| **W7** | Ship fire.8 + Sparkle appcast + HANDOFF refresh. | ~30min | - |

**Total estimated**: 9.5-11.5h. Realistically spread across 2-3 sessions.

**W1+W2 are the long-pole.** They unblock everything else. If a session is short, the right starter is W4 (`list_layouts` MCP tool - reads the existing plist, ships independently as fire.7.1).

**Cross-MCP demo concept** (post-W3 milestone, blog/tweet content): live screencast of a Fantastical event → AI agent reads via Fantastical MCP → AI calls Fire's `apply_layout("Meeting")` → menu bar visibly cleans up. ~30 min to record once W3 lands. This is the actual headline content for Fire's positioning as AI-native.

## 🛑 IMPORTANT DISCOVERY — Option D is NOT viable as planned (2026-05-26 ~11:35)

**Attempted**: In-process XPCListener in Ice main app hosting `com.jordanbaird.Ice.MCPBackend` Mach service, with MachServices declared in Ice's Info.plist.

**Result**: launchd refuses registration:

```
launchd: failed activation: name = com.jordanbaird.Ice.MCPBackend,
         requestor = Ice[89968], error = 1: Operation not permitted
```

**Root cause**: macOS does NOT allow regular GUI apps to register arbitrary named Mach services with launchd. The MachServices Info.plist key is only honored for LaunchAgents / LaunchDaemons (loaded via launchctl from /Library/LaunchAgents or ~/Library/LaunchAgents plists, not from .app bundles). For GUI apps the only supported XPC patterns are:
1. Embedded .xpc bundles (separate subprocess, what MenuBarItemService.xpc already does)
2. Anonymous NSXPCListener with endpoint sharing through some side channel
3. Becoming a LaunchAgent (changes the install pattern entirely)

The Option D plan in the prior HANDOFF section (host MCP backend in Ice main app process via XPCListener) was **architecturally infeasible on macOS for a non-LaunchAgent app**. Code that explored it: commit `f455335` (added `Ice/Services/MCPBackend.swift` + `MCPBackendStateManager.swift` + MachServices entry); reverted in `aefac16` after the launchd error surfaced.

**The `MCPBackendStateManager.swift` implementation is still good** — it's Worker B's 380-line move/listItems/applyLayout logic adapted for instance-injection of the Ice manager (since Ice's `MenuBarItemManager` is owned by `AppState`, not a singleton). Resurrect from commit `f455335` if going with Path 1 below.

## ⏭️ NEXT SESSION — Pick a viable path to fire.7 write ops

Three realistic options, ranked:

**Path 1 - Embedded MCPBackend.xpc bundle (recommended, ~3-4h)**

Add a new `.xpc` service bundle alongside the existing `MenuBarItemService.xpc`. Same separate-subprocess pattern, but dedicated to MCP. Self-contained: reimplements the AX move logic inside the .xpc target using primitives that DO live in `Shared/` (`Bridging`, `WindowInfo`, `AXHelpers`, `CGEvent` posting via the wrapped APIs Ice already uses). The .xpc service runs fresh AX scans for each tool call rather than relying on Ice main app's `MenuBarItemManager.itemCache` state.

Pros:
- Architecturally supported by macOS - same pattern as MenuBarItemService.xpc that already works
- Build / pbxproj surgery limited to new .xpc target (mostly an Xcode UI operation)
- No cross-target type sharing needed for the simple move case
- TCC-inherited AX permission from parent Ice.app

Cons:
- Reimplement (lean version of) Ice's drag-event posting code in the .xpc service. Risk: subtle differences from `MenuBarItemManager.move()` that could miss edge cases. Mitigation: lift the actual event-posting helpers from MenuBarItemManager (or refactor them into Shared/) and reuse.
- Two move pipelines (Ice's Layout drag UI + this .xpc service) need to stay coordinated. Same risk MCPBackendStateManager already noted in its header comments.

**Path 2 - Move MenuBar* types into Shared/ (~6-8h, cascade risk)**

Move `MenuBarItem.swift` (374 lines, clean), `MenuBarItemTag.swift` (small), `MenuBarSection.swift` (296 lines, references AppState), and `MenuBarItemManager.swift` (1839 lines, references AppState 5x) into `Shared/`. Stub or extract the AppState references. Existing fire.6 read-only `MenuBarStateManager` in `MenuBarItemService.xpc` then becomes the full-fledged backend, and the bridge keeps targeting `com.jordanbaird.Ice.MenuBarItemService`.

Pros:
- Single move pipeline (reused for both Layout UI and MCP)
- No new XPC service or bundle to set up

Cons:
- AppState cascade is real and unbounded - moving 1839-line MenuBarItemManager into Shared/ may pull in 3-4 more files
- This was the path I rejected before fire.6 due to time risk; the risk hasn't gone down

**Path 3 - Defer write ops indefinitely (~0h)**

Ship fire.7 as a polish release focused on improvements to the read-only MCP layer (multi-display support, better section detection, additional info in `list_items` response, etc.). Write ops remain "Coming soon" in tool descriptions. Set a clear deadline for revisiting (e.g., when Apple introduces a new in-process Mach service mechanism on macOS 27).

Pros:
- No risk
- Keeps current shipping cadence

Cons:
- The headline "AI-native menu bar manager" needs write ops to be genuinely useful. fire.7 without writes is a smaller win than the positioning advertises.

## 🔥 SHIPPED fire.6 — MCP read-only (2026-05-26 ~08:40)

**Tagged `v0.11.13-fire.6`** (build 1128). CI workflow "Build macOS and Create DMG" running on the tag — will sign + notarize + draft GitHub Release with the DMG. Tracked at https://github.com/pdurlej/Ice/actions.

**What fire.6 adds over fire.5:**
- Real `list_items` MCP tool — Claude/Cursor/Continue can read your menu bar layout. Section detection works when Ice is running (uses Ice's 3 control items as x-coordinate boundaries). Graceful fallback to "all alwaysVisible" when Ice isn't running. Multi-display deferred to fire.7.
- Real `save_layout` MCP tool — snapshots current state to `MCPLayouts` dict in `com.jordanbaird.Ice` plist. fire.7's `apply_layout` will read from the same key.
- `move_item / hide_item / show_item / apply_layout` return a friendly "Coming in fire.7" message instead of "Not implemented" — clients understand the deferral.

**Wave G commit on fire/main**: `ad5542a feat(mcp): Wave G — listItems + saveLayout real impl (fire.6)`. Touched `MenuBarItemService/MenuBarStateManager.swift` (replaced stubs) + version bumps in `Ice.xcodeproj/project.pbxproj` (1127→1128, fire.5→fire.6). No cross-target refactor needed — the new code uses only `Bridging` + `WindowInfo` + `SourcePIDCache` (all in Shared/) and `NSRunningApplication`.

**Smoke test verification (local)**: bridge protocol over stdin → JSON-RPC initialize works → tools/list returns all 6 with annotations → `tools/call list_items` dispatches via XPC → returns 3 real items (Ice + ControlCenter + BentoBox on macOS 26) → `tools/call save_layout` persists to plist (`defaults read com.jordanbaird.Ice MCPLayouts` confirms). 2 MenuBarItemService processes seen during test: installed fire.4 + my Debug build — bridge correctly routed to its sibling Debug XPC service via bundle proximity.

**Still pending (next session, for fire.7):**
1. **Sparkle appcast update**: append fire.6 item to `pdurlej/fire-releases/appcast.xml` with EdDSA signature of the DMG (`sign_update build/Ice-v0.11.13-fire.6.dmg` using the SUPublicEDKey's private counterpart, which lives in pdurlej's local keychain — not in any repo). Until this lands, fire.5 users won't auto-update; they have to grab fire.6 manually from the GitHub Release page.
2. **Option D — Ice hosts MCP backend (write ops)**: see the "NEXT SESSION" brief that follows this section. ~2-3h work.

## ⏭️ NEXT SESSION — Option D: Ice.app hosts MCP backend (unblocks write ops)

**Goal**: fire.7 ships full write op support — `move_item`, `hide_item`, `show_item`, `apply_layout` actually move menu bar items via AX drag events.

**Approach (Option D from the G→D analysis)**: Add a new XPC service hosted by Ice.app itself (`com.jordanbaird.Ice.MCPBackend`), separate from the existing `com.jordanbaird.Ice.MenuBarItemService` (which stays for legacy sourcePID handshake + the read-only listItems/saveLayout fire.6 path). The bridge talks to the new service; the new service runs in Ice.app's process so `MenuBarItemManager.shared` is populated and `move(item:to:)` Just Works.

**Concrete steps:**
1. Add `Ice/Services/MCPBackend.swift` — XPCListener registered for `com.jordanbaird.Ice.MCPBackend`. Same handler shape as `MenuBarItemService/Listener.swift` but lives in the Ice main app target so it has access to MenuBarItem / MenuBarItemManager / MenuBarSection.
2. Promote `MenuBarItemService/MenuBarStateManager.swift.proposal.phase3` to `Ice/Services/MCPBackendStateManager.swift`. Worker B already wrote 380 lines of correct logic — it'll compile in Ice main app target since all referenced types are local. Drop the existing fire.6 read-only logic OR keep both implementations behind a feature flag during transition.
3. Update `Ice/Resources/Info.plist` with an `XPCService` dict entry for the new service name (similar to how MenuBarItemService is currently embedded).
4. Update `Bridge/Sources/IceMCPBridge/main.swift` to connect to `com.jordanbaird.Ice.MCPBackend` instead of `com.jordanbaird.Ice.MenuBarItemService`. (Or keep both connections, use MCPBackend for MCP-extension cases, keep MenuBarItemService for legacy.)
5. Smoke test from Claude Desktop: install fire.7 build, ask "hide control center" → it actually moves. Ask "undo" if undo ring buffer lands at the same time.
6. Ship fire.7.

**Estimated effort**: 2-3h. Worker B's pre-written logic does most of the heavy lifting; the new XPC service plumbing is standard.

**Optional — also in fire.7**:
- Undo ring buffer (Phase 5 of the original plan — 1h, useless without write ops, ship together)
- `.v1` XPC service version marker (Q5 — only if the new MCPBackend service makes deprecation of the old wire-contract cases practical)
- AppDelegate lifecycle plumbing if Settings UI "Enable MCP server" toggle needs to spawn anything (currently the toggle just stores a preference; bridge is spawned by MCP client per Q4)
- UNUserNotification on write ops gated by `mcpNotifyOnWrite` default

## 🗄️ SUPERSEDED — MCP Phase 4.5 wire-only milestone (2026-05-26 ~03:30)

PR #2 merged. 4 commits on fire/main beyond fire.5. **fire.6 NOT
tagged** — per the plan's "if smoke test fails, do not tag" guardrail.
End-to-end MCP protocol works (clients can connect + discover all 6
tools + call them) but every call returns "Not implemented in Phase 1"
because Worker B's real `MenuBarStateManager` implementation needs a
cross-target refactor that didn't fit in tonight's window.

**What the merge ships:**

| Commit | Wave | What |
|---|---|---|
| `aded612` | Phase 1 (prev session) | XPC wire contract — Request/Response enums, 6 MCP cases, ItemSection, ItemInfo |
| `13c1d6e` | Phase 2 (prev session) | IceMCPBridge Xcode target scaffold (later removed in Wave 1 below) |
| `9417801` | **Wave 1 (tonight)** | **Pivot to SwiftPM executable** — Xcode 26's SwiftPM bridge cannot resolve swift-nio transitive deps (`DequeModule`, `Atomics`) for tool-product targets. Tried the full Option A spectrum (explicit `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + `PBXBuildFile` + project `packageReferences`); NIOCore still fails every variation. Bridge moved to `Bridge/Package.swift`; vanilla `swift build` works (335-module graph, ~30s). Old Xcode IceMCPBridge target REMOVED entirely. Ice target gains a Run Script ("Build and Embed IceMCPBridge") that runs `cd Bridge && swift build -c $CONFIG` and copies the 13MB binary to `Ice.app/Contents/MacOS/IceMCPBridge` with ad-hoc sign. CI's `--deep` codesign pass will re-sign with Developer ID. Documented bug: https://forums.swift.org/t/xcode-26-unable-to-find-module-dependency/80516 |
| `5f907a7` | **Wave 2 (tonight)** | Real MCP server (`Bridge/Sources/IceMCPBridge/main.swift`, 498 lines) using modelcontextprotocol/swift-sdk with verified API surface — `Server` + `withMethodHandler(ListTools.self/CallTool.self)`, `StdioTransport`, `XPCSession` (NOT NSXPCConnection) mirroring Ice's existing `MenuBarItemServiceConnection` with `.isFromSameTeam()` ad-hoc-build guard, 6 tools registered with FULL annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`). PLUS Settings UI subpane "MCP Server (experimental)" with 3 consent toggles (`mcpServerEnabled` / `mcpAllowWrites` / `mcpNotifyOnWrite`, mirroring the existing Sentry shareDiagnostics pattern). PLUS `docs/mcp/CLIENT-SETUP.md` (per-client config for Claude Desktop / Claude Code / Cursor / Continue, all verified from each client's official MCP docs) + README MCP Server section. |

**Verification at merge:**
- `xcodebuild -scheme Ice build` succeeds
- `Ice.app/Contents/MacOS/IceMCPBridge` exists (13MB)
- Bridge process starts on stdio and registers 6 tools (verified by `Server` type loading)
- Worker C's 3 toggles render in Settings → Advanced (visual confirmation pending — relies on user running the local build)

**Why fire.6 NOT tagged:** Worker B's `MenuBarStateManager` real implementation cannot compile in MenuBarItemService XPC target — references `MenuBarSection`, `MenuBarItem`, `MenuBarItemManager`, `MenuBarItemTag` which all live in Ice main app target. Saved as `MenuBarItemService/MenuBarStateManager.swift.proposal.phase3` (380 lines, architecturally correct, just needs the types accessible). The end-to-end "Claude Desktop hides Control Center" smoke test would currently return `"Not implemented in Phase 1"` — that's not a fire.6-worthy ship.

**Phases NOT in this merge (deferred to next session):**
- Worker B's real MenuBarStateManager (the cross-target refactor below unblocks it)
- Wave 3 lifecycle plumbing (MCP clients spawn bridge directly per Q4 — no AppDelegate work needed for now)
- Wave 3 `UNUserNotification` on write ops (useless while mutations are stubs)
- Wave 3 `.v1` XPC service rename (risky without smoke-test coverage)
- Wave 4 undo ring buffer (useless without mutations)
- Wave 5 fire.6 release tag

## ⏭️ NEXT SESSION — Unblock Worker B + ship fire.6

**Primary task: cross-target refactor of MenuBar* types.** Currently `Ice/MenuBar/MenuBarItems/MenuBarItem.swift`, `MenuBarItemManager.swift`, and `MenuBarSection.swift` are members of the Ice main app target only. Worker B's `MenuBarStateManager.swift.proposal.phase3` needs these types from the XPC service target.

**Approach options (in order of preference):**
1. **Move the files to `Shared/MenuBar/`** — they become accessible to both Ice and MenuBarItemService targets via the existing `Shared/` fileSystemSynchronizedGroup. Risk: cascading deps (these files may depend on more Ice-internal types). Map the dep tree first.
2. **Add the files to MenuBarItemService target's fileSystemSynchronizedGroup via a custom exception set** that includes specific `Ice/MenuBar/...swift` paths. Less clean (duplicated compilation across both targets) but no refactor cascade.
3. **Reimplement MenuBarStateManager from AX primitives** — bypass MenuBarItemManager entirely, use only `AXHelpers` + `WindowInfo` + manual CGEvent dispatch. Largest reimplementation but cleanest target boundary.

**Recommended path:** Try option 1 first. Read `MenuBarSection.swift` first (smallest), trace its imports / type deps, then `MenuBarItem.swift`, then `MenuBarItemManager.swift`. Move whatever they need into `Shared/MenuBar/`. Expect 1-2h.

**Then:** rename `MenuBarStateManager.swift.proposal.phase3` → `MenuBarStateManager.swift` (overwriting the stub), fix the `Listener.swift` async-handler bridge (XPC handlers expect sync closures — wrap async calls in `Task.detached` + `DispatchSemaphore` or use `syncWait` pattern: spawn a detached Task, blocking-wait the semaphore), full project build, ship the smoke test (Claude Desktop list_items + hide_item + undo), tag fire.6.

**Estimated total to fire.6 ship:** 2-3h next session.

## 🚧 SUPERSEDED — original WIP PR #2 brief (kept for reference)

## 🚧 IN-FLIGHT — MCP MVP Phase 1+2 in WIP PR #2 (2026-05-26 ~02:00)

After fire.5 shipped, the session continued with the actual MCP MVP
implementation work, getting through Phases 1 and 2 of the five-phase
plan from `docs/mcp/ARCHITECTURE.md`.

**WIP PR #2** — https://github.com/pdurlej/Ice/pull/2 (draft, branch
`feature/mcp-mvp-phase1-xpc-contract` → `fire/main`).
The PR body is the canonical source for what's in / what's missing.

Two commits on the branch:

- **`aded612`** — Phase 1: XPC contract extension. Adds 6 new Request
  cases + 3 Response cases + `ItemSection` / `ItemInfo` shared types
  to `Shared/Services/MenuBarItemService.swift`. NEW
  `MenuBarItemService/MenuBarStateManager.swift` with Phase-1 stubs
  (every operation returns `"Not implemented in Phase 1 — wire-contract
  stub"`). `Listener.swift` extended to dispatch the 6 new cases to
  the state manager. Builds clean.

- **`13c1d6e`** — Phase 2: IceMCPBridge target scaffold. NEW Xcode
  target (Command Line Tool, `com.jordanbaird.IceMCPBridge` bundle ID,
  file-system-sync to `IceMCPBridge/` + `Shared/`). Minimal
  `IceMCPBridge/main.swift` that proves the Shared/ group is reachable
  via compile-time witnesses on `MenuBarItemService.name` and
  `MenuBarItemService.ItemSection.allCases`. Plus
  `IceMCPBridge/main.swift.proposal.phase3` — 384-line worker draft
  of the full MCP server (Swarmheart structural-planner lane, fell back
  to DeepSeek v4-pro). Reference only — uses `NSXPCConnection` instead
  of `XPCSession`, guesses MCP SDK API names. Phase 3 rewrites from it.

**Critical Phase 3 first task** — the IceMCPBridge target doesn't yet
build when `import MCP` is added. Reason: SPM-in-Xcode transitive
dependency resolution bug — `swift-nio` (pulled by MCP SDK) can't
resolve its own deps on `DequeModule` and `Atomics` for the target's
compile environment.

Three Phase-3 fix options documented in the `IceMCPBridge/main.swift`
header (in order of preference):

1. Explicit `XCRemoteSwiftPackageReference` entries for
   `swift-collections` + `swift-atomics`, then link `Collections` /
   `Atomics` / `NIOCore` products to IceMCPBridge target via
   `XCSwiftPackageProductDependency`. Standard SPM-in-Xcode workaround.
2. Switch IceMCPBridge to a `swift build` executable in a sibling
   `Package.swift`, embed via Copy Files build phase.
3. Use a Swift MCP implementation without NIO dependency.

**CI is unaffected.** `build-dmg.yml` uses `-scheme Ice` which does
not touch the new IceMCPBridge target. Fire users who pull fire.5 see
zero behavior change from the MCP work — it's all behind the scenes
on a feature branch.

**Phase 3-5 outstanding** — issue #1 has the full plan + the 9
architecture decisions are all resolved in `docs/mcp/ARCHITECTURE.md`
§10. Phase 3 next-session start: resolve the IceMCPBridge build, then
rewrite `main.swift` from the Phase-3 proposal reference, then
implement the 6 tool handlers (can dispatch to Swarmheart senior-coder
in parallel — one worker per tool, independent).

Effort remaining: ~10-12h focused for Phase 3-5.

---

## ✅ SHIPPED — fire.5 (Sentry opt-in) + MCP scaffold (2026-05-26 01:30)

**fire.5** is live with opt-in Sentry crash reporting. DMG SHA256
`ca3bc7a84270cf53df430ae365f1301ab8ceb4227b3a21e56225eae90fbc081c`,
5.88 MB (bigger than fire.4 4.28 MB due to Sentry SDK).

- Strict opt-in toggle in Advanced Settings → Privacy & Diagnostics
  (DEFAULT OFF). Sentry SDK never initializes unless user explicitly
  flips. Existing fire.4 → fire.5 upgraders see zero behavior change
  unless they opt in.
- DSN embedded in `AppDelegate.swift` (public-readable write-only by
  design — safe to embed).
- Sentry CLI authenticated locally (`p@durlej.me`, token ~4 weeks).
- Sentry project: `pdurlej/fire` (apple-macos, project ID 4511453022388304).
- Sentry MCP added to Claude Code config (`~/.claude.json`) — works
  after Claude Code restart picks up the new MCP server.
- Sparkle appcast updated — fire.4 users get auto-update prompt to fire.5.

**MCP Phase 4.5 scaffold prepared** (Issue #1 has progress comment):

- `modelcontextprotocol/swift-sdk` Swift Package dep added project-level.
- Transitive deps resolved: swift-log, swift-nio, swift-system,
  swift-atomics, swift-collections, EventSource.
- `MCPBridge/README.md` placeholder describing next-session file layout.
- All 9 architecture open questions ALREADY resolved in
  `docs/mcp/ARCHITECTURE.md` §10 — no more design work.
- Next session: create `IceMCPBridge` Xcode target + implement 6 tools +
  auth flow + onboarding UI. ~14h focused work.

## ✅ SHIPPED — fire.4 + landing page + community evangelism (2026-05-26)

First fully Developer-ID-signed + Apple-notarized + stapled Fire build
is live: `v0.11.13-fire.4`, SHA256
`231cbd038fb41242d7a298cdb7d46ac5f0f7c8a05ccef633668a13147a4b0e09`.

After fire.4 landed, the session continued through several follow-up
deliverables:

- **README rewrite** as "Fire from Ice" landing page (commit `f58942d`)
  with all-new branding, removed upstream-pointing links (sponsor, license,
  download badges), tabela of what-this-fork-fixes (XPC bug + TCC + Node),
  install/upgrade flow with one-time `tccutil reset`, Sparkle/EdDSA
  security explanation, bundle ID compat note, Credits & GPL-3.0.
- **Hero banner image** added (commit `4386279`) — `Resources/Banner.png`
  generated via DALL-E 3 from a Swarmheart-drafted prompt (ice cube with
  inner flame, blue-to-ember gradient, 1659x948, 1.6 MB).
- **Repo metadata** updated via `gh repo edit`: description, homepage URL
  (now points at our releases/latest, not upstream), issues enabled
  (was disabled).
- **Workflow Node deprecation cleanup** (commits `4a1e812` + `3f33c00`):
  `actions/checkout@v4 → @v6`, `actions/upload-artifact@v4 → @v7`,
  `softprops/action-gh-release@v1 → @v3`, `--preserve-metadata=
  entitlements,identifier,flags` added to codesign step. All future
  CI runs free of Node 20 deprecation warnings.
- **Sparkle appcast** published (commit `2dd30cc` on `fire-releases`).
  fire.4 item with EdDSA signature live at
  `https://pdurlej.github.io/fire-releases/appcast.xml`. Sparkle
  auto-update path verified.
- **Upstream Ice community evangelism — 10 comments total** spanning the
  XPC bug class + the project-abandoned megatreads (see section 3 below).
  Cumulative audience ~210 thumbs subscribers + everyone who finds these
  issues via Google.
- **MCP Phase 4.5 design doc + tracking issue** — `docs/mcp/
  ARCHITECTURE.md` (commit `86945db`, 569 lines, 9 sections), and
  [Issue #1](https://github.com/pdurlej/Ice/issues/1) as milestone
  tracker.

Owner installed fire.4 over fire.3 and confirmed Menu Bar Layout pane
displays all three sections correctly after one-time `tccutil reset`.

### Three CI fails before the win — capture so we never repeat them

The fire.4 build needed three iterations on the same tag (`gh run rerun`,
no fire.5/.6/.7 churn). Each fail had a different cause:

1. **Wrong cert in the `.p12`.** Owner first exported `Apple Development:
   piotr@durlej.me (57JQP6CCJZ)` — the *legacy* personal-team cert —
   instead of `Developer ID Application: Piotr Durlej (R47JTHX25P)`.
   Both certs lived in the local Keychain; the right one was in
   `System` keychain (not `login`), and its private key was in `login`
   — Keychain Access didn't show the cert with a ▶ expander until the
   user navigated to **Moje certyfikaty → Logowanie**. The fix was a
   fresh export specifically of the Developer ID Application identity
   to `/Users/pd/Documents/Certyfikaty1.p12`. Verified before pushing
   the secret with:
   ```
   openssl pkcs12 -legacy -in <path>.p12 -nokeys -info | grep -E "friendlyName|subject="
   ```
   `-legacy` is mandatory — OpenSSL 3.x dropped RC2-40 which Keychain
   Access uses for .p12 export.
2. **Notarytool 401 "account does not exist".** `APPLE_ID` secret was
   set to `p@durlej.me` but the owner's actual Apple ID (which holds
   the Developer Program enrollment) is `piotr@durlej.me`. Confirmed
   locally with:
   ```
   xcrun notarytool history --apple-id piotr@durlej.me --team-id R47JTHX25P --password <app-spec>
   ```
   Returns `No submission history.` (success) for `piotr@`; the same
   401 for `p@`. Fixed by `gh secret set APPLE_ID` with the right
   email.
3. **TCC ghost grants on the running app.** After installing fire.4,
   `AXHelpers.isProcessTrusted()` in MenuBarItemService kept returning
   false even though System Settings showed Ice as "granted". Because
   fire.3 was ad-hoc-signed (TCC anchored to CDHash) and fire.4 is
   Developer ID (different anchor), the stale TCC record matches the
   visible name but fails the cryptographic match silently. Standard
   fix:
   ```
   tccutil reset All com.jordanbaird.Ice
   tccutil reset All com.jordanbaird.Ice.MenuBarItemService
   osascript -e 'tell application "Ice" to quit' && open /Applications/Ice.app
   # then re-grant Accessibility (and Screen Recording if used) in Settings
   ```
   **All subsequent fire.5+ builds (same Team ID anchor) will NOT need
   this** — TCC will key by Team ID + bundle ID and inherit cleanly.

### Lesson for me

When debugging fire.4's TCC issue I went down a rabbit hole insisting
the XPC was never spawning (because `ps` showed no MenuBarItemService
process). That was a SYMPTOM — the XPC was spawning per-request, doing
its AX check, failing it instantly, returning `.sourcePID(nil)`, and
exiting. Owner just ran `tccutil reset` (my initial Plan A) and it
worked. **For "permission shows granted but app behaves like denied" on
macOS Tahoe → always try `tccutil reset <bundleid>` FIRST** before
spelunking through XPC, codesign, hardened runtime, etc. Cheap, fast,
non-destructive.

### Outstanding low-priority issues on the workflow

- `.github/workflows/build-dmg.yml` line 99 has a comment about
  `--preserve-metadata=entitlements` but the flag is **missing** from
  the actual `codesign` call. The build works because Ice has no
  custom entitlements in source anyway, but if upstream ever adds an
  entitlements file the codesign step will silently strip it. Fix:
  add `--preserve-metadata=entitlements,identifier,flags`.
- `actions/checkout@v4` triggers a Node.js 20 deprecation warning on
  every run (hard deadline 2026-09-16, current date is 2026-05-25 so
  ~4 months runway). Latest is `@v6.0.2` — straight bump should work.
- The "build mapping" in `/tmp/fire-publish-update.sh` was hardcoded up
  to fire.1 — currently lives in `/tmp` (ephemeral). When publishing
  fire.4 to appcast we bypassed the script (one-off manual XML edit).
  If we revive the script, generalise: derive build number from
  Info.plist instead of `case $TAG`.

## Who and where

- Owner: pdurlej (Piotr Krzysztof Durlej). GitHub `pdurlej`, Forgejo also `pdurlej`.
- Machine: MacBook Pro Apple Silicon, macOS 26.5 (25F71 Tahoe), Xcode 26.5 installed.
- Important: `xcode-select` points at `/Library/Developer/CommandLineTools` — every `tuist`/`xcodebuild` invocation needs
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` prefixed.
- Sparkle CLI lives at `/opt/homebrew/Caskroom/sparkle/2.9.2/bin/` (used by `/tmp/fire-publish-update.sh`).
- Ollama Pro subscription owned by `p@durlej.me`.

## Active threads and their state

### 1. Fire — maintained fork of jordanbaird/Ice

- Repo: `https://github.com/pdurlej/Ice`, default branch `fire/main`.
- Local: `/Users/pd/Developer/fire`. Remotes: origin = pdurlej/Ice, upstream = jordanbaird/Ice (push disabled).
- Currently shipping: tag `v0.11.13-fire.3`, installed in `/Applications/Ice.app`, working on the owner's machine
  with menu bar items loading after the XPC fix.
- Bundle ID unchanged from upstream: `com.jordanbaird.Ice`.
- Sparkle appcast: `https://pdurlej.github.io/fire-releases/appcast.xml` served from the
  separate `pdurlej/fire-releases` repo. Sparkle EdDSA public key in
  `Ice/Resources/Info.plist:SUPublicEDKey` = `JQ+doXtLQyWmGDao7dTzF4dNgnkSmAWmN66Ee/lw9Yc=`. Private key lives only in
  the owner's macOS Keychain.
- Phase plan in `FORK.md` and `ROADMAP.md` at repo root. Rebrand plan (Ice → Fire) in `docs/REBRAND_PLAN.md`.
  Icon brief in `docs/ICON_BRIEF.md`.

### 2. Fire — signed builds (SHIPPED at fire.4)

- `feature/signed-builds-prep` merged into `fire/main` at commit `8d3aee5`.
- All six GH Actions secrets set on `pdurlej/Ice`: `BUILD_CERTIFICATE_BASE64`,
  `P12_PASSWORD`, `APPLE_ID` (= `piotr@durlej.me` — NOT `p@durlej.me`),
  `APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` (= `R47JTHX25P`), `KEYCHAIN_PASSWORD` (uuid).
- Apple Developer Program approved (individual, Team `R47JTHX25P`, name `Piotr Krzysztof Durlej`).
- Developer ID Application cert lives in System keychain on the owner's
  Mac; private key in login keychain. Sound on local
  `security find-identity -v -p codesigning` showing both legacy
  "Apple Development" + Developer ID Application.
- fire.4 DMG (tag `v0.11.13-fire.4`, build 1126) is live:
  `https://github.com/pdurlej/Ice/releases/tag/v0.11.13-fire.4`. Notarized,
  stapled, Gatekeeper-accepted, installed on owner's Mac.
- Future tagged builds (`v0.11.13-fire.5`, etc.) will go through the same
  workflow with zero secret/manual intervention. Just bump
  `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` and `git push --tags`.
- Sparkle appcast: when a new tagged build lands on GitHub Releases,
  publish via `/tmp/fire-publish-update.sh <tag>` (or manual XML edit if
  the script's build-number mapping is stale — see "Outstanding
  low-priority issues" above for the planned fix).

### 3. Fire — community engagement (10 comments live, ~210 thumbs reach)

**Round 1 — manual hand-crafted (3 comments):**
- `#913` → [`4537464216`](https://github.com/jordanbaird/Ice/issues/913#issuecomment-4537464216),
  full technical writeup. Template at `/tmp/fire-913-comment.md`.
- `#744` → [`4537479624`](https://github.com/jordanbaird/Ice/issues/744#issuecomment-4537479624),
  shorter + explicit "happy to open PR" offer.
- `#891` → [`4537479697`](https://github.com/jordanbaird/Ice/issues/891#issuecomment-4537479697),
  shortest sibling pointer.

**Round 2 — Swarmheart-drafted via document-worker / minimax (7 comments):**

Group A — XPC duplicates (technical, follow Round 1 template):
- `#846` → [`4537661456`](https://github.com/jordanbaird/Ice/issues/846#issuecomment-4537661456) (27 thumbs)
- `#818` → [`4537661537`](https://github.com/jordanbaird/Ice/issues/818#issuecomment-4537661537) (7 thumbs)
- `#832` → [`4537661628`](https://github.com/jordanbaird/Ice/issues/832#issuecomment-4537661628) (5 thumbs)
- `#872` → [`4537661719`](https://github.com/jordanbaird/Ice/issues/872#issuecomment-4537661719) (8 thumbs, also flagged "broader instability may exist")

Group B — "project abandoned" megatreads (Fire-as-continuation, I-voice):
- `#823` → [`4537661813`](https://github.com/jordanbaird/Ice/issues/823#issuecomment-4537661813) (**69 thumbs — TOP REACH**), edited from we-voice
- `#939` → [`4537661900`](https://github.com/jordanbaird/Ice/issues/939#issuecomment-4537661900) (10 thumbs), edited from we-voice
- `#877` → [`4537661970`](https://github.com/jordanbaird/Ice/issues/877#issuecomment-4537661970) (8 thumbs), edited from we-voice

All comment bodies preserved at `/tmp/fire-comments-final/{ISSUE}.md`.
GH shows "edited" badge on Group B (3 PATCH operations to flip
we-voice → I-voice after a Write-must-Read-first race condition
posted the wrong version first; recovered via `gh api -X PATCH`).

**4 remaining drafts at `/tmp/fire-community-comments.md`** for `#760,
#344, #665` — different bug classes than the XPC trifecta. Check those
issues are still relevant + write fresh comments before sending.

**Upstream PR with the XPC fix.** All three Round 1 comments offered to
open one. No reply from @jordanbaird yet. If silence continues, push
the branch + open the PR proactively after a respectful wait (~1–2 weeks).
- **Open upstream PR with the XPC fix.** Commits `f3ee848` + `b32181f`
  on `fire/main` cleanly cherry-pick onto `upstream/macos-26`. The
  posted comment on #913 already explicitly offers this — wait for
  @jordanbaird's reply before pushing the branch.

### 4. CodexBar — invisible menu bar bug

- Bug: CodexBar 0.29.0 on macOS 26.5 registers 7 NSStatusItems (osascript confirms) but none are visible.
- Reproduced under `osascript`/log/exhaustive testing. Defended that it's NOT Ice/Fire's fault by showing
  ClaudeBar 0.4.63 (functionally identical LSUIElement + NSStatusItem pattern) works on the same machine.
- Posted reproduction comment on upstream issue: `https://github.com/steipete/CodexBar/issues/1109` (comment id
  4531994889). Maintainer ("@steipete") had said "can't reproduce" — our comment is the first concrete
  comparison data point.
- Owner has switched to **ClaudeBar** as daily-use menu bar monitor. CodexBar app menu bar disabled, but the
  CodexBar MCP server stays alive (Claude Code SessionStart hook keeps showing provider data).

### 5. ClaudeBar PR #197 — Ollama provider

- Upstream: `tddworks/ClaudeBar`, 1161⭐. Local fork: `/Users/pd/Developer/claudebar`, branch
  `feature/ollama-provider`.
- PR: `https://github.com/tddworks/ClaudeBar/pull/197` — adds Ollama Cloud / Pro support.
- 5 new files (~1050 lines), 8 integration touches (~171 lines). Dual probe mode (API key + browser session
  cookies via SweetCookieKit), modeled on the existing `KimiProvider` pattern.
- Domain + Infrastructure targets build clean. Full ClaudeBar app build hits PRE-EXISTING aws-sdk-swift Cognito
  generic-inference errors, unrelated to this PR — flagged in PR body.
- CodeRabbit review posted 5 findings. We addressed 2 (credential log redaction in
  `OllamaConfigCard.swift:367` and `OllamaUsageProbe.swift:109`, commit `30a6f31`). Defended 3 in PR comment
  4532219737 with pointers to existing repo conventions:
  - `@unchecked Sendable` matches `KimiProvider`/`CodexProvider`.
  - Split JSON-config + UserDefaults-credentials storage matches `saveGithubToken` precedent.
- Build cmd that works: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -workspace
  ClaudeBar.xcworkspace -scheme Domain -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`.
  Tuist generate also needs the same `DEVELOPER_DIR` override.

### 7. MCP-friendly Fire — Phase 4.5 flagship (designed, not built)

- **Vision:** Fire exposes a local Model Context Protocol server so AI
  agents (Claude Code, Codex, Cursor, Continue) can introspect and
  manage the menu bar programmatically. Positions Fire as the **first
  AI-native menu bar manager** — no competitor has this.
- **Architecture doc:** [`docs/mcp/ARCHITECTURE.md`](./docs/mcp/ARCHITECTURE.md)
  (569 lines, 9 sections — vision, ASCII component diagram, 6 MVP
  tools with JSON schemas, auth/consent flow, discovery configs,
  FORK.md roadmap integration, risks, effort estimate, 9 open
  questions). Drafted via Swarmheart `structural-planner` lane (kimi
  primary, fell back to glm-5.1).
- **Tracking issue:** [pdurlej/Ice#1](https://github.com/pdurlej/Ice/issues/1)
  — first issue on our repo, milestone tracker.
- **MVP scope:** 6 tools (`list_items`, `move_item`, `hide_item`,
  `show_item`, `apply_layout`, `save_layout`), separate `IceMCPBridge`
  Xcode target talking to existing `MenuBarItemService` XPC, Keychain-
  scoped per-client-binary consent with SHA-256 anti-impersonation.
  ~14 hours / 1.5–2 dev days.
- **Phase 4.5 positioning:** must come after rebrand (Phase 4) because
  the MCP socket path embeds bundle ID; must come before original
  features (Phase 5) so profile/trigger features can be exposed as MCP
  tools rather than requiring a separate API surface.
- **9 open questions** in the architecture doc need operator decisions
  before MVP implementation starts: MCP SDK choice (native Swift vs
  Node wrap), layout storage format, consent granularity, lifecycle,
  bundle ID version markers, concurrent client handling, undo tokens,
  sandbox compat, tool annotation strictness.

### 6. AuditLM — Forgejo AI code review (decided, not installed yet)

- `https://github.com/ellenhp/auditlm` — Rust, AGPLv3, 35⭐, default model GLM-4.5-Air, supports any
  OpenAI-compatible LLM endpoint.
- Owner's plan: install locally, point at Ollama (`http://127.0.0.1:11434/v1`) running a code-specialized
  model — `qwen2.5-coder:32b` if RAM allows, otherwise `qwen2.5-coder:14b`. Hybrid setup possible —
  use local Ollama for routine PRs, Anthropic Claude 4.7 for complex ones.
- Setup is ~15 min: `brew install rust`, clone, `cargo build --release`, create a bot user in owner's Forgejo,
  generate API token, export `FORGEJO_TOKEN`, run with `--base-url 'http://127.0.0.1:11434/v1'`.
- Possible contributions to `ellenhp/auditlm` (good side projects): auto-trigger flag (no @mention required),
  Anthropic Claude API adapter, GitHub Releases binaries (currently build-from-source only).

## Recurring patterns / things I should know

- **macOS Tahoe 26.5 + ad-hoc signed apps** is a minefield: TCC keys permissions to CDHash absent a
  stable Developer ID, so every new build resets Accessibility / Screen Recording / etc. Workaround for now:
  `tccutil reset Accessibility com.bundle.id` + relaunch + re-grant. Permanent fix: Apple Developer Program.
- **TCC ghost grants on the ad-hoc → Developer-ID upgrade boundary.** The
  ONE-time `tccutil reset` is also needed when upgrading from an
  ad-hoc-signed build to the first Developer-ID-signed build of the same
  bundle (fire.3 → fire.4 hit this). System Settings shows the app as
  granted but cryptographic match fails silently → app behaves as
  denied. Reset for BOTH the main bundle and any XPC service that uses
  TCC APIs:
  ```
  tccutil reset All com.jordanbaird.Ice
  tccutil reset All com.jordanbaird.Ice.MenuBarItemService
  ```
  Subsequent Developer-ID → Developer-ID upgrades (fire.5+) do NOT need
  this — TCC keys cleanly on Team ID + bundle ID.
- **Ice's MenuBarItemService XPC** uses `.isFromSameTeam()` on both listener and client side, which silently
  rejects ad-hoc-signed builds (no team ID to compare against). Both sides patched via
  `MenuBarItemService.ownTeamIdentifier() != nil` guard. Signed builds will still use strict same-team
  matching automatically.
- **Tuist 4.x**: `tuist install` → `tuist generate --no-open` → opens `*.xcworkspace`. Needs the
  `DEVELOPER_DIR` override on this machine.
- Owner's session ran from ~21:00 May 24 to ~08:30 May 25 (≈11.5h marathon) before this handoff. If they
  ping in a fresh session they may be tired or jumping back in mid-thought.
- **Swarmheart routing for drafting tasks** (lessons learned 2026-05-26):
  - `structural-planner` lane defaults to **kimi-k2.6:cloud** which is a
    *reasoning model*. With `--max-output-tokens` below ~12000, Kimi
    spends its budget on chain-of-thought and truncates the actual answer.
    Pass `--allow-reasoning-budget-cap` AND raise tokens to 12000+ if you
    really want Kimi.
  - For multi-section drafting tasks (many comments, many doc sections),
    the **`document-worker` lane (minimax-m2.7:cloud)** is dramatically
    more efficient — non-reasoning, hits the structure directly, ~3x less
    token usage. Used it successfully for the 7-comment batch with only
    2577 eval_count tokens.
  - The dispatcher's `--output-file` writes the **full JSON wrapper**,
    not the model's response. Extract with
    `jq -r '.spawn_result.response'` to get the clean output.
  - Sub-bug found in our editing flow: `Write` tool requires `Read`
    first. If you build files via Python subprocess and then try to
    `Write` over them, the Write will fail silently AFTER any
    downstream consumer already used the original file. Posted 3
    comments with the wrong voice once because of this; recovered via
    `gh api -X PATCH repos/.../issues/comments/{id} --field body=...`.

## Style preferences I've observed

- Owner writes in Polish, prefers replies in Polish (English code/comments/PRs are fine).
- Loves Game of Thrones references — "Balerion", "they will hear us roar", "Daenerys Mhysa" style flair welcome.
- Likes status tables (`|---|---|` markdown) for state snapshots.
- Likes dry technical reasoning interspersed with one-line emoji acknowledgements (`🐉🔥`, `🦁🐉🖤`).
- Comfortable with multi-agent parallelism — happy when you launch background work and report what's running.
- Wants to be in the loop on architectural decisions but is fine with you executing once direction is set.
- "Auto mode" was on most of this session — bias toward action over asking, but explicit clarifying
  questions when the decision needs them (branding, hard-stops, security).

## Quick wins I can offer in a fresh session

1. Status check: `gh pr view 197 --repo tddworks/ClaudeBar` and `gh issue view 1109 --repo steipete/CodexBar`.
2. Fix the workflow's `actions/checkout@v4` → `@v6.0.2` (Node 20 deprecation), and add
   `--preserve-metadata=entitlements,identifier,flags` to the codesign step. Two-line patch on `fire/main`.
3. Post the six community comments (`/tmp/fire-community-comments.md`) on upstream Ice issues
   `#823 #760 #744 #344 #891 #665` now that we have a signed DMG to point at.
4. Open an upstream PR to `jordanbaird/Ice` with the `MenuBarItemService.ownTeamIdentifier()`
   guard — fire.3 fix benefits every community ad-hoc build of Ice.
5. If owner wants to install AuditLM: ~15-min path with the commands in handoff section 6.
6. If owner wants to extend AuditLM with a Claude API adapter: ~1-day side project,
   write a `ClaudeProvider` mirroring its existing OpenAI provider in Rust.

## What NOT to do

- Do not modify `/Applications/Ice.app` directly via the script approach — that broke once mid-session and
  required reinstall. Owner now controls all `Ice.app` launches manually.
- Do not delete `~/Library/Preferences/com.surteesstudios.Bartender.plist` without asking — it has codexbar
  cross-references that we don't fully understand the impact of.
- Do not auto-merge any PR to `fire/main` without owner sign-off.
- Do not post community comments to upstream issues until the first signed Fire build is live.
- Do not `sudo killall WindowServer` (kicks owner to login screen, lose state).
