import AppKit
import ApplicationServices

/// Inspects and minimizes app windows, and remembers what it minimized so one click can bring it all back.
@MainActor
final class Windows {
    private var minimized: [pid_t: [AXUIElement]] = [:]
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = self?.minimized.removeValue(forKey: pid) }
        }
    }

    /// Whether the app shows a real window on the current Space. Hidden and minimized windows do not count.
    /// Uses the window server rather than Accessibility, so it never waits on the app itself.
    func hasVisibleWindows(_ app: NSRunningApplication) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let pid = Int(app.processIdentifier)
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? Int == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowAlpha as String] as? Double ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            // Some apps keep tiny invisible helper windows on screen.
            return frame.width > 40 && frame.height > 40
        }
    }

    var appsWithMinimizedWindows: [NSRunningApplication] {
        minimized.keys.compactMap(NSRunningApplication.init(processIdentifier:))
    }

    func hasMinimizedWindows(_ app: NSRunningApplication) -> Bool {
        minimized[app.processIdentifier]?.contains(where: \.isMinimized) ?? false
    }

    /// Same as Cmd+H. Goes through Accessibility because `NSRunningApplication.hide()` silently fails
    /// the first time an accessory app calls it.
    func hide(_ app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        element.set(kAXHiddenAttribute, kCFBooleanTrue)
    }

    func minimize(_ app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        guard let all: [AXUIElement] = element.value(kAXWindowsAttribute) else { return }
        var targets = all.filter {
            $0.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole && !$0.isMinimized
        }
        // The focused window goes last so it is also restored last and ends up on top again.
        if let focused = element.element(kAXFocusedWindowAttribute),
           let index = targets.firstIndex(where: { CFEqual($0, focused) }) {
            targets.append(targets.remove(at: index))
        }
        guard !targets.isEmpty else { return }
        for window in targets {
            window.set(kAXMinimizedAttribute, kCFBooleanTrue)
        }
        minimized[app.processIdentifier] = targets
    }

    /// Minimizes again the windows from the last `minimize(_:)` that have been restored since.
    func minimizeRestored(_ app: NSRunningApplication) {
        for window in minimized[app.processIdentifier] ?? [] where !window.isMinimized {
            log.debug("window came back right after minimizing, minimizing it again")
            window.set(kAXMinimizedAttribute, kCFBooleanTrue)
        }
    }

    func restore(_ app: NSRunningApplication) {
        guard let windows = minimized.removeValue(forKey: app.processIdentifier) else { return }
        for window in windows where window.isMinimized {
            window.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        app.activate()
    }
}
