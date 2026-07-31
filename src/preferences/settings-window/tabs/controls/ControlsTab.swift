import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

/// Coordinator for the Shortcuts section: the recorder rows + the global shortcut registry.
/// Every row edits a preference through `LabelAndControl.makeLabelWithRecorder`; the registry
/// (`shortcuts` dict, `addShortcut` / `removeShortcutIfExists` / `applyShortcutPreference`)
/// keeps the runtime `ATShortcut` model in sync so KeyboardEvents can bind them.
class ControlsTab {
    // MARK: - Public runtime state consumed by other modules

    /// Runtime model of all globally-bound shortcuts, keyed by their identifier
    /// (`holdShortcut`, `nextWindowShortcut`, `previousWindowShortcut`, …). Driven by
    /// `applyShortcutPreference`. Read by KeyboardEvents, KeyRepeatTimer, ATShortcut,
    /// TilesView, CustomRecorderControl, and the conflict detectors.
    static var shortcuts = [String: ATShortcut]()

    /// UI lookup: for any recorder currently displayed in Settings, its (control, label string).
    /// Populated by `LabelAndControl.makeLabelWithRecorder`.
    static var shortcutControls = [String: (CustomRecorderControl, String)]()

    /// Canonical id → localized label for the always-active shortcuts. Single source
    /// of truth: `conflictLabel(_:)` uses it to name a conflicting shortcut.
    static let staticShortcutLabels = [
        "focusWindowShortcut": NSLocalizedString("Focus selected window", comment: ""),
        "previousWindowShortcut": NSLocalizedString("Select previous window", comment: ""),
        "cancelShortcut": NSLocalizedString("Cancel", comment: ""),
        "closeWindowShortcut": NSLocalizedString("Close window", comment: ""),
        "minDeminWindowShortcut": NSLocalizedString("Minimize/Deminimize window", comment: ""),
        "toggleFullscreenWindowShortcut": NSLocalizedString("Fullscreen/Defullscreen window", comment: ""),
        "quitAppShortcut": NSLocalizedString("Quit app", comment: ""),
        "hideShowAppShortcut": NSLocalizedString("Hide/Show app", comment: ""),
    ]
    private static let staticManagedShortcutPreferences = [
        "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut",
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut",
    ]
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let arrowKeyCodes: Set<KeyCode> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]

    // MARK: - Initialization / teardown

    static func initializePreferencesDependentState() {
        applyActiveShortcutPreferences()
        staticManagedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreferenceWithoutDialogs()
        applyVimKeysPreferenceWithoutDialogs()
    }

    static func initTab() -> NSView {
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        let rows: [(String, String, Shortcut?)] = [
            (NSLocalizedString("Select next window", comment: ""), Preferences.indexToName("nextWindowShortcut", 0), Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", 0))),
            (NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut),
            (NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut),
            (NSLocalizedString("Cancel", comment: ""), "cancelShortcut", Preferences.cancelShortcut),
            (NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut),
            (NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut),
            (NSLocalizedString("Fullscreen/Defullscreen window", comment: ""), "toggleFullscreenWindowShortcut", Preferences.toggleFullscreenWindowShortcut),
            (NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut),
            (NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut),
            (NSLocalizedString("Hold to trigger switcher", comment: ""), Preferences.indexToName("holdShortcut", 0), Preferences.shortcut(Preferences.indexToName("holdShortcut", 0))),
        ]
        for (label, id, shortcut) in rows {
            // `makeLabelWithRecorder` builds [label, recorder]; the row's left column shows the
            // label, so only the recorder goes on the right — no duplicated text.
            let views = LabelAndControl.makeLabelWithRecorder(label, id, shortcut)
            table.addRow(leftText: label, rightViews: views[1])
        }
        return TableGroupSetView(originalViews: [table], padding: 0, bottomPadding: 0)
    }

    static func cleanup() {
        shortcutControls.removeAll()
    }

    // MARK: - Preference-change routing

    static func preferenceChanged(_ key: String) {
        switch key {
        case "shortcutCount":
            applyActiveShortcutPreferences()
        case let k where isShortcutPreferenceKey(k):
            if Preferences.nameToIndex(k) < Preferences.shortcutCount {
                applyShortcutPreference(k)
            } else {
                removeShortcutIfExists(k)
            }
        case let k where staticManagedShortcutPreferences.contains(k):
            applyShortcutPreference(k)
        case "arrowKeysEnabled":
            applyArrowKeysPreferenceWithoutDialogs()
        case "vimKeysEnabled":
            applyVimKeysPreferenceWithoutDialogs()
        default:
            break
        }
    }

    // MARK: - Shortcut registry (global keyboard binding)

    private static func applyActiveShortcutPreferences() {
        (0..<Preferences.maxShortcutCount).forEach { index in
            ["holdShortcut", "nextWindowShortcut"].forEach { base in
                let key = Preferences.indexToName(base, index)
                if index < Preferences.shortcutCount {
                    applyShortcutPreference(key)
                } else {
                    removeShortcutIfExists(key)
                }
            }
        }
    }

    private static func applyShortcutPreference(_ controlId: String) {
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            removeShortcutIfExists(controlId)
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            applyHoldShortcutPreference(controlId)
            applyShortcutPreference(Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(controlId)))
            return
        }
        guard let shortcut = combinedShortcut(controlId) else {
            removeShortcutIfExists(controlId)
            restrictModifiersOfHoldShortcut(controlId, [])
            return
        }
        addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, shortcut, controlId, nil)
        restrictModifiersOfHoldShortcut(controlId, [shortcut.modifierFlags])
    }

    private static func applyHoldShortcutPreference(_ controlId: String) {
        let i = Preferences.nameToIndex(controlId)
        guard let shortcut = Preferences.shortcut(controlId) else {
            removeShortcutIfExists(controlId)
            return
        }
        addShortcut(.up, .global, shortcut, controlId, i)
    }

    private static func combinedShortcut(_ controlId: String) -> Shortcut? {
        guard let baseShortcut = Preferences.shortcut(controlId) else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    private static func combineShortcuts(_ holdShortcut: Shortcut?, _ baseShortcut: Shortcut) -> Shortcut {
        guard let holdShortcut else { return baseShortcut }
        return Shortcut(code: baseShortcut.keyCode, modifierFlags: [holdShortcut.modifierFlags, baseShortcut.modifierFlags], characters: baseShortcut.characters, charactersIgnoringModifiers: baseShortcut.charactersIgnoringModifiers)
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId)
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
            ControlsTab.toggleNativeCommandTabIfNeeded()
        }
        recomputeEscapeAbsorption()
    }

    /// Issue #5585. The shared cghidEventTap absorbs Esc keyDown only when a configured shortcut
    /// binds Escape; otherwise Esc passes through to the active app unchanged.
    static func recomputeEscapeAbsorption() {
        KeyboardEvents.anyShortcutUsesEscape = shortcuts.values.contains { $0.shortcut.carbonKeyCode == kVK_Escape }
    }

    /// Thin adapter over `NativeHotkeyResolver.resolve` — builds the snapshot inputs from the live
    /// shortcut registry and applies the resolver's verdict via the symbolic-hotkey API.
    static func toggleNativeCommandTabIfNeeded() {
        let snapshots = shortcuts.values.map { ShortcutSnapshot(modifiers: $0.shortcut.carbonModifierFlags, keyCode: $0.shortcut.carbonKeyCode) }
        let holdShortcutModifiers: [UInt32] = (0..<Preferences.holdShortcut.count).compactMap { i in
            shortcuts[Preferences.indexToName("holdShortcut", i)]?.shortcut.carbonModifierFlags
        }
        let result = NativeHotkeyResolver.resolve(shortcuts: snapshots, holdShortcutModifiers: holdShortcutModifiers)
        setNativeCommandTabEnabled(false, Array(result.disable))
        setNativeCommandTabEnabled(true, Array(result.enable))
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            let i = Preferences.nameToIndex(controlId)
            guard let shortcut = Preferences.shortcut(controlId) else {
                removeShortcutIfExists(controlId)
                return
            }
            addShortcut(.up, .global, shortcut, controlId, i)
            if let nextWindowShortcut = shortcutControls[Preferences.indexToName("nextWindowShortcut", i)]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newShortcut = combineHoldAndNextWindow(controlId, sender)
            if newShortcut == nil {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
                (sender as! CustomRecorderControl).objectValue = nil
            } else {
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, newShortcut!, controlId, nil)
                restrictModifiersOfHoldShortcut(controlId, [(sender as! CustomRecorderControl).objectValue!.modifierFlags])
            }
        }
    }

    private static func restrictModifiersOfHoldShortcut(_ controlId: String, _ modifiers: NSEvent.ModifierFlags) {
        if controlId.hasPrefix("nextWindowShortcut") {
            let i = Preferences.nameToIndex(controlId)
            if let holdShortcut = shortcutControls[Preferences.indexToName("holdShortcut", i)]?.0 {
                holdShortcut.restrictModifiers(modifiers)
            }
        }
    }

    static func combineHoldAndNextWindow(_ controlId: String, _ sender: NSControl) -> Shortcut? {
        guard let baseShortcut = (sender as! RecorderControl).objectValue else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    private static func applyArrowKeysPreferenceWithoutDialogs() {
        guard Preferences.arrowKeysEnabled else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            return
        }
        if hasArrowKeysConflictWithoutUi() {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            Preferences.set("arrowKeysEnabled", "false", false)
            return
        }
        arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
    }

    private static func hasArrowKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            guard arrowKeyCodes.contains($0.shortcut.keyCode) else { return false }
            return !arrowKeys.contains($0.id)
        }
    }

    private static func applyVimKeysPreferenceWithoutDialogs() {
        guard Preferences.vimKeysEnabled else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            return
        }
        if hasVimKeysConflictWithoutUi() {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            Preferences.set("vimKeysEnabled", "false", false)
            return
        }
        vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
    }

    private static func hasVimKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            if let key = $0.shortcut.characters, vimKeyActions.keys.contains(key) {
                return !vimKeyActions.values.contains($0.id)
            }
            return false
        }
    }

    /// Human-readable label for the action bound to `id`, resolved purely from the model — the id's
    /// shape plus `staticShortcutLabels` — NOT from `shortcutControls`. This is what lets the conflict
    /// dialog name a shortcut that isn't currently displayed.
    static func conflictLabel(_ id: String) -> String? {
        if arrowKeys.contains(id) { return NSLocalizedString("Arrow keys", comment: "") }
        if vimKeyActions.values.contains(id) { return NSLocalizedString("Vim keys", comment: "") }
        if id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut") {
            return NSLocalizedString("Shortcut", comment: "") + " - " + NSLocalizedString("Trigger", comment: "")
        }
        return staticShortcutLabels[id]
    }

    /// Clear the shortcut bound to `id` and let the normal preference-change pipeline reconcile the
    /// registry and UI. Used by the conflict dialog's "Unassign existing shortcut and continue".
    static func unassignShortcut(_ id: String) {
        let keyToClear = (id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut"))
            ? Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(id))
            : id
        Preferences.setShortcut(keyToClear, nil)
        shortcutControls[keyToClear]?.0.objectValue = nil
    }

    private static func removeShortcutIfExists(_ controlId: String) {
        if let atShortcut = shortcuts[controlId] {
            if atShortcut.scope == .global {
                KeyboardEvents.removeGlobalShortcut(controlId, atShortcut.shortcut)
            }
            shortcuts.removeValue(forKey: controlId)
            if atShortcut.scope == .global {
                ControlsTab.toggleNativeCommandTabIfNeeded()
            }
            recomputeEscapeAbsorption()
        }
    }

    private static func isShortcutPreferenceKey(_ key: String) -> Bool {
        return (0..<Preferences.maxShortcutCount).contains(where: { index in
            ["holdShortcut", "nextWindowShortcut"].contains { key == Preferences.indexToName($0, index) }
        })
    }
}
