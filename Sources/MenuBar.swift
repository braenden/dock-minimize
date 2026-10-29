import AppKit
import ServiceManagement

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let minimizer: DockMinimizer

    init(minimizer: DockMinimizer) {
        self.minimizer = minimizer
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "dock.arrow.down.rectangle", accessibilityDescription: "Dock Minimize"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    /// A dimmed icon means clicks are not being handled, either because it is switched off or lacks access.
    func refreshIcon() {
        statusItem.button?.appearsDisabled = !(minimizer.isEnabled && AccessibilityPermission.isGranted)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AccessibilityPermission.isGranted {
            menu.addItem(item("Needs Accessibility access", action: nil))
            menu.addItem(item("Open System Settings…", action: #selector(openAccessibility)))
            menu.addItem(.separator())
        }

        menu.addItem(item("Enabled", action: #selector(toggleEnabled), on: minimizer.isEnabled))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Clicking the active app’s icon"))
        menu.addItem(item("Minimizes its windows", action: #selector(chooseMinimize), on: Settings.action == .minimize))
        menu.addItem(item("Hides it (no animation)", action: #selector(chooseHide), on: Settings.action == .hide))
        menu.addItem(.separator())

        menu.addItem(item("Launch at Login", action: #selector(toggleLaunchAtLogin), on: launchesAtLogin))
        menu.addItem(.separator())
        menu.addItem(item("Quit Dock Minimize", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector?, on: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleEnabled() {
        minimizer.isEnabled.toggle()
        Settings.isEnabled = minimizer.isEnabled
        refreshIcon()
    }

    @objc private func chooseHide() { Settings.action = .hide }
    @objc private func chooseMinimize() { Settings.action = .minimize }
    @objc private func openAccessibility() { AccessibilityPermission.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchesAtLogin {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
