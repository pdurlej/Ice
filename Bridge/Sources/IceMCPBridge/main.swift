//
//  main.swift
//  IceMCPBridge — Swift Package executable.
//
//  Wave 2 / Worker A: real MCP server with 6 tools that dispatch to
//  the same `MenuBarItemService` XPC listener Ice itself talks to.
//
//  Architecture
//  ------------
//  Claude Desktop (or any MCP client) launches this binary as an
//  embedded MCP server. It speaks stdio framed JSON-RPC to the client
//  and translates `tools/call` into `MenuBarItemService.Request`
//  enum cases, hands them to a Wave-1 frozen XPC service over
//  `XPCSession`, and unwraps the `MenuBarItemService.Response` back
//  into `CallTool.Result` content.
//
//  Why no `@main`
//  --------------
//  This file is `main.swift`, so SwiftPM treats it as the implicit
//  top-level entry point. Adding `@main` to anything in this target
//  would produce a duplicate-entry-point diagnostic.
//
//  Wire contract — FROZEN
//  ----------------------
//  Do NOT change `MenuBarItemService.Request` / `.Response` shapes
//  here. The file at this target's path is a symlink to
//  ../../../Shared/Services/MenuBarItemService.swift, which is the
//  single source of truth for both the Ice client side and the XPC
//  service side. Worker B (MenuBarStateManager) owns the server-side
//  handlers in `MenuBarItemService/Listener.swift`.
//
//  XPC service name
//  ----------------
//  Read from `MenuBarItemService.name` — NOT hardcoded. Wave 3 may
//  rename it to `…MenuBarItemService.v1`, and this file should not
//  need to be touched when that happens.
//
//  Build
//  -----
//      cd Bridge && swift build -c release
//  Output:
//      Bridge/.build/release/IceMCPBridge
//

import Foundation
import MCP
import OSLog

// MARK: - Logger

/// Subsystem matches Ice's logger conventions so MCP-bridge messages
/// surface alongside everything else when filtering Console.app on the
/// Ice subsystem.
let log = os.Logger(subsystem: "com.jordanbaird.Ice.mcp", category: "bridge")

// MARK: - Section enum bridging

/// Allowed JSON string values for the `section` / `to_section` tool
/// arguments. Mirrors `MenuBarItemService.ItemSection.rawValue` so the
/// generated JSON schemas stay in lockstep with the wire enum.
private let sectionRawValues: [String] = MenuBarItemService.ItemSection.allCases.map(\.rawValue)

/// Parses an `ItemSection` raw value out of an MCP `Value` argument.
/// Returns `nil` if the value is missing or not a string; throws if
/// the value is present but does not match a known section.
private func parseSection(_ value: Value?) throws -> MenuBarItemService.ItemSection? {
    guard let value = value, let raw = value.stringValue else { return nil }
    guard let section = MenuBarItemService.ItemSection(rawValue: raw) else {
        throw ToolError.invalidArgument(
            "section must be one of \(sectionRawValues.joined(separator: ", ")); got \"\(raw)\""
        )
    }
    return section
}

/// Same as `parseSection` but requires a value to be present.
private func parseRequiredSection(_ value: Value?, name: String) throws -> MenuBarItemService.ItemSection {
    guard let section = try parseSection(value) else {
        throw ToolError.invalidArgument("\(name) is required")
    }
    return section
}

private func parseRequiredString(_ value: Value?, name: String) throws -> String {
    guard let value = value, let str = value.stringValue, !str.isEmpty else {
        throw ToolError.invalidArgument("\(name) is required and must be a non-empty string")
    }
    return str
}

private func parseOptionalInt(_ value: Value?) -> Int? {
    guard let value = value else { return nil }
    if let i = value.intValue { return i }
    if let d = value.doubleValue { return Int(d) }
    return nil
}

/// MCP `Value.doubleValue` is a strict case-match — a JSON `30` arrives as
/// `.int` and would silently read as nil. Accept both numeric shapes.
private func parseOptionalDouble(_ value: Value?) -> Double? {
    guard let value = value else { return nil }
    if let d = value.doubleValue { return d }
    if let i = value.intValue { return Double(i) }
    return nil
}

/// Parses an agent-supplied `set_trigger` payload into the wire `TriggerSpec`.
/// Shape validation (presence of `type`) happens here; semantic validation
/// (ranges, enum values, hysteresis) is the main app's job in
/// `TriggerSpecTranslator` — the single trust boundary.
private func parseTriggerSpec(_ arguments: [String: Value]?) throws -> MenuBarItemService.TriggerSpec {
    let name = try parseRequiredString(arguments?["name"], name: "name")

    guard let conditionObj = arguments?["condition"]?.objectValue else {
        throw ToolError.invalidArgument("condition is required (an object with a \"type\")")
    }
    guard let conditionType = conditionObj["type"]?.stringValue else {
        throw ToolError.invalidArgument("condition.type is required")
    }
    let condition = MenuBarItemService.TriggerSpec.ConditionSpec(
        type: conditionType,
        bundleID: conditionObj["bundle_id"]?.stringValue,
        focusState: conditionObj["focus_state"]?.stringValue,
        percent: parseOptionalInt(conditionObj["percent"]),
        resetAbove: parseOptionalInt(conditionObj["reset_above"]),
        days: conditionObj["days"]?.arrayValue?.compactMap { parseOptionalInt($0) },
        startHour: parseOptionalInt(conditionObj["start_hour"]),
        startMinute: parseOptionalInt(conditionObj["start_minute"]),
        endHour: parseOptionalInt(conditionObj["end_hour"]),
        endMinute: parseOptionalInt(conditionObj["end_minute"]),
        timeZoneID: conditionObj["time_zone"]?.stringValue
    )

    guard let actionObj = arguments?["action"]?.objectValue else {
        throw ToolError.invalidArgument("action is required (an object with a \"type\")")
    }
    guard let actionType = actionObj["type"]?.stringValue else {
        throw ToolError.invalidArgument("action.type is required")
    }
    let action = MenuBarItemService.TriggerSpec.ActionSpec(
        type: actionType,
        bundleIDs: actionObj["bundle_ids"]?.arrayValue?.compactMap { $0.stringValue },
        section: actionObj["section"]?.stringValue
    )

    return MenuBarItemService.TriggerSpec(
        name: name,
        condition: condition,
        action: action,
        cooldownSeconds: parseOptionalDouble(arguments?["cooldown_seconds"])
    )
}

// MARK: - Errors

private enum ToolError: Swift.Error, CustomStringConvertible {
    case invalidArgument(String)
    case xpcUnavailable(String)
    case unexpectedResponse(String)
    case failure(String)

    var description: String {
        switch self {
        case .invalidArgument(let m): "invalid argument: \(m)"
        case .xpcUnavailable(let m): "xpc unavailable: \(m)"
        case .unexpectedResponse(let m): "unexpected response: \(m)"
        case .failure(let m): "failure: \(m)"
        }
    }
}

// MARK: - XPC client

/// Sends `MenuBarItemService.Request` values to the Ice XPC service.
///
/// Mirrors the pattern in `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift`:
/// lazy `XPCSession` creation, peer-requirement gated on whether we
/// actually have a Team Identifier (ad-hoc-signed builds otherwise
/// reject themselves — upstream issues #744 / #891), one shared
/// session re-used across requests, recreated on cancel/error.
@available(macOS 26.0, *)
final class XPCClient: @unchecked Sendable {
    private let serviceName: String
    private let queue: DispatchQueue
    private var session: XPCSession?
    private let lock = NSLock()

    init(serviceName: String) {
        self.serviceName = serviceName
        self.queue = DispatchQueue(
            label: "com.jordanbaird.Ice.mcp.xpc",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    private func getOrCreateSession() throws -> XPCSession {
        lock.lock()
        defer { lock.unlock() }
        if let existing = session { return existing }
        let new = try XPCSession(xpcService: serviceName, options: .inactive) { [weak self] error in
            guard let self else { return }
            log.warning("XPC session cancelled: \(error.localizedDescription, privacy: .public)")
            self.lock.lock()
            self.session = nil
            self.lock.unlock()
        }
        if MenuBarItemService.ownTeamIdentifier() != nil {
            new.setPeerRequirement(.isFromSameTeam())
        }
        new.setTargetQueue(queue)
        try new.activate()
        session = new
        return new
    }

    /// Sends a request synchronously and decodes the reply as a
    /// `MenuBarItemService.Response`.
    func send(_ request: MenuBarItemService.Request) throws -> MenuBarItemService.Response {
        let session = try getOrCreateSession()
        do {
            let reply = try session.sendSync(request)
            return try reply.decode(as: MenuBarItemService.Response.self)
        } catch {
            // Drop the session so the next call recreates it after a
            // wire error — matches the connection-recreation pattern
            // in Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift.
            lock.lock()
            self.session = nil
            lock.unlock()
            throw ToolError.xpcUnavailable(error.localizedDescription)
        }
    }
}

// MARK: - JSON encoding helpers

/// Encodes a `Codable` payload to a compact JSON string, suitable to
/// hand back to an MCP client inside `Tool.Content.text`.
private func jsonString<T: Encodable>(_ payload: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{\"error\":\"encoding failed: \(error.localizedDescription)\"}"
    }
}

/// Sentinel mutation-result payload the MCP client sees.
private struct MutationPayload: Encodable {
    let success: Bool
    let undoToken: String?
    let message: String?
}

private struct LayoutSavedPayload: Encodable {
    let success: Bool
    let name: String
    let itemCount: Int
}

private struct TriggerResultPayload: Encodable {
    let success: Bool
    let id: String?
    let enabled: Bool
    let message: String?
}

// MARK: - Tool dispatch

/// Builds one `Tool` descriptor with sensible defaults for the
/// annotations we know about. Older SDKs without `Tool.Annotations`
/// would surface a build error here; current swift-sdk (≥ 0.10) has
/// it. `openWorldHint: false` — every effect is on the local menu bar.
private func makeTool(
    name: String,
    description: String,
    inputSchema: Value,
    readOnly: Bool = false,
    destructive: Bool = false,
    idempotent: Bool = false
) -> Tool {
    Tool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        annotations: Tool.Annotations(
            readOnlyHint: readOnly,
            destructiveHint: destructive,
            idempotentHint: idempotent,
            openWorldHint: false
        )
    )
}

/// Static `tools/list` payload. Schemas use JSON-schema-style
/// object/property notation expressed as MCP `Value` literals.
private func buildToolList() -> [Tool] {
    let sectionEnum: Value = .object([
        "type": .string("string"),
        "enum": .array(sectionRawValues.map { .string($0) }),
        "description": .string(
            "Menu bar section: alwaysVisible (left of the notch / always shown), hidden (between the section dividers), or alwaysHidden (only revealed while holding option)."
        ),
    ])

    let bundleIDProp: Value = .object([
        "type": .string("string"),
        "description": .string(
            "Bundle identifier of the owning app (e.g. com.apple.controlcenter). Use list_items first to discover identifiers."
        ),
    ])

    let listSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "section": sectionEnum,
        ]),
        "additionalProperties": .bool(false),
    ])

    let moveSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "bundle_id": bundleIDProp,
            "to_section": sectionEnum,
            "to_index": .object([
                "type": .string("integer"),
                "minimum": .int(0),
                "description": .string("0-indexed position within the section (left to right). Omit to append."),
            ]),
        ]),
        "required": .array([.string("bundle_id"), .string("to_section")]),
        "additionalProperties": .bool(false),
    ])

    let bundleIDOnlySchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "bundle_id": bundleIDProp,
        ]),
        "required": .array([.string("bundle_id")]),
        "additionalProperties": .bool(false),
    ])

    let layoutNameSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "name": .object([
                "type": .string("string"),
                "minLength": .int(1),
                "description": .string("Layout name as stored in Ice's preferences plist."),
            ]),
        ]),
        "required": .array([.string("name")]),
        "additionalProperties": .bool(false),
    ])

    // MARK: Trigger (automation) schemas — fire.10 P1

    let conditionSchema: Value = .object([
        "type": .string("object"),
        "description": .string(
            "When the automation fires. Provide exactly one condition type and only its fields."
        ),
        "properties": .object([
            "type": .object([
                "type": .string("string"),
                "enum": .array([.string("appFocus"), .string("batteryBelow"), .string("timeWindow")]),
                "description": .string("appFocus: an app gains/loses focus. batteryBelow: battery crosses a threshold. timeWindow: a recurring weekly time range."),
            ]),
            "bundle_id": .object([
                "type": .string("string"),
                "description": .string("appFocus only: the app to watch (e.g. com.tinyspeck.slackmacgap)."),
            ]),
            "focus_state": .object([
                "type": .string("string"),
                "enum": .array([.string("active"), .string("inactive")]),
                "description": .string("appFocus only: fire when the app becomes frontmost (active) or stops being frontmost (inactive). Default active."),
            ]),
            "percent": .object([
                "type": .string("integer"),
                "minimum": .int(1), "maximum": .int(99),
                "description": .string("batteryBelow only: fire when battery drops below this percent."),
            ]),
            "reset_above": .object([
                "type": .string("integer"),
                "minimum": .int(2), "maximum": .int(100),
                "description": .string("batteryBelow only: re-arm only once battery rises above this (hysteresis; must exceed percent). Defaults to percent+10."),
            ]),
            "days": .object([
                "type": .string("array"),
                "items": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(7)]),
                "description": .string("timeWindow only: weekdays, 1=Sunday … 7=Saturday."),
            ]),
            "start_hour": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(23), "description": .string("timeWindow only: window start hour (0–23).")]),
            "start_minute": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(59), "description": .string("timeWindow only: window start minute (0–59). Default 0.")]),
            "end_hour": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(23), "description": .string("timeWindow only: window end hour (0–23).")]),
            "end_minute": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(59), "description": .string("timeWindow only: window end minute (0–59). Default 0.")]),
            "time_zone": .object(["type": .string("string"), "description": .string("timeWindow only: IANA tz id (e.g. Europe/Warsaw). Defaults to the user's current zone.")]),
        ]),
        "required": .array([.string("type")]),
    ])

    let actionSchema: Value = .object([
        "type": .string("object"),
        "description": .string("What the automation does when its condition becomes true."),
        "properties": .object([
            "type": .object([
                "type": .string("string"),
                "enum": .array([.string("setSection")]),
                "description": .string("P1 supports setSection: move one or more items to a section."),
            ]),
            "bundle_ids": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("Bundle ids to move. Use list_items to discover them."),
            ]),
            "section": sectionEnum,
        ]),
        "required": .array([.string("type"), .string("bundle_ids"), .string("section")]),
    ])

    let setTriggerSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "name": .object([
                "type": .string("string"),
                "minLength": .int(1),
                "description": .string("Short human name for the automation (shown in the consent prompt and Fire's Automations settings)."),
            ]),
            "condition": conditionSchema,
            "action": actionSchema,
            "cooldown_seconds": .object([
                "type": .string("number"),
                "minimum": .int(1),
                "description": .string("Minimum seconds between fires. Optional; Fire clamps to 1–3600. Default 5."),
            ]),
        ]),
        "required": .array([.string("name"), .string("condition"), .string("action")]),
        "additionalProperties": .bool(false),
    ])

    let removeTriggerSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("Trigger id (UUID) from list_triggers."),
            ]),
        ]),
        "required": .array([.string("id")]),
        "additionalProperties": .bool(false),
    ])

    return [
        makeTool(
            name: "list_items",
            description: "List menu bar items. Optionally filter to one section. Returns a JSON array of {bundleID, displayName, windowID, section, position, isOnScreen}.",
            inputSchema: listSchema,
            readOnly: true,
            idempotent: true
        ),
        makeTool(
            name: "move_item",
            description: "Move an item identified by bundle_id to a target section, optionally at a specific index within that section.",
            inputSchema: moveSchema,
            destructive: true
        ),
        makeTool(
            name: "hide_item",
            description: "Convenience: move an item to the hidden section.",
            inputSchema: bundleIDOnlySchema,
            destructive: true,
            idempotent: true
        ),
        makeTool(
            name: "show_item",
            description: "Convenience: move an item to the alwaysVisible section.",
            inputSchema: bundleIDOnlySchema,
            destructive: true,
            idempotent: true
        ),
        makeTool(
            name: "apply_layout",
            description: "Apply a previously-saved named layout. Layouts live in Ice's preferences plist.",
            inputSchema: layoutNameSchema,
            destructive: true
        ),
        makeTool(
            name: "save_layout",
            description: "Save the current menu bar arrangement under the given name. Writes to Ice's preferences plist.",
            inputSchema: layoutNameSchema,
            destructive: true,
            idempotent: true
        ),
        makeTool(
            name: "list_layouts",
            description: "List all saved menu bar layout names. Use this first to see what layouts the user has saved (e.g. 'Focus', 'Meeting', 'Default'), then pass a name to apply_layout. Returns an empty array if no layouts are saved yet.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ]),
            readOnly: true,
            idempotent: true
        ),
        // AI-Native Triggers (fire.10 P1). set_trigger / remove_trigger are
        // gated: Fire shows its own consent prompt and binds approval to the
        // exact write set — the tool returns only after the user decides, so a
        // success means the user approved in Fire.
        makeTool(
            name: "set_trigger",
            description: "Propose a menu-bar automation: when a condition becomes true (an app gains/loses focus, battery drops below a threshold, or a weekly time window), move items to a section. Fire shows the user a consent prompt describing exactly what will happen; nothing is installed unless they approve. On success returns {success, id, enabled, message}. Use list_items first to find bundle ids.",
            inputSchema: setTriggerSchema,
            destructive: false
        ),
        makeTool(
            name: "list_triggers",
            description: "List the user's installed menu-bar automations. Returns a JSON array of {id, name, enabled, conditionDescription, actionDescription}. Use the id with remove_trigger.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ]),
            readOnly: true,
            idempotent: true
        ),
        makeTool(
            name: "remove_trigger",
            description: "Remove an installed automation by id (from list_triggers). Fire asks the user to confirm before deleting. Returns {success, id, message}.",
            inputSchema: removeTriggerSchema,
            destructive: true,
            idempotent: true
        ),
    ]
}

/// Dispatches a single `tools/call` to the XPC service and turns the
/// response into a `CallTool.Result` payload.
@available(macOS 26.0, *)
private func dispatch(
    name: String,
    arguments: [String: Value]?,
    xpc: XPCClient
) -> CallTool.Result {
    // Truncated debug log — never log full argument values, which could
    // contain user-supplied layout names.
    let argsSummary = arguments?.keys.sorted().joined(separator: ",") ?? ""
    log.debug("tool=\(name, privacy: .public) args=[\(argsSummary, privacy: .public)]")

    do {
        let request: MenuBarItemService.Request
        switch name {
        case "list_items":
            let section = try parseSection(arguments?["section"])
            request = .listItems(section: section)

        case "move_item":
            let bundleID = try parseRequiredString(arguments?["bundle_id"], name: "bundle_id")
            let toSection = try parseRequiredSection(arguments?["to_section"], name: "to_section")
            let toIndex = parseOptionalInt(arguments?["to_index"])
            request = .moveItem(bundleID: bundleID, toSection: toSection, toIndex: toIndex)

        case "hide_item":
            let bundleID = try parseRequiredString(arguments?["bundle_id"], name: "bundle_id")
            request = .hideItem(bundleID: bundleID)

        case "show_item":
            let bundleID = try parseRequiredString(arguments?["bundle_id"], name: "bundle_id")
            request = .showItem(bundleID: bundleID)

        case "apply_layout":
            let layoutName = try parseRequiredString(arguments?["name"], name: "name")
            request = .applyLayout(name: layoutName)

        case "save_layout":
            let layoutName = try parseRequiredString(arguments?["name"], name: "name")
            request = .saveLayout(name: layoutName)

        case "list_layouts":
            request = .listLayouts

        case "set_trigger":
            let spec = try parseTriggerSpec(arguments)
            request = .setTrigger(spec: spec)

        case "list_triggers":
            request = .listTriggers

        case "remove_trigger":
            let id = try parseRequiredString(arguments?["id"], name: "id")
            request = .removeTrigger(id: id)

        default:
            throw ToolError.invalidArgument("unknown tool: \(name)")
        }

        let response = try xpc.send(request)
        return encode(response: response, for: name)
    } catch {
        let message: String
        if let toolError = error as? ToolError {
            message = String(describing: toolError)
        } else {
            message = error.localizedDescription
        }
        log.error("tool=\(name, privacy: .public) error=\(message, privacy: .public)")
        return CallTool.Result(
            content: [.text(text: "error: \(message)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

@available(macOS 26.0, *)
private func encode(
    response: MenuBarItemService.Response,
    for toolName: String
) -> CallTool.Result {
    switch response {
    case .items(let items):
        let body = jsonString(items)
        return CallTool.Result(
            content: [.text(text: body, annotations: nil, _meta: nil)],
            isError: false
        )

    case .mutationResult(let success, let undoToken, let message):
        let payload = MutationPayload(success: success, undoToken: undoToken, message: message)
        return CallTool.Result(
            content: [.text(text: jsonString(payload), annotations: nil, _meta: nil)],
            isError: !success
        )

    case .layoutSaved(let layoutName, let itemCount):
        let payload = LayoutSavedPayload(success: true, name: layoutName, itemCount: itemCount)
        return CallTool.Result(
            content: [.text(text: jsonString(payload), annotations: nil, _meta: nil)],
            isError: false
        )

    case .layouts(let names):
        // Just the array of names - simpler structure than items
        // (no per-element metadata). LLM can use this directly to
        // decide which layout to apply_layout next.
        return CallTool.Result(
            content: [.text(text: jsonString(names), annotations: nil, _meta: nil)],
            isError: false
        )

    case .triggerResult(let success, let id, let enabled, let message):
        let payload = TriggerResultPayload(success: success, id: id, enabled: enabled, message: message)
        return CallTool.Result(
            content: [.text(text: jsonString(payload), annotations: nil, _meta: nil)],
            isError: !success
        )

    case .triggers(let summaries):
        return CallTool.Result(
            content: [.text(text: jsonString(summaries), annotations: nil, _meta: nil)],
            isError: false
        )

    case .start, .sourcePID, .relayWork, .relayAck:
        // These cases belong to Ice's own usage of the service (legacy
        // handshake + the fire.10.2 main-app relay) and shouldn't surface
        // from any MCP tool. Treat as a wire-protocol bug.
        log.error("unexpected XPC response for tool \(toolName, privacy: .public): \(String(describing: response), privacy: .public)")
        return CallTool.Result(
            content: [.text(text: "error: unexpected response from XPC service", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

// MARK: - Entry point

/// Runs the server. The whole binary is gated on macOS 26 because the
/// `XPCSession` API and `MenuBarItemService.Connection` we mirror are
/// macOS-26-only — older macOS would have to fall back to the legacy
/// NSXPCConnection plumbing, which Wave 2 does not implement.
@available(macOS 26.0, *)
func run() async throws {
    // fire.8 re-target: connect to MCPBackend.xpc instead of
    // MenuBarItemService.xpc. Both services implement the same wire
    // contract (Shared/Services/MenuBarItemService.swift Request/Response
    // enums), but MCPBackend owns the write-op pipeline carved out in
    // W2. MenuBarItemService.xpc stays in the bundle for the legacy
    // sourcePID handshake from the Ice main app.
    let serviceName = "com.jordanbaird.Ice.MCPBackend"
    let supportedSections = MenuBarItemService.ItemSection.allCases.map(\.rawValue).joined(separator: ", ")

    log.info("IceMCPBridge starting (xpc=\(serviceName, privacy: .public), sections=\(supportedSections, privacy: .public))")

    let xpc = XPCClient(serviceName: serviceName)
    let tools = buildToolList()

    let server = Server(
        name: "fire-mcp",
        version: "1.0.0",
        instructions: """
            Read and modify the macOS menu bar layout managed by the Ice / Fire app.
            Use list_items first to discover bundle IDs, then move_item / hide_item /
            show_item to rearrange them. apply_layout / save_layout work on named
            layouts persisted in Ice's preferences plist.
            """,
        capabilities: Server.Capabilities(
            tools: Server.Capabilities.Tools(listChanged: false)
        )
    )

    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: tools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        dispatch(name: params.name, arguments: params.arguments, xpc: xpc)
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)
    log.info("IceMCPBridge ready; waiting for stdin")

    // Block forever — the SDK's stdio transport stops the receive loop
    // on EOF and the surrounding `await waitUntilCompleted()` returns,
    // at which point the process exits naturally.
    await server.waitUntilCompleted()
    log.info("IceMCPBridge stdio transport closed; exiting")
}

if #available(macOS 26.0, *) {
    try await run()
} else {
    FileHandle.standardError.write(Data("IceMCPBridge requires macOS 26 or newer.\n".utf8))
    exit(78) // EX_CONFIG
}
