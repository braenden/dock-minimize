import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let minimizer = DockMinimizer()
    private var menuBar: MenuBar?
    private var permissionObserver: NSObjectProtocol?
    private var hadAccess = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }

        log.info("launched, accessibility: \(AccessibilityPermission.isGranted), enabled: \(Settings.isEnabled)")
        minimizer.isEnabled = Settings.isEnabled
        guard minimizer.start() else {
            let alert = NSAlert()
            alert.messageText = "Dock Minimize can’t listen for clicks"
            alert.informativeText = "Allow it under System Settings > Privacy & Security > Accessibility, then open it again."
            alert.runModal()
            AccessibilityPermission.openSettings()
            NSApp.terminate(nil)
            return
        }

        menuBar = MenuBar(minimizer: minimizer)
        hadAccess = AccessibilityPermission.isGranted

        // The trust flag flips shortly after the notification, so check again a moment later.
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: AccessibilityPermission.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.accessibilityChanged() }
            }
        }
    }

    private func accessibilityChanged() {
        let hasAccess = AccessibilityPermission.isGranted
        if hasAccess && !hadAccess {
            log.info("accessibility granted, restarting click tap: \(self.minimizer.restart())")
        }
        hadAccess = hasAccess
        menuBar?.refreshIcon()
    }
}
