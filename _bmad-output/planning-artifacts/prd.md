# Fire 10.8 Safe Core Product Requirements

## Outcome

Fire remains a dependable menu bar manager for users who want only the core
experience, while local AI features are explicit, optional capabilities that
cannot degrade the core runtime.

## Release requirements

1. A fresh install starts in **Menu Bar only** mode.
2. Core hiding, showing, hover/click, appearance, hotkeys, permissions, and
   updates work without starting MCP, trigger evaluation, quota polling, or
   any future ambient UI.
3. **Contexts & Agents** is one explicit opt-in. Existing AI Quotas users and
   users with stored triggers retain that opt-in on migration. Legacy MCP flags
   are reset on the first rebuild launch because fire.10.4 blanket-enabled them
   for upgrades, making them unusable as evidence of user intent.
4. Disabling Contexts & Agents preserves configuration but stops its runtime
   surfaces and background work.
5. Synchronous XPC calls have caller-side deadlines and replace wedged sessions
   without holding the session-state lock through the blocking call.
6. Pull requests run FireLogic, Bridge, and the all-target Xcode build.
7. Every candidate is a prerelease until signed install and desktop E2E pass.
   GitHub Latest and Sparkle appcast promotion remain separate operations.

## Acceptance evidence

- Pure policy tests cover default-off, explicit choice, legacy opt-in migration,
  and stopped trigger behavior.
- FireLogic, Bridge, and all-target Xcode builds pass.
- Kill-STOP testing proves XPC calls return a bounded error and recover.
- Local runtime smoke proves Menu Bar only and Contexts & Agents independently.
- Signed DMG E2E proves clean install, upgrade, restart, permissions, core menu
  bar behavior, optional AI behavior, and rollback before promotion.
