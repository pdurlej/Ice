//
//  FireFeaturePolicyTests.swift
//  FireLogicTests
//

import XCTest
@testable import FireLogic

final class FireFeaturePolicyTests: XCTestCase {
    func testFreshInstallDefaultsToMenuBarOnly() {
        XCTAssertEqual(
            FireFeaturePolicy.initialOptionalFeatureState(
                storedContextsAndAgentsEnabled: nil,
                storedMCPServerEnabled: nil,
                storedMCPAllowWrites: nil,
                legacyAIQuotasEnabled: false,
                hasStoredTriggers: false
            ),
            .init(
                contextsAndAgentsEnabled: false,
                mcpServerEnabled: false,
                mcpAllowWrites: false
            )
        )
    }

    func testExplicitStoredChoiceWinsOverLegacySignals() {
        XCTAssertEqual(
            FireFeaturePolicy.initialOptionalFeatureState(
                storedContextsAndAgentsEnabled: false,
                storedMCPServerEnabled: true,
                storedMCPAllowWrites: true,
                legacyAIQuotasEnabled: true,
                hasStoredTriggers: true
            ),
            .init(
                contextsAndAgentsEnabled: false,
                mcpServerEnabled: true,
                mcpAllowWrites: true
            )
        )
    }

    func testLegacyAdvancedUseIsPreserved() {
        let state = FireFeaturePolicy.initialOptionalFeatureState(
            storedContextsAndAgentsEnabled: nil,
            storedMCPServerEnabled: nil,
            storedMCPAllowWrites: nil,
            legacyAIQuotasEnabled: false,
            hasStoredTriggers: true
        )
        XCTAssertTrue(state.contextsAndAgentsEnabled)
        XCTAssertFalse(state.mcpServerEnabled)
        XCTAssertFalse(state.mcpAllowWrites)
    }

    func testLegacyAIQuotasKeepsRuntimeWithoutEnablingMCP() {
        let state = FireFeaturePolicy.initialOptionalFeatureState(
            storedContextsAndAgentsEnabled: nil,
            storedMCPServerEnabled: true,
            storedMCPAllowWrites: true,
            legacyAIQuotasEnabled: true,
            hasStoredTriggers: false
        )
        XCTAssertTrue(state.contextsAndAgentsEnabled)
        XCTAssertFalse(state.mcpServerEnabled)
        XCTAssertFalse(state.mcpAllowWrites)
    }

    func testAutomaticallySeededLegacyMCPDoesNotEnableAnyOptionalFeature() {
        XCTAssertEqual(
            FireFeaturePolicy.initialOptionalFeatureState(
                storedContextsAndAgentsEnabled: nil,
                storedMCPServerEnabled: true,
                storedMCPAllowWrites: true,
                legacyAIQuotasEnabled: false,
                hasStoredTriggers: false
            ),
            .init(
                contextsAndAgentsEnabled: false,
                mcpServerEnabled: false,
                mcpAllowWrites: false
            )
        )
    }
}

final class TriggerRuntimePolicyTests: XCTestCase {
    func testPausedRuntimeDoesNotEvaluateTriggers() {
        XCTAssertFalse(TriggerRuntimePolicy.shouldEvaluate(isRunning: false))
    }

    func testRunningRuntimeEvaluatesTriggers() {
        XCTAssertTrue(TriggerRuntimePolicy.shouldEvaluate(isRunning: true))
    }
}
