//
//  MCPWriteAuthorization.swift
//  Ice
//
//  Main-app authorization gate for MCP write commands (fire.9.8).
//
//  WHY (the confused-deputy stopgap)
//  ---------------------------------
//  The file write channel (MCPWriteChannel) cannot be an authorization
//  boundary against a *same-user* process: anything that can drop a
//  syntactically valid command file would otherwise borrow Ice's
//  Accessibility (TCC) grant to mutate the menu bar — the classic
//  "confused deputy". The consent check in IceMCPBridge does not help,
//  because the privileged actor is THIS app, not the bridge.
//
//  Fix: the TCC-bearing main app authorizes every write in its OWN UI
//  before acting. An approval may arm a short in-memory lease so a burst
//  of writes (e.g. apply_layout) isn't N prompts. The lease lives only in
//  memory — never UserDefaults, never a file — so no same-user process can
//  forge or extend it, and there is no persistent "skip approval" knob to
//  flip. The file channel becomes a request queue, not the authority.
//
//  This is a deliberate STOPGAP (GPT-5.5 Pro design review, rank #2). The
//  real fix is a peer-authenticated XPC service with a code-signing
//  requirement (NSXPCListener.setConnectionCodeSigningRequirement, 13+).
//  Until then, unattended/automated MCP writes are intentionally NOT
//  supported through the file channel — they require a human approval.
//

import AppKit
import OSLog

@MainActor
final class MCPWriteAuthorization {
    static let shared = MCPWriteAuthorization()

    /// In-memory only. Never persisted (persisting it would re-open the
    /// bypass: a same-user process could write the key and skip consent).
    private var leaseUntil: Date?
    private let leaseDuration: TimeInterval = 5 * 60

    private let logger = Logger(category: "MCPWriteAuthorization")

    private init() {}

    /// Returns true only on explicit user approval, or while an in-memory
    /// lease the user armed is still active. Presents a blocking, app-modal
    /// alert from the main (TCC-bearing) app otherwise.
    func authorize(_ command: MCPWriteChannel.Command) -> Bool {
        if let leaseUntil, Date() < leaseUntil {
            logger.debug("MCP write allowed by active lease")
            return true
        }

        // Bring the (accessory/LSUIElement) app forward so the prompt is
        // visible above whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow an AI assistant to change your menu bar?"
        alert.informativeText = """
        An MCP client asked Fire to \(Self.describe(command)).

        Fire would do this using its Accessibility permission. Only allow it \
        if you just asked an assistant to rearrange your menu bar.
        """
        // Deny is added first → it is the default button (Return/Esc deny),
        // the safe choice for a security prompt.
        alert.addButton(withTitle: "Deny")               // .alertFirstButtonReturn
        alert.addButton(withTitle: "Allow Once")          // .alertSecondButtonReturn
        alert.addButton(withTitle: "Allow for 5 Minutes") // .alertThirdButtonReturn

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            logger.log("MCP write allowed once for \(command.id, privacy: .public)")
            return true
        case .alertThirdButtonReturn:
            leaseUntil = Date().addingTimeInterval(leaseDuration)
            logger.log("MCP write allowed; armed \(Int(self.leaseDuration))s lease")
            return true
        default:
            logger.log("MCP write denied by user for \(command.id, privacy: .public)")
            return false
        }
    }

    /// Human-readable summary of a command for the consent prompt.
    private static func describe(_ command: MCPWriteChannel.Command) -> String {
        let section: String
        switch command.toSection {
        case "alwaysVisible": section = "the always-visible area"
        case "hidden":        section = "the hidden section"
        case "alwaysHidden":  section = "the always-hidden section"
        default:              section = command.toSection
        }
        switch command.op {
        case "move": return "move “\(command.bundleID)” to \(section)"
        default:     return "\(command.op) “\(command.bundleID)”"
        }
    }
}
