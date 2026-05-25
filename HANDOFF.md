# HANDOFF — Fire fork + ClaudeBar PR + CodexBar issue + AuditLM

This is for me (Claude) after session compression strips context.
Owner (pdurlej) will tell me to read this in a fresh session.

## ✅ SHIPPED — fire.4 signed + notarized (2026-05-25 23:15)

First fully Developer-ID-signed + Apple-notarized + stapled Fire build is
live. Download URL:
`https://github.com/pdurlej/Ice/releases/download/v0.11.13-fire.4/Ice-v0.11.13-fire.4.dmg`
(4.28 MB, SHA256 `231cbd038fb41242d7a298cdb7d46ac5f0f7c8a05ccef633668a13147a4b0e09`).

Owner installed it (over fire.3) and after `tccutil reset` + re-grant of
Accessibility the menu bar items load correctly.

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

### 3. Fire — community engagement (first comment posted, more pending)

- ✅ **XPC bug class trifecta posted on upstream Ice** (2026-05-25,
  combined audience ~80 thumbs + subscribed users):
  - `#913` → comment id [`4537464216`](https://github.com/jordanbaird/Ice/issues/913#issuecomment-4537464216),
    full technical writeup. Template at `/tmp/fire-913-comment.md`.
  - `#744` → comment id [`4537479624`](https://github.com/jordanbaird/Ice/issues/744#issuecomment-4537479624),
    shorter, explicit "happy to open PR if @jordanbaird wants" offer.
    Template at `/tmp/fire-744-comment.md`.
  - `#891` → comment id [`4537479697`](https://github.com/jordanbaird/Ice/issues/891#issuecomment-4537479697),
    shortest, just connects to siblings. Template at `/tmp/fire-891-comment.md`.
  - All three cross-link each other — Triangle. Anyone hitting one
    finds the others and the DMG.
- Six original drafts at `/tmp/fire-community-comments.md` for `#823,
  #760, #744, #344, #891, #665`. The #744 and #891 ones are now SUPERSEDED
  by the live posts above. Remaining four (`#823, #760, #344, #665`)
  are different bug classes — check those issues are still relevant
  and write fresh comments before sending.
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
