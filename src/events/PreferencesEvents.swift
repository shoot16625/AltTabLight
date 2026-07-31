import Cocoa

/// Side-effect dispatcher for preference changes. Each branch of `preferenceChanged(_:)`
/// calls into a domain-specific owner rather than implementing the side effect inline.
class PreferencesEvents {
    private static var initialized = false
    private static let preferencesRequiringUiReset = [
        "appearanceStyle",
        "appearanceSize",
        "appearanceTheme",
        "showOnScreen",
    ]

    static func initialize() {
        guard !initialized else { return }
        initialized = true
        ControlsTab.initializePreferencesDependentState()
    }

    static func preferenceChanged(_ key: String) {
        if !initialized {
            return
        }
        ControlsTab.preferenceChanged(key)
        switch key {
        case "menubarIcon", "menubarIconShown": applyMenubarPreferencesIfReady()
        case let k where preferencesRequiringUiReset.contains(k) && TilesPanel.shared != nil: App.resetPreferencesDependentComponents()
        default: break
        }
    }

    private static func applyMenubarPreferencesIfReady() {
        guard Menubar.statusItem != nil else { return }
        Menubar.menubarIconCallback(nil)
    }
}
