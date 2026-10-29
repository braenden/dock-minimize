import CoreGraphics

/// A listen-only event tap for left mouse clicks. It observes clicks but can never delay, swallow or change them,
/// so the Dock and every other app keep getting exactly the input they always did.
@MainActor
final class ClickTap {
    enum Phase { case down, up }

    var isEnabled = false {
        didSet { if let port { CGEvent.tapEnable(tap: port, enable: isEnabled) } }
    }

    private let handler: (Phase, CGPoint, CGEventFlags) -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping (Phase, CGPoint, CGEventFlags) -> Void) {
        self.handler = handler
    }

    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: clickTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        // The main run loop keeps callbacks on the main thread, and common modes keep them coming while menus are open.
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
        CGEvent.tapEnable(tap: port, enable: isEnabled)
        return true
    }

    /// A tap created before the app got Accessibility access stays deaf even after access is granted,
    /// so it has to be created again.
    func restart() -> Bool {
        if let port {
            CFMachPortInvalidate(port)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        source = nil
        return start()
    }

    fileprivate func receive(_ type: CGEventType, at location: CGPoint, flags: CGEventFlags) {
        switch type {
        case .leftMouseDown: handler(.down, location, flags)
        case .leftMouseUp: handler(.up, location, flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port, isEnabled { CGEvent.tapEnable(tap: port, enable: true) }
        default: break
        }
    }
}

private func clickTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let tap = Unmanaged<ClickTap>.fromOpaque(refcon).takeUnretainedValue()
        let location = event.location
        let flags = event.flags
        MainActor.assumeIsolated { tap.receive(type, at: location, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}
