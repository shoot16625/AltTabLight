import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControl: RecorderControl {
    static let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])
    var clearable: Bool!
    /// The preference key this recorder edits. Derived from `identifier` (set in `init`).
    var id: String { identifier!.rawValue }

    convenience init(_ shortcutString: String, _ clearable: Bool, _ id: String) {
        self.init(Shortcut(keyEquivalent: shortcutString), clearable, id)
    }

    convenience init(_ shortcut: Shortcut?, _ clearable: Bool, _ id: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        identifier = NSUserInterfaceItemIdentifier(id)
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        allowsModifierFlagsOnlyShortcut = true
        restrictModifiers([])
        objectValue = shortcut
        addOrUpdateConstraint(widthAnchor, 100)
    }

    override func drawClearButton(_ aDirtyRect: NSRect) {
        if clearable {
            super.drawClearButton(aDirtyRect)
        }
    }

    override func clearAndEndRecording() {
        if clearable {
            super.clearAndEndRecording()
        }
    }

    func restrictModifiers(_ restrictedModifiers: NSEvent.ModifierFlags) {
        set(allowedModifierFlags: CustomRecorderControl.allowedModifiers.subtracting(restrictedModifiers), requiredModifierFlags: [], allowsEmptyModifierFlags: true)
    }

    func alertIfSameShortcutAlreadyAssigned(_ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) {
        let label = ControlsTab.conflictLabel(shortcutAlreadyAssigned) ?? "an unknown action"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to: %@", comment: ""),
                                       label.replacingOccurrences(of: " ", with: "\u{00A0}"))
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        let userChoice = alert.runModal()
        guard userChoice == .alertFirstButtonReturn else { return }
        ControlsTab.unassignShortcut(shortcutAlreadyAssigned)
        updateShortcut(self, candidateShortcut, self, id)
    }

    func updateShortcut(_ control: CustomRecorderControl, _ objectValue: Shortcut?, _ senderControl: NSControl, _ id: String) {
        control.objectValue = objectValue
        LabelAndControl.controlWasChanged(senderControl, id)
        ControlsTab.shortcutChangedCallback(senderControl)
    }

    func alertIfShortcutReservedByMacos(_ candidateShortcut: Shortcut, _ shortcutReservedByMacos: String) {
        let label = ControlsTab.conflictLabel(shortcutReservedByMacos) ?? "an unknown action"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, and ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound. AltTabLight cannot use them.\n\nYour change would assign one of these to: %@.", comment: ""), label)
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runModal()
        guard userChoice == .alertFirstButtonReturn, id != shortcutReservedByMacos else { return }
        ControlsTab.unassignShortcut(shortcutReservedByMacos)
        updateShortcut(self, candidateShortcut, self, id)
    }

    func save(_ candidateShortcut: Shortcut) {
        LabelAndControl.controlWasChanged(self, id)
        // shortcutChangedCallback is called automatically here
        // setting objectValue also happens automatically
    }
}

extension CustomRecorderControl: RecorderControlDelegate {
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        if let conflictId = conflictWithExistingShortcut(shortcut) {
            alertIfSameShortcutAlreadyAssigned(shortcut, conflictId)
        }
        if let reservedByMacosId = shortcutReservedByMacos(shortcut) {
            alertIfShortcutReservedByMacos(shortcut, reservedByMacosId)
        }
        save(shortcut)
        return true
    }

    /// Returns the id of an existing bound shortcut conflicting with `candidate`, if any.
    /// Arrow keys are checked separately because they're hard-bound (no recorder UI).
    private func conflictWithExistingShortcut(_ candidate: Shortcut) -> String? {
        if candidate.keyCode == .none { return nil }
        for (existingId, atShortcut) in ControlsTab.shortcuts {
            guard existingId != id else { continue }
            let existing = atShortcut.shortcut
            if existing.keyCode != .none &&
                existing.keyCode == candidate.keyCode &&
                existing.carbonModifierFlags.cleaned() == candidate.carbonModifierFlags.cleaned() {
                return existingId
            }
        }
        return nil
    }

    /// macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound.
    private func shortcutReservedByMacos(_ candidate: Shortcut) -> String? {
        let modifiers = candidate.carbonModifierFlags.cleaned()
        let forceQuitCombos: [UInt32] = [
            UInt32(cmdKey | optionKey | controlKey),
            UInt32(cmdKey | optionKey | shiftKey | controlKey),
            UInt32(cmdKey | optionKey | shiftKey | controlKey) & ~UInt32(shiftKey),
        ]
        guard candidate.carbonKeyCode == UInt32(kVK_Escape),
              forceQuitCombos.contains(modifiers) else { return nil }
        return ControlsTab.shortcuts.values.first { $0.id != id && $0.shortcut.carbonKeyCode == UInt32(kVK_Escape) }?.id
    }
}
