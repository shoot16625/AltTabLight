import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    static var permissionCalloutMenuItems: [NSMenuItem]?
    private static var permissionCallout: PermissionCallout?
    private static var isVisibleObserver: NSKeyValueObservation?
    private static let menuDelegate = MenubarMenuDelegate()

    @discardableResult
    static func addMenuItem(_ title: String, _ action: Selector, _ keyEquivalent: String, _ symbolName: String?, _ color: NSColor? = nil, _ target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if #available(macOS 26.0, *), let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            if let color {
                item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        }
        return item
    }

    static func initialize() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        menu.delegate = menuDelegate
        let permissionCalloutMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let callout = PermissionCallout()
        permissionCallout = callout
        permissionCalloutMenuItem.view = callout
        let calloutSeparator = NSMenuItem.separator()
        permissionCalloutMenuItems = [permissionCalloutMenuItem, calloutSeparator]
        addMenuItem(NSLocalizedString("Show", comment: "Menubar option"), #selector(App.showUiFromShortcut0), "", "eye", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(NSLocalizedString("Settings…", comment: "Menubar option"), #selector(App.showSettingsWindow), ",", "gear", nil, App.self)
        addMenuItem(NSLocalizedString("Check permissions…", comment: "Menubar option"), #selector(App.checkPermissions), "", "hand.raised", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"), App.name), #selector(NSApplication.terminate(_:)), "q", nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button!.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
        applyMenubarIconPreferences()
        observeRemovalFromMenubar()
    }

    static func refreshPermissionCallout() {
        let dependentFeatures = Preferences.screenRecordingDependentFeatures
        let show = PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: ScreenRecordingPermission.status == .granted,
            dependentFeatures: dependentFeatures)
        if show { permissionCallout?.update(dependentFeatures) }
        togglePermissionCallout(show)
    }

    // NSMenuItem.isHidden isn't reliable with custom views. We add/remove to hide/show these items
    static func togglePermissionCallout(_ show: Bool) {
        permissionCalloutMenuItems?.enumerated().forEach { offset, element in
            if show && !menu.items.contains(element) {
                menu.insertItem(element, at: offset)
            }
            if !show && menu.items.contains(element) {
                menu.removeItem(element)
            }
        }
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.showUiFromShortcut0()
        } else {
            statusItem.menu = Menubar.menu
            statusItem.button?.performClick(nil)
        }
    }

    static func menubarIconCallback(_: NSControl?) {
        guard statusItem != nil else { return }
        applyMenubarIconPreferences()
    }

    static private func applyMenubarIconPreferences() {
        if Preferences.menubarIconShown {
            loadPreferredIcon()
        } else {
            statusItem.isVisible = false
        }
    }

    // The user can ⌘-drag the icon off the menubar (enabled by `.removalAllowed`). When that
    // happens, `isVisible` flips true→false and we persist the preference.
    static private func observeRemovalFromMenubar() {
        statusItem.behavior = .removalAllowed
        isVisibleObserver = statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            if change.oldValue == true && change.newValue == false {
                Preferences.set("menubarIconShown", "false")
            }
        }
    }

    static private func loadPreferredIcon() {
        let i = Preferences.menubarIcon.indexAsString
        let image = NSImage(named: "menubar-\(i)")!
        image.isTemplate = i != "2"
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
    }
}

private final class MenubarMenuDelegate: NSObject, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Menubar.refreshPermissionCallout()
    }
}

class PermissionCallout: StackView {
    private var label: NSTextField!
    private var button: NSButton!

    convenience init() {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.preferredMaxLayoutWidth = 250
        label.isSelectable = false
        label.addOrUpdateConstraint(label.widthAnchor, 250)
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.attributedTitle = NSAttributedString(string: NSLocalizedString("Grant permission", comment: "Menubar callout button"), attributes: [NSAttributedString.Key.foregroundColor: NSColor.white])
        self.init([label, button], .vertical, true, top: 8, right: 15, bottom: 10, left: 15)
        self.label = label
        self.button = button
        wantsLayer = true
        layer!.backgroundColor = NSColor.purple.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard button.frame.contains(location) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        Preferences.remove("screenRecordingPermissionSkipped")
        App.restart()
    }

    // Name only the feature(s) the user actually enabled, so we never promise back a feature they
    // don't use. The wrapped label's height depends on the message, so re-fit after setting it.
    func update(_ dependentFeatures: PermissionCalloutResolver.DependentFeatures) {
        label.stringValue = PermissionCallout.message(dependentFeatures)
        constraints.filter {
            ($0.firstAnchor == widthAnchor || $0.firstAnchor == heightAnchor) && $0.secondAnchor == nil
        }.forEach { $0.isActive = false }
        fit()
    }

    // One reusable sentence template + a feature subject inserted at `%@`, so translators localize the
    // shared sentence (and the spacing/punctuation between its two clauses) once and only the subject
    // varies. The Thumbnails subject reuses the existing appearance-style string, already translated
    // everywhere. `.none` is unreachable here — the callout is hidden when no feature needs it.
    static func message(_ dependentFeatures: PermissionCalloutResolver.DependentFeatures) -> String {
        let subject: String
        switch dependentFeatures {
            case .thumbnails: subject = NSLocalizedString("Thumbnails", comment: "")
            case .previews: subject = NSLocalizedString("Window previews", comment: "Menubar callout subject: the preview-selected-window feature")
            case .both: subject = NSLocalizedString("Thumbnails and window previews", comment: "Menubar callout subject")
            case .none: return ""
        }
        return String(format: NSLocalizedString("AltTabLight is running without Screen Recording permissions. %@ won’t show.", comment: "Menubar callout. %@ is one or more feature names, e.g. Thumbnails"), subject)
    }
}
