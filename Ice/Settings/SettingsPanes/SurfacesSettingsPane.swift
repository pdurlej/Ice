import SwiftUI

struct SurfacesSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Surface = .menuBar

    private enum Surface: String, CaseIterable, Identifiable {
        case menuBar = "Menu Bar"
        case fireline = "Fireline"
        case behavior = "Behavior"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Surface", selection: $selection) {
                ForEach(Surface.allCases) { surface in
                    Text(surface.rawValue).tag(surface)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .accessibilityLabel("Fire surface settings")

            Divider()

            switch selection {
            case .menuBar:
                MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
            case .fireline:
                FirelineSettingsContent {
                    selection = .behavior
                }
            case .behavior:
                GeneralSettingsPane(settings: appState.settings.general)
            case .appearance:
                MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
            case .shortcuts:
                HotkeysSettingsPane(settings: appState.settings.hotkeys)
            }
        }
    }
}

private struct FirelineSettingsContent: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var contextStore = TriggerStore.shared
    let onOpenBehavior: () -> Void

    private var firelineContexts: [TriggerRule] {
        contextStore.rules.filter {
            guard case .activateContext = $0.onEnter else { return false }
            return true
        }
    }

    var body: some View {
        IceForm {
            IceSection("Fireline") {
                Text("One useful thing, right below the notch or menu bar.")
                    .font(.title2.weight(.semibold))
                Text("Each Context Scene decides whether Fireline stays hidden, shows a local AI quota, or surfaces one exact menu bar item.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 75)
            }

            IceSection("Context control") {
                LabeledContent("Scenes using Fireline") {
                    Text("\(firelineContexts.count)")
                        .monospacedDigit()
                        .accessibilityLabel("\(firelineContexts.count) Context Scenes use Fireline")
                }
                HStack {
                    Button("Open Contexts") {
                        appState.navigationState.settingsNavigationIdentifier = .contexts
                    }
                    Button("Connect an Agent") {
                        appState.navigationState.settingsNavigationIdentifier = .agents
                    }
                }
            }

            IceSection("Hidden Items Bar") {
                Text("The classic rescue surface for hidden menu bar items remains available under Behavior. It is separate from Fireline.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Behavior") {
                    onOpenBehavior()
                }
            }
        }
    }
}
