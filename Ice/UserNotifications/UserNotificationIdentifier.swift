//
//  UserNotificationIdentifier.swift
//  Ice
//

/// An identifier for a user notification.
enum UserNotificationIdentifier: String {
    case updateCheck = "UpdateCheck"

    /// Posted after an MCP client successfully changes the menu bar, when
    /// the user has "Notify on write operations" enabled (fire.10.4). A
    /// single stable identifier means a burst of moves (e.g. apply_layout)
    /// coalesces into one updating banner instead of spamming Notification
    /// Center.
    case mcpWrite = "MCPWrite"

    /// Posted once when a competing menu bar manager (Bartender, Hidden Bar,
    /// Dozer…) is detected running alongside Fire (fire.10.6, issue #14).
    case competingManager = "CompetingManager"
}
