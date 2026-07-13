# Connect local agents to Fire

Fire ships a local stdio MCP server, a diagnostic CLI, and one canonical Agent
Skill inside the compatibility bundle `Ice.app`. Nothing listens on the network.

Paths:

```text
/Applications/Ice.app/Contents/MacOS/IceMCPBridge
/Applications/Ice.app/Contents/MacOS/fire
/Applications/Ice.app/Contents/Resources/AgentSkills/program-fire
```

Prerequisites: macOS 26 or later, Fire installed in `/Applications`, MCP enabled
in Fire Settings → Agents, and write operations enabled when you want an agent
to propose changes. Writes remain subject to Fire's own approval sheet.

## One shared skill

Codex and OpenCode discover personal skills in `~/.agents/skills`; Claude Code
discovers them in `~/.claude/skills`. Point both locations at the same skill
shipped by Fire:

```bash
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
ln -sfn "/Applications/Ice.app/Contents/Resources/AgentSkills/program-fire" \
  "$HOME/.agents/skills/program-fire"
ln -sfn "/Applications/Ice.app/Contents/Resources/AgentSkills/program-fire" \
  "$HOME/.claude/skills/program-fire"
```

This is intentionally one source, not three copied prompts. App updates refresh
the skill behind the stable symlink.

## Codex

Current Codex versions share MCP configuration across the desktop app, CLI, and
IDE extension. Add the local server:

```bash
codex mcp add fire -- /Applications/Ice.app/Contents/MacOS/IceMCPBridge
codex mcp get fire
```

The equivalent `~/.codex/config.toml` entry is:

```toml
[mcp_servers.fire]
command = "/Applications/Ice.app/Contents/MacOS/IceMCPBridge"
default_tools_approval_mode = "writes"
```

Restart the client after editing TOML directly.

## Claude Code

Add Fire as a user-scoped local stdio server:

```bash
claude mcp add --transport stdio --scope user fire -- \
  /Applications/Ice.app/Contents/MacOS/IceMCPBridge
claude mcp get fire
```

Inside Claude Code, `/mcp` shows connection status and `/program-fire` invokes
the shared skill directly.

## OpenCode

Add this entry to the `mcp` object in `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "fire": {
      "type": "local",
      "command": [
        "/Applications/Ice.app/Contents/MacOS/IceMCPBridge"
      ],
      "enabled": true
    }
  },
  "permission": {
    "fire_*": "ask"
  }
}
```

Use `opencode mcp list` to verify it. OpenCode also reads the shared skill from
`~/.agents/skills/program-fire`.

## Claude Desktop and other JSON clients

Use this stdio server entry (the bridge accepts no required arguments):

```json
{
  "mcpServers": {
    "fire": {
      "command": "/Applications/Ice.app/Contents/MacOS/IceMCPBridge",
      "args": []
    }
  }
}
```

## Fire 1.0 tools

- `list_items`: discover items and exact stable selectors.
- `move_item`, `hide_item`, `show_item`: direct approval-gated moves.
- `save_layout`, `apply_layout`, `list_layouts`: manual layout snapshots.
- `set_context`, `list_contexts`, `remove_context`: Context Scenes and Fireline.
- `set_trigger`, `list_triggers`, `remove_trigger`: compatible legacy aliases.

Use `list_items` first and pass its exact selector. A legacy bundle id is
accepted only when it resolves to one manageable item; ambiguity fails closed.

## Diagnose

```bash
/Applications/Ice.app/Contents/MacOS/fire doctor
/Applications/Ice.app/Contents/MacOS/fire capabilities
/Applications/Ice.app/Contents/MacOS/fire items
/Applications/Ice.app/Contents/MacOS/fire contexts
```

`doctor` verifies MCP initialization and a live read through the signed XPC
path. If it reports a same-team/XPC failure, reinstall the signed Fire release;
do not replace the embedded bridge with an ad-hoc build.

Fire itself sends no menu-bar state over the network. The chosen agent may send
tool arguments to its model provider under that agent's normal privacy policy.
