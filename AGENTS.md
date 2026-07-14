# AGENTS.md — Fire (Ice fork) working notes

Entry point for coding agents (Codex, and whoever else). Fire is a fork of
jordanbaird/Ice, a macOS 26 menu bar manager, repositioned as AI-native (MCP
server + automations). This file is the fast path; **`HANDOFF.md` has the full
shipped-history and deep context** — read its top CURRENT STATE first. The dated
"🧭 RESUME HERE" block is historical context, not current operating truth.

- **Repo:** `pdurlej/fire-from-ice` (GitHub). Always `-R pdurlej/fire-from-ice`
  for `gh`. Branch: **`fire/main`** (not `main`). Local: `/Users/pd/Developer/fire`.
- **Bundle id stays `com.jordanbaird.Ice`**, product `Ice.app`, on purpose (TCC,
  Sentry, appcast version-matching depend on it).
- **Owner (`pdurlej`) runs the shipped build as his DAILY menu bar manager.** Every
  install step below updates his real machine; every Sentry App-Hang is him
  hitting it in normal use. He can test menu-bar behaviour on request — the only
  way to verify the event-handler paths.

## ✅ LIVE NOW / NEXT

**`v1.0.12` “Ignition” (build 1171, release commit `d0a87b2`) is the installed,
signed, notarized GitHub candidate but is NO-SHIP: its Fire-authored consent
modal can remain invisible while the app runs with accessory activation policy.
The fix is being prepared as `v1.0.13` (build 1172). Neither version is on the
Sparkle appcast yet.** The appcast still serves `v0.11.13-fire.10.7.3` (build
1158), so existing Sparkle users have not received Fire 1.0.

The installed `/Applications/Ice.app` passed deep codesign, stapler, Gatekeeper,
preserved the existing TCC identity, and passes `fire doctor` (13 tools),
`contexts`, and `list_triggers`. Its embedded `program-fire` skill is byte-for-byte
identical to the canonical repo skill. Public lint and the full signed/notarized
CI workflow are green. An unanswered Context Scene proposal previously expired
fail-closed in 120.20 s and both reads recovered in under 0.2 s without restarting
the app. `FIRE-V` was a 1.0.9 false App Hang from the expected consent modal;
the capture-time marker shipped in 1.0.10 remains in 1.0.12 and suppresses only
that narrow interval, without suppressing genuine hangs elsewhere. The initial
Sentry CLI query returned zero issues for `com.jordanbaird.Ice@1.0.12+1171`;
The consent-visibility fix, both reference scenes, and a post-scene Sentry
recheck remain the final pre-appcast runtime gates.

**NEXT is a human consent + publish gate:** install and enable the real `Coding`
(Codex quota Fireline) and `Mail` (Fantastical Fireline) Context Scenes one at a
time, verify their runtime behavior, then run
`scripts/publish-appcast.sh v1.0.13 --notes-file docs/releases/1.0.13.html`.
The owner must click the two Fire consent dialogs and the local Sparkle Keychain
prompt. Do not bypass or pre-authorize those gates. After Pages serves 1.0.10,
update this section from candidate to live.

## Commands (exact)

```bash
# Build-gate the app (all targets: Ice + MCPBackend.xpc + MenuBarItemService.xpc)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

# The MCP bridge (separate SPM package)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Bridge

# Tests (needs the Xcode toolchain — plain `swift test` lacks XCTest)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path FireLogic  # 40 tests
```

**Ship flow** (per release): bump BOTH `MARKETING_VERSION` (`1.0.X`) +
`CURRENT_PROJECT_VERSION` in `Ice.xcodeproj/project.pbxproj` (2 occurrences each)
→ commit → `git tag -a v1.0.X` → `git push origin fire/main` + push tag
→ CI (`gh run list -R pdurlej/fire-from-ice`) builds/signs/notarizes/uploads-dSYMs
and publishes the GitHub release → download DMG, `ditto` it over `/Applications/Ice.app`
(quit Ice first), smoke it → **`scripts/publish-appcast.sh v1.0.X`** for
the Sparkle appcast (one Keychain "Allow" for signing; idempotent; `--dry-run`
and `--notes-file` supported).

## Hard rules

- **Do NOT tell the owner to rest / sleep / wrap up** (a documented Opus tic;
  applies to everyone).
- **Owner handles all secrets/tokens/agreements personally.** Never enter API
  tokens. The Sparkle EdDSA key stays in his Keychain — signing is LOCAL, never CI.
- **Oracle** only via the `oracle` MCP wrapper (browser, gpt-5.5-pro); don't rerun
  on timeout (use `oracle-await`).
- Commit trailer for this repo: `Co-Authored-By: <model> <noreply@anthropic.com>`.
- CI GitHub Actions are **SHA-pinned** (tag in a trailing comment). To bump one,
  resolve the SHA via `gh api repos/OWNER/REPO/commits/TAG`.
- **App-Hang model:** Sentry (project `pdurlej/fire`) + dSYM upload in CI means
  each new App Hang symbolicates to a precise stack (FIRE-<letter>). The loop is:
  read the named frame → make a targeted off-main/timeout fix → field-verify by
  the issue going SILENT on the next build. Don't guess; the frame names the organ.

## Gotchas I actually hit (read before repeating)

1. **`log show` is shadowed** by a function in the shell snapshot AND blocked by
   the Bash sandbox. Use the full path `/usr/bin/log show …` and pass
   `dangerouslyDisableSandbox: true` (read-only diagnostics only).
2. **Do NOT cache geometry that changes at guard-evaluation time.** fire.10.7
   cached the menu-bar *item* frames for `isMouseInsideMenuBarItem` (#7); it broke
   show-on-hover/click (lagged / misfired / did nothing) because items move at the
   exact instant the guard runs. Reverted in 10.7.1 — that query stays LIVE. The
   *application-menu* frame cache (#17) is fine because it only changes on app
   switch. `⌘-drag` is the one path that bypasses these guards (useful control).
3. **`SecCodeCopySigningInformation` needs `kSecCSSigningInformation`** or the
   returned dict omits the team id. This silently made `ownTeamIdentifier()`
   return nil for every build since fire.10.2 → `.isFromSameTeam()` was NEVER
   applied (fixed in 10.7.1). If you touch signing/XPC-peer code, verify with a
   standalone `SecCode…` probe against `/Applications/Ice.app`.
4. **`publish-appcast.sh`:** `hdiutil attach -quiet` prints nothing and DMG volume
   names contain spaces — parse the mount point via `-plist` + plistlib (already
   done; don't "simplify" it back to grep).
5. **New source files:** the `Ice`, `MCPBackend`, `MenuBarItemService` targets are
   `PBXFileSystemSynchronizedRootGroup`s — adding/removing a `.swift` file needs
   NO pbxproj edit (`git rm`/create just works). The **Bridge** wire files are
   symlinks to `Shared/Services/…`; edit the Shared source, not the symlink.
6. **Notarization needs the owner's Apple Developer Program License Agreement
   in-effect.** If CI fails with HTTP 403 "agreement missing/expired", the owner
   accepts it at developer.apple.com, then `gh run rerun --failed <run-id>` (no
   code change).
7. **Expected authorization modals need an explicit capture-time marker.** Sentry
   client frames can be unsymbolicated, so `frame.function` matching alone did
   not suppress FIRE-V. `TimedAuthorizationAlert` now increments the
   thread-safe `ExpectedAuthorizationModal` marker around `runModal`; Sentry
   drops only App Hang events while that marker is active. Keep the scope narrow.

## Open issues (`gh issue list -R pdurlej/fire-from-ice`)

| # | P | needs | note |
|---|---|---|---|
| 7 | P2 | design | `isMouseInsideMenuBarItem` live SLS. Do NOT cache (see gotcha #2). If it ever hangs, make the QUERY cheaper. Never fired an App-Hang. |
| 5 | P2 | careful pass | sendSync watchdog. **Deadlock trap** (documented in the issue): `send()` holds an `OSAllocatedUnfairLock`; no native timeout on macOS 26. Needs kill-STOP testing. |
| 11 | P3 | some runtime | remaining LIGHT single main-thread SLS calls (SearchPanel view body, IceBar getOrigin, AppState publisher). |
| 13 | P3 | VoiceOver | a11y labels on fork-added UI. |

Shipped from the board so far: #16+#15 (10.4.2), #8+#9 (10.5), #10 (appcast
script), #6+#4+#14 (10.6), and #17's activation-safe app-menu cache plus signed
MCP verification (#4) in 10.7.2. The #7 item-frame cache shipped in 10.7 and was
reverted in 10.7.1. Issue #12's honest MCP mutation contract shipped in 10.7.3.
The App-Hang franchise (FIRE-F/G/H/K/M/N/P) is field-quiet; FIRE-Q/J are false
modal ANRs that the current filter catches only best-effort.
