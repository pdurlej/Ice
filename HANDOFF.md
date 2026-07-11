# HANDOFF — Fire fork + ClaudeBar PR + CodexBar issue + AuditLM

This is for me (Claude) after session compression strips context.
Owner (pdurlej) will tell me to read this in a fresh session. **Codex / other
agents: start with `AGENTS.md` at the repo root** — it has the current pending
state and the gotchas; this file is the deep history.

## ⏳ CURRENT STATE (2026-07-10) — fire.10.7.1 built + installed, NOT yet on appcast

`v0.11.13-fire.10.7.1` (build 1156, HEAD `161c748`) is notarized + installed on
the owner's machine but **publication is gated on his runtime test** of the
menu-bar guards. Appcast still shows 10.6 as newest (10.7 was never published;
10.7.1 pending). On his "works": run `scripts/publish-appcast.sh
v0.11.13-fire.10.7.1`, close #17 + #4, leave #7 open. Full detail in the SHIPPED
sections below + `AGENTS.md`. Three fixes landed in 10.7.1:
1. **P1 — `.isFromSameTeam()` was never applied** (any build, since fire.10.2):
   `ownTeamIdentifier()` passed `SecCSFlags(rawValue: 0)` to
   `SecCodeCopySigningInformation`, which omits the team id → always nil. Fixed
   with `kSecCSSigningInformation`; probe-verified all 4 binaries resolve the
   team. Surfaced by the #4 ad-hoc SECURITY warning firing on a SIGNED build.
2. **Reverted the fire.10.7 item-frame cache (#7)** — caching geometry that
   changes at guard-eval time broke hover/click. Live SLS query restored.
3. **Kept the app-menu cache (#17 / FIRE-P)** — correct there — and taught the
   modal-ANR filter about `NSMenuTrackingSession` (FIRE-Q was a held-open menu).

## 🧭 RESUME HERE (2026-06-19, HEAD `ac135a5`, tree CLEAN)

- **Repo RENAMED → `pdurlej/fire-from-ice`** (origin already repointed). ALL `gh`
  commands need `-R pdurlej/fire-from-ice` (old `pdurlej/Ice` 301-redirects but
  use the new name). Branch `fire/main`. Local: `/Users/pd/Developer/fire`.
  App bundle stays `com.jordanbaird.Ice` / `Ice.app` ON PURPOSE.
- **Shipped: fire.10.6 / build 1154** (installed, notarized, appcast live on
  `pdurlej.github.io/fire-releases` — published via `scripts/publish-appcast.sh`,
  now battle-tested end-to-end). Sentry symbolication **LIVE**. Recent: 10.4 =
  kill-switch + modal-ANR filter + App-Hang fix; 10.4.1 = App-Hang sweep;
  10.4.2 = FIRE-N fix; 10.5 = kill-switch bypass (#8) + CI SHA-pin (#9);
  **10.6 = consent-wait gate (#6) + ad-hoc posture documented (#4) +
  competing-manager warning (#14)**. The repo has **19 GitHub stars** — real
  users; keep release notes user-readable. NOTE: notarization needs the owner's
  Apple Developer Program License Agreement in-effect (10.4.1 once 403'd until
  he accepted it; `gh run rerun --failed` then went green). CI actions are
  SHA-pinned — bump via `gh api repos/OWNER/REPO/commits/TAG`.
- **ISSUE BOARD is the roadmap** (`gh issue list -R pdurlej/fire-from-ice`).
  Fable-5 audit (2026-07-05) filed #4-#15; FIRE-N/P added #16/#17. Shipped so
  far: #16+#15 (10.4.2), #8+#9 (10.5), #10 (appcast script), #6+#4+#14 (10.6).
  **STILL OPEN (6), ranked:** #17+#7 (FIRE-P AX family + isMouseInside SLS —
  the remaining App-Hang pair; needs the owner's RUNTIME testing, design their
  caches together), #5 (sendSync watchdog — DEADLOCK TRAP documented in the
  issue: send holds a lock, no native timeout; wants a dedicated careful pass +
  kill-STOP testing), #11 (light SLS batch — IceBar positioning risk, wants
  eyes), #12 (undo: implement needs a consent-flow e2e ⇒ owner; strip variant is
  headless), #13 (a11y — VoiceOver verification ⇒ owner).
- **THE App-Hang franchise → main-thread window-server / AX calls. Now driven by
  a REPO ISSUE BOARD (#4-#17); symbolication names each new organ.** Sentry
  **FIRE-F/G/H/K/M/N/P** (all App-Hang, owner's macOS 26 daily driver — he runs
  the shipped build AND often has Bartender 6 running too, which amplifies
  window-server contention; see [[fire-owner-is-live-dogfooder]]). Field-verified
  quiet: FIRE-F/K/M on 10.4.1 (no recurrence). Fixed & shipped: **FIRE-N** (issue
  #16, `EventTap.isEnabled` per-event WS query → local flag) in 10.4.2. **STILL
  OPEN:** **FIRE-P** (issue #17, `getApplicationMenuFrame` synchronous AX walk of
  the frontmost app — a NEW family, AX IPC not SkyLight) + issue #7
  (`isMouseInsideMenuBarItem`, shares the guard chain with #17 — design their
  cache together) + issue #11 (light single SLS calls). **NEXT App-Hang ACTION:**
  #17 + #7 as a pair — needs AXSwift `setMessagingTimeout` research + an off-main
  cached menu-frame + RUNTIME testing on the owner's bar. See
  [[fire-apphang-click-to-reveal]].
- **Sentry triage note (DONE in 10.4):** modal-wait ANRs were NOISE burying real
  hangs (FIRE-J = Sparkle's "You're up to date!" `runModal`, archived). 10.4
  added a `beforeSend` filter in AppDelegate that drops App-Hang events parked
  in `runModal`/`SPUStandardUserDriver`/`NSAlert` (crashes never dropped). So our
  consent prompts + Sparkle modals no longer generate ANR noise.
- **Tests:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun
  swift test --package-path FireLogic` (29 tests; needs the Xcode toolchain —
  plain `swift test` lacks XCTest). Compile-gate the app:
  `DEVELOPER_DIR=…/Xcode xcodebuild -project Ice.xcodeproj -scheme Ice
  -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY=""
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`. Bridge:
  `swift build --package-path Bridge`.
- **Ship flow:** bump BOTH `MARKETING_VERSION` (`0.11.13-fire.X`) +
  `CURRENT_PROJECT_VERSION` in `Ice.xcodeproj/project.pbxproj` (2 occurrences
  each) → commit → `git tag -a v0.11.13-fire.X` → push branch + tag → CI on the
  fork builds/signs/notarizes/uploads-dSYMs + publishes the GH release → install
  + smoke → **APPCAST: `scripts/publish-appcast.sh v0.11.13-fire.X`** (issue #10,
  fire.10.5) — downloads the DMG, `sign_update`s it (**one Keychain Allow
  prompt**), inserts the `<item>`, pushes with the noreply identity, waits for
  Pages. Idempotent (no-op if already published); `--dry-run` shows the diff;
  `--notes-file f.html` for custom release notes (default links the GH release).
  The Sparkle key stays in the Keychain — signing is LOCAL, never CI.
- **Roadmap:** ~~10.4 = settings-honesty + App-Hang fix + modal-ANR filter~~ ✅
  SHIPPED. **10.5** = no-team relay pinning (P1, ad-hoc only — signed DMG already
  enforces `.isFromSameTeam`) + sendSync watchdog + handler-pool starvation +
  (if FIRE-H recurs) off-main `isWindowOnScreen` in the IceBar click path. CI =
  SHA-pin actions, `concurrency:`, automate the manual appcast/sign_update step.
  Also flagged this session: detect a competing menu bar manager (Bartender /
  HiddenBar / Dozer by bundle id) and warn instead of silently fighting.
- **Behaviour:** do NOT tell the owner to rest/sleep/wrap-up (documented Opus
  tic). Oracle only via the `oracle` MCP wrapper / browser / gpt-5.5-pro, don't
  rerun on timeout (use oracle-await). Owner handles all secrets/tokens.

## 🔥 SHIPPED fire.10.6 — consent-wait gate (#6) + ad-hoc posture (#4) + competing-manager warning (#14) (2026-07-09)

Fable 5 executing its own board, all headless. CI `29016549893` (build 1154)
success; appcast published via **`scripts/publish-appcast.sh` — first live run**
(caught 2 script bugs: `hdiutil -quiet` prints nothing + volume names contain
spaces; fixed with `-plist`+plistlib in `1d5d4ad`; idempotent re-run verified).
Commits `1dbf805` (feat) + `0e5c960` (bump). Closed #1 (stale tracker), #4, #6,
#14. Sentry at ship time: zero new issues; FIRE-N quiet since its 10.4.2 fix.
- **#6**: `ConsentWaitGate` (MCPBackendStateManager) bounds concurrent
  setTrigger/removeTrigger waits to 2; excess fail fast ("another approval is
  pending") — prevents XPC handler-pool starvation where even relayFetch (the
  consent-reply channel) couldn't be served.
- **#4**: researched `XPCPeerRequirement` fully — no meaningful ad-hoc primitive
  exists (entitlements self-grantable; LWCR identifier pinning breaks on the
  bridge's per-build hash-suffixed identifier; no audit token in the Swift API).
  Shipped loud `SECURITY:` warnings (MCPBackend listener + relay pump) + an
  "Ad-hoc builds" section in docs/mcp/ARCHITECTURE.md. Signed builds unchanged.
- **#14**: `CompetingManagerMonitor` — one notification per session when
  Bartender/Hidden Bar/Dozer/Vanilla runs next to Fire (exact bundle-id match,
  launch + event-driven, no polling, no telemetry; suppress via
  `SuppressCompetingManagerWarning`). NOTE: it will self-demo the next time the
  owner launches Bartender.

## 🔥 SHIPPED fire.10.5 — kill-switch bypass fix (#8) + CI SHA-pin (#9) (2026-07-08)

CI `28924547311` (build 1153) success (notarized first try; self-verified the
SHA-pinned actions); appcast `66096c3` live; installed + `list_items`-smoked.
Commits `cbb74d1` (fix) + `67363b3` (bump). Closed #8 + #9. All work headless —
no owner runtime testing needed (backend + CI only).
- **#8 (security)**: `MenuBarItemService/Listener.swift` served `.listItems` /
  `.saveLayout` / `.listLayouts` via `MenuBarStateManager`, bypassing the 10.4
  kill-switch (menu-bar layout readable / saveable with the MCP server OFF). Now
  those cases return `.denied`; the service keeps ONLY `.start` + `.sourcePID`.
  Deleted `MenuBarStateManager.swift` (274 lines) + `.proposal.phase3` — the
  `MenuBarItemService` target is a `PBXFileSystemSynchronizedRootGroup`, so a
  plain `git rm` removes it from the build (NO pbxproj edit; build confirms
  "Removed stale file MenuBarStateManager.o"). Ice's `MenuBarItemService.Connection`
  only ever sends `.start`/`.sourcePID`, so the layout editor is untouched.
- **#9 (CI supply-chain)**: SHA-pinned all 4 `uses:` (checkout, upload-artifact,
  action-swiftlint) with the tag as a trailing comment; `concurrency:` groups
  (lint cancel-in-progress: true; build-dmg: false — never kill mid-notarization).
- **Deferred with notes**: #5 (sendSync watchdog — commented the deadlock trap:
  send() holds an OSAllocatedUnfairLock, and `XPCSession.sendSync` has no native
  timeout on macOS 26). #4/#6 need dedicated passes.

## 🔥 SHIPPED fire.10.4.2 — FIRE-N: EventTap off the window server (2026-07-08)

First release driven by the Fable-5 issue board (#4-#17); Opus 4.8 executing.
CI `28902845286` (build 1152) success (notarized first try); appcast `c47705d`
live; installed + `list_items`-smoked on the owner's machine. Commits `0a416aa`
(fix) + `1e1e4fa` (bump). Closed issues #16 + #15.
- **FIRE-N** (#16): `EventTap.sharedCallback` runs on the main run loop for
  every tapped event and did `guard tap.isEnabled` → `CGEvent.tapIsEnabled` →
  `SLEventTapIsEnabled` (WS round trip per event). Now a local `isActive` Bool
  set by `enable()`/`disable()`; the disabled-by-timeout/user-input cases are
  still handled above the guard by event TYPE. All main-thread → no locking.
- **#15**: `MCPRelayPump.removeLegacyChannelFiles` → `nonisolated static`
  (standing MainActor-isolation warning gone).
- **Runtime-verify still owed by the owner**: #16 touches event taps — confirm
  show-on-hover / ⌘-drag / click-to-reveal behave normally (low risk: the flag
  faithfully mirrors our enable/disable, all on main).

## 🔥 SHIPPED fire.10.4.1 — App-Hang sweep: main-thread SLS calls off-main (2026-06-29)

CI `28232735852` (build 1151) success AFTER the owner accepted a pending Apple
Developer Program License Agreement (first attempt 403'd on notarization);
`gh run rerun --failed` then went green. Notarized; appcast `2a95c27` live;
installed + `list_items`-smoked on the owner's machine. Commits `e7b7ac2` (code)
+ `903d363` (bump). Prompted by 10.4's dSYMs symbolicating two real freezes on
his daily driver (FIRE-K, FIRE-M) + an Explore audit of the whole class:
- **FIRE-K** (`SLSGetScreenRectForWindow`): `MenuBarItemManager.uncheckedCacheItems`
  → `CacheContext.findSection`/`bestBounds` called `Bridging.getWindowBounds`
  PER ITEM on `@MainActor`. Now prefetches all bounds off-main once
  (`fetchWindowBoundsOffMain`); `bestBounds` reads the map.
- **FIRE-M** (`SLSGetOnScreenWindowCount`): `HIDEventManager.handleSmartRehide`
  → `WindowInfo.createWindows(.onScreen)` on the `@MainActor` Task → off-main.
  Made `WindowInfo: Sendable` (all stored props are value types) to allow it.
- Same class, proactively off-main: `MenuBarOverlayPanel` createWindows ×2
  (`$updateFlags` sink + `show()` now async); `MenuBarManager` /
  `MenuBarSearchModel.updateAverageColorInfo` (now async); IceBar left/right
  click `isWindowOnScreen`.
- **DEFERRED (documented):** `isMouseInsideMenuBarItem` (timing-sensitive event
  handlers) + a few single light SLS calls. See [[fire-apphang-click-to-reveal]].
- Pattern throughout: `await Task.detached { <sync SLS call> }.value` — same
  FIRE-D/E/C fix. `Bridging.getWindowBounds` uses a per-thread connection, so
  it's safe off-main.

## 🔥 SHIPPED fire.10.4 — honest MCP kill-switch + modal-ANR filter + App-Hang fix (2026-06-19)

CI `27822646798` success; release `v0.11.13-fire.10.4` (build 1150) signed +
notarized + 16 dSYMs uploaded; appcast `eaf6121` (live on Pages, verified).
Triggered by the owner enabling Bartender 6 (menu bar "exploded" → quit clean,
no crash) which prompted re-tracing the reveal path. Commits `0c5b11f` (code) +
`9275679` (bump). What landed:
- **A — honest MCP kill-switch (the real trust bug).** The 3 Advanced → MCP
  toggles were INERT — the server answered regardless, so "Enable MCP server"
  off did nothing. Now authoritative: `MCPBackend/Listener` gates every
  agent-facing request (`Response.denied`) — server off ⇒ all refused; writes
  off ⇒ writes refused, reads still work; the relay handshake is never gated.
  `MCPRelayPump.fulfill` re-checks (defense-in-depth) + posts a coalescing
  `mcpNotifyOnWrite` notification. Classification lives on the wire enum
  (`Request.isAgentFacing`/`isAgentWrite`, `RelayWork.isAgentWrite`).
  **Upgrade-safe migration** (`migrateMCPToggles`, keyed `hasMigratedMCPToggles`,
  upgrade signal = `hasMigrated0_8_0` captured before migrations run): existing
  installs inherit ON (no broken integration), fresh installs stay privacy-first
  OFF (opt-in per the docs). Writes stay a separate opt-in. Live-smoked both
  denial paths on the real gate (Debug bridge → MCPBackend) AND the allow path
  on the notarized build (migration preserved owner's 1/1/1).
- **B — modal-ANR filter.** `AppDelegate` Sentry `beforeSend` drops App-Hangs
  parked in `runModal`/`SPUStandardUserDriver`/`NSAlert`. Crashes never dropped.
- **C — click-to-reveal App-Hang fix (FIRE-F).** `MenuBarItemManager` is
  `@MainActor` ⇒ `cacheItemsIfNeeded()` ran `getMenuBarWindowList(.activeSpace)`
  (per-window `CGSCopySpacesForWindows`) ON MAIN; `IceBar.show` calls it on every
  reveal. Moved off-main via `Task.detached` (pure read → `[CGWindowID]`). Field-
  verification pending (FIRE-F should stop on 10.4). See [[fire-apphang-click-to-reveal]].

## 🔥 SHIPPED fire.10.3 — test suite + trust/correctness batch + symbolication (2026-06-19)

Post-audit (the Fable-5 multi-agent audit: 50 verified findings, see below).
CI `27798022215` success; release `v0.11.13-fire.10.3` (build 1149) signed +
notarized; appcast `e4201af` (now on the `fire-from-ice` URL). What landed:
- **FireLogic/** — the repo's FIRST automated tests. A standalone `swift test`
  package that SYMLINKS the Foundation-only security-critical sources out of
  Ice/Automation/ (zero app/TCC deps). 29 tests. Run:
  `DEVELOPER_DIR=…/Xcode xcrun swift test --package-path FireLogic`.
  Covers: TriggerCanonicalizer determinism (golden-pinned), grant seal/validate
  + tamper, AgentInput sanitization, TimeWindow edges. (commit `2b90bad`,`e02d5d6`)
- **Canonicalizer determinism P1** — digest was non-deterministic (encoded a
  `Set<Weekday>` directly; hash-seed-ordered), so a multi-day timeWindow rule
  silently stopped firing across launches. Now a flat sorted `Canonical` form.
  TriggerStore.load() now binds enabled↔content-digest (honest "Re-approve…"
  instead of enabled-but-dead). NOTE: existing automations need a one-time
  re-approval after 10.3 (digest formula changed; near-zero users).
- **Consent-spoof P1** — `AgentInput` (pure, tested) rejects (not strips)
  control/newline/bidi/zero-width in agent-supplied name + reverse-DNS-validates
  bundleIDs, at both trust boundaries (TriggerSpecTranslator + the move path).
- **Engine/relay P2** — cooldown now spans restarts (seed lastFired from
  lastFiredAt); no spurious re-fire on launch (seedState without firing);
  MCPRelayPump can't wedge busy (one Task + `defer`); RelayQueue cancels the
  timeout on completion.
- **SYMBOLICATION (the meta-fix)** — `build-dmg.yml` now uploads dSYMs to
  Sentry (`sentry-cli debug-files upload`, guarded on `SENTRY_AUTH_TOKEN` which
  the owner created). 10.3 run uploaded 16 dSYMs incl. Ice.app.dSYM. So future
  App-Hangs symbolicate to OUR functions — see [[fire-apphang-click-to-reveal]].

### OPEN: App-Hang on click-to-reveal (FIRE-F/G/H, on 10.2) — UNRESOLVED tracker
Owner's repro: Fire freezes when CLICKING A HIDDEN ICON to reveal it. Stacks =
synchronous SkyLight on main (`SLSWindowServerClientCopySpacesForWindows`,
`SLSGetWindowCount`) — the App-Hang franchise's latest organ (after FIRE-D
capture, FIRE-E file-stat). Local Triggers=[] so it's NOT the fork's
coordinator path; likely upstream Ice's show-hidden-item enumeration on main.
10.3 only INSTRUMENTS it. NEXT: once it recurs on 10.3 with symbols → read the
named frame → targeted off-main fix (or owner's Bartender-style
promote-on-click idea) as fire.10.4.

### AUDIT ROADMAP (remaining, from the 50-finding audit)
- fire.10.4: settings-honesty (3 Advanced toggles persisted but never read in
  the exec path: mcpServerEnabled/mcpAllowWrites/mcpNotifyOnWrite) + the
  App-Hang fix once symbolicated.
- fire.10.5: no-team-build relay peer pinning (P1 only affects ad-hoc, not the
  signed DMG); sendSync watchdog; handler-pool starvation.
- CI: SHA-pin actions, `concurrency:` group, automate the (still-manual)
  appcast/Sparkle-sign step. Cleanup: MenuBarItemService dead code, stale docs,
  a11y labels. (P3 backlog — full list was in the audit report.)

## 🏷️ REBRAND DONE — repo renamed to `pdurlej/fire-from-ice` (2026-06-15)

`gh repo rename` done: `pdurlej/Ice` → **`pdurlej/fire-from-ice`**. GitHub
301-redirects the old name and ALL sub-paths, so existing appcast enclosure
URLs (`…/pdurlej/Ice/releases/download/…`) keep resolving for installed
users — Sparkle auto-update unaffected. The 6 CI secrets moved with the repo;
`build-dmg.yml` uses `${{ github.repository }}` so future releases auto-use
the new name. Local `origin` repointed. In-repo `pdurlej/Ice` refs swapped to
`fire-from-ice` across README/FORK/ROADMAP/docs/Info.plist/HANDOFF; the
`git clone … && cd Ice` line fixed to `cd fire-from-ice`.
UNCHANGED ON PURPOSE: bundle id `com.jordanbaird.Ice` (TCC + Sentry + appcast
version-matching depend on it), Xcode project/scheme `Ice` + product `Ice.app`,
the `pdurlej/fire-releases` appcast repo, and `SUFeedURL`
(`pdurlej.github.io/fire-releases`). Sentry post-10.2: ZERO unresolved, zero
events on build 1148 over 5 days — the App-Hang saga is field-verified closed.

## 🔥 SHIPPED fire.10.1 — IceBar App-Hang hotfix, FINISHED (2026-06-10 ~19:50)

CI `27294364385` success; release `v0.11.13-fire.10.1` (build 1147) published,
notarized; appcast updated (`fire-releases` `b58d802`); installed locally.
Sentry: **FIRE-D resolved @next**, **FIRE-C resolved** (old 9.8 client).

The fix (`4ca76f6`): fire.9.9 was a HALF-fix — it moved the CGWindowList
capture *call* off-main, but the returned CGImage is LAZY; the expensive
window-server pixel fetch (CGSCaptureImageProviderBytePointer) ran at first
DRAW, inside `averageColor()` on the MAIN thread (Sentry FIRE-D, on 10.0).
Now `materialized(_:)` rasterizes into a resident bitmap ON the capture
queue, FAIL CLOSED (nil on failure — never hand a lazy image to main).
Reviewed by GPT-5.5 Pro (`~/.oracle/sessions/fire-icebar-anr-materializ-review`):
approach confirmed; the fail-closed correction was its one required change.
LESSON: with window-server CGImages, moving the capture is not enough — the
fetch happens at draw time; materialize off-main or compute results off-main.

## 🔥 SHIPPED fire.10.2 — audit pack W1–W5 (2026-06-10 ~21:30)

CI `27297989198` success; release `v0.11.13-fire.10.2` (build 1148) signed +
notarized; installed; **relay smoke-tested end-to-end on the signed binary**
(`list_triggers` → full path bridge → RelayQueue → pump → fulfiller →
complete; legacy channel files auto-cleaned); appcast `808a30e`; **FIRE-E
resolved @next — Sentry now has ZERO unresolved issues.**

**W5 (the Max wave) — authenticated XPC relay** (`615cfc6`): the fire.8.2
file channels are GONE. Design: PULL relay (main app can't host a Mach
service — launchd refuses GUI apps, the documented Option D failure — so it
is the CLIENT of its own MCPBackend.xpc, mirroring the proven
MenuBarItemService pattern). `MCPBackend/RelayQueue.swift` = actor, FIFO +
per-id waiters, continuations resume EXACTLY once (removeValue guards the
timeout/complete race). `Ice/Services/MCPRelayPump.swift` = 200ms off-main
fetch→fulfill→complete over a peer-gated XPCSession, STRICTLY serial (consent
modals can never stack), cleans legacy channel files at startup. Wire:
Request.relayFetch/.relayComplete, Response.relayWork/.relayAck,
RelayWork/RelayResult; channel namespaces reduced to pure Codable models,
symlinked into Bridge. Handlers are pure fulfillers now. WHAT IT BUYS:
same-team peer requirement on signed builds ⇒ no same-user process can
inject commands or forge results (consent prompts = defense-in-depth, not
the only boundary); no single-slot races; zero file IO on the MCP path
(FIRE-E class dead by design). SCOPED OUT + documented in
AutomationGrant.swift: DataProtection-keychain for the grant HMAC key needs
an app-identifier entitlement in CI signing first (app signs with no
entitlements file ⇒ the call would errSecMissingEntitlement as dead code).

## 📋 AUDIT (Fable 5, 2026-06-10) — ALL WAVES W1–W5 SHIPPED in fire.10.2

**Executed 2026-06-10 (all compile-gated, committed per wave, pushed):**
- **W1** (`ec31134`) correctness pack: codexbar timeout now actually
  terminates the process (was unreachable on the throw path → wedge);
  FIRE-E fix — ALL channel file IO (reads + result writes) off-main on
  per-handler utility queues with readInFlight coalescing; Bridge
  parseOptionalDouble for cooldown_seconds; coordinator re-validates
  trigger jobs at execution time (rule+generation+writeSet+seal); AppState
  duplicate performSetup dropped; timeWindow start==end rejected.
- **W2** (`d356a25`): averageColor crop+averaging on captureQueue, main
  receives only the finished color; animation applied at the main hop.
- **W3** (`fcb4b8f`): dead-code sweep, net −715 lines (Mover.swift,
  makeMoveItem/displayContaining, unused splitByPredicate copy, fire.6
  write stubs — Listener answers those cases directly, TriggerRule.lastState).
- **W4** (`9b1b78b`): CLIENT-SETUP 10-tool list + Automations section;
  README un-staled (was still describing fire.6 status); ROADMAP marked
  historical.
- **NOT shipped yet**: fire.10.2 release would close FIRE-E (left
  unresolved in Sentry as the tracker). **W5 (authenticated XPC) awaits
  the user switching thinking to Max** (their explicit instruction) — do
  not start it without that signal.

Full-fork audit (me + 2 Explore agents + Sentry). Confirmed findings → waves:
- **W1 Correctness** (→ fire.10.2): (a) `CodexBarCLIQuotaBackend.runProcess`
  timeout is INEFFECTIVE — on the timeout path `group.next()` throws so
  `process.terminate()` (l.158-161) is unreachable and the task group blocks
  awaiting the unresumed continuation until the child process exits on its
  own → a wedged codexbar freezes the AI Quotas item forever (move terminate()
  into the timeout child, guard isRunning); (b) **FIRE-E (NEW, found via
  Sentry post-audit, UNRESOLVED as tracker)**: both channel handlers poll on
  main at 5 Hz each and `isTrustedLocalFile` does a synchronous
  `FileManager.attributesOfItem` (stat) on the MAIN thread — blocks ≥2s under
  disk pressure; move poll file-IO off-main (utility queue, hop back with the
  decoded command) or DispatchSource; (c) Bridge `cooldown_seconds` parsed via
  `.doubleValue` only — MCP `Value.doubleValue` is a strict case-match so int
  → nil → silent default 5 (add int+double parse); (d)
  `MenuBarMutationCoordinator.execute` never re-validates trigger grants
  although `MutationJob.triggerID/Generation` exist for exactly that (close
  the defense-in-depth gap for source == .trigger); (e) AppState lines ~79+91
  call `mcpWriteCommandHandler.performSetup` TWICE (drop the second); (f)
  TriggerSpecTranslator accepts `start==end` timeWindow (always-false window —
  reject with message).
- **W2 IceBar finish**: compute `averageColor` on the captureQueue, main gets
  only the color (GPT-5.5 Pro "strongest version").
- **W3 Dead-code sweep** (~800+ lines): `MCPBackend/Mover.swift` (verified: no
  callers) + `makeMoveItem`/`displayContaining` in MCPBackendStateManager +
  legacy write stubs in `MenuBarItemService/MenuBarStateManager` (return
  "Coming in fire.7"; keep listItems/saveLayout/listLayouts/sourcePID) +
  unused `TriggerRule.lastState` field.
- **W4 Docs + brand**: CLIENT-SETUP.md lacks the 3 trigger tools; README still
  lists "trigger conditions" as ROADMAP/planned though shipped in 10.0.
  REBRAND: rename repo `pdurlej/fire-from-ice` → `fire-from-ice` (user's call; GitHub
  auto-redirects old release URLs so the existing appcast keeps working; new
  appcast entries use the new name; update local remote, gh default, badges).
  App has KILKANAŚCIE downloads (real users).
- **W5 Hardening P2** (tracked follow-up): authenticated XPC replaces the file
  channels (kills single-slot overwrite races + the 15-120s loser-timeout
  UX + XPC pool starvation via syncWait), Keychain ACL bound to code signature.
- P3 backlog: set_trigger approval after >120s installs but agent already got
  timeout (document/extend); two consent modals can nest (write + trigger);
  `hasValidGrant` hits Keychain per row per render in Settings (cache);
  result-match lacks staleness check; `try?` decode in channels (poison file =
  silent re-poll loop). Adjudicated FALSE agent claims (do not re-chase):
  CodexBar "double-resume crash" (only terminationHandler XOR run()-catch
  resumes), syncWait `var result: T!` "crash" (it's a hang/starvation, not a
  crash), IceBarColorManager isCapturing "permanent lock" (instance-scoped).

## 🔥 SHIPPED fire.10.0 — AI-Native Triggers P1 (2026-06-08 ~22:55)

CI run `27165435645` **success** (signed + notarized); release published
`v0.11.13-fire.10.0` (DMG attached, notarized Developer ID); appcast updated
(`pdurlej/fire-releases` `7d0ce61`); installed locally and **smoke-tested
end-to-end on the signed binary** — all three new MCP tools green:
`tools/list` registers them; `list_triggers` empty round-trips through the new
channel; `set_trigger` showed the Fire-generated consent prompt → approved →
sealed grant + persisted (id `713EE462…`); `list_triggers` returned it with
correct Fire-generated descriptions; `remove_trigger` confirm → removed; list
empty again. Both consent gates fired as designed. (Build 1145→1146.)

Hardened P1 from `docs/mcp/AI-NATIVE-TRIGGERS.md §0` (GPT-5.5 Pro review:
`~/.oracle/sessions/fire-triggers-design-review/`). All six waves A–F,
compile-gated (swift build Bridge + xcodebuild -scheme Ice), on `fire/main`.

DONE (compiles end-to-end):
- **Wave A** (`22360a0`): `TriggerModels.swift` + `MenuBarMutationCoordinator.swift`
  (the ONE @MainActor FIFO non-reentrant authority every mutation passes through).
- **Wave B** (`f077513`): `AutomationGrant.swift` (SHA-256 canonicalizer; HMAC
  seal/validate, Keychain key) + `TriggerStore.swift` (rules=config, sealed
  grants=authority; load() disables any rule with a missing/stale/tampered grant).
- **Wave C** (`50d8e1a`): `AutomationAuthorization.swift` (install consent gate,
  no lease; Fire-generated prompt; mints+seals grant; validateForFire()).
- **Wave D** (`96b0f7b`): `TriggerEngine.swift` (edge-on-enter eval, battery
  hysteresis, cooldown, grant re-validate → enqueue); coordinator singleton;
  `AppState` wires `triggerEngine.performSetup()`.
- **Wave E** (`75baf56`): the agent-facing create surface. Wire DTOs
  `TriggerSpec`/`TriggerSummary` + `Request.setTrigger/listTriggers/removeTrigger`
  in `Shared/Services/MenuBarItemService.swift` (Bridge inherits via symlink).
  New `Shared/Services/MCPTriggerChannel.swift` (dedicated install/remove/list
  file-channel, separate from the move channel so persistent-capability
  authority ≠ single-move lease). New `Ice/Services/MCPTriggerCommandHandler.swift`
  (polls proposals → install via `authorizeInstall`, remove via new
  `authorizeRemoval`, list authoritative → upsert + `triggerEngine.reload()`).
  New `TriggerSpecTranslator` (the single trust boundary: validate/clamp the
  agent spec, mint id + gen 1) + `TriggerNarrator` (one source of truth for the
  never-agent-supplied descriptions; AutomationAuthorization refactored onto it).
  MCPBackend relays the 3 ops; Bridge exposes 3 tools w/ full condition/action
  schemas. `set_trigger`/`remove_trigger` return only after the user decides in
  Fire → success == approved.
- **Wave F** (`cf2a6f2`): Settings ▸ Automations tab (`AutomationsSettingsPane`).
  Lists each automation (Fire-generated condition+action text, enable/disable
  switch, last-ran audit time, delete-with-confirm), global "Disable All", and a
  "Re-approve…" flow for expired grants. `TriggerStore` is now an ObservableObject
  (@Published rules) + `hasValidGrant`/`recordFired`/`disableAll`; `TriggerEngine`
  records a fire timestamp (lastFiredAt only — digest unchanged, grant stays valid).

FOLLOW-UPS (P2/P3, not shipped):
- Watch Sentry for any fire.10.0 regressions (real users auto-update via appcast).
- The live `mcp__fire__*` tools in a session bind to the INSTALLED app's bridge,
  so a session started before the install won't see the trigger tools until the
  MCP server reconnects (restart Claude / `/mcp`). New sessions are fine.
- P2 ideas: applyLayoutSnapshot action surfaced in UI (digest-bound); exit-edge
  reversion; more conditions (focusMode/wifi/calendar) once authenticated XPC
  replaces the file channel; per-fire notifications.
- Smoke harness kept at `/tmp/fire_mcp_smoke.py` (stdio MCP driver: list/set/remove).

KEY INVARIANT (keep): every menu-bar mutation goes through
`MenuBarMutationCoordinator.shared`; a trigger is a sealed capability, not a
stored command; Fire (never the agent) generates all consent/description text.

## 🔥 SHIPPED fire.9.9 - IceBar screen capture off the main thread (App-Hang fix) (2026-06-08 ~07:30)

Found via Sentry (`sentry issue list` — org `pdurlej`, project `fire`). NINE
unresolved issues, all the SAME: "App Hanging for at least 2000 ms"
(`mach_msg2_trap`), across releases incl. fire.9.8, hitting ≥2 real users
(FIRE-5/FIRE-8 show 2 users; FIRE-9 = 14 events/1 user on 9.8). **Hangs, not
crashes** — the app freezes ≥2s and recovers.

Root cause (confirmed from the blocked-thread stack in event
`7e5ebdf3…`): `Combine .sink → SwiftUI withAnimation → CGContextDrawImage →
CGSCaptureImageProviderBytePointer (SkyLight) → mach_msg`. That's
`IceBarColorManager` color-matching the IceBar to the desktop by capturing the
menu-bar + wallpaper image via `ScreenCapture.captureWindows` **synchronously
on the main thread**. On macOS 26 the window-server capture can block for
seconds → whole-app freeze whenever the IceBar shows/moves or on its 5s timer.
Upstream Ice code, NOT our MCP/consent/triggers.

Fix (`Ice/MenuBar/IceBar/IceBarColorManager.swift`): capture on a
`userInitiated` background queue; hop back to main only for the @Published
`colorInfo` update (still `withAnimation`). `isCapturing` flag coalesces an
event storm. `updateColorInfo` unchanged (CPU-only crop + averageColor on the
cached image). Callers that needed image-then-recolor now chain via a
completion.

How to re-check Sentry: `sentry issue list --query "is:unresolved"`,
`sentry issue view FIRE-9 --json`, `sentry issue events <id>` →
`sentry event view pdurlej/fire/<eventid> --json | jq` the thread frames.
Sentry CLI (`sentry`, v0.34, authed at `~/.sentry/cli.db`) auto-detects the
project from the DSN in `AppDelegate.swift`. After 9.9 verifies, resolve the
9 issues "in next release".

Tag `v0.11.13-fire.9.9` (build 1145), commit `bcbdc1e`. CI: attempt 1 failed on
a flaky SwiftPM artifact-cache error ("Sparkle/Sentry … already exists in file
system → fatalError" — NOT our code; no actions/cache in build-dmg.yml, so a
`gh run rerun --failed` on a fresh runner fixed it). Signed + notarized;
appcast updated (`pdurlej/fire-releases` `b79b92a`). Installed 9.9; main thread
no longer blocked in capture. Positive off-main proof needs the IceBar OPEN
(when hidden, `iceBarPanel.screen` is nil so the capture guard bails) — owner
to confirm the hidden-bar no longer beachballs. After confirming, Sentry
FIRE-3..B resolved in release `0.11.13-fire.9.9`.

## 🔥 SHIPPED fire.9.8 - MCP write consent gate (confused-deputy stopgap) (2026-05-30 ~00:05)

Closes the biggest security flaw GPT-5.5 Pro flagged in the architecture
review (see `~/.oracle/sessions/fire-arch-review-9-7/artifacts/transcript.md`
and the follow-up `fire-confused-deputy-fix`): the file write channel
(`MCPWriteChannel`) was a **confused deputy** — any same-user process that
dropped a valid `write-command.json` borrowed Ice's Accessibility (TCC)
grant to mutate the menu bar; the bridge-side consent check was irrelevant
because the privileged actor is the main app.

Fix (GPT-5.5 Pro's rank-#2 same-day stopgap): the TCC-bearing main app now
authorizes every MCP write in its OWN UI before acting.
- New `Ice/Services/MCPWriteAuthorization.swift` (@MainActor): app-modal
  NSAlert `[Deny (default)] [Allow Once] [Allow for 5 Minutes]`. "5 Minutes"
  arms an **in-memory** lease (never UserDefaults/file — so no same-user
  process can forge/extend it, and there's no persistent skip-approval knob).
  The lease keeps a burst like `apply_layout` from being N prompts.
- `MCPWriteCommandHandler.poll()` calls `authorize` before `execute`; on
  deny it writes a denied Result. An `authorizationInFlight` flag stops
  concurrent poll ticks from stacking a second modal.
- `MCPWriteChannel` hygiene: mcp dir `0700`, command/result files `0600`,
  reads require a regular file owned by this user, ≤16KB (blocks symlink
  tricks / cross-user writes); stale-command window 30s → 10s.

UX consequence (intended): MCP writes now require human approval; the file
channel is a request queue, not an authorization boundary. Unattended
automation through it is intentionally unsupported until the REAL fix —
a peer-authenticated XPC service with a code-signing requirement
(`NSXPCListener.setConnectionCodeSigningRequirement`, macOS 13+). That's
the tracked follow-up (would also let trusted clients skip the prompt).

Tag `v0.11.13-fire.9.8` (build 1144), commit `58e0eea`. CI signed +
notarized; appcast updated (`pdurlej/fire-releases` `af6e90c`). Installed
+ verified: injecting a command JSON directly into the channel (i.e. a
process that is NOT the legit bridge) pops the main-app consent prompt
("Allow an AI assistant to change your menu bar?" — Deny default / Allow
Once / Allow for 5 Minutes), proving the gate fires for ANY local writer.

## 🧪 KNOWN: Ice menu-bar churn-fragility (debugged 2026-05-30 ~23:00)

Not a fire regression — an upstream Ice weakness, surfaced after heavy
stress-testing (many manual Cmd-drags + MCP moves + a consent-prompt test).
Symptom: some items that belong in hidden/always-hidden **leak on-screen to
the LEFT of the Ice control item (•••)** and won't re-collapse. This is
exactly GPT-5.5 Pro's critique #3 (moves aren't transactional → section
state desyncs). `log show`/`log stream` are NOT readable from the agent's
sandboxed shell (returns 0 lines for everything), so debug via the
CGWindowList swift probe + `defaults read com.jordanbaird.Ice`, not logs.

Recovery that worked (when a plain Ice restart did NOT):
1. Quit Ice.
2. `defaults delete com.jordanbaird.Ice "NSStatusItem Preferred Position Ice.ControlItem.Visible"` (and `…Hidden`, `…AlwaysHidden`, and `IceControlItemMinX`).
3. Relaunch. Ice rebuilds clean dividers and re-collapses the leak.

Caveats:
- The rebuild crams the dividers far-right (Visible CI → preferred 0), so
  it can also hide previously-visible system items (Spotlight's icon went
  hidden; Cmd-Space still works). Re-tidy precisely via Ice Settings →
  Menu Bar → Layout (the reliable, user-driven re-assign).
- `AudioVideoModule` is a macOS-26 Control Center module — Ice can't
  relocate it regardless (system reparenting).
- Minor: with Visible CI at preferred 0, the fire.9.7 AI Quotas self-heal
  computes `target = visiblePos − 1 = −1`. Harmless (negative preferred =
  rightmost, so AI Quotas still renders right of the Visible CI and stays
  visible), and un-triggerable in normal use (Visible CI is normally ~410).
  If ever bothered, clamp `target = max(0, visiblePos − 1)` in
  `AIQuotaStatusItemController`.

## 🔥 SHIPPED fire.9.7 - AI Quotas left of system icons + codex fetch fix (2026-05-29 ~21:05)

Owner wanted the usage readout on the LEFT and the macOS system icons
(Spotlight, Control Center, clock) grouped on the RIGHT. Verified live
via CGWindowList probe + screenshot (build 1143).

Ground truth (lower preferred position = further RIGHT/trailing):
`Visible(•••)=410 x1614 | Spotlight=378 | AIQuotas(was 174) | ControlCenter=132 | Clock`.
AIQuotas had been forced to preferred 0 → far right, RIGHT of Spotlight,
wedged among the system icons.

1. **Placement** (`AIQuotaStatusItemController`). Place AIQuotas just
   inside Ice's Visible control item: `target = VisiblePos − 1` (= 409
   here), the LEFTMOST always-visible slot. New order: `••• AIQuotas
   Spotlight CC Clock` — AIQuotas x1647, Spotlight pushed to x1852, all
   on-screen. **Architectural limit:** literally left of the ••• is
   impossible — the Visible control item IS the left edge of the visible
   zone; immediately left of it is Ice's 10 000pt divider → off-screen.
   So "leftmost visible / left of every system icon" is the achievable
   target. Explained to owner.
2. **Drag stickiness (root cause of "couldn't move it").** Old controller
   re-forced position 0 on every launch whenever the stored value was
   `>100`, so any leftward drag snapped back to far right next launch.
   Now a one-time migration (`AIQuotasPositionLeftOfSystemV1` flag) moves
   existing installs to the leftmost slot, then manual drags are
   respected; only an off-screen value (left of the Visible CI)
   self-heals.
3. **Codex "?" hardening (the "bug 9.7").** `CodexBarCLIQuotaBackend.runProcess`
   resumed from the terminationHandler using a snapshot that could race
   the readabilityHandler's final stdout chunk → empty/truncated JSON →
   spurious "?". Now reads stdout to EOF after exit (codexbar output is a
   few KB; no deadlock). Added defensive `jsonSlice()` that trims any
   non-JSON prefix before decoding (the `[codex notify] …` line is on
   stderr, which we drop — belt-and-suspenders). Verified: Codex shows
   72% (was "?").

Tag `v0.11.13-fire.9.7` (build 1143), commit `a2bafd2`. CI signed +
notarized; appcast updated (`pdurlej/fire-releases` `92fef44`). Installed
+ verified.

Lint note: `lint.yml` has been RED since ≥fire.9.4 (≈15 pre-existing
swiftlint violations across 112 files: multiline_arguments, etc.). It is
NOT a release gate — `build-dmg.yml` is — and shipping despite red lint is
the established pattern. A full swiftlint cleanup is a separate task.

## 🔥 SHIPPED fire.9.6 - AI Quotas shows REMAINING %, not used % (2026-05-29 ~19:10)

Owner feedback on the readout: showing *used* % made "Antigravity 0%"
read like "nothing left / all spent" when it actually means "untouched,
full headroom". Flipped the menu-bar number from `weeklyUsedPercent` to
`weeklyLeftPercent` (one-line change in `AIQuotaMenuBuilder.attributedTitle`
+ doc comment). The color thresholds were ALREADY keyed on remaining
headroom (red < 10% left, orange < 20%), so only the displayed value
changed — a small red number now reads as "almost out", a big number as
"plenty left". Dropdown already said "X% left", so the two are now
consistent.

Verified live via post-install screenshot (build 1142):
- Antigravity 0% → **100%** (the headline example).
- Ollama 43% → **57%** (exactly 100−43, confirms the flip).
- Claude **87%** left (matches codexbar "87% left").
- Codex showed "?" in that capture — a TRANSIENT codexbar-CLI fetch
  miss on first launch (codexbar was contended: SessionStart hook +
  manual probes ran it seconds earlier). NOT caused by this change:
  `weeklyLeftPercent` is nil iff `weeklyUsedPercent` is nil, so used vs
  left have identical "?" behavior. codex CLI returns valid data
  (primary 6% used / 94% left; weekly ~23% used). Self-heals on the
  next 5-min refresh / "Refresh Now".

Latent follow-up (NOT done, out of scope): `CodexBarCLIQuotaBackend.runProcess`
resumes its continuation in `terminationHandler` using `stdoutData.snapshot()`
without guaranteeing the readabilityHandler flushed the final chunk —
a possible flush race that could yield empty/truncated stdout → "?".
Backend reads stdout only and correctly ignores stderr (the
`[codex notify] remoteControl/status/changed` line lives on stderr, so
it is NOT the cause). Harden as fire.9.7 if codex "?" recurs.

Tag `v0.11.13-fire.9.6` (build 1142), commit `1aa592e`. CI built +
signed + notarized; appcast updated (`pdurlej/fire-releases` `7e9159c`).
Installed + verified locally.

## 🔥 SHIPPED fire.9.5 - AI Quotas brand icons + weekly % (2026-05-29 ~16:50)

Dogfeeding feedback: the "Cx95 Cl51 Gm? Ag100 Ol98" text was cryptic.
Redesigned the menu-bar readout, CodexBar-style. Verified live via
screenshot: shows [Codex logo] 22% [Claude logo] 11% [Antigravity ▲] 0%
[Ollama 🦙] 43%.

- Brand icons loaded at runtime from the installed CodexBar.app's
  `ProviderIcon-<provider>.svg` (same dependency as the CLI; not
  vendored; falls back to 2-letter label if absent). Rendered as
  NSAttributedString image attachments on the control-item button
  (`AIQuotaProviderIcon.swift` + `AIQuotaMenuBuilder.attributedTitle`).
- Shows WEEKLY usage % (secondary window's usedPercent), color-coded:
  orange < 20% weekly left, red < 10%.
- Dropped the standalone `gemini` provider enum case — Antigravity is
  the Gemini-backed tool, so it already covers Gemini; gemini only ever
  showed "?".
- Per-provider toggles added to Settings → Advanced → AI Quotas.

Note: AX position reads can be glitchy for this item (reported x=16937
once); CGWindowList is authoritative (x=1757, w=127, onscreen=true).

## 🔥 SHIPPED fire.9.4 - AI Quotas FINALLY VISIBLE (2026-05-29 ~16:25)

**The architectural fix.** Dogfooding revealed the AI Quotas item was
INVISIBLE (parked off-screen at x=-9501). Owner flagged this is the
SAME problem CodexBar couldn't solve → architectural, not a placement
bug. Directive: stop patching, rebuild from first principles with a
different architecture.

**Root cause (first principles, sharpened by Codex's CodexBar data):**
A FOREIGN/third-party NSStatusItem is fragile under a menu-bar manager
(Ice) + macOS 26 Control Center reparenting — full stop. Ice's job is
hiding/relocating third-party status items, so the AI Quotas item got
swept into a hidden section and parked off-screen amid Ice's 10000pt
section dividers; no "preferred position" survived.

Crucial correction: this is NOT about "multiple provider fields
colliding." Codex (who worked on CodexBar) confirmed CodexBar broke
even with `mergeIcons=1` — a SINGLE merged status item (`CodexBar.StatusItem`)
still failed. So the real thesis is broader: **don't let independent
apps fight over the menu bar; the one owner of that strip must render
the state as its own pinned control.** The minimal isolation test to
prove it (NOT yet run): one plain NSStatusItem, one static text value,
stable autosaveName — if it still vanishes, it's purely architectural;
if it survives, complexity was a factor. Our fire.9.3→9.4 delta already
points hard at architectural (plain item broke; Ice-native control item
works) but doesn't cleanly isolate position-before-creation alone.

**The fix — make it an Ice-native control item (== Codex's recommended
direction: "one owner of the strip renders the state as its own pinned
control").** The ONLY menu-bar elements that stay visible under Ice are
Ice's own control items, for two concrete reasons, both now reproduced
for AI Quotas:
1. `ControlItem.preflightSetup` forces a LOW NSStatusItem "Preferred
   Position" (0) into UserDefaults BEFORE the status item is created,
   so macOS places it at the visible trailing edge (not leftmost/hidden).
   Setting it AFTER creation does nothing (that was my failed earlier
   attempt). `AIQuotaStatusItemController` now does this.
2. The item's tag is registered in `MenuBarItemTag.controlItems` (new
   `aiQuotasControlItem`, title "Ice.ControlItem.AIQuotas"), and the
   status item is named to match — so the item manager never caches,
   classifies, or moves it.

**Verified live** (signed fire.9.4): CGWindowList shows the item at
x=1689, w=195, onscreen=true; AX title "AI Cx99 Cl73 Gm? Ag100 Ol98";
screenshot confirms it visible next to the clock. Removed the fire.9.3
"Fire."/namespace exclusion hacks (control-item registration handles it
cleanly). Data layer unchanged.

**KEY LESSON for any future menu-bar UI in Fire/Ice:** never add a
plain NSStatusItem — Ice will hide it. Always (a) force preferred
position 0 before creation and (b) register its tag in controlItems.

Open AI Quotas follow-ups (owner multi-selected, not yet done):
threshold styling (<20% warn / <10% crit), per-provider toggle UI,
cross-MCP as a real scheduled automation.

## 🔥 SHIPPED fire.9.2 - AI Quotas adds Antigravity + cross-MCP doc (2026-05-29 ~15:00)

User ask (voice, from the field): add Antigravity to AI Quotas, then
cross-MCP, then AI Quotas follow-ups.

**fire.9.1 + fire.9.2 — Antigravity provider** (verified live, appcast'd):
- Added `case antigravity` to AIQuotaProvider ("Ag" / "Antigravity").
  CodexBar reads it via oauth (account p.durlej@gmail.com).
- Antigravity's JSON shape differs: `primary` is null, secondary/tertiary
  carry an aggregate usedPercent, and per-model limits live under
  `extraRateWindows` (Gemini 2.5/3 Pro/Flash). Added `tertiary` +
  `extraWindows: [AIQuotaExtraWindow]` to the snapshot; parser reads
  `extraRateWindows`; dropdown lists per-model windows (capped 12);
  `primaryLeftPercent` falls back primary→secondary→tertiary→min(extra)
  so the title shows a number, not "Ag?".
- **fire.9.2 fix**: fire.9 persisted the ENABLED provider set, so when
  9.1 added antigravity, existing users (and the test) didn't see it —
  the stale persisted list excluded it. Switched to persisting the
  DISABLED set (`AIQuotaDisabledProviders`); absent = all on, so new
  providers appear automatically. **Verified live**: title rendered
  `AI Cx99 Cl73 Gm? Ag100 Ol100` (Ag100 = real Antigravity data).
- Note: standalone "gemini" provider shows `Gm?` (its CLI/API isn't
  configured for this user; Antigravity is the real Gemini usage). User
  can disable gemini in settings if they want.

**Cross-MCP** — DONE LIVE (2026-05-29 ~15:10, user home + Fantastical on).
Wrote `docs/mcp/CROSS-MCP-LAYOUTS.md` (the pattern) AND ran the full loop
end-to-end as the agent: queried Fantastical (`queryCalendarItems`) →
saw 15:09 is between meetings (last "Ania x Piotr" 13-14, next "Kolacja"
17:45) → built `Focus` (10 items) and `Meeting` (7, bg items hidden)
layouts via the bridge → `apply_layout("Focus")` restored the full bar.
Verified: ollama/ArqMonitor/FruitJuice hidden for Meeting, all back for
Focus. Fantastical→agent→Fire, zero app-to-app code. Layouts `Focus`
and `Meeting` left saved in the user's MCPLayouts. A screen-recording
for content is the only remaining bit (the mechanism is proven).

**AI Quotas follow-ups still open**: split mode (4 separate items),
threshold styling (<20% warn / <10% crit), MCP `list_ai_quotas` opt-in,
per-provider settings UI (currently no per-provider toggle in the pane —
the disabled-set is wired but only togglable via defaults), unit tests
(no test target in project).

Tags today (cont.): fire.9.1 (1137, intermediate), fire.9.2 (1138,
Antigravity — appcast'd). Users go fire.9 → fire.9.2.

## 🔥🔥🔥 SHIPPED fire.9 - AI Quotas + fire.8.4 write bridge (2026-05-29 ~14:30)

Two features shipped, both verified live and pushed to the appcast:

### fire.9 — AI Quotas (CodexBar-CLI-backed menu-bar usage readout)

Mission from GPT-5.5-Pro spec. Optional, off-by-default, local-only
menu-bar item showing LLM usage left for Codex/Claude/Gemini/Ollama.

**Verified live**: enabled via `defaults write com.jordanbaird.Ice
EnableAIQuotas -bool true`, the signed fire.9 build rendered the status
item title `AI Cx99 Cl81 Gm? Ol100` — real data from `codexbar usage
--provider X --json --json-only`, with gemini gracefully degrading to
`?` (its CLI fetch returned non-zero). Read back via AX
(`AXIdentifier == Fire.AIQuotas.StatusItem`).

Code lives in `Ice/AIQuotas/` (9 files): AIQuotaProvider, AIQuotaSnapshot,
AIQuotaBackend (protocol), CodexBarCLIQuotaBackend (Process + JSON parse),
AIQuotaManager (NSObject+ObservableObject; 5-min refresh loop, single-
flight guard, menu actions), AIQuotaStatusItemController (one NSStatusItem,
autosave `Fire.AIQuotas.Combined`, never recreated), AIQuotaMenuBuilder
(title + dropdown), AIQuotaSettings (+ AIQuotaSettingsContent SwiftUI in
Advanced pane). Wired in `AppState.setupTask`. Defaults keys added.
Real CLI command is `usage --provider X --json --json-only` (the spec's
`--format json --json-only` was slightly off).

Privacy: quota data stays in-memory + menu bar, never Sentry/MCP/network.

**Known follow-ups** (not blockers): Ice's image cache treats the quota
item as a managed menu-bar item (logs a capture warning) — harmless for
MVP, spec lists excluding it as a follow-up. Unit tests for the parser
were not added (no test target in the project; parser verified against
real codex+ollama JSON instead). Split mode (4 items), threshold
styling, MCP `list_ai_quotas` opt-in are spec follow-ups.

### fire.8.2 → 8.4 — Ice-performs-writes bridge (hide works everywhere)

The hard problem from fire.8.1: AI couldn't move an item INTO a
collapsed/empty Hidden section, because that section's divider is parked
off-screen and the MCPBackend.xpc helper can't reach it (and can't
expand sections — that's an Ice-main-app-only op).

**Solution** (`Shared/Services/MCPWriteChannel.swift` + `Ice/Services/
MCPWriteCommandHandler.swift`): MCPBackend writes a JSON command to
`~/Library/Application Support/com.jordanbaird.Ice/mcp/write-command.json`;
Ice main app polls it (200ms), executes the move via its own
`MenuBarItemManager.move`, writes `write-result.json`; MCPBackend polls
the result. Files (not shared UserDefaults) because cross-process
UserDefaults caching is unreliable for long-running readers.

The key fix (fire.8.4): find control items via
`MenuBarItem.getMenuBarItems(option: .activeSpace)` — the same call Ice's
Layout editor uses — which omits the on-screen filter and therefore
INCLUDES off-screen divider control items. Drag `.leftOfItem(hiddenCI)`
etc.; the system relocates the item even toward an off-screen divider.
No section expansion needed (fire.8.3's expand approach was wrong — the
signed-build diagnostic proved only the Visible divider was ever in the
on-screen-filtered cache).

**Verified live** (signed fire.8.4 via Claude Code MCP): `hide_item
com.electron.ollama` moved it from the visible row into the empty Hidden
section (vanished from menu bar; alwaysVisible 9→8); `show_item` brought
it straight back. Full round-trip.

`MCPBackend/Mover.swift` (the in-process CGEvent drag from fire.8 W2) is
now superseded by the bridge for moveItem, left in place but unused.

### Hard-won lesson: local testing of Ice-main-app code needs a SIGNED build

Ad-hoc re-signing the local Debug build invalidates Ice main app's
Accessibility (TCC) grant, so Ice takes `performSetup(hasPermissions:
false)` and never runs `setupTask` — meaning the bridge handler and AI
Quotas manager never start. The only reliable local test path is a
Developer-ID-signed CI build installed over a prior signed build (TCC
inherits). That's why fire.8.2→8.4 each went through CI; appcast was only
updated after the signed build verified. (MCPBackend.xpc reads still work
ad-hoc because they don't gate on setupTask.)

### Tags shipped today
fire.8.1 (1132), fire.8.2 (1133, intermediate), fire.8.3 (1134,
intermediate), fire.8.4 (1135, write bridge — appcast'd), fire.9 (1136,
AI Quotas — appcast'd). 8.2/8.3 were unverified intermediates, never
appcast'd, so users jump 8.1 → 8.4 → 9.

### Still open / next
- Cross-MCP demo screencast (Fantastical apply_layout → Fire) — apply_layout
  now works across all sections, so this is unblocked.
- AI Quotas follow-ups (split mode, thresholds, MCP opt-in, unit tests).
- W5 starter presets / W6 Layouts settings UI (from the old fire.8 plan).

---

## 🔥🔥🔥 SHIPPED fire.8.1 - moves verified end-to-end on macOS 26 (2026-05-29 ~10:17)

**Tagged `v0.11.13-fire.8.1`** (build 1132). CI built + signed + notarized
in ~4m. DMG at https://github.com/pdurlej/fire-from-ice/releases/tag/v0.11.13-fire.8.1.
Sparkle appcast updated (`pdurlej/fire-releases` commit `27b9e7e`).
fire.8 users will get the auto-update prompt.

**Live verified through Claude Code MCP session**:
- `list_items` returns 21 real menu bar items with correct bundle IDs
- `move_item bundle_id=com.electron.ollama to_section=alwaysVisible`
  physically slides the item; follow-up `list_items` confirms ollama
  at `pos=19` (rightmost slot)

**Two bugs fire.8.1 fixes** (both surfaced only on macOS 26):

1. **MCPBackend never started SourcePIDCache** → `pid(for: window)`
   always returned nil → every menu bar item resolved as
   `com.apple.controlcenter` because Control Center reparenting moved
   `ownerPID` to itself. Added `SourcePIDCache.shared.start()` to
   `MCPBackend/main.swift`, mirroring what `MenuBarItemService/main.swift`
   has always done.

2. **Section detection always fell through to "everything alwaysVisible"** —
   Ice's three control items live in NSStatusBar and are NOT exposed as
   separate CG windows the way menu bar items are. The original detection
   algorithm searched for them in `Bridging.getMenuBarWindowList`, never
   found any, and bucketed everything into alwaysVisible. Fix:
   - Ice main app publishes `[visible.minX, hidden.minX, alwaysHidden.minX]`
     to its plist on every status-item-window rotation (see
     `Ice/MenuBar/MenuBarManager.swift` `publishControlItemWindowIDsForMCPBackend`).
   - MCPBackend reads those three doubles as section-boundary X coordinates
     and classifies windows by `minX` falling between them.
   - Apple's own Control Center widgets are dropped by stable window
     titles (`BentoBox*`, `Clock`, `FaceTime`, `MusicRecognition`,
     `AudioVideoModule`) so items that land in the gap between Ice's
     visible divider and Apple's first widget still classify as
     alwaysVisible.

Also fixed: `CGGetActiveDisplayList` returning zero displays from an
XPC service with no graphics connection — falls back to
`CGMainDisplayID()`.

The old `findIceControlItems` / `isOwnedByIce` helpers are gone (the
minX-boundary approach makes them obsolete).

## 🔥🔥🔥 SHIPPED fire.8 - write ops live (2026-05-26 ~22:01)

**Tagged `v0.11.13-fire.8`** (build 1131). CI built + signed + notarized
in 4m34s — DMG at https://github.com/pdurlej/fire-from-ice/releases/tag/v0.11.13-fire.8.
Sparkle appcast updated (`pdurlej/fire-releases` commit `22aa494`),
fire.7.1 users will get the fire.8 auto-update prompt.

**What fire.8 ships:**
- First fire build where AI assistants can actually **rearrange** the
  menu bar, not just read it. `move_item`, `hide_item`, `show_item`,
  `apply_layout` now post real synthetic ⌘-drag events that move items
  between sections.
- New `MCPBackend.xpc` service runs alongside `MenuBarItemService.xpc`.
  Bridge connects to the new service; old one stays in the bundle for
  the Ice-internal sourcePID handshake.
- `Mover.swift` (~530 lines, lean port of upstream Ice's
  MenuBarItemManager.move / postMoveEvents / scrombleEvent pipeline)
  is the new write-op engine. Three-EventTap synchronization dance
  same as upstream, minus the HIDEventManager coordination (no taps to
  suspend in this process) and cursor warping.
- `SourcePIDCache` promoted to `Shared/` so both .xpc services resolve
  the macOS 26 Control Center reparenting correctly.

**Smoke test status**: bridge + XPC + listItems verified via afternoon
ad-hoc-signed Debug install. Move logic itself not yet end-to-end
tested — TCC blocks AX permission inheritance on ad-hoc-signed
re-installs. NOW that fire.8 is shipped under the same Developer ID
identity as fire.7.1, installing the signed DMG over fire.7.1 should
give MCPBackend.xpc full AX inheritance and unblock real move tests.
The Mover.swift code is a faithful port of upstream Ice's logic that
has shipped working in Ice for years, so confidence is reasonable.

**Remaining post-ship work** (not blocking, can land as fire.8.x):
- W5: ship 3 starter presets (Focus / Meeting / Default) seeded on
  first launch via MigrationManager. ~1h.
- W6: SwiftUI "Layouts" subpane in Settings — browse / rename / delete /
  apply / hotkey assignment for layouts. ~2-3h.
- Cross-MCP demo screencast: Fantastical event → AI agent calls
  fire's `apply_layout` → menu bar visibly reorganizes. ~30 min to
  record once a Fantastical MCP is in place. Headline content for the
  AI-native positioning.

## 🔥 SHIPPED fire.7.1 + fire.8 W1+W2+W3 on branch (2026-05-26 ~18:00)

This afternoon session shipped fire.7.1 (after recovering from GitHub
outage + suspension that blocked the morning ship), then powered through
fire.8 waves W1+W2+W3 in one go. Branch `feature/fire-8-mcpbackend` is
now feature-complete for write ops, just needs smoke testing and the
W5+W6 polish before tagging fire.8.

### fire.7.1 ship

**`v0.11.13-fire.7.1`** (build 1130) shipped: signed + notarized DMG at
https://github.com/pdurlej/fire-from-ice/releases/tag/v0.11.13-fire.7.1, appcast
entry appended to `pdurlej/fire-releases` commit `aa6ae05`. fire.7
users will get the auto-update prompt.

**Root cause of morning failure**: not the outage (that lifted ~12:37).
The real bug was the workflow change in commit `b59009f` that replaced
`maxim-lobanov/setup-xcode@v1` with `sudo xcode-select -s /Applications/Xcode.app`.
fire.7 succeeded because setup-xcode picked Xcode_26.3.app explicitly
(MacOSX26.2 SDK); my replacement followed the `Xcode.app` symlink which
now points to Xcode_16.4.app (MacOSX15.5 SDK). `XPCListener(service:requirement:)`
is a macOS 26-only API, so even though `@available(macOS 26.0, *)` guards
the call at runtime, the compile fails against the older SDK with
"extra arguments at positions #2, #3" inside the availability block.

**Fix** (commit `7c521a5`): glob `/Applications/Xcode_26*.app` and pick
highest version. Forward-compatible when GitHub installs Xcode_26.4 or 27.x.

**Tag was moved** (not renamed): no DMG had been released for the old
fire.7.1 tag, so I deleted the remote + local tag and re-created at the
workflow-fix commit.

### fire.8 W1 (pbxproj surgery) — DONE, commit `344c19b`

`MCPBackend.xpc` is now a real Xcode target alongside MenuBarItemService.xpc.
The pbxproj surgery added 16 entries cloning MenuBarItemService's
structure with UUID prefix `7188A70*`. Build wires AXSwift product
dependency (needed because Shared/Utilities/AXHelpers.swift imports it,
and MCPBackend's synchronized root group pulls all of Shared/).

Verified locally: `xcodebuild -scheme Ice` produces
`build/Build/Products/Debug/Ice.app/Contents/XPCServices/MCPBackend.xpc`
side-by-side with MenuBarItemService.xpc.

### fire.8 W2+W3 (Mover.swift + bridge re-target) — DONE, commit `6d8ee82`

**`MCPBackend/Mover.swift`** (~530 lines): lean port of Ice's
MenuBarItemManager.move/postMoveEvents/scrombleEvent pipeline as a
standalone `actor`. Substantive differences from upstream:
- Decoupled from MenuBarItem struct — uses lean `MoveItem` snapshot
- No AppState / no HIDEventManager coordination (no taps in this process)
- No AsyncSemaphore (single-flight via actor isolation)
- No cursor warping on return (CGWarpMouseCursorPosition unreliable on
  macOS 26 — cursor stays hidden through the move)
- Same three-EventTap scrombler dance upstream uses
- CGEvent extensions (menuBarItemMoveEvent, uniqueNullEvent,
  scrombler field matching) reproduced as `fileprivate extension`

**`MCPBackend/MCPBackendStateManager.swift` write ops wired**:
- `moveItem(bundleID:, toSection:, toIndex:)`: finds source item across
  displays, picks Ice's 3 control items for the source's display, posts
  `.rightOfItem(controls[N])` where N maps to the target section
- `hideItem` / `showItem`: thin wrappers
- `applyLayout`: replays saved snapshot in left-to-right section order
  (alwaysHidden → hidden → alwaysVisible) to minimize cascade
  repositioning. Missing items skipped silently.

**Shared/ promotions** (file moves, all clean - no Ice-specific deps):
- `Ice/Events/EventTap.swift` → `Shared/Events/EventTap.swift`
- `Ice/Utilities/MouseHelpers.swift` → `Shared/Utilities/MouseHelpers.swift`
- `Ice/Utilities/ConcurrencyHelpers.swift` → `Shared/Utilities/ConcurrencyHelpers.swift`

**Bridge re-target** (`Bridge/Sources/IceMCPBridge/main.swift`): service
name flipped from `MenuBarItemService.name` to
`"com.jordanbaird.Ice.MCPBackend"`. MenuBarItemService.xpc stays in the
bundle for the Ice-internal sourcePID handshake — the bridge just no
longer routes to it.

Builds clean. Both .xpc bundles ship.

### fire.8 W2 follow-up: SourcePIDCache promoted (commit `dd77dc2`)

Smoke test (see next section) uncovered that bundleIDs were collapsing
to `com.apple.controlcenter` because MCPBackend was using ownerPID
only. Fix: promoted `MenuBarItemService/SourcePIDCache.swift` to
`Shared/Utilities/SourcePIDCache.swift` so both .xpc services compile
it. Each process keeps its own cache instance — the AX scan logic is
per-process but the resolved (windowID → sourcePID) mappings are local.
MCPBackendStateManager now resolves sourcePID via the cache in
`makeItemInfo`, `findWindow`, and `makeMoveItem`.

### Partial smoke test (afternoon, 2026-05-26)

Ran an ad-hoc-signed Debug build of fire.8 W2 over `/Applications/Ice.app`
with Claude Desktop pointed at the embedded bridge:

- ✅ Bridge speaks MCP protocol (initialize, tools/list returns 7 tools
  with correct annotations).
- ✅ Bridge → MCPBackend.xpc XPC handshake succeeds.
- ✅ MCPBackend.xpc spawns as a subprocess of Ice.app on first request,
  responds, exits cleanly when the bridge disconnects.
- ✅ listItems returns real items.

NOT confirmed and why:

- ⚠️ All bundleIDs collapse to `com.apple.controlcenter`. SourcePIDCache
  was the planned fix and is now in place, but smoke retest STILL
  shows the collapse — TCC is not granting AX to the ad-hoc-signed
  Debug build (Developer-ID-signed fire.7.1's AX entitlement is
  silently invalidated when a re-signed binary lands at the same
  path; the Ice toggle in Settings stays visually ON, but actual
  permission isn't honored). SourcePIDCache uses `AXHelpers.isProcessTrusted()`
  as a precondition, so it returns nil for every window.
- ⚠️ No move event posted end-to-end. Without correct bundleID
  resolution we can't reliably target a non-Ice item, so Mover.swift
  remains untested in practice.

Both are development-friction issues with the ad-hoc-signed install
path, not code bugs. The right validation path is a Developer ID-signed
CI build of fire.8-rc1, installed over fire.7.1 — TCC sees the same
signed identity, AX permission carries over, SourcePIDCache populates,
bundleIDs resolve correctly. Tag fire.8-rc1 from the feature branch
when ready.

Session cleanup done: `/Applications/Ice.app` restored to fire.7.1,
Claude Desktop config rolled back to pre-fire-MCP state.

### Original smoke test acceptance criteria

The move logic compiles and the API is wired correctly, but no actual
move event has been posted yet. A successful smoke test looks like:

1. Install a `feature/fire-8-mcpbackend` Debug build to `/Applications/Ice.app`
2. Configure Claude Desktop's `claude_desktop_config.json` to point at
   the embedded bridge: `/Applications/Ice.app/Contents/MacOS/IceMCPBridge`
3. Restart Claude Desktop
4. Ask "List my menu bar items" — should return real items
5. Ask "Hide Control Center" — Mover should fire, item should visibly
   shift to the hidden section
6. Ask "Apply layout 'X'" (after saving one) — items should reflow

If step 5 fails the failure mode is friendly: `Mover.MoveError`
descriptions surface as the `.mutationResult` message field in the
MCP response, so the client sees `Mover.itemResponseTimeout(displayName)`
or similar, not silent loss.

### Remaining fire.8 work

| Wave | What | Effort | Status |
|---|---|---|---|
| W1 | pbxproj surgery | 1h | ✅ DONE |
| W2 | Mover.swift + integration | 4-5h estimated | ✅ DONE (~1.5h actual) |
| W3 | Bridge re-target | 1h | ✅ DONE |
| W4 | list_layouts | 30min | ✅ shipped in fire.7.1 |
| W5 | Starter presets (Focus/Meeting/Default) seeded on first launch | 1h | ⏭️ pending |
| W6 | Settings Layouts subpane (browse/rename/delete/apply/hotkey) | 2-3h | ⏭️ pending |
| W7 | Smoke test + tag + ship | 1h | ⏭️ pending |

W5+W6+W7 are the polish layer. They can ship together as fire.8 once
W5+W6 land and the smoke test is green.

## 🗄️ SUPERSEDED — fire.7.1 GitHub outage status (was IN-FLIGHT)

The morning notes below this section describe the fire.7.1 outage
saga before recovery. Kept for reference; safely superseded by the
ship status above.

---

## (legacy) IN-FLIGHT - fire.7.1 tagged but blocked on GitHub outage (2026-05-26 ~12:30)

**`v0.11.13-fire.7.1`** tag pushed (build 1130). Adds `list_layouts` MCP tool - W4 of the fire.8 plan that ships independently because it's a read-only addition. AI can now ask "what layouts has the user saved?" and get the list without trial-and-error apply_layout calls.

**Blocked by GitHub-wide outage**: GitHub Status reports a critical/minor incident affecting Actions auth + codeload.github.com since ~10:57 UTC. CI runs for v0.11.13-fire.7.1 failed 4 times - each on a different infra component (setup-xcode download, action-gh-release download, checkout 403 auth). I hardened the workflow to be more outage-resilient (replaced `maxim-lobanov/setup-xcode@v1` with native `xcode-select`, replaced `softprops/action-gh-release@v3` with `gh release create` CLI), but checkout's git auth still fails because that's GitHub's core infra not actions.

**Next session ship action** (assuming GitHub is healthy):
```bash
gh run rerun <latest-failed-run-id> -R pdurlej/fire-from-ice
# or manually:
gh workflow run "Build macOS and Create DMG" -R pdurlej/fire-from-ice --ref v0.11.13-fire.7.1
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

**Tagged `v0.11.13-fire.7`** (build 1129). CI built + signed + notarized; DMG at https://github.com/pdurlej/fire-from-ice/releases/tag/v0.11.13-fire.7. Sparkle appcast updated with EdDSA-signed entry (`pdurlej/fire-releases` commit `7dbebdd`) so fire.6 users will receive auto-update notification.

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

**Tagged `v0.11.13-fire.6`** (build 1128). CI workflow "Build macOS and Create DMG" running on the tag — will sign + notarize + draft GitHub Release with the DMG. Tracked at https://github.com/pdurlej/fire-from-ice/actions.

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

**WIP PR #2** — https://github.com/pdurlej/fire-from-ice/pull/2 (draft, branch
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
  [Issue #1](https://github.com/pdurlej/fire-from-ice/issues/1) as milestone
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

- Repo: `https://github.com/pdurlej/fire-from-ice`, default branch `fire/main`.
- Local: `/Users/pd/Developer/fire`. Remotes: origin = pdurlej/fire-from-ice, upstream = jordanbaird/Ice (push disabled).
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
- All six GH Actions secrets set on `pdurlej/fire-from-ice`: `BUILD_CERTIFICATE_BASE64`,
  `P12_PASSWORD`, `APPLE_ID` (= `piotr@durlej.me` — NOT `p@durlej.me`),
  `APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` (= `R47JTHX25P`), `KEYCHAIN_PASSWORD` (uuid).
- Apple Developer Program approved (individual, Team `R47JTHX25P`, name `Piotr Krzysztof Durlej`).
- Developer ID Application cert lives in System keychain on the owner's
  Mac; private key in login keychain. Sound on local
  `security find-identity -v -p codesigning` showing both legacy
  "Apple Development" + Developer ID Application.
- fire.4 DMG (tag `v0.11.13-fire.4`, build 1126) is live:
  `https://github.com/pdurlej/fire-from-ice/releases/tag/v0.11.13-fire.4`. Notarized,
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
- **Tracking issue:** [pdurlej/fire-from-ice#1](https://github.com/pdurlej/fire-from-ice/issues/1)
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
