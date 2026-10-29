import Foundation

enum ClickAction: String {
    /// Minimizes every window of the app into the Dock, the way Windows does it.
    case minimize
    /// Hides the whole app like Cmd+H. Instant, no animation.
    case hide
}

@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    static var action: ClickAction {
        get { defaults.string(forKey: "action").flatMap(ClickAction.init) ?? .minimize }
        set { defaults.set(newValue.rawValue, forKey: "action") }
    }
}
