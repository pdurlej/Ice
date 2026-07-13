# Fire MCP tool contract

Use the schemas returned by `tools/list` as the final authority. This reference
captures the Fire 1.0 workflow and examples; it does not override a newer
runtime schema.

## Read tools

- `list_items({section?})` returns menu bar items and stable selectors.
- `list_contexts({})` returns installed Context Scenes and legacy automations.
- `list_layouts({})` returns saved manual layouts.

## Direct writes

Use the exact `selector` object from `list_items`:

```json
{
  "selector": {
    "version": 1,
    "namespace": "copied namespace",
    "title": "copied title",
    "source_bundle_id": "copied source bundle id"
  },
  "to_section": "alwaysVisible"
}
```

Tools: `move_item`, `show_item`, `hide_item`. `move_item` additionally accepts
`to_index`. The Fire approval path remains authoritative for writes.

## Context Scene

Supported conditions:

- `appFocus`: `bundle_id`, optional `focus_state` (`active` or `inactive`)
- `batteryBelow`: `percent`, optional `reset_above`
- `timeWindow`: `days` (1 Sunday through 7 Saturday), start/end hour and minute,
  optional IANA `time_zone`

Coding example (replace the discovered bundle id):

```json
{
  "name": "Coding",
  "condition": {
    "type": "appFocus",
    "bundle_id": "discovered.bundle.id",
    "focus_state": "active"
  },
  "action": {
    "type": "activateContext",
    "fireline_type": "quota",
    "fireline_provider": "codex"
  }
}
```

Mail example (replace the selector copied from `list_items`):

```json
{
  "name": "Mail + calendar",
  "condition": {
    "type": "appFocus",
    "bundle_id": "com.apple.mail",
    "focus_state": "active"
  },
  "action": {
    "type": "activateContext",
    "selectors": [
      {
        "version": 1,
        "namespace": "copied namespace",
        "title": "copied Fantastical title",
        "source_bundle_id": "copied source bundle id"
      }
    ],
    "section": "alwaysVisible",
    "fireline_type": "hidden"
  }
}
```

Call `set_context` with the object. After the Fire-authored approval completes,
call `list_contexts` and compare name, condition description, action
description, and enabled state. Remove only on explicit request with
`remove_context({"id":"uuid from list_contexts"})`.
