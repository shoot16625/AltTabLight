import Cocoa

class PreviewPanel: NSPanel {
    private static let previewView = LightImageView()
    private static let borderView = BorderView()
    private static var currentId: CGWindowID?
    static var shared: PreviewPanel!

    /// this allows the window to be above the menubar when its origin.y is set to 0
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        contentView = Self.previewView
        Self.borderView.autoresizingMask = [.width, .height]
        Self.previewView.addSubview(Self.borderView)
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        Self.shared = self
    }

    static func show(_ id: CGWindowID, _ preview: CALayerContents, _ position: CGPoint, _ size: CGSize) {
        repositionAndResize(position, size)
        if id != currentId {
            previewView.updateContents(preview, size)
        }
        if id != currentId || !Self.shared.isVisible {
            if Preferences.previewFadeInAnimation {
                Self.shared.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    Self.shared.animator().alphaValue = 1
                }
            }
            currentId = id
            Self.shared.order(.below, relativeTo: TilesPanel.shared.windowNumber)
            // Despite using `previewPanel.order(.below)`, a z-ordering issue can occur in the following scenario:
            // 1. Show a preview of a window that is on a different monitor than the thumbnails panel
            // 2. Select a window in the switcher that is on the same monitor as the thumbnails panel, and whose position overlaps with the thumbnails panel
            // 3. For a single frame, the preview of the newly selected window can appear above the thumbnails panel before going back underneath it
            // Simply using order(.below) is not sufficient to prevent this brief flicker. We explicitly set the preview panel's window level to be one below the thumbnails panel
            Self.shared.level = NSWindow.Level(rawValue: TilesPanel.shared.level.rawValue - 1)
        }
    }

    static func updateIfShowing(_ id: CGWindowID?,  _ preview: CALayerContents, _ position: CGPoint, _ size: CGSize) {
        if Self.shared.isVisible && id == currentId {
            repositionAndResize(position, size)
            previewView.updateContents(preview, size)
        }
    }

    /// Called when a window is removed from `Windows.list`: if our preview was showing that
    /// window, drop the cached IOSurface in `previewView.contents` so it can deallocate.
    /// Without this, closing the previewed window in the background leaves its full-resolution
    /// screenshot pinned in the static `previewView` for the rest of the app's lifetime.
    static func clearIfShowing(_ wid: CGWindowID) {
        if currentId == wid {
            previewView.releaseImage()
            currentId = nil
        }
    }

    /// Called when the switcher hides: the full-resolution preview screenshot is no longer
    /// needed, so drop the IOSurface instead of keeping it pinned in `previewView.contents`.
    static func clearImage() {
        previewView.releaseImage()
        currentId = nil
    }

    private static func repositionAndResize( _ position: CGPoint, _ size: CGSize) {
        var frame = NSRect(origin: position, size: size)
        // Flip Y coordinate from Quartz (0,0 at bottom-left) to Cocoa coordinates (0,0 at top-left)
        // Always use the primary screen as reference since all coordinates are relative to it
        frame.origin.y = NSScreen.screens.first!.frame.maxY - frame.maxY
        Self.shared.setFrame(frame, display: false)
    }
}

/// The border is a CAShapeLayer instead of a `draw(_:)` override: drawing allocates a window-sized backing
/// store (~11MB for a large window, x2 buffered) that stays pinned after the panel hides; a shape layer has none.
private class BorderView: NSView {
    private let shapeLayer = CAShapeLayer()

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        shapeLayer.fillRule = .evenOdd
        shapeLayer.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer!.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePath()
    }

    private func updatePath() {
        shapeLayer.frame = bounds
        // CGPath.addRoundedRect traps when the corner radius exceeds half the rect
        guard bounds.width > 20, bounds.height > 20 else { shapeLayer.path = nil; return }
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRoundedRect(in: bounds.insetBy(dx: 5, dy: 5), cornerWidth: 5, cornerHeight: 5)
        shapeLayer.path = path
        shapeLayer.fillColor = NSColor.systemAccentColor.withAlphaComponent(0.5).cgColor
    }
}
