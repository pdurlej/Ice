//
//  SettingsNavigationIdentifier.swift
//  Ice
//

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case home = "Home"
    case surfaces = "Surfaces"
    case contexts = "Contexts"
    case agents = "Agents"
    case advanced = "Advanced"
    case about = "About"

    var iconResource: IconResource {
        switch self {
        case .home: .systemSymbol("house")
        case .surfaces: .systemSymbol("rectangle.topthird.inset.filled")
        case .contexts: .systemSymbol("wand.and.rays")
        case .agents: .systemSymbol("terminal")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .systemSymbol("flame")
        }
    }
}
