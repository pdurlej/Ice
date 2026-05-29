//
//  AIQuotaSettings.swift
//  Ice
//
//  Settings model for the AI Quotas feature. Follows Ice's settings
//  convention: @Published properties, loadInitialState() from Defaults,
//  configureCancellables() persisting each change back to Defaults.
//

import Combine
import Foundation
import OSLog

@MainActor
final class AIQuotaSettings: ObservableObject {
    /// Master switch. Off by default — the feature is opt-in.
    @Published var enableAIQuotas = false

    /// Seconds between automatic refreshes.
    @Published var refreshIntervalSeconds: Double = 300

    /// Providers to fetch + display. Defaults to all four.
    @Published var enabledProviders: Set<AIQuotaProvider> = Set(AIQuotaProvider.allCases)

    /// When true, drop the leading "AI " prefix in the menu-bar title.
    @Published var compactTitle = false

    /// Optional explicit path to the CodexBar CLI binary. Empty = auto.
    @Published var codexBarCLIPath = ""

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(category: "AIQuotaSettings")

    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    private func loadInitialState() {
        Defaults.ifPresent(key: .enableAIQuotas, assign: &enableAIQuotas)
        Defaults.ifPresent(key: .aiQuotaRefreshIntervalSeconds, assign: &refreshIntervalSeconds)
        Defaults.ifPresent(key: .aiQuotaCompactTitle, assign: &compactTitle)
        Defaults.ifPresent(key: .aiQuotaCodexBarCLIPath, assign: &codexBarCLIPath)
        // Persist the DISABLED set, not the enabled set: an empty/absent
        // disabled set means "all providers on", so a provider added in a
        // later release (e.g. antigravity) shows up automatically for
        // existing users instead of being silently excluded by a stale
        // persisted enabled-list.
        if let raw = Defaults.array(forKey: .aiQuotaDisabledProviders) as? [String] {
            let disabled = Set(raw.compactMap(AIQuotaProvider.init(rawValue:)))
            enabledProviders = Set(AIQuotaProvider.allCases).subtracting(disabled)
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAIQuotas
            .sink { Defaults.set($0, forKey: .enableAIQuotas) }
            .store(in: &c)

        $refreshIntervalSeconds
            .sink { Defaults.set($0, forKey: .aiQuotaRefreshIntervalSeconds) }
            .store(in: &c)

        $compactTitle
            .sink { Defaults.set($0, forKey: .aiQuotaCompactTitle) }
            .store(in: &c)

        $codexBarCLIPath
            .sink { Defaults.set($0, forKey: .aiQuotaCodexBarCLIPath) }
            .store(in: &c)

        $enabledProviders
            .sink { providers in
                let disabled = Set(AIQuotaProvider.allCases).subtracting(providers)
                Defaults.set(disabled.map(\.rawValue).sorted(), forKey: .aiQuotaDisabledProviders)
            }
            .store(in: &c)

        cancellables = c
    }
}
