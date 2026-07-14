//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import AppKit
import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            switch itemManager.cacheState {
            case .idle, .loading:
                loadingMenuBarItems
            case .repairingControlItem:
                repairingControlItem
            case .ready:
                IceForm(spacing: 20) {
                    header
                    if itemManager.itemCache.managedItems.isEmpty {
                        noMenuBarItems
                    } else {
                        layoutBars
                    }
                }
            case .missingControlItem:
                missingControlItem
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        IceSection {
            VStack(spacing: 3) {
                Text("Drag to arrange your menu bar items into different sections.")
                    .font(.title3.bold())
                Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Fire cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var repairingControlItem: some View {
        VStack {
            Text("Repairing Fire's menu bar registration…")
            ProgressView()
        }
        .font(.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noMenuBarItems: some View {
        ContentUnavailableView(
            "No manageable menu bar items",
            systemImage: "menubar.rectangle",
            description: Text("Open an app with a menu bar item, then try again.")
        )
    }

    @ViewBuilder
    private var missingControlItem: some View {
        ContentUnavailableView {
            Label("Fire cannot see its section dividers", systemImage: "menubar.rectangle")
        } description: {
            Text(
                """
                Your permissions are already granted. Fire can safely refresh its own menu bar \
                registration without changing the arrangement of other apps.
                """
            )
        } actions: {
            HStack {
                Button("Repair and Retry") {
                    Task {
                        await itemManager.repairControlItemRegistration()
                    }
                }
                .accessibilityLabel("Repair Fire menu bar registration and retry")

                Button("Open Menu Bar Settings") {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
                    ) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
                .accessibilityLabel("Open macOS Menu Bar settings")
            }
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }
}
