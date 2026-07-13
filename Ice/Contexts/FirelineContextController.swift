//
//  FirelineContextController.swift
//  Ice
//

import AppKit
import OSLog

/// Owns the ambient Context Scene surface. Menu-bar mutations remain owned by
/// `MenuBarMutationCoordinator`; this controller only presents the already
/// approved Fireline payload after those mutations succeed.
@MainActor
final class FirelineContextController {
    private weak var appState: AppState?
    private let panel = FirelinePanel()
    private let logger = Logger(category: "Fireline.Context")

    private(set) var activeRuleID: UUID?

    func performSetup(with appState: AppState) {
        self.appState = appState
        panel.performSetup(with: appState)
    }

    func activate(rule: TriggerRule) {
        guard case .activateContext(let context) = rule.onEnter else { return }
        activeRuleID = rule.id

        switch context.fireline {
        case .hidden:
            panel.hide()
        case .quota(let provider):
            panel.show(sceneName: rule.name, payload: .quota(provider))
        case .menuBarItem(let item):
            panel.show(sceneName: rule.name, payload: .menuBarItem(item))
        }
        logger.log("Activated Context Scene \(rule.id, privacy: .public)")
    }

    func deactivate() {
        activeRuleID = nil
        panel.hide()
    }
}
