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
    private static let windowWidth: CGFloat = contentWidth + 2 * sectionContentHorizontalMargin + 30

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
                  styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        minSize = NSSize(width: Self.windowWidth, height: 400)
        maxSize = NSSize(width: Self.windowWidth, height: CGFloat.greatestFiniteMagnitude)
        setupWindow()
        setupView()
        if !setFrameAutosaveNameSafely("SettingsWindow") {
            center()
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

    private func setupView() {
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
            sectionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 10),
            sectionView.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor, constant: -10),
            sectionView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 10),
            sectionView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -10),
        ])
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
