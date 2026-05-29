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
        if let raw = Defaults.array(forKey: .aiQuotaEnabledProviders) as? [String] {
            let providers = raw.compactMap(AIQuotaProvider.init(rawValue:))
            if !providers.isEmpty {
                enabledProviders = Set(providers)
            }
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
                let raw = providers.map(\.rawValue).sorted()
                Defaults.set(raw, forKey: .aiQuotaEnabledProviders)
            }
            .store(in: &c)

        cancellables = c
    }
}
