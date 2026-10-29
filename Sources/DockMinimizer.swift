import AppKit
/// Turns a plain click on the Dock icon of the frontmost app into hiding or minimizing it,
/// and a click on an app it minimized into restoring all of that app's windows.
///
/// Everything is decided when the button goes down, before the Dock reacts to the click,
/// and carried out when it comes up, so dragging icons and long-press menus still work untouched.
@MainActor
final class DockMinimizer {
    private enum Intent { case hide, minimize, restore }

    private struct PendingClick {
        let app: NSRunningApplication
        let item: AXUIElement
        let intent: Intent
        let location: CGPoint
        let time: TimeInterval
    }

    /// The Dock starts dragging an icon after a few points of movement and opens its menu on a long press.
    /// Anything beyond these limits is not a plain click.
    private static let maxTravel: CGFloat = 4
    private static let maxDuration: TimeInterval = 0.5

    /// On mouse up the Dock asks the app to reopen, and apps answer by restoring a minimized window.
    /// Minimizing a moment later usually lets that request land first, while the windows are still visible.
    /// When it arrives even later, a second pass puts back whatever it restored.
    private static let reopenDelay: TimeInterval = 0.05
    private static let reopenGrace: TimeInterval = 0.4
    private static let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    var isEnabled: Bool {
        get { tap.isEnabled }
        set {
            tap.isEnabled = newValue
            pending = nil
        }
    }

    private let dock = Dock()
    private let windows = Windows()
    private var pending: PendingClick?
    private var clicks = 0
    private lazy var tap = ClickTap { [unowned self] phase, location, flags in
        switch phase {
        case .down: mouseDown(at: location, flags: flags)
        case .up: mouseUp(at: location)
        }
    }

    func start() -> Bool {
        dock.prepare()
        return tap.start()
    }

    func restart() -> Bool {
        pending = nil
        return tap.restart()
    }

    private func mouseDown(at location: CGPoint, flags: CGEventFlags) {
        pending = nil
        clicks &+= 1
        log.debug("mouse down at \(location.x), \(location.y)")
        guard flags.isDisjoint(with: Self.modifiers),
              let item = dock.applicationItem(at: location),
              let (app, intent) = intent(for: item) else { return }
        log.debug("click on frontmost app icon: \(String(describing: intent), privacy: .public)")
        pending = PendingClick(
            app: app, item: item, intent: intent, location: location,
            time: ProcessInfo.processInfo.systemUptime
        )
    }

    private func intent(for item: AXUIElement) -> (NSRunningApplication, Intent)? {
        if let front = NSWorkspace.shared.frontmostApplication, Dock.item(item, represents: front) {
            if windows.hasVisibleWindows(front) {
                return (front, Settings.action == .minimize ? .minimize : .hide)
            }
            // No windows showing: let the Dock reopen the app as usual, unless we put its windows away ourselves.
            return windows.hasMinimizedWindows(front) ? (front, .restore) : nil
        }
        guard let app = windows.appsWithMinimizedWindows.first(where: { Dock.item(item, represents: $0) }),
              windows.hasMinimizedWindows(app), !windows.hasVisibleWindows(app) else { return nil }
        return (app, .restore)
    }

    private func mouseUp(at location: CGPoint) {
        guard let click = pending else { return }
        pending = nil
        guard hypot(location.x - click.location.x, location.y - click.location.y) <= Self.maxTravel,
              ProcessInfo.processInfo.systemUptime - click.time <= Self.maxDuration,
              click.item.element(kAXShownMenuUIElementAttribute) == nil,
              !click.app.isTerminated else { return }

        switch click.intent {
        case .hide: windows.hide(click.app)
        case .minimize:
            let app = click.app
            let generation = clicks
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reopenDelay) {
                MainActor.assumeIsolated { self.windows.minimize(app) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reopenDelay + Self.reopenGrace) {
                MainActor.assumeIsolated {
                    // Skipped once the user has clicked again, so a deliberate restore is never undone.
                    if self.clicks == generation { self.windows.minimizeRestored(app) }
                }
            }
        case .restore: windows.restore(click.app)
        }
    }
}
