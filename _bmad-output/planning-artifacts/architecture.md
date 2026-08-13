# Fire Rebuild Architecture

## Ownership

- **Core menu bar runtime** remains owned by the existing Ice-derived managers.
- **FireFeaturePolicy** is Foundation-only policy shared with FireLogic tests.
- **AppState** is the composition root and the only owner allowed to start or
  stop optional runtimes.
- Existing MCP and trigger components remain behind the top-level optional
  runtime gate; their nested consent and write gates remain authoritative.

## Invariants

1. Contexts & Agents defaults off unless an explicit legacy opt-in exists.
2. Agent features may depend on core item/quota adapters; core managers must
   never depend on MCP, automations, or future ambient surfaces.
3. Turning optional features off must not delete scenes, grants, preferences,
   or quota configuration.
4. Fireline, context detection, and automatic menu bar rearrangement are not
   part of 10.8.
5. Blocking XPC requests run on dedicated concurrent queues; session locks
   protect only creation and replacement, so deadline cancellation can run.
6. No release promotion is implied by a green local build.

## Verification layers

1. FireLogic policy and security tests.
2. Bridge and all-target compilation.
3. Unsigned local runtime smoke.
4. Signed prerelease install and desktop E2E.
5. Sentry release health, then explicit Latest/appcast promotion.
