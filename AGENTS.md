# AGENTS.md — Fire (Ice fork) working notes

Entry point for coding agents (Codex, and whoever else). Fire is a fork of
jordanbaird/Ice, a macOS 26 menu bar manager, repositioned as AI-native (MCP
server + automations). This file is the fast path; **`HANDOFF.md` has the full
shipped-history and the deep context** — read its "🧭 RESUME HERE" block after
this.

- **Repo:** `pdurlej/fire-from-ice` (GitHub). Always `-R pdurlej/fire-from-ice`
  for `gh`. Branch: **`fire/main`** (not `main`). Local: `/Users/pd/Developer/fire`.
- **Bundle id stays `com.jordanbaird.Ice`**, product `Ice.app`, on purpose (TCC,
  Sentry, appcast version-matching depend on it).
- **Owner (`pdurlej`) runs the shipped build as his DAILY menu bar manager.** Every
  install step below updates his real machine; every Sentry App-Hang is him
  hitting it in normal use. He can test menu-bar behaviour on request — the only
  way to verify the event-handler paths.

## ⏳ PENDING RIGHT NOW (do this first)

**fire.10.7.1 (build 1156) is built, notarized, and installed on the owner's
machine, but NOT on the appcast** — publication is gated on his runtime test of
the menu-bar guards (show-on-hover, show-on-click over empty space vs an icon,
app-menu hover, smart-rehide, ⌘-drag, ctrl-click secondary menu).

- If he says the guards behave **deterministically**: publish the appcast
  (`scripts/publish-appcast.sh v0.11.13-fire.10.7.1 --notes-file <notes.html>`),
  then **close #17** (FIRE-P app-menu AX walk — fixed by the cached app-menu
  frame) and **#4** (P1, below — the peer requirement is now really engaged;
  headless-verified `list_items` works, no XPC rejections). **Leave #7 OPEN**
  (see gotcha #2).
- If a guard still misbehaves: it is almost certainly the **application-menu
  cache** (`Ice/Utilities/MenuBarGeometryCache.swift`, issue #17) being stale or
  dropped for a display — debug there, NOT in the live item query.

## Commands (exact)

```bash
# Build-gate the app (all targets: Ice + MCPBackend.xpc + MenuBarItemService.xpc)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

# The MCP bridge (separate SPM package)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Bridge

# Tests (needs the Xcode toolchain — plain `swift test` lacks XCTest)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path FireLogic  # 29 tests
```

**Ship flow** (per release): bump BOTH `MARKETING_VERSION` (`0.11.13-fire.X`) +
`CURRENT_PROJECT_VERSION` in `Ice.xcodeproj/project.pbxproj` (2 occurrences each)
→ commit → `git tag -a v0.11.13-fire.X` → `git push origin fire/main` + push tag
→ CI (`gh run list -R pdurlej/fire-from-ice`) builds/signs/notarizes/uploads-dSYMs
and publishes the GitHub release → download DMG, `ditto` it over `/Applications/Ice.app`
(quit Ice first), smoke it → **`scripts/publish-appcast.sh v0.11.13-fire.X`** for
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

## Open issues (`gh issue list -R pdurlej/fire-from-ice`)

| # | P | needs | note |
|---|---|---|---|
| 4 | P1 | headless verify | Peer requirement now really engaged (10.7.1). Confirm signed build MCP works, then close. |
| 17 | P2 | owner runtime | FIRE-P fixed by the app-menu cache; close after the 10.7.1 guard test passes. |
| 7 | P2 | design | `isMouseInsideMenuBarItem` live SLS. Do NOT cache (see gotcha #2). If it ever hangs, make the QUERY cheaper. Never fired an App-Hang. |
| 5 | P2 | careful pass | sendSync watchdog. **Deadlock trap** (documented in the issue): `send()` holds an `OSAllocatedUnfairLock`; no native timeout on macOS 26. Needs kill-STOP testing. |
| 11 | P3 | some runtime | remaining LIGHT single main-thread SLS calls (SearchPanel view body, IceBar getOrigin, AppState publisher). |
| 12 | P3 | mixed | undoToken is always null: implement minimal undo (needs consent e2e) or strip it (headless). |
| 13 | P3 | VoiceOver | a11y labels on fork-added UI. |

Shipped from the board so far: #16+#15 (10.4.2), #8+#9 (10.5), #10 (appcast
script), #6+#4+#14 (10.6), #7-cache+#17 (10.7, then #7 reverted in 10.7.1). The
App-Hang franchise (FIRE-F/G/H/K/M/N/P) is field-quiet; FIRE-Q was a false ANR
(open NSMenu) now filtered.
