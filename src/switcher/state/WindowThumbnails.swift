import Cocoa

/// Off-main-thread screenshot capture for window thumbnails, plus the
/// "preview the selected window" overlay shown next to the switcher panel.
enum WindowThumbnails {
    /// Throttle guard: only one preview capture per window per show-session.
    private static var previewCaptureDispatched = Set<CGWindowID>()

    static func resetPreviewState() {
        previewCaptureDispatched.removeAll()
    }

    static func previewSelectedIfNeeded() {
        guard let session = SwitcherSession.current, ScreenRecordingPermission.status == .granted
                && Preferences.effectivePreviewSelectedWindow(session.shortcutIndex)
                && TilesPanel.shared.isKeyWindow,
              let window = Windows.selectedWindow(),
              let id = window.cgWindowId,
              let position = window.position,
              let size = window.size else {
            PreviewPanel.shared.orderOut(nil)
            return
        }
        // Use full-resolution preview image when available; fall back to the thumbnail
        let preview = window.previewImage ?? window.thumbnail
        if let preview {
            PreviewPanel.show(id, preview, position, size)
        }
        // Trigger a full-resolution capture in the background if not already scheduled
        if window.previewImage == nil && !previewCaptureDispatched.contains(id) {
            previewCaptureDispatched.insert(id)
            BackgroundWork.screenshotsQueue.addOperation { [weak window] in
                guard let window, let wid = window.cgWindowId else { return }
                guard let image = WindowCaptureScreenshotsPrivateApi.capturePreviewSync(wid) else { return }
                DispatchQueue.main.async { [weak window] in
                    guard let window, SwitcherSession.isActive else { return }
                    window.previewImage = .cgImage(image)
                    // If this window is still the selected one, update the preview
                    if let selected = Windows.selectedWindow(), selected.cgWindowId == wid,
                       let position = window.position, let size = window.size {
                        PreviewPanel.show(wid, .cgImage(image), position, size)
                    }
                }
            }
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        let shortcutIndex = SwitcherSession.activeShortcutIndex
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !ScreenLockEvents.isScreenLocked
               && (!Appearance.hideThumbnails || Preferences.effectivePreviewSelectedWindow(shortcutIndex))
               && (Preferences.captureWindowsInBackground || SwitcherSession.isActive) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *),
           // mitigate macOS 15 bugs with ScreenCapture Kit (see https://github.com/lwouis/alt-tab-macos/issues/5190)
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }
}
