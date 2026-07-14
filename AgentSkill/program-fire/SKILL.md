---
name: program-fire
description: Program the local macOS menu bar and Fireline with Fire. Use when the user wants to inspect, show, hide, move, or automate menu bar items; create a Context Scene for an app, time, or battery condition; show Codex or Claude quota near the notch; surface a calendar item while using Mail; diagnose the Fire MCP connection; or recover and remove an installed Fire context. Do not use for Dock, Control Center settings, arbitrary widgets, or remote machines.
---

# Program Fire

Use Fire as the user's local, approval-gated control plane for the menu bar and
the small Fireline surface below the notch. Prefer Fire's MCP tools because they
carry structured exact selectors. Use the embedded `fire` CLI for diagnostics
or when MCP tool discovery is unavailable.

## Workflow

1. Establish local readiness.
   - With a shell, run `/Applications/Ice.app/Contents/MacOS/fire doctor`.
   - If that path is absent, explain that Fire must be installed or updated.
   - If MCP tools are available, call `list_items` as the authoritative
     capability check. Do not infer item identity from screenshots.
2. Discover before proposing.
   - Call `list_items` without a section filter unless the user narrowed it.
   - Preserve the complete `selector` returned for each item.
   - Treat `windowID` as observation only. Never persist or approve by it.
   - Resolve an app-focus bundle id from the installed app, not from memory.
3. Translate the user's intent into one minimal change.
   - For a direct move, use `move_item`, `show_item`, or `hide_item` with the
     exact selector.
   - For contextual behavior, use `set_context` with one supported condition,
     optional exact menu-bar moves, and at most one Fireline payload.
   - Ask only when an item, destination, condition, or quota provider remains
     genuinely ambiguous after discovery.
4. Let Fire own authorization.
   - Describe the intended effect briefly, then make one tool call.
   - Fire authors the exact approval sheet and seals the approved condition,
     selectors, destinations, and Fireline payload.
   - Never simulate approval, edit defaults, call private XPC services, or move
     status items with Accessibility/System Events as a bypass.
5. Verify and hand back control.
   - After installation, call `list_contexts` and confirm the returned Fire
     description matches the request.
   - Explain the activation edge: the condition must change from false to true;
     Fire does not continuously fight manual menu-bar changes.
   - Tell the user the context can be disabled in Fire Settings or removed with
     `remove_context`. Do not remove it unless asked.

## Exact identity rules

- Prefer `selector = {version, namespace, title, source_bundle_id}` copied
  verbatim from `list_items`.
- Use legacy `bundle_id` only when no selector is available. Fire will reject a
  bundle id that matches zero or multiple manageable items.
- Never guess which of several status items from one app the user meant.
- Never restore or recommend caching the live item-frame query. Item geometry
  changes while Fire evaluates hover/click guards.

## Context patterns

### Coding

Resolve the installed coding app's bundle id. Create an `appFocus` context with
`focus_state: active`, `action.type: activateContext`, no menu moves unless the
user requested them, `fireline_type: quota`, and the chosen provider (`codex`
or `claude`). If local quota data is unavailable, report Fire's diagnostic; do
not substitute invented values or a cloud scrape.

### Mail and calendar

Resolve Mail's installed bundle id. Find the exact Fantastical status item with
`list_items`, show the candidates if more than one looks plausible, and use the
user-selected selector. When the user asks to surface or show Fantastical near
the notch, create an `appFocus` context with no menu-bar moves and
`fireline_type: menuBarItem` plus that exact `fireline_selector`. Move the item
to `alwaysVisible` only when the user explicitly asks to change its normal menu
bar section; in that case keep Fireline hidden unless they also request it.

## CLI fallback

The embedded CLI speaks to the same MCP server and does not bypass Fire's
approval path:

```text
/Applications/Ice.app/Contents/MacOS/fire doctor
/Applications/Ice.app/Contents/MacOS/fire capabilities
/Applications/Ice.app/Contents/MacOS/fire items
/Applications/Ice.app/Contents/MacOS/fire contexts
/Applications/Ice.app/Contents/MacOS/fire call <tool> '<json-object>'
```

Prefer native MCP calls over `fire call` when both are available. Shell quoting
is not a reason to switch away from structured tools.

For exact tool fields and examples, read
[references/tool-contract.md](references/tool-contract.md) only when composing
or repairing a direct tool call.

## Stop conditions

Stop without mutation and report the narrow blocker when Fire is not running,
the bridge is missing or rejected by same-team signing, Accessibility access is
missing, item identity stays ambiguous, or the approval is denied. A failed
reviewer, bridge, or helper is not evidence that the requested change happened.
