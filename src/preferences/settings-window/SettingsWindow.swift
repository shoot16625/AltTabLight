import Cocoa

class SettingsWindow: NSWindow {
    static let contentWidth = CGFloat(710)
    static let width = contentWidth
    /// Horizontal margin inside each section between the section's container and the
    /// TableGroupView's rounded background.
    static let sectionContentHorizontalMargin = CGFloat(15)
    static var shared: SettingsWindow!

    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }

    private static let windowHeight = CGFloat(640)
    private static let windowWidth: CGFloat = contentWidth + 2 * sectionContentHorizontalMargin

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
                  styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        minSize = NSSize(width: Self.windowWidth, height: 400)
        maxSize = NSSize(width: Self.windowWidth, height: CGFloat.greatestFiniteMagnitude)
        setupWindow()
        let sectionView = setupView()
        // Fit the window to its content: the shortcuts table is the only section, so a taller
        // window just adds empty space below it (content is top-aligned inside the scroll view).
        sectionView.layoutSubtreeIfNeeded()
        let fittedHeight = min(max(sectionView.fittingSize.height + 24, 400), 720)
        setContentSize(NSSize(width: Self.windowWidth, height: fittedHeight))
        // Restore the saved frame (position + size). `setFrameAutosaveName` persists the current
        // frame, so this must run after the height fit. A saved frame from before the height fit
        // (or any other height mismatch) would anchor the top edge and leave the window hanging
        // off-center — fall back to centering in that case.
        let hasSavedFrame = setFrameAutosaveNameSafely("SettingsWindow")
        if !hasSavedFrame || abs(frame.height - fittedHeight) > 40 {
            // `NSWindow.center()` misbehaves on recent macOS (offsets the window from screen
            // center); center manually within the visible frame instead.
            NSScreen.preferred.repositionPanel(self)
        }
        Self.shared = self
    }

    private func setupWindow() {
        delegate = self
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
    }

    private func setupView() -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let documentView = SettingsFlippedView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        contentView!.addSubview(scrollView)
        let sectionView = ControlsTab.initTab()
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(sectionView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            sectionView.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            sectionView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
            sectionView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -12),
        ])
        return sectionView
    }
}

extension SettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        ControlsTab.cleanup()
        SettingsWindow.shared = nil
    }
}

/// A flipped document view so content stacks from the top, like the original settings layout.
private class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}
