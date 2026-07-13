//
//  TriggerModels.swift
//  Ice
//
//  AI-Native Triggers (fire.10 P1) — shared data model.
//  See docs/mcp/AI-NATIVE-TRIGGERS.md §0 (hardened per GPT-5.5 Pro review).
//
//  Principle: a trigger is NOT a stored command. It is a stored, sealed,
//  user-approved CAPABILITY with an exact write set. The engine decides WHEN
//  it fires; only the single MenuBarMutationCoordinator may mutate the bar.
//

import Foundation

// MARK: - Section name (wire <-> Ice)

/// Wire section name. Mirrors the MCP wire vocabulary; maps to Ice's
/// `MenuBarSection.Name` (.visible / .hidden / .alwaysHidden).
enum TriggerSection: String, Codable, Equatable, CaseIterable {
    case alwaysVisible
    case hidden
    case alwaysHidden
}

// MARK: - Conditions

/// A predicate over system state that becomes true/false over time.
/// P1 ships only `appFocus`, `batteryBelow`, and `timeWindow` (no calendar,
/// focusMode, wifi, or MCP-fireable `manual` — those are capability tokens,
/// not conditions, and wait for authenticated XPC).
enum TriggerCondition: Codable, Equatable {
    case appFocus(bundleID: String, state: AppFocusState)
    /// Hysteresis is mandatory: fires when crossing below `percent`, resets
    /// only above `resetAbove` (else it flaps at the threshold).
    case batteryBelow(percent: Int, resetAbove: Int)
    case timeWindow(days: Set<Weekday>, start: LocalTime, end: LocalTime, timeZoneID: String)

    enum AppFocusState: String, Codable, Equatable {
        case active
        case inactive
    }
}

enum Weekday: Int, Codable, Equatable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

struct LocalTime: Codable, Equatable {
    let hour: Int    // 0...23
    let minute: Int  // 0...59
}

// MARK: - Actions

/// The exact, resolved action a trigger is approved to perform. Never a bare
/// layout NAME — a name is mutable and would let an approved trigger execute a
/// widened action set later (privilege expansion). Bind to content.
enum TriggerAction: Codable, Equatable {
    case setSection(items: [ItemIdentity], section: TriggerSection)
    /// Fire 1.0 Context Scene: an exact set of optional menu-bar moves plus
    /// one ambient Fireline payload. The whole action is sealed together.
    case activateContext(ContextSceneAction)
    /// Layout bound by content digest. If the layout changes, the trigger is
    /// disabled until re-approved.
    case applyLayoutSnapshot(layoutID: UUID, layoutDigest: String, moves: [MovePlan])

    /// The flattened, exact set of moves this action performs — the "write
    /// set" the approval binds to.
    var writeSet: [MovePlan] {
        switch self {
        case .setSection(let items, let section):
            return items.map { MovePlan(item: $0, toSection: section) }
        case .activateContext(let context):
            return context.moves
        case .applyLayoutSnapshot(_, _, let moves):
            return moves
        }
    }

    /// Whether this action can remain in the pre-1.0 `Triggers` defaults
    /// payload. Fire 10.7.3 decodes that array atomically, so one new enum case
    /// or exact selector would otherwise hide every legacy automation after a
    /// rollback until Fire 1.0 was reinstalled.
    var isLegacyStorageCompatible: Bool {
        switch self {
        case .setSection(let items, _):
            return items.allSatisfy { !$0.isExact }
        case .applyLayoutSnapshot(_, _, let moves):
            return moves.allSatisfy { !$0.item.isExact }
        case .activateContext:
            return false
        }
    }
}

struct ContextSceneAction: Codable, Equatable {
    let moves: [MovePlan]
    let fireline: FirelinePayload
}

enum FirelinePayload: Codable, Equatable {
    case hidden
    case quota(FirelineQuotaProvider)
    case menuBarItem(ItemIdentity)
}

enum FirelineQuotaProvider: String, Codable, Equatable, CaseIterable {
    case codex
    case claude
    case antigravity
    case ollama
}

/// Stable identity for one menu bar item.
///
/// Fire 1.0 persists the existing tag identity (`namespace + title`) so two
/// status items from the same app cannot be confused. `bundleID` remains
/// required for compatibility with pre-1.0 rules and for useful diagnostics.
/// A legacy bundle-only identity is permitted, but execution must reject it if
/// it resolves to zero or multiple manageable items.
struct ItemIdentity: Codable, Equatable {
    let bundleID: String
    let namespace: String?
    let title: String?

    init(bundleID: String, namespace: String? = nil, title: String? = nil) {
        self.bundleID = bundleID
        self.namespace = namespace
        self.title = title
    }

    var isExact: Bool {
        namespace != nil && title != nil
    }

    /// Canonical key used by sealed grants. Legacy identities intentionally
    /// keep the old bundle-only key so existing approvals remain valid.
    var canonicalKey: String {
        guard let namespace, let title else { return bundleID }
        return "v1:\(namespace.utf8.count):\(namespace):\(title.utf8.count):\(title):\(bundleID.utf8.count):\(bundleID)"
    }
}

/// One resolved move in an action plan.
struct MovePlan: Codable, Equatable {
    let item: ItemIdentity
    let toSection: TriggerSection

    /// Compatibility accessor for existing diagnostics and callers.
    var bundleID: String { item.bundleID }

    init(item: ItemIdentity, toSection: TriggerSection) {
        self.item = item
        self.toSection = toSection
    }

    init(bundleID: String, toSection: TriggerSection) {
        self.init(item: ItemIdentity(bundleID: bundleID), toSection: toSection)
    }

    private enum CodingKeys: String, CodingKey {
        case item, bundleID, toSection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let item = try container.decodeIfPresent(ItemIdentity.self, forKey: .item) {
            self.item = item
        } else {
            // Decode grants/layout snapshots written before Fire 1.0.
            self.item = ItemIdentity(bundleID: try container.decode(String.self, forKey: .bundleID))
        }
        self.toSection = try container.decode(TriggerSection.self, forKey: .toSection)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if item.isExact {
            try container.encode(item, forKey: .item)
        } else {
            // Preserve the legacy canonical wire shape for bundle-only rules.
            try container.encode(item.bundleID, forKey: .bundleID)
        }
        try container.encode(toSection, forKey: .toSection)
    }
}

/// P1 ships only edge-on-enter actions; no false-edge reversion (deceptively
/// hard once two triggers touch the same item — deferred to P3).
enum ExitPolicy: Codable, Equatable {
    case none
}

// MARK: - Trigger rule

/// A user-approved automation. Stored as config; "enabled" is NOT authority —
/// the matching sealed `ApprovedAutomationGrant` is.
struct TriggerRule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    /// Bumped on every edit. The grant binds to a specific generation; any
    /// edit invalidates it until re-approved.
    var generation: Int
    var condition: TriggerCondition
    var onEnter: TriggerAction
    var exitPolicy: ExitPolicy
    var priority: Int
    var cooldown: TimeInterval
    var lastFiredAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = false,
        generation: Int = 1,
        condition: TriggerCondition,
        onEnter: TriggerAction,
        exitPolicy: ExitPolicy = .none,
        priority: Int = 0,
        cooldown: TimeInterval = 5,
        lastFiredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.generation = generation
        self.condition = condition
        self.onEnter = onEnter
        self.exitPolicy = exitPolicy
        self.priority = priority
        self.cooldown = cooldown
        self.lastFiredAt = lastFiredAt
    }
}

// MARK: - Sealed approval grant

/// Tamper-evident proof that the user approved a specific automation
/// capability. The canonical bytes are sealed with HMAC-SHA256 using a key in
/// the Keychain (bound to Fire's signing identity), so a same-user process can
/// edit defaults but cannot forge a valid grant. (Sealing/verification lands
/// in the AutomationAuthorization wave.)
struct ApprovedAutomationGrant: Codable, Equatable {
    let triggerID: UUID
    let generation: Int
    /// SHA-256 over the canonical (condition + action + write set).
    let canonicalDigest: String
    /// The exact item moves this grant authorizes.
    let allowedWriteSet: [MovePlan]
    let approvedAt: Date
    let approvedByFireVersion: String
}

// MARK: - Mutation jobs (the single coordinator's unit of work)

/// A typed, source-tagged mutation enqueued to `MenuBarMutationCoordinator`.
/// MCP writes, trigger actions, and UI actions all become jobs — none touch
/// `itemManager.move` directly. The coordinator serializes them (FIFO,
/// non-reentrant), preserving the invariant: every menu-bar mutation passes
/// through exactly one actor.
struct MutationJob: Identifiable {
    enum Source: String { case mcp, trigger, ui }

    let id: UUID
    let source: Source
    /// Set for trigger-sourced jobs, so the coordinator can re-validate the
    /// trigger's grant + generation immediately before executing.
    let triggerID: UUID?
    let triggerGeneration: Int?
    let moves: [MovePlan]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        source: Source,
        triggerID: UUID? = nil,
        triggerGeneration: Int? = nil,
        moves: [MovePlan],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.triggerID = triggerID
        self.triggerGeneration = triggerGeneration
        self.moves = moves
        self.createdAt = createdAt
    }
}

/// The result of executing a `MutationJob`.
struct MutationResult {
    let jobID: UUID
    let success: Bool
    let movedCount: Int
    /// First failure reason, if any.
    let message: String?
}
