import AppKit
import ApplicationServices

/// Finds the Dock icon under a screen point by asking the Dock process alone.
///
/// Hit testing through the system-wide element would instead query whichever app owns the point,
/// which can stall for over a second when that app is busy. The Dock answers in well under a millisecond,
/// and it reports nothing while it is hidden (auto-hide or full screen) because its icons are then off screen.
@MainActor
final class Dock {
    private var process: NSRunningApplication?
    private var element: AXUIElement?

    func applicationItem(at point: CGPoint) -> AXUIElement? {
        guard let dock = resolve() else { return nil }
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit)
        if error != .success && error != .noValue { log.error("Dock hit test failed: \(error.rawValue)") }
        if error == .invalidUIElement || error == .cannotComplete { element = nil }
        guard error == .success, let hit,
              hit.value(kAXSubroleAttribute) as String? == "AXApplicationDockItem" else { return nil }
        return hit
    }

    /// Warms up the connection to the Dock. The very first hit test is otherwise around 60 ms.
    func prepare() {
        _ = applicationItem(at: .zero)
    }

    static func item(_ item: AXUIElement, represents app: NSRunningApplication) -> Bool {
        guard let url: URL = item.value(kAXURLAttribute), let bundleURL = app.bundleURL else {
            return item.value(kAXTitleAttribute) as String? == app.localizedName
        }
        if url.standardizedFileURL.path == bundleURL.standardizedFileURL.path { return true }
        // Paths differ for translocated apps and some aliases, but the bundle stays the same.
        return app.bundleIdentifier != nil && Bundle(url: url)?.bundleIdentifier == app.bundleIdentifier
    }

    private func resolve() -> AXUIElement? {
        if let element, let process, !process.isTerminated { return element }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        self.process = dock
        self.element = element
        return element
    }
}
