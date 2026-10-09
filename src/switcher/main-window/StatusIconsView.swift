import Cocoa

class StatusIconsView: FlippedView {
    struct Icon {
        var symbol: String
        var tooltip: String?
        var visible = false
    }

    static let spaceIdx = 0
    static let hiddenIdx = 1
    static let fullscreenIdx = 2
    static let minimizedIdx = 3
    // fork-local: drawn from `NSImage(systemSymbolName:)`, since the bundled SF Pro subset has no speaker glyph
    // and regenerating it needs SF Symbols.app. The SF Symbol name stands in for the glyph in `Icon.symbol`.
    // A white speaker on a green disk, the only colored status icon, so the one sounding tile stands out among
    // dozens (the owner's pick over a tinted border, the playing tab's title and animated waves).
    static let audioIdx = 4
    private static let audioSymbolName = "speaker.wave.2.circle.fill"
    private static var audioImageCache: (size: CGFloat, image: NSImage)?

    private static let defaultSymbols: [(Symbols, String?)] = [
        (.circledNumber0, nil),
        (.circledSlashSign, NSLocalizedString("App is hidden", comment: "")),
        (.circledPlusSign, NSLocalizedString("Window is fullscreen", comment: "")),
        (.circledMinusSign, NSLocalizedString("Window is minimized", comment: "")),
    ]

    var icons: [Icon]
    private var visibleCount = 0
    private var tooltipsDirty = true
    private var tooltipStrings: [NSView.ToolTipTag: String] = [:]
    /// Single-character cell size, recomputed on appearance changes for the layout cache
    var iconCellSize: NSSize

    // periphery:ignore - AppKit private overrides, found by the ObjC runtime rather than called
    @objc func _windowChangedKeyState() {}
    // periphery:ignore - AppKit private overrides, found by the ObjC runtime rather than called
    @objc func _layoutSubtreeWithOldSize(_ oldSize: NSSize) {}

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: NSRect) {
        icons = Self.defaultSymbols.map { Icon(symbol: $0.0.rawValue, tooltip: $0.1) }
            + [Icon(symbol: Self.audioSymbolName, tooltip: NSLocalizedString("Playing audio", comment: ""))]
        iconCellSize = Self.measureIconCellSize()
        super.init(frame: frame)
    }

    private static func measureIconCellSize() -> NSSize {
        let font = NSFont(name: "SF Pro Text", size: (Appearance.fontHeight * 0.85).rounded())!
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: TileFontIconView.paragraphStyle]
        return NSAttributedString(string: Symbols.circledNumber0.rawValue, attributes: measureAttrs).size()
    }

    /// Re-apply appearance-baked metrics so a recycled instance survives an appearance change
    /// without being reallocated (which would free this tooltip owner; see TileView.reapplyAppearance).
    func reapplyAppearance() {
        iconCellSize = Self.measureIconCellSize()
        tooltipsDirty = true
    }

    static func cachedAttrString(for symbol: String) -> NSAttributedString {
        let size = Appearance.fontHeight
        let color = Appearance.fontColor
        let key = TileFontIconView.SymbolCacheKey(symbol: symbol, size: size, colorKey: TileFontIconView.symbolColorKey(color))
        if let cached = TileFontIconView.symbolCache[key] { return cached }
        let font = NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!
        let str = NSAttributedString(string: symbol, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: TileFontIconView.paragraphStyle,
        ])
        TileFontIconView.symbolCache[key] = str
        return str
    }

    required init?(coder: NSCoder) { fatalError() }

    var totalWidth: CGFloat { CGFloat(visibleCount) * TilesView.layoutCache.iconWidth }

    func update(isHidden: Bool, isFullscreen: Bool, isMinimized: Bool, isPlayingAudio: Bool, showSpace: Bool) {
        icons[Self.audioIdx].visible = isPlayingAudio
        icons[Self.hiddenIdx].visible = isHidden
        icons[Self.fullscreenIdx].visible = isFullscreen
        icons[Self.minimizedIdx].visible = isMinimized
        icons[Self.spaceIdx].visible = showSpace
        visibleCount = icons.count(where: { $0.visible })
    }

    func setSpaceStar() {
        icons[Self.spaceIdx].symbol = Symbols.circledStar.rawValue
        icons[Self.spaceIdx].tooltip = NSLocalizedString("Window is on every Space", comment: "")
    }

    func setSpaceNumber(_ number: Int) {
        icons[Self.spaceIdx].symbol = Self.symbolForSpace(number)
        icons[Self.spaceIdx].tooltip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), number)
    }

    static func symbolForSpace(_ number: Int) -> String {
        let (base, offset) = number <= 9
            ? (Symbols.circledNumber0.rawValue, number * 2)
            : (Symbols.circledNumber10.rawValue, number - 10)
        return String(UnicodeScalar(Int(base.unicodeScalars.first!.value) + offset)!)
    }

    var spaceVisible: Bool { icons[Self.spaceIdx].visible }

    func layoutIcons(hWidth: CGFloat, hHeight: CGFloat, edgeInsets: CGFloat) {
        let indicatorSpace = totalWidth
        assignIfDifferent(&frame.size.width, indicatorSpace)
        assignIfDifferent(&frame.size.height, hHeight)
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        assignIfDifferent(&frame.origin.x, isLTR ? edgeInsets + hWidth - indicatorSpace : edgeInsets)
        assignIfDifferent(&frame.origin.y, edgeInsets)
        tooltipsDirty = true
        needsDisplay = true
    }

    func ensureTooltipsInstalled() {
        guard tooltipsDirty else { return }
        tooltipsDirty = false
        removeAllToolTips()
        tooltipStrings.removeAll()
        forEachVisibleIcon { icon, rect in
            guard let tooltip = icon.tooltip else { return }
            tooltipStrings[addToolTip(rect, owner: self, userData: nil)] = tooltip
        }
    }

    /// The tooltip rects and the glyphs must land in the same slots, so both get their geometry
    /// here: icons fill from the trailing edge inwards, one `iconWidth` cell each.
    private func forEachVisibleIcon(_ body: (Icon, NSRect) -> Void) {
        let iconWidth = TilesView.layoutCache.iconWidth
        let iconHeight = TilesView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            body(icon, NSRect(x: x, y: yOffset, width: iconWidth, height: iconHeight))
        }
    }

    // periphery:ignore - NSViewToolTipOwner, called by AppKit through the ObjC runtime
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        return tooltipStrings[tag] ?? ""
    }

    override func draw(_ dirtyRect: NSRect) {
        guard visibleCount > 0 else { return }
        forEachVisibleIcon { icon, rect in
            guard icon.symbol != Self.audioSymbolName else { return Self.drawAudioImage(in: rect) }
            Self.cachedAttrString(for: icon.symbol).draw(at: rect.origin)
        }
    }

    /// Sized like the glyphs (`cachedAttrString`'s font size), centered in the cell.
    private static func drawAudioImage(in cell: NSRect) {
        let image = audioImage()
        let origin = NSPoint(x: cell.midX - image.size.width / 2, y: cell.midY - image.size.height / 2)
        image.draw(in: NSRect(origin: origin, size: image.size).integral, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func audioImage() -> NSImage {
        let size = Appearance.fontHeight
        if let cache = audioImageCache, cache.size == size { return cache.image }
        let configuration = NSImage.SymbolConfiguration(pointSize: (size * 0.85).rounded(), weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemGreen]))
        let image = NSImage(systemSymbolName: audioSymbolName, accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
        audioImageCache = (size, image)
        return image
    }
}
