import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class TilesView {
    static var scrollView: ScrollView!
    static var contentView: EffectView!
    static var currentEffectViewKind: EffectViewKind?
    private static var cachedEffectViews: [EffectViewKind: EffectView] = [:]
    static var noWindowLabel = NSTextField(labelWithString: NSLocalizedString("No Window", comment: ""))
    static var rows = [[TileView]]()
    private static var lastRowSignature = [Int]()
    static var recycledViews = [TileView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)
    static var layoutCache = LayoutCache()
    static var thumbnailUnderLayer = TileUnderLayer()
    static var thumbnailOverView = TileOverView()
    private static var initialized = false

    static func initialize() {
        guard !initialized else { return }
        configureNoWindowLabel()
        updateBackgroundView()
        // TODO: think about this optimization more
        (1...20).forEach { _ in TilesView.recycledViews.append(TileView()) }
        Self.updateCachedSizes()
        initialized = true
    }

    private static func configureNoWindowLabel() {
        noWindowLabel.textColor = .secondaryLabelColor
        noWindowLabel.font = .systemFont(ofSize: 13)
        noWindowLabel.alignment = .center
        noWindowLabel.isHidden = true
    }

    static func updateCachedSizes() {
        guard let firstView = TilesView.recycledViews.first else { return }
        layoutCache.labelHeight = firstView.label.cell!.cellSize.height
        let iconCellSize = firstView.statusIcons.iconCellSize
        layoutCache.iconWidth = iconCellSize.width
        layoutCache.iconHeight = iconCellSize.height
        layoutCache.comfortableReadabilityWidth = TileView.widthOfComfortableReadability()
        TileFontIconView.symbolCache.removeAll()
        let spaceNumberStrings = (0...19).map { StatusIconsView.symbolForSpace($0) }
        TileFontIconView.warmCaches(symbols: [.circledPlusSign, .circledMinusSign, .circledSlashSign, .circledStar], extraStrings: spaceNumberStrings, size: Appearance.fontHeight, color: Appearance.fontColor)
    }

    static func updateBackgroundView() {
        let kind = requiredEffectViewKind()
        contentView = cachedEffectView(for: kind)
        currentEffectViewKind = kind
        scrollView?.removeFromSuperview()
        scrollView = ScrollView()
        contentView.addSubview(scrollView)
        contentView.addSubview(noWindowLabel)
    }

    static func swapBackgroundViewIfNeeded() {
        guard contentView != nil else { return }
        let desired = requiredEffectViewKind()
        guard desired != currentEffectViewKind else { return }
        let newView = cachedEffectView(for: desired)
        currentEffectViewKind = desired
        newView.addSubview(scrollView)
        newView.addSubview(noWindowLabel)
        contentView = newView
        TilesPanel.shared.contentView = newView
    }

    private static func cachedEffectView(for kind: EffectViewKind) -> EffectView {
        if let cached = cachedEffectViews[kind] {
            cached.updateAppearance()
            return cached
        }
        let view = makeEffectView(for: kind)
        cachedEffectViews[kind] = view
        return view
    }

    static func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        Tooltips.hideAll()
        NSScreen.updatePreferred()
        Appearance.update()
        // thumbnails are captured continuously. They will pick up the new size on the next cycle
        TilesPanel.updateMaxPossibleThumbnailSize()
        // app icons are captured once at launch; we need to manually update them if needed
        let old = TilesPanel.maxPossibleAppIconSize.width
        TilesPanel.updateMaxPossibleAppIconSize()
        if old != TilesPanel.maxPossibleAppIconSize.width {
            Applications.updateAppIcons()
        }
        updateBackgroundView()
        TilesPanel.shared.contentView = contentView
        for i in 0..<TilesView.recycledViews.count {
            TilesView.recycledViews[i] = TileView()
        }
        thumbnailUnderLayer = TileUnderLayer()
        thumbnailOverView = TileOverView()
        thumbnailOverView.scrollView = scrollView
        lastRowSignature.removeAll()
        TileView.invalidateTitleAttributesCache()
        Self.updateCachedSizes()
    }

    static func highlight(_ indexInRecycledViews: Int) {
        guard indexInRecycledViews >= 0, indexInRecycledViews < recycledViews.count else { return }
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        guard view.frame != .zero else { return }
        view.drawHighlight()
        let underLayer = TilesView.thumbnailUnderLayer
        let selectedIndex = SwitcherSession.current?.selectedIndex ?? 0
        guard selectedIndex >= 0, selectedIndex < recycledViews.count else { return }
        let focusedView = recycledViews[selectedIndex]
        let hoveredView = SwitcherSession.current?.hoveredIndex.flatMap { $0 >= 0 && $0 < recycledViews.count ? recycledViews[$0] : nil }
        underLayer.updateHighlight(
            focusedView: focusedView.frame != .zero ? focusedView : nil,
            hoveredView: hoveredView != focusedView && hoveredView?.frame != .zero ? hoveredView : nil
        )
    }

    static func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [TileView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.selectedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap {
                    nextRow = nextRow % rows.count
                } else {
                    return nil
                }
            } else if nextRow < 0 {
                if allowWrap {
                    nextRow = rows.count + nextRow
                } else {
                    return nil
                }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) &&
                   (ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    static func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        let selectedIndex = SwitcherSession.current?.selectedIndex ?? 0
        guard selectedIndex < TilesView.recycledViews.count else { return }
        let focusedViewFrame = TilesView.recycledViews[selectedIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        guard let targetRow = nextRow(direction, allowWrap: allowWrap), !targetRow.isEmpty else { return }
        let leftSide = originCenter < NSMidX(contentView.frame)
        let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
        let iterable = leadingSide ? targetRow : targetRow.reversed()
        guard let targetView = iterable.first(where: {
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
            }
            return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
        }) ?? iterable.last else { return }
        guard let targetIndex = TilesView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateSelectedAndHoveredWindowIndex(targetIndex)
    }

    static func updateItemsAndLayout(_ preservedScrollOrigin: CGPoint?) {
        var widthMax = TilesPanel.maxThumbnailsWidth().rounded()
        if Preferences.effectiveAppearanceSize(SwitcherSession.activeShortcutIndex) == .auto {
            resolveAutoSize(widthMax)
            Self.updateCachedSizes()
            widthMax = TilesPanel.maxThumbnailsWidth().rounded()
        }
        if let (maxX, maxY, labelHeight, rowSignature) = layoutTileViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            centerRows(TilesView.thumbnailsWidth)
            if rowSignature != lastRowSignature {
                for row in rows {
                    for (j, view) in row.enumerated() {
                        view.numberOfViewsInRow = row.count
                        view.isFirstInRow = j == 0
                        view.isLastInRow = j == row.count - 1
                        view.indexInRow = j
                    }
                }
                lastRowSignature = rowSignature
            }
            highlightStartView()
            if let preservedScrollOrigin {
                restoreScrollOrigin(preservedScrollOrigin)
            }
        }
    }

    static func currentScrollOrigin() -> CGPoint {
        return scrollView.contentView.bounds.origin
    }

    private static func restoreScrollOrigin(_ scrollOrigin: CGPoint) {
        guard let documentView = scrollView.documentView else { return }
        let visibleSize = scrollView.contentView.bounds.size
        let documentSize = documentView.frame.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let clampedOrigin = CGPoint(x: min(max(0, scrollOrigin.x), maxX), y: min(max(0, scrollOrigin.y), maxY))
        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func resolveAutoSize(_ widthMax: CGFloat) {
        let heightMax = max(0, TilesPanel.maxThumbnailsHeight())
        for size in [AppearanceSizePreference.large, .medium, .small] {
            Appearance.applySize(size)
            Self.updateCachedSizes()
            let maxY = dryRunLayoutTileViews(widthMax)
            if size == .small || maxY <= heightMax { return }
        }
    }

    private static func dryRunLayoutTileViews(_ widthMax: CGFloat) -> CGFloat {
        let labelHeight = Self.layoutCache.labelHeight
        let height = TileView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxY = currentY + height + Appearance.interCellPadding
        var index = 0
        while index < TilesView.recycledViews.count {
            guard SwitcherSession.isActive else { return maxY }
            defer { index += 1 }
            let view = TilesView.recycledViews[index]
            guard index < Windows.list.count else { break }
            let window = Windows.list[index]
            guard Windows.shouldDisplay(window) else { view.frame = .zero; continue }
            view.updateRecycledCellWithNewContent(window, index, height)
            let width = view.frame.size.width
            let projectedX = projectedWidth(currentX, width).rounded(.down)
            if needNewLine(projectedX, widthMax) {
                currentX = startingX
                currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                currentX = projectedWidth(currentX, width).rounded(.down)
                maxY = max(currentY + height + Appearance.interCellPadding, maxY)
            } else {
                currentX = projectedX
            }
        }
        return maxY
    }

    private static func layoutTileViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat, [Int])? {
        let labelHeight = Self.layoutCache.labelHeight
        let height = TileView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [TileView]()
        var rowSignature = [Int]()
        rows.removeAll(keepingCapacity: true)
        rows.append([TileView]())
        var index = 0
        while index < TilesView.recycledViews.count {
            guard SwitcherSession.isActive else { return nil }
            defer { index = index + 1 }
            let view = TilesView.recycledViews[index]
            if index < Windows.list.count {
                let window = Windows.list[index]
                guard Windows.shouldDisplay(window) else {
                    view.frame = .zero
                    continue
                }
                view.updateRecycledCellWithNewContent(window, index, height)
                let width = view.frame.size.width
                let projectedX = projectedWidth(currentX, width).rounded(.down)
                if needNewLine(projectedX, widthMax) {
                    currentX = startingX
                    currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedWidth(currentX, width).rounded(.down)
                    maxY = max(currentY + height + Appearance.interCellPadding, maxY)
                    rows.append([TileView]())
                } else {
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedX
                    maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
                }
                rows[rows.count - 1].append(view)
                newViews.append(view)
                rowSignature.append(index)
                window.rowIndex = rows.count - 1
            } else {
                // release images and stale window references from unused recycledViews; they take lots of RAM
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
                view.window_ = nil
            }
        }
        scrollView.documentView!.subviews = newViews
        scrollView.documentView!.addSubview(thumbnailOverView)
        thumbnailOverView.scrollView = scrollView
        let docLayer = scrollView.documentView!.layer!
        if thumbnailUnderLayer.superlayer !== docLayer {
            docLayer.insertSublayer(thumbnailUnderLayer, at: 0)
        }
        return (maxX, maxY, labelHeight, rowSignature)
    }

    private static func needNewLine(_ projectedX: CGFloat, _ widthMax: CGFloat) -> Bool {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return projectedX > widthMax
        }
        return projectedX < 0
    }

    private static func projectedWidth(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return currentX + width + Appearance.interCellPadding
        }
        return currentX - width - Appearance.interCellPadding
    }

    private static func localizedCurrentX(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width
    }

    private static func layoutParentViews(_ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat, _ labelHeight: CGFloat) {
        let heightMax = max(0, TilesPanel.maxThumbnailsHeight())
        let minWidth = min(widthMax, 320)
        TilesView.thumbnailsWidth = max(min(maxX, widthMax), maxX == 0 ? minWidth : 0)
        TilesView.thumbnailsHeight = min(maxY, heightMax)
        let appIconsBottomViewportPadding = appIconsBottomViewportPadding(maxY, heightMax, labelHeight)
        let frameWidth = TilesView.thumbnailsWidth + Appearance.windowPadding * 2
        var frameHeight = TilesView.thumbnailsHeight + Appearance.windowPadding * 2
        let originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        let scrollHeight = max(0, min(maxY, heightMax) - appIconsBottomViewportPadding * 2)
        scrollView.frame.size = NSSize(width: TilesView.thumbnailsWidth, height: scrollHeight)
        scrollView.frame.origin = CGPoint(x: originX, y: originY + appIconsBottomViewportPadding * 2)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = max(0, TilesView.thumbnailsWidth - maxX)
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        let docSize = scrollView.documentView!.frame.size
        thumbnailOverView.frame = CGRect(origin: .zero, size: docSize)
        thumbnailUnderLayer.frame = CGRect(origin: .zero, size: docSize)
        let isEmpty = maxX == 0
        noWindowLabel.isHidden = !isEmpty
        if isEmpty {
            noWindowLabel.sizeToFit()
            let labelX = originX + (TilesView.thumbnailsWidth - noWindowLabel.frame.width) * 0.5
            let labelY = scrollView.frame.origin.y + (scrollView.frame.height - noWindowLabel.frame.height) * 0.5
            noWindowLabel.frame.origin = CGPoint(x: labelX, y: labelY)
        }
    }

    private static func appIconsBottomViewportPadding(_ maxY: CGFloat, _ heightMax: CGFloat, _ labelHeight: CGFloat) -> CGFloat {
        guard Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .appIcons, maxY > heightMax else { return 0 }
        return max(0, Appearance.windowPadding - labelHeight)
    }

    static func centerRows(_ maxX: CGFloat) {
        for row in rows where !row.isEmpty {
            guard SwitcherSession.isActive else { return }
            let rowWidth = Appearance.interCellPadding + row.reduce(CGFloat(0)) { $0 + $1.frame.size.width + Appearance.interCellPadding }
            let offset = ((maxX - rowWidth) / 2).rounded()
            if offset > 0 {
                for view in row {
                    view.frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
                }
            }
        }
    }

    private static func highlightStartView() {
        let session = SwitcherSession.current
        if Windows.selectedWindow() != nil {
            TilesView.highlight(session?.selectedIndex ?? 0)
        } else {
            thumbnailUnderLayer.updateHighlight(focusedView: nil, hoveredView: nil)
            thumbnailOverView.hideWindowControls()
        }
        if let hoveredWindowIndex = session?.hoveredIndex,
           hoveredWindowIndex >= 0,
           hoveredWindowIndex < Windows.list.count,
           Windows.shouldDisplay(Windows.list[hoveredWindowIndex]) {
            TilesView.highlight(hoveredWindowIndex)
            if thumbnailOverView.isShowingWindowControls {
                thumbnailOverView.showWindowControls(for: TilesView.recycledViews[hoveredWindowIndex])
            }
        } else {
            thumbnailOverView.hideWindowControls()
        }
    }

    static func windowIdsInViewport() -> Set<CGWindowID> {
        guard let scrollView else { return [] }
        let visibleBounds = scrollView.documentVisibleRect
        var ids = Set<CGWindowID>()
        let count = min(recycledViews.count, Windows.list.count)
        for index in 0..<count {
            let frame = recycledViews[index].frame
            if frame == .zero { continue } // filtered-out window, not "off-screen"
            if visibleBounds.intersects(frame), let wid = Windows.list[index].cgWindowId {
                ids.insert(wid)
            }
        }
        return ids
    }

    static func clearNeedsLayout() {
        var views = [NSView]()
        if let contentView { views.append(contentView as NSView) }
        views.append(noWindowLabel)
        if let scrollView {
            views.append(scrollView)
            views.append(scrollView.contentView)
            if let documentView = scrollView.documentView { views.append(documentView) }
        }
        for view in views {
            view.needsLayout = false
            view.needsDisplay = false
            view.needsUpdateConstraints = false
        }
    }

    struct LayoutCache {
        var labelHeight = CGFloat(0)
        var iconWidth = CGFloat(0)
        var iconHeight = CGFloat(0)
        var comfortableReadabilityWidth: CGFloat?
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false

    convenience init() {
        self.init(frame: .zero)
        documentView = TilesDocumentView(frame: .zero)
        documentView!.wantsLayer = true
        drawsBackground = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingStarted), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingEnded), name: NSScrollView.didEndLiveScrollNotification, object: nil)
    }

    @objc private func scrollingStarted() { isCurrentlyScrolling = true }
    @objc private func scrollingEnded() { isCurrentlyScrolling = false }

    /// holding shift and using the scrolling wheel will generate a horizontal movement
    /// shift can be part of shortcuts so we force shift scrolls to be vertical
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && event.scrollingDeltaY == 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
            super.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class TilesDocumentView: FlippedView {
    @objc func _windowChangedKeyState() {}
    @objc func _layoutSubtreeWithOldSize(_ oldSize: NSSize) {}

    func cancelDraggingTimer() {}
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum Direction {
    case right
    case left
    case leading
    case trailing
    case up
    case down

    func step() -> Int {
        if self == .left {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? -1 : 1
        } else if self == .right {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? 1 : -1
        }
        return self == .leading ? 1 : -1
    }
}
