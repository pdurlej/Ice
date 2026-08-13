# Fire MCP Architecture

This document describes the implementation shipped on the stable Fire lineage
and the 10.8 Safe Core candidate. Historical socket, Keychain-per-client, and
bundle-ID migration designs are not current behavior.

## Runtime path

```text
MCP client
  ↕ stdio
IceMCPBridge (embedded executable)
  ↕ authenticated XPC, caller-side deadline
MCPBackend.xpc (policy, request queue, consent wait limits)
  ↕ relayFetch / relayComplete
Fire main app (user consent and menu bar mutation)
  ↕ authenticated XPC, caller-side deadline
MenuBarItemService.xpc (AX/source-PID work)
```

- `IceMCPBridge` implements the MCP tools and translates requests to the shared
  `MenuBarItemService.Request` wire types.
- `MCPBackend.xpc` is the agent-facing listener and authoritative settings gate.
  It refuses all requests unless **Contexts & Agents** and **MCP Server** are
  enabled. Writes additionally require **Allow write operations**.
- `MCPRelayPump` in the main app fetches queued consent work. The main app owns
  every Fire-authored approval prompt and performs approved mutations through
  the shared coordinator.
- `MenuBarItemService.xpc` performs the AX/source-PID work needed by the core
  menu bar runtime. It is not an agent-facing bypass.

## Consent and persistence

There is no per-client Keychain consent record.

- Read access is controlled by the two explicit top-level settings gates.
- Direct writes require the write toggle and a Fire-authored approval prompt.
- Approved automations are sealed with an HMAC key stored in Keychain. The seal
  binds the exact normalized condition and action; changing either invalidates
  the grant and requires approval again.
- Disabling Contexts & Agents stops the optional runtime but preserves settings,
  automation definitions, and sealed grants.

## Peer authentication

Signed releases apply `.isFromSameTeam()` on both listener and client whenever
the process has a Team Identifier. Ad-hoc builds have no meaningful same-team
identity; they log that limitation and still retain settings and consent gates.
The bundle identifier remains `com.jordanbaird.Ice` so TCC, Sparkle, Sentry, and
the signed XPC lineage remain continuous.

## Failure boundaries

macOS 26 `XPCSession.sendSync` has no native timeout. Fire wraps every remaining
synchronous client call in `XPCSyncDeadline`:

- blocking sends run on dedicated concurrent queues;
- session locks protect creation and replacement only;
- the caller returns a bounded error at the request-specific deadline;
- the exact wedged session is cancelled and the next request creates a new one;
- late replies are discarded.

The MenuBarItemService process also caps global AX messaging to 0.5 seconds.
Release acceptance still requires a kill-STOP test against both XPC services;
compilation alone is not proof of recovery.

## Tools and safety

The bridge currently exposes read tools for items, layouts, and automations,
plus write tools for moving/hiding/showing items, saving/applying layouts, and
installing/removing automations. Tool annotations describe read-only,
destructive, and idempotent behavior, but annotations are hints rather than an
authorization boundary. The settings gates and Fire-owned consent remain the
authority.

All quota snapshots, menu bar contents, prompts, and automation definitions stay
local. Sentry is separate, opt-in crash reporting and is configured not to send
screenshots, view hierarchy, default PII, network breadcrumbs, or usage traces.
