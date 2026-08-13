//
//  FireFeaturePolicy.swift
//  Ice
//

import Foundation

/// Pure policy for keeping Fire's menu bar foundation independent from its
/// optional local-agent and ambient-context features.
struct FireFeaturePolicy: Equatable {
    struct InitialOptionalFeatureState: Equatable {
        let contextsAndAgentsEnabled: Bool
        let mcpServerEnabled: Bool
        let mcpAllowWrites: Bool
    }

    /// Resolves the first rebuild state for optional features. The fire.10.4
    /// migration blanket-enabled legacy MCP flags for every upgrade, so those
    /// values cannot prove intent and are reset when the top-level choice has
    /// not been stored yet. Once the user has made that top-level choice, all
    /// nested configuration is preserved while its runtime is paused.
    static func initialOptionalFeatureState(
        storedContextsAndAgentsEnabled: Bool?,
        storedMCPServerEnabled: Bool?,
        storedMCPAllowWrites: Bool?,
        legacyAIQuotasEnabled: Bool,
        hasStoredTriggers: Bool
    ) -> InitialOptionalFeatureState {
        if let storedContextsAndAgentsEnabled {
            return InitialOptionalFeatureState(
                contextsAndAgentsEnabled: storedContextsAndAgentsEnabled,
                mcpServerEnabled: storedMCPServerEnabled ?? false,
                mcpAllowWrites: storedMCPAllowWrites ?? false
            )
        }

        return InitialOptionalFeatureState(
            contextsAndAgentsEnabled: legacyAIQuotasEnabled || hasStoredTriggers,
            mcpServerEnabled: false,
            mcpAllowWrites: false
        )
    }
}

/// A stopped trigger runtime may reload persisted rules for its settings UI,
/// but it must never evaluate or fire them until the user opts back in.
enum TriggerRuntimePolicy {
    static func shouldEvaluate(isRunning: Bool) -> Bool {
        isRunning
    }
}
