//
//  AIQuotaManager.swift
//  Ice
//
//  Coordinates the AI Quotas feature: owns the settings, the backend,
//  and the single status item; runs the refresh loop; and handles the
//  dropdown menu actions.
//
//  Local-only: snapshots are held in memory and rendered to the menu
//  bar. Nothing is sent to Sentry, analytics, or MCP.
//

import AppKit
import Combine
import OSLog

@MainActor
final class AIQuotaManager: NSObject, ObservableObject {
    let settings = AIQuotaSettings()

    /// Latest snapshot per provider (in-memory cache).
    @Published private(set) var snapshots: [AIQuotaProvider: AIQuotaSnapshot] = [:]

    private weak var appState: AppState?
    private let statusItemController = AIQuotaStatusItemController()
    private var backend: AIQuotaBackend = CodexBarCLIQuotaBackend()

    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(category: "AIQuotaManager")

    func performSetup(with appState: AppState) {
        self.appState = appState
        settings.performSetup()
        rebuildBackend()
        configureObservers()

        if settings.enableAIQuotas {
            start()
        }
    }

    // MARK: Observers

    private func configureObservers() {
        var c = Set<AnyCancellable>()

        // Master toggle: start/stop the whole feature.
        settings.$enableAIQuotas
            .removeDuplicates()
            .dropFirst() // initial state handled in performSetup
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { start() } else { stop() }
            }
            .store(in: &c)

        // Interval change: restart the loop with the new cadence.
        settings.$refreshIntervalSeconds
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, settings.enableAIQuotas else { return }
                restartLoop()
            }
            .store(in: &c)

        // CLI path change: rebuild the backend.
        settings.$codexBarCLIPath
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildBackend()
            }
            .store(in: &c)

        // Enabled-providers / compact change: re-render immediately.
        settings.$enabledProviders
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, settings.enableAIQuotas else { return }
                render()
            }
            .store(in: &c)
        settings.$compactTitle
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, settings.enableAIQuotas else { return }
                render()
            }
            .store(in: &c)

        cancellables = c
    }

    private func rebuildBackend() {
        let path = settings.codexBarCLIPath.isEmpty ? nil : settings.codexBarCLIPath
        backend = CodexBarCLIQuotaBackend(configuredPath: path)
    }

    // MARK: Lifecycle

    private func start() {
        logger.debug("AI Quotas enabled")
        render() // show the item immediately (with "?" until first fetch)
        restartLoop()
    }

    private func stop() {
        logger.debug("AI Quotas disabled")
        refreshTask?.cancel()
        refreshTask = nil
        statusItemController.hide()
    }

    private func restartLoop() {
        refreshTask?.cancel()
        let interval = max(30, settings.refreshIntervalSeconds)
        refreshTask = Task { [weak self] in
            // Immediate first refresh, then every `interval` seconds.
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    // MARK: Refresh

    /// Refreshes all enabled providers, one CLI run at a time. Guards
    /// against overlapping refreshes.
    func refresh() async {
        guard !isRefreshing else {
            logger.debug("Refresh already in flight, skipping")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = orderedEnabledProviders()
        for provider in providers {
            let snapshot = await backend.fetch(provider: provider)
            snapshots[provider] = snapshot
            render() // progressive update as each provider returns
        }
        render()
    }

    /// The enabled providers in canonical (allCases) order.
    private func orderedEnabledProviders() -> [AIQuotaProvider] {
        AIQuotaProvider.allCases.filter { settings.enabledProviders.contains($0) }
    }

    // MARK: Rendering

    private func render() {
        let providers = orderedEnabledProviders()
        let title = AIQuotaMenuBuilder.title(
            for: providers, snapshots: snapshots, compact: settings.compactTitle
        )
        let menu = AIQuotaMenuBuilder.menu(
            for: providers,
            snapshots: snapshots,
            backendAvailable: backend.isAvailable,
            target: self,
            refreshAction: #selector(menuRefreshNow),
            openSettingsAction: #selector(menuOpenSettings),
            installCLIAction: #selector(menuInstallCLI)
        )
        statusItemController.show(title: title, menu: menu)
    }

    // MARK: Menu actions

    @objc private func menuRefreshNow() {
        Task { await refresh() }
    }

    @objc private func menuOpenSettings() {
        appState?.openWindow(.settings)
    }

    @objc private func menuInstallCLI() {
        // Point the user at where to get CodexBar; the settings pane has
        // the custom-path field.
        appState?.openWindow(.settings)
        if let url = URL(string: "https://github.com/Asummon/codexbar") {
            NSWorkspace.shared.open(url)
        }
    }
}
