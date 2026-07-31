import Cocoa
import Darwin
import ShortcutRecorder

class App: NSApplication {
    /// periphery:ignore
    static let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Prevent App Nap to preserve responsiveness")
    static let bundleIdentifier = Bundle.main.bundleIdentifier!
    static let bundleURL = Bundle.main.bundleURL
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static let appIconReps = CGImage.allNamed("app.icns")

    static func appIcon(for size: NSSize) -> CGImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let scaled = NSSize(width: size.width * scale, height: size.height * scale)
        return CGImage.bestMatch(appIconReps, for: scaled)
    }
    override class var shared: App { super.shared as! App }
    static var isTerminating = false
    private static var isVeryFirstSummon = true
    private static var pendingShowSettingsWindow = false
    // don't queue multiple delayed rebuildUi() calls
    private static var delayedDisplayScheduled = 0
    private static let switcherUiRefreshThrottler = Throttler(delayInMs: 200)

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// we put application code here which should be executed on init() and Preferences change
    static func resetPreferencesDependentComponents() {
        TilesView.reset()
    }

    static func restart() {
        // we use -n to open a new instance, to avoid calling applicationShouldHandleReopen
        // we use Bundle.main.bundlePath in case of multiple AltTab versions on the machine
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        App.shared.terminate(nil)
    }

    static func hideUi(_ keepPreview: Bool = false) {
        guard SwitcherSession.current != nil else { return } // already hidden
        SwitcherSession.current = nil
        CursorEvents.toggle(false)
        Windows.releaseThumbnails()
        Tooltips.hideAll()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.shared.orderOut(nil)
            PreviewPanel.clearImage()
        }
        MainMenu.toggle(true)
    }

    /// we don't want another window to become key when the TilesPanel is hidden
    static func hideTilesPanelWithoutChangingKeyWindow() {
        allSecondaryWindowsCanBecomeKey(false)
        TilesPanel.shared.orderOut(nil)
        allSecondaryWindowsCanBecomeKey(true)
    }

    private static func allSecondaryWindowsCanBecomeKey(_ canBecomeKey_: Bool) {
        SettingsWindow.canBecomeKey_ = canBecomeKey_
        PermissionsWindow.canBecomeKey_ = canBecomeKey_
    }

    static func focusTarget() {
        guard SwitcherSession.isActive else { return } // already hidden
        let selectedWindow = Windows.selectedWindow()
        focusSelectedWindow(selectedWindow)
    }

    @objc static func checkPermissions(_ sender: NSMenuItem) {
        showPermissionsWindow()
    }

    @objc static func showSettingsWindow() {
        guard Menubar.statusItem != nil else {
            pendingShowSettingsWindow = true
            return
        }
        initializeSettingsWindowIfNeeded()
        showSecondaryWindow(SettingsWindow.shared!)
        if SettingsWindow.shared!.isVisible != true {
            let window = SettingsWindow()
            showSecondaryWindow(window)
            window.orderFrontRegardless()
        }
    }

    static func showSecondaryWindow(_ window: NSWindow) {
        NSScreen.updatePreferred()
        App.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        var restored = false
        ObjCExceptionCatcher.catching { restored = window.setFrameUsingName(window.frameAutosaveName) }
        if !restored {
            NSScreen.preferred.repositionPanel(window)
            window.center()
        }
    }

    private static func initializeSettingsWindowIfNeeded() {
        if SettingsWindow.shared == nil { _ = SettingsWindow() }
    }

    private static func initializePermissionsWindowIfNeeded() {
        if PermissionsWindow.shared == nil { _ = PermissionsWindow() }
    }

    @discardableResult
    private static func showSettingsWindowOnFirstLaunchIfNeeded() -> Bool {
        guard !Preferences.settingsWindowShownOnFirstLaunch else { return false }
        showAndCenterSettingsWindowOnFirstLaunch()
        return true
    }

    /// `showSettingsWindow()` relies on a saved autosave frame to position the window. On first
    /// launch there's no saved frame, and `showSecondaryWindow`'s fallback centering doesn't always
    /// stick. Force a center pass after showing so the user sees the window in the middle of the screen.
    private static func showAndCenterSettingsWindowOnFirstLaunch() {
        showSettingsWindow()
        if let window = SettingsWindow.shared {
            NSScreen.preferred.repositionPanel(window)
            window.center()
        }
        Preferences.markSettingsWindowShownOnFirstLaunch()
    }

    static func showPermissionsWindow() {
        initializePermissionsWindowIfNeeded()
        PermissionsWindow.show()
    }

    static func showUi(_ shortcutIndex: Int) {
        showUiOrCycleSelection(shortcutIndex, true)
    }

    @objc static func showUiFromShortcut0() {
        showUi(0)
    }

    static func cycleSelection(_ direction: Direction, allowWrap: Bool = true) {
        (TilesView.scrollView?.documentView as? TilesDocumentView)?.cancelDraggingTimer()
        CursorEvents.resetDeadzone()
        if direction == .up || direction == .down {
            TilesView.navigateUpOrDown(direction, allowWrap: allowWrap)
        } else {
            Windows.cycleSelectedWindowIndex(direction.step(), allowWrap: allowWrap)
        }
    }

    static func previousWindowShortcutWithRepeatingKey() {
        cycleSelection(.trailing)
        KeyRepeatTimer.startRepeatingKeyPreviousWindow()
    }

    static func focusSelectedWindow(_ selectedWindow: Window?) {
        guard SwitcherSession.isActive else { return } // already hidden
        hideUi(true)
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
            window.focus()
            if Preferences.cursorFollowFocus == .always || (
                Preferences.cursorFollowFocus == .differentScreen && (Spaces.screenSpacesMap.first { $0.value.contains { space in window.spaceIds.contains(space) } })?.key != NSScreen.active()?.cachedUuid()) {
                moveCursorToSelectedWindow(window)
            }
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
    }

    static func moveCursorToSelectedWindow(_ window: Window) {
        let referenceWindow = window.referenceWindowForTabbedWindow()
        guard let position = referenceWindow?.position, let size = referenceWindow?.size else { return }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        CGWarpMouseCursorPosition(point)
    }

    static func refreshOpenUiAfterExternalEvent(_ windowsToScreenshot: [Window], windowRemoved: Bool = false) {
        WindowThumbnails.refreshAsync(windowsToScreenshot, .refreshUiAfterExternalEvent, windowRemoved: windowRemoved)
        switcherUiRefreshThrottler.throttleOrProceed {
            guard SwitcherSession.isActive else { return }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            refreshUi(true)
        }
    }

    static func refreshUi(_ preserveScrollPosition: Bool = false) {
        guard SwitcherSession.isActive else { return }
        let preservedScrollOrigin = preserveScrollPosition ? TilesView.currentScrollOrigin() : nil
        Windows.updateSelectedWindow()
        guard SwitcherSession.isActive else { return }
        TilesPanel.shared.updateContents(preservedScrollOrigin)
        guard SwitcherSession.isActive else { return }
        Windows.voiceOverWindow() // at this point TileViews are assigned to the window, and ready
        guard SwitcherSession.isActive else { return }
        WindowThumbnails.previewSelectedIfNeeded()
        guard SwitcherSession.isActive else { return }
        Applications.refreshBadgesAsync()
    }

    static func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        let session = SwitcherSession.current ?? {
            let new = SwitcherSession()
            SwitcherSession.current = new
            return new
        }()
        session.forceDoNothingOnRelease = forceDoNothingOnRelease_
        if session.isFirstSummon || shortcutIndex != session.shortcutIndex {
            NSScreen.updatePreferred()
            if isVeryFirstSummon {
                Windows.sortByLevel()
                isVeryFirstSummon = false
            }
            session.isFirstSummon = false
            session.shortcutIndex = shortcutIndex
            // Hide instantly so the rebuild for a different shortcut (Appearance change, layout
            // recalc) is invisible. `TilesPanel.show()` flips alpha back to 1 once everything is
            // in its final state. No-op on first summon (panel was orderOut'd with alpha=0).
            TilesPanel.shared.alphaValue = 0
            let shouldStartInSearchMode = Preferences.effectiveShortcutStyle(shortcutIndex) == .searchOnRelease
            if shouldStartInSearchMode {
                session.forceDoNothingOnRelease = true
            }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            Windows.setInitialSelectedAndHoveredWindowIndex()
            if Preferences.windowDisplayDelay == DispatchTimeInterval.milliseconds(0) {
                buildUiAndShowPanel()
            } else {
                delayedDisplayScheduled += 1
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { () -> () in
                    if delayedDisplayScheduled == 1 {
                        buildUiAndShowPanel()
                    }
                    delayedDisplayScheduled -= 1
                }
            }
        } else {
            cycleSelection(.leading)
            KeyRepeatTimer.startRepeatingKeyNextWindow()
        }
    }

    static func buildUiAndShowPanel() {
        guard SwitcherSession.isActive else { return }
        // `App.hideUi` detaches the content view to release the effect view's backing store;
        // re-attach it before the panel is shown again.
        if TilesPanel.shared.contentView !== TilesView.contentView {
            TilesPanel.shared.contentView = TilesView.contentView
        }
        Appearance.update()
        guard SwitcherSession.isActive else { return }
        TilesView.swapBackgroundViewIfNeeded()
        guard SwitcherSession.isActive else { return }
        refreshUi()
        guard SwitcherSession.isActive else { return }
        TilesPanel.shared.show()
        WindowThumbnails.previewSelectedIfNeeded()
        KeyRepeatTimer.startRepeatingKeyNextWindow()
        let prioritizedIds = TilesView.windowIdsInViewport()
        WindowThumbnails.refreshAsync(Windows.list, .refreshOnlyThumbnailsAfterShowUi, prioritizedIds: prioritizedIds)
    }

    static func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: Application?) {
        let app = activeWindow?.application ?? activeApp!
        let shortcutsShouldBeDisabled = ExceptionMatcher.disablesShortcuts(
            app.state,
            isFullscreen: activeWindow?.isFullscreen ?? false,
            exceptions: Preferences.exceptions)
        KeyboardEvents.toggleGlobalShortcuts(shortcutsShouldBeDisabled)
        if shortcutsShouldBeDisabled && SwitcherSession.isActive {
            hideUi()
        }
    }

    static func continueAppLaunchAfterPermissionsAreGranted() {
        Logger.info { "System permissions are granted; continuing launch" }
        BackgroundWork.start()
        NSScreen.updatePreferred()
        Appearance.update()
        TilesPanel.updateMaxPossibleThumbnailSize()
        TilesPanel.updateMaxPossibleAppIconSize()
        Menubar.initialize()
        MainMenu.create()
        _ = TilesPanel()
        _ = PreviewPanel()
        Spaces.refresh()
        Screens.refresh()
        SpacesEvents.observe()
        ScreensEvents.observe()
        ScreenLockEvents.observe()
        SleepWakeEvents.observe()
        Applications.initialDiscovery()
        KeyboardEvents.addEventHandlers()
        CursorEvents.observe()
        PreferencesEvents.initialize()
        showSettingsWindowOnFirstLaunchIfNeeded()
        if pendingShowSettingsWindow {
            pendingShowSettingsWindow = false
            showSettingsWindow()
        }
        Logger.info { "Finished launching AltTabLight" }
    }
}

extension App: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Logger.initialize()
        Logger.info { "Launching AltTab \(App.version)" }
        AXUIElement.setGlobalTimeout()
        Preferences.initialize()
        BackgroundWork.preStart()
        SystemPermissions.ensurePermissionsAreGranted()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        App.showSettingsWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // symbolic hotkeys state persist after the app is quit; we restore this shortcut before quitting
        setNativeCommandTabEnabled(true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        makeSureAllCapturesAreFinished()
        return .terminateNow
    }
}

enum RefreshCausedBy {
    case refreshOnlyThumbnailsAfterShowUi
    case refreshUiAfterExternalEvent
}
