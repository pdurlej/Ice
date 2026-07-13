//
//  FirelinePanel.swift
//  Ice
//

import AppKit
import Combine
import SwiftUI

/// A single-purpose ambient surface below the notch/menu bar. It deliberately
/// renders one Context payload rather than becoming a dashboard.
@MainActor
final class FirelinePanel: NSPanel {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        title = "Fireline"
        titlebarAppearsTransparent = true
        isMovable = false
        isFloatingPanel = true
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        hasShadow = true
        level = .mainMenu + 1
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        setAccessibilityLabel("Fireline current context")
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard let self, isVisible else { return }
            position(on: NSScreen.main ?? NSScreen.screens.first)
        }
        .store(in: &cancellables)
    }

    func show(sceneName: String, payload: FirelinePayload) {
        guard let appState else { return }
        let view = FirelineContentView(appState: appState, sceneName: sceneName, payload: payload)
        let hosting = NSHostingView(rootView: view)
        hosting.setAccessibilityIdentifier("Fire.Fireline.Content")
        contentView = hosting
        setContentSize(hosting.fittingSize)
        position(on: NSScreen.main ?? NSScreen.screens.first)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        contentView = nil
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let menuBarHeight = screen.getMenuBarHeight() ?? 24
        let y = screen.frame.maxY - menuBarHeight - frame.height - 6
        let lower = screen.frame.minX + 8
        let upper = screen.frame.maxX - frame.width - 8
        let centered = screen.frame.midX - frame.width / 2
        setFrameOrigin(CGPoint(x: centered.clamped(to: lower...max(lower, upper)), y: y))
    }
}

private struct FirelineContentView: View {
    @ObservedObject var appState: AppState
    let sceneName: String
    let payload: FirelinePayload

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(sceneName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Divider().frame(height: 18)

            payloadView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fireline context \(sceneName)")
    }

    @ViewBuilder
    private var payloadView: some View {
        switch payload {
        case .hidden:
            EmptyView()
        case .quota(let provider):
            FirelineQuotaView(manager: appState.aiQuotaManager, provider: provider)
        case .menuBarItem(let identity):
            FirelineItemView(appState: appState, identity: identity)
        }
    }
}

private struct FirelineQuotaView: View {
    @ObservedObject var manager: AIQuotaManager
    let provider: FirelineQuotaProvider

    private var appProvider: AIQuotaProvider? {
        AIQuotaProvider(rawValue: provider.rawValue)
    }

    var body: some View {
        Group {
            if let appProvider {
                let snapshot = manager.snapshots[appProvider]
                HStack(spacing: 6) {
                    Text(appProvider.displayName)
                        .font(.callout.weight(.medium))
                    Text(summary(snapshot))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(snapshot?.error == nil ? .primary : .secondary)
                }
                .task { await manager.refresh(provider: appProvider) }
                .accessibilityLabel("\(appProvider.displayName) limits, \(summary(snapshot))")
            }
        }
    }

    private func summary(_ snapshot: AIQuotaSnapshot?) -> String {
        guard let snapshot else { return "checking…" }
        if snapshot.error != nil { return "unavailable" }
        var parts: [String] = []
        if let session = snapshot.primaryLeftPercent {
            parts.append("\(Int(session.rounded()))% session")
        }
        if let week = snapshot.weeklyLeftPercent {
            parts.append("\(Int(week.rounded()))% week")
        }
        return parts.isEmpty ? "no limit data" : parts.joined(separator: " · ")
    }
}

private struct FirelineItemView: View {
    @ObservedObject var appState: AppState
    let identity: ItemIdentity

    private var item: MenuBarItem? {
        appState.itemManager.itemCache.managedItems.first { candidate in
            let bundleID = candidate.sourceApplication?.bundleIdentifier
                ?? candidate.owningApplication?.bundleIdentifier
            guard bundleID == identity.bundleID else { return false }
            if let namespace = identity.namespace, let title = identity.title {
                return candidate.tag.namespace.description == namespace && candidate.tag.title == title
            }
            return true
        }
    }

    var body: some View {
        Group {
            if let item, let image = appState.imageCache.images[item.tag]?.nsImage {
                Button {
                    click(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: image)
                        Text(item.displayName).font(.callout.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.displayName) menu")
            } else {
                Text("\(identity.title ?? identity.bundleID) unavailable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .task {
                        await appState.itemManager.cacheItemsRegardless()
                        await appState.imageCache.updateCache()
                    }
            }
        }
    }

    private func click(_ item: MenuBarItem) {
        Task {
            if item.isOnScreen {
                try? await appState.itemManager.click(item: item, with: .left)
            } else {
                await appState.itemManager.temporarilyShow(item: item, clickingWith: .left)
            }
        }
    }
}
