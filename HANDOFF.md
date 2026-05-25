# HANDOFF — Fire fork + ClaudeBar PR + CodexBar issue + AuditLM

This is for me (Claude) after session compression strips context.
Owner (pdurlej) will tell me to read this in a fresh session.

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

### 2. Fire — signed builds prep branch

- Branch: `feature/signed-builds-prep` on `pdurlej/Ice`. NOT merged to `fire/main`.
- Contains: rewritten `.github/workflows/build-dmg.yml` for Developer ID signed + notarized flow,
  plus `docs/signed-builds/{SETUP.md, HELPER.md, TROUBLESHOOTING.md}` (~600 lines).
- Workflow needs six GitHub Actions secrets that don't exist yet:
  `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `APPLE_ID`, `APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`, `KEYCHAIN_PASSWORD`.
- Workflow correctly staples the `.app` BEFORE packing the DMG (Caught and fixed during draft —
  the original "staple DMG only" was insufficient because the extracted `.app` ended up unstapled).
- Owner has paid for Apple Developer Program (`p@durlej.me`) and uploaded passport scan via
  `https://developer.apple.com/contact/file-upload/`. Apple ID name was updated to "Piotr Krzysztof Durlej" so it
  matches the passport. Status: waiting for approval (typically 1–3 days for individual EU enrollments).
- Passport expires 2026-12-15 — that's ~6.5 months from now, on the edge of Apple's "6-month minimum" rule.
  If Apple rejects for expiry, fallback is the new (post-2015) Polish national ID card, which is bilingual.
- When approval lands: owner runs through `docs/signed-builds/SETUP.md` step by step, gets a Developer ID
  Application cert, exports to .p12, sets the six secrets, and tags `v0.11.13-fire.4`. CI auto-publishes
  signed + notarized DMG.

### 3. Fire — community engagement (drafts not yet sent)

- Six drafts in `/tmp/fire-community-comments.md` for upstream issues `#823, #760, #744, #344, #891, #665`.
  These should only be posted AFTER the first signed `fire.4` DMG is downloadable — the drafts invite testing,
  and we don't want testers hitting the ad-hoc TCC reset problem.
- The Ice's MenuBarItemService XPC fix (commits `f3ee848` + `b32181f`) is genuinely upstream-bound: it fixes
  upstream issues #744 + #891 (combined ~76 reactions). Worth opening a PR to `jordanbaird/Ice` once we have
  a signed build to point at.

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
2. Apple Dev status: ask whether the enrollment got approved; if yes, walk through
   `docs/signed-builds/SETUP.md` step by step.
3. If owner wants to install AuditLM: that's a ~15-minute path with the commands in this handoff section 6.
4. If owner wants to extend AuditLM with a Claude API adapter: that's a ~1-day side project,
   write a `ClaudeProvider` mirroring its existing OpenAI provider in Rust.

## What NOT to do

- Do not modify `/Applications/Ice.app` directly via the script approach — that broke once mid-session and
  required reinstall. Owner now controls all `Ice.app` launches manually.
- Do not delete `~/Library/Preferences/com.surteesstudios.Bartender.plist` without asking — it has codexbar
  cross-references that we don't fully understand the impact of.
- Do not auto-merge any PR to `fire/main` without owner sign-off.
- Do not post community comments to upstream issues until the first signed Fire build is live.
- Do not `sudo killall WindowServer` (kicks owner to login screen, lose state).
