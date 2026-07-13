# Cross-MCP: calendar-driven menu bar layouts

This is the headline of Fire being an AI-native menu bar manager: your
menu bar reacts to *context* an AI agent reads from a *different* app,
with no app-to-app integration code. A calendar MCP tells the agent what
you're doing; the agent calls Fire's MCP to match your menu bar to it.

Nothing in Fire knows about your calendar, and nothing in your calendar
app knows about Fire. The agent is the glue.

## The idea

```
Fantastical MCP  ──reads──▶  AI agent  ──calls──▶  Fire MCP
  "Meeting at 2pm"            (Claude)             apply_layout("Meeting")
```

When a meeting starts, the agent hides everything noisy. When you're
back to focused work, it restores your full row. You never touch the
menu bar — you just keep your calendar honest.

## Prerequisites

- Fire installed, **Settings → Agents → Enable local MCP server** enabled with
  **Allow approved changes** on.
- A calendar MCP connected to your agent (e.g. Fantastical's MCP).
- Fire's MCP connected to the same agent:
  `claude mcp add --transport stdio --scope user fire -- /Applications/Ice.app/Contents/MacOS/IceMCPBridge`
  (or the Claude Desktop / Cursor config in `CLIENT-SETUP.md`).

## Step 1 — save the layouts you want to switch between

`save_layout` snapshots your *current* menu bar arrangement under a
name. So arrange the bar the way you like it, then save — repeat for
each named layout.

Ask your agent:

> Arrange my menu bar the way I have it now and `save_layout` it as
> "Focus".

Then hide the noisy items and save again:

> Hide Slack, Discord, and Stream Deck, then `save_layout` as "Meeting".

Now `list_layouts` returns `["Focus", "Meeting"]`. (fire.8.4+ can move
items into the Hidden/Always-Hidden sections, so "Meeting" can genuinely
tuck distractions away, not just reorder the visible row.)

## Step 2 — let the agent drive it from your calendar

The orchestration is just a prompt the agent can follow on demand, on a
schedule, or as a standing instruction:

> Check my calendar for the next hour with the Fantastical tools. If a
> meeting is starting, `apply_layout("Meeting")` in Fire. Otherwise make
> sure `apply_layout("Focus")` is active.

The agent:
1. calls the calendar MCP's `queryCalendarItems` for the current window,
2. decides the context (in a meeting vs. heads-down),
3. calls Fire's `apply_layout` with the matching name.

No integration code — the agent reads one MCP and writes another.

## Notes

- `apply_layout` replays each saved item's section assignment in
  left-to-right order (Always-Hidden → Hidden → Always-Visible) to
  minimize re-shuffling. Items recorded in a layout but no longer in the
  menu bar are skipped silently.
- Layouts live in Fire's preferences plist (`MCPLayouts`), local to your
  Mac. Nothing about your layouts or your calendar leaves the device via
  Fire.
- This pattern generalizes: any MCP that exposes context (location,
  focus mode, now-playing, CI status) can drive `apply_layout`. The
  calendar is just the most legible example.
