//
//  AdvancedSettings.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
final class AdvancedSettings: ObservableObject {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    @Published var enableAlwaysHiddenSection = false

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    @Published var showAllSectionsOnUserDrag = true

    /// The display style for section divider control items.
    @Published var sectionDividerStyle: SectionDividerStyle = .noDivider

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus = true

    /// A Boolean value that indicates whether to show a context menu
    /// when the user right-clicks the menu bar.
    @Published var enableSecondaryContextMenu = true

    /// The delay before showing on hover.
    @Published var showOnHoverDelay: TimeInterval = 0.2

    /// Time interval to temporarily show items for.
    @Published var tempShowInterval: TimeInterval = 15

    /// A Boolean value that indicates whether the user has opted into
    /// sharing anonymous crash reports with the Fire fork maintainer.
    ///
    /// When `true`, the Sentry SDK is initialized at app launch and
    /// captures crashes (stack trace + thread state + macOS version
    /// + Ice version only — no PII, no menu bar item contents, no
    /// screenshots, no user interactions). When `false` (the default),
    /// Sentry is never initialized and nothing leaves the device.
    ///
    /// This is a Fire-fork-specific addition; upstream Ice has no
    /// crash reporting at all because it predates the maintainer's
    /// Apple Developer Program enrollment.
    @Published var shareDiagnostics = false

    /// A Boolean value that indicates whether the MCP (Model Context
    /// Protocol) server is enabled, allowing external AI assistants
    /// to inspect (and optionally modify) the menu bar layout.
    ///
    /// When `false` (the default), the MCP bridge is never spawned
    /// and no external process can reach Ice's internals. This is a
    /// Fire-fork-specific addition.
    @Published var mcpServerEnabled = false

    /// A Boolean value that indicates whether MCP clients are allowed
    /// to perform write operations (e.g. moving items between sections,
    /// toggling visibility). When `false`, the bridge exposes only
    /// read-only tools.
    @Published var mcpAllowWrites = false

    /// A Boolean value that indicates whether the user should be
    /// notified when an MCP client performs a write operation. Only
    /// relevant when both ``mcpServerEnabled`` and ``mcpAllowWrites``
    /// are `true`.
    @Published var mcpNotifyOnWrite = true

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)
        Defaults.ifPresent(key: .shareDiagnostics, assign: &shareDiagnostics)
        Defaults.ifPresent(key: .mcpServerEnabled, assign: &mcpServerEnabled)
        Defaults.ifPresent(key: .mcpAllowWrites, assign: &mcpAllowWrites)
        Defaults.ifPresent(key: .mcpNotifyOnWrite, assign: &mcpNotifyOnWrite)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableAlwaysHiddenSection)
            }
            .store(in: &c)

        $showAllSectionsOnUserDrag
            .receive(on: DispatchQueue.main)
            .sink { showAll in
                Defaults.set(showAll, forKey: .showAllSectionsOnUserDrag)
            }
            .store(in: &c)

        $sectionDividerStyle
            .receive(on: DispatchQueue.main)
            .sink { style in
                Defaults.set(style.rawValue, forKey: .sectionDividerStyle)
            }
            .store(in: &c)

        $hideApplicationMenus
            .receive(on: DispatchQueue.main)
            .sink { shouldHide in
                Defaults.set(shouldHide, forKey: .hideApplicationMenus)
            }
            .store(in: &c)

        $enableSecondaryContextMenu
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableSecondaryContextMenu)
            }
            .store(in: &c)

        $showOnHoverDelay
            .receive(on: DispatchQueue.main)
            .sink { delay in
                Defaults.set(delay, forKey: .showOnHoverDelay)
            }
            .store(in: &c)

        $tempShowInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .tempShowInterval)
            }
            .store(in: &c)

        $shareDiagnostics
            .receive(on: DispatchQueue.main)
            .sink { share in
                Defaults.set(share, forKey: .shareDiagnostics)
            }
            .store(in: &c)

        $mcpServerEnabled
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .mcpServerEnabled)
            }
            .store(in: &c)

        $mcpAllowWrites
            .receive(on: DispatchQueue.main)
            .sink { allow in
                Defaults.set(allow, forKey: .mcpAllowWrites)
            }
            .store(in: &c)

        $mcpNotifyOnWrite
            .receive(on: DispatchQueue.main)
            .sink { notify in
                Defaults.set(notify, forKey: .mcpNotifyOnWrite)
            }
            .store(in: &c)

        // Ask for notification permission the moment the user turns write
        // notifications on — `dropFirst` skips the value replayed at launch so
        // an upgraded install with the toggle already on doesn't get an
        // out-of-the-blue permission prompt at startup.
        $mcpNotifyOnWrite
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notify in
                if notify {
                    self?.appState?.userNotificationManager.requestAuthorization()
                }
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: - SectionDividerStyle

enum SectionDividerStyle: Int, CaseIterable, Identifiable {
    case noDivider = 0
    case chevron = 1

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noDivider: "None"
        case .chevron: "Chevron"
        }
    }
}
