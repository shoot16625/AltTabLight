import Cocoa

/// Classic keyboard shortcuts like copy-and-paste are missing without a MainMenu
/// see https://stackoverflow.com/a/3746058/2249756
class MainMenu {
    private static var mainMenu: NSMenu!
    private static var menuItemsWithShortcut = [NSMenuItem: String]()
    private static var editMenuItems = Set<NSMenuItem>()
    private static var toggleState = true
    private static var editToggleState = true

    static func create() {
        mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        App.shared.mainMenu = mainMenu
        rememberMenuItemsWithShortcut()
    }

    static func toggle(_ enabled: Bool) {
        guard toggleState != enabled else { return }
        toggleState = enabled
        for (item, keyEquivalent) in menuItemsWithShortcut {
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
        // toggle() also touches Edit items; keep editToggleState in sync so a
        // following toggleEditMenu(true) doesn't no-op and leave them disabled.
        editToggleState = enabled
    }

    static func toggleEditMenu(_ enabled: Bool) {
        guard editToggleState != enabled else { return }
        editToggleState = enabled
        for item in editMenuItems {
            guard let keyEquivalent = menuItemsWithShortcut[item] else { continue }
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    private static func rememberMenuItemsWithShortcut() {
        guard let items = mainMenu?.items else { return }
        let editSubmenu = items.first { $0.submenu?.title == "Edit" }?.submenu
        var stack: [(NSMenu, Bool)] = [(mainMenu, false)]
        while let (menu, isEdit) = stack.popLast() {
            let isEditMenu = isEdit || menu === editSubmenu
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    menuItemsWithShortcut[item] = item.keyEquivalent
                    if isEditMenu { editMenuItems.insert(item) }
                }
                if let submenu = item.submenu {
                    stack.append((submenu, isEditMenu))
                }
            }
        }
    }

    // MARK: - Menu builders

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "AltTabLight")
        menu.addItem(item("Settings…", "orderFrontPreferencesPanel:", ","))
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item("Show All", "unhideAllApplications:"))
        menu.addItem(.separator())
        menu.addItem(item("Quit AltTabLight", "terminate:", "q"))
        return menuBarItem(menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", "undo:", "z"))
        menu.addItem(item("Redo", "redo:", "Z", [.shift, .command]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", "cut:", "x"))
        menu.addItem(item("Copy", "copy:", "c"))
        menu.addItem(item("Paste", "paste:", "v"))
        menu.addItem(item("Paste and Match Style", "pasteAsPlainText:", "V", [.option, .shift, .command]))
        menu.addItem(item("Delete", "delete:"))
        menu.addItem(item("Select All", "selectAll:", "a"))
        return menuBarItem(menu)
    }

    // MARK: - Helpers

    private static func menuBarItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }
}
