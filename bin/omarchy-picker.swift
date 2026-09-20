// Full-screen image carousel picker -- the macOS stand-in for omarchy's
// `omarchy-menu-images` (shell/plugins/image-picker/ImagePicker.qml).
//
// Same shape as the original: one expanded preview in the middle, every other
// entry a narrow skewed slice fanning out either side, filter-as-you-type,
// arrows to slide, Return to apply. The geometry constants below are omarchy's
// own, scaled to the screen.
//
// It is deliberately generic -- it knows nothing about themes. Rows arrive on
// stdin as TSV and the chosen row's first field goes to stdout, so the caller
// decides what a selection means (theme.py does the applying, exactly like
// omarchy-theme-switcher | omarchy-theme-set).
//
//   value <TAB> image-path <TAB> label <TAB> hex,hex,hex,...   (palette, optional)
//
// Exit: 0 = printed a selection, 3 = printed a selection via the alt key
// (--alt-key), 1 = cancelled.
//
// Built by install.sh with a plain `swiftc -O` -- no Xcode project, no bundle.

import AppKit
import CoreGraphics
import CryptoKit
import ImageIO

// ── Colour helpers ───────────────────────────────────────────────────────────

func hexColor(_ raw: String, alpha: CGFloat = 1) -> NSColor {
    var h = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if h.hasPrefix("#") { h.removeFirst() }
    if h.hasPrefix("0x") { h.removeFirst(2) }
    if h.count == 8 { h = String(h.suffix(6)) }   // sketchybar's 0xAARRGGBB
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return NSColor(white: 0.08, alpha: alpha) }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                   green:   CGFloat((v >> 8)  & 0xff) / 255,
                   blue:    CGFloat( v        & 0xff) / 255,
                   alpha:   alpha)
}

// ── Input ────────────────────────────────────────────────────────────────────

struct Row {
    let value: String
    let imagePath: String
    let label: String
    let palette: [NSColor]
}

struct Options {
    var selected     = ""
    var showLabels   = false
    var filterable   = false
    var chrome       = false     // compose a mock desktop over the wallpaper
    var hint         = ""
    var altKey: Character? = nil
    var background   = "#101315"
    var foreground   = "#cacccc"
    var accent       = "#798186"
    var darkBackground = "#0c0e10"
}

func parseArgs() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next() -> String { args.isEmpty ? "" : args.removeFirst() }
    while !args.isEmpty {
        switch args.removeFirst() {
        case "--selected":   o.selected = next()
        case "--labels":     o.showLabels = true
        case "--filterable": o.filterable = true
        case "--chrome":     o.chrome = true
        case "--hint":       o.hint = next()
        case "--alt-key":    o.altKey = next().lowercased().first
        case "--background": o.background = next()
        case "--foreground": o.foreground = next()
        case "--accent":     o.accent = next()
        case "--dark-background": o.darkBackground = next()
        default: break
        }
    }
    return o
}

func readRows() -> [Row] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split(separator: "\n").compactMap { line in
        let f = line.components(separatedBy: "\t")
        guard let value = f.first, !value.isEmpty else { return nil }
        let image = f.count > 1 ? f[1] : ""
        let label = f.count > 2 ? f[2] : value
        let palette = (f.count > 3 ? f[3] : "")
            .split(separator: ",").map { hexColor(String($0)) }
        return Row(value: value, imagePath: image, label: label, palette: palette)
    }
}

// ── Thumbnails ───────────────────────────────────────────────────────────────
//
// ImageIO reads webp natively, which matters: most of omarchy's backgrounds are
// .webp now. Thumbnails are cached on disk keyed by path+size+mtime so a second
// open is instant, the same trick omarchy plays with vipsthumbnail.

let thumbCache = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".cache/omarchy-mac/thumbs", isDirectory: true)

func cacheKey(_ parts: [String]) -> String {
    let digest = Insecure.MD5.hash(data: Data(parts.joined(separator: "|").utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func decodeThumbnail(_ path: String, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

func writeJPEG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

func readCached(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// A theme with no wallpaper on disk yet still needs a card, and a wallpaper on
// its own does not say much about a *theme* -- so the card is a small mock
// desktop: the wallpaper (or a palette gradient), a bar strip along the top and
// a terminal window, all painted from that theme's own colours.
func composeCard(wallpaper: CGImage?, palette: [NSColor], size: CGSize, chrome: Bool) -> CGImage? {
    let w = Int(size.width), h = Int(size.height)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }

    func color(_ i: Int, _ fallback: NSColor) -> NSColor {
        i < palette.count ? palette[i] : fallback
    }
    // Row palette order (see theme.py picker-rows):
    // 0 background, 1 dark_background, 2 foreground, 3 accent, 4 muted,
    // 5 red, 6 green, 7 yellow, 8 blue, 9 magenta, 10 cyan
    let bg      = color(0, NSColor(white: 0.07, alpha: 1))
    let darkbg  = color(1, bg)
    let fg      = color(2, NSColor(white: 0.8, alpha: 1))
    let accent  = color(3, fg)
    let muted   = color(4, accent)

    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    if let wp = wallpaper {
        // aspect-fill, centred -- PreserveAspectCrop in the original
        let iw = CGFloat(wp.width), ih = CGFloat(wp.height)
        let scale = max(size.width / iw, size.height / ih)
        let dw = iw * scale, dh = ih * scale
        ctx.draw(wp, in: CGRect(x: (size.width - dw) / 2, y: (size.height - dh) / 2, width: dw, height: dh))
    } else {
        // No wallpaper: a quiet gradient between the theme's two backgrounds,
        // so the card still reads as that theme rather than as an error.
        let colors = [darkbg.cgColor, bg.cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    guard chrome else { return ctx.makeImage() }

    // Bar strip (sketchybar), pinned to the top edge.
    let barH = size.height * 0.062
    ctx.setFillColor(bg.withAlphaComponent(0.97).cgColor)
    ctx.fill(CGRect(x: 0, y: size.height - barH, width: size.width, height: barH))
    let pip = barH * 0.26
    for i in 0..<4 {
        ctx.setFillColor((i == 0 ? accent : muted).cgColor)
        ctx.fillEllipse(in: CGRect(x: barH * 0.5 + CGFloat(i) * pip * 2.1,
                                   y: size.height - barH / 2 - pip / 2, width: pip, height: pip))
    }
    for i in 0..<3 {
        ctx.setFillColor(fg.withAlphaComponent(0.55).cgColor)
        ctx.fill(CGRect(x: size.width - barH * 0.6 - CGFloat(i) * pip * 3.4,
                        y: size.height - barH / 2 - pip * 0.22, width: pip * 2.2, height: pip * 0.44))
    }

    // Terminal window, lower left, with palette-coloured "output".
    let winW = size.width * 0.46, winH = size.height * 0.42
    let win = CGRect(x: size.width * 0.09, y: size.height * 0.14, width: winW, height: winH)
    let path = CGPath(roundedRect: win, cornerWidth: winH * 0.035, cornerHeight: winH * 0.035, transform: nil)
    ctx.setFillColor(darkbg.withAlphaComponent(0.96).cgColor)
    ctx.addPath(path); ctx.fillPath()
    ctx.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(max(2, size.height * 0.004))
    ctx.addPath(path); ctx.strokePath()

    let lineH = winH * 0.055, gap = winH * 0.105
    let lineColors = [accent, color(6, fg), fg, color(8, fg), color(7, fg), fg, color(5, fg)]
    for i in 0..<6 {
        let y = win.maxY - gap * CGFloat(i + 1)
        let width = winW * [0.62, 0.38, 0.74, 0.45, 0.55, 0.3][i]
        ctx.setFillColor(lineColors[i % lineColors.count].withAlphaComponent(0.85).cgColor)
        ctx.fill(CGRect(x: win.minX + winW * 0.06, y: y, width: width, height: lineH))
    }
    return ctx.makeImage()
}

// ── The carousel ─────────────────────────────────────────────────────────────

final class ItemLayer {
    let holder = CALayer()        // animated frame; unmasked so the border shows
    let content = CALayer()       // masked to the parallelogram
    let image = CALayer()
    let dim = CALayer()
    let shape = CAShapeLayer()    // mask
    let border = CAShapeLayer()
    var loaded = false

    init(scale: CGFloat) {
        image.contentsGravity = .resizeAspectFill
        image.masksToBounds = true
        image.contentsScale = scale
        content.addSublayer(image)
        content.addSublayer(dim)
        content.mask = shape
        holder.addSublayer(content)
        holder.addSublayer(border)
        border.fillColor = nil
        border.contentsScale = scale
    }
}

final class CarouselView: NSView {
    let rows: [Row]
    let opts: Options
    var selected = 0
    var filter = ""

    // omarchy's geometry, scaled to the screen
    let s: CGFloat
    var expandedW: CGFloat { 768 * s }
    var expandedH: CGFloat { 475 * s }
    var sliceW: CGFloat { 108 * s }
    var sliceH: CGFloat { 432 * s }
    var spacing: CGFloat { -30 * s }
    var skew: CGFloat { 28 * s }
    var step: CGFloat { sliceW + spacing }
    var carouselW: CGFloat { expandedW + 13 * step }

    var items: [ItemLayer] = []
    let labelLayer = CATextLayer()
    let filterLayer = CATextLayer()
    let hintLayer = CATextLayer()
    let hintBacking = CALayer()
    let scrimLayer = CALayer()
    var frames: [Int: CGRect] = [:]
    var wheelAccum: CGFloat = 0

    init(rows: [Row], opts: Options, frame: NSRect, scale: CGFloat) {
        self.rows = rows
        self.opts = opts
        // 768pt of preview is about half of a 1512pt laptop screen, which is
        // how it looks on omarchy's 1440p reference. Track the screen so an
        // external display does not shrink it into the middle.
        self.s = min(max(min(frame.width / 1512, frame.height / 982), 0.72), 1.9)
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsScale = scale
        build(scale: scale)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: filtering, mirroring ImagePickerModel.js

    func matches(_ i: Int) -> Bool {
        filter.isEmpty || rows[i].label.lowercased().contains(filter.lowercased())
            || rows[i].value.lowercased().contains(filter.lowercased())
    }
    func filteredPosition(_ i: Int) -> Int {
        var n = 0
        for j in 0..<i where matches(j) { n += 1 }
        return n
    }
    var selectedFilteredPosition: Int { filteredPosition(selected) }

    func selectAdjacent(_ direction: Int) {
        guard !rows.isEmpty else { return }
        var i = selected
        for _ in 0..<rows.count {
            i = ((i + direction) % rows.count + rows.count) % rows.count
            if matches(i) { select(i); return }
        }
    }
    func select(_ i: Int) {
        guard matches(i), i != selected else { return }
        selected = i
        layout(animated: true)
        loadNearby()
    }
    func updateFilter(_ text: String) {
        filter = text
        if !matches(selected), let first = (0..<rows.count).first(where: { matches($0) }) {
            selected = first
        }
        layout(animated: true)
        loadNearby()
    }

    // MARK: layers

    func build(scale: CGFloat) {
        scrimLayer.backgroundColor = hexColor(opts.background, alpha: 0.5).cgColor
        layer?.addSublayer(scrimLayer)

        for _ in rows {
            let item = ItemLayer(scale: scale)
            item.dim.backgroundColor = hexColor(opts.background).cgColor
            item.holder.isHidden = true
            layer?.addSublayer(item.holder)
            items.append(item)
        }
        layer?.addSublayer(hintBacking)
        for t in [labelLayer, filterLayer, hintLayer] {
            t.contentsScale = scale
            t.alignmentMode = .center
            t.truncationMode = .end
            t.shadowColor = hexColor(opts.background).cgColor
            t.shadowOpacity = 0.75
            t.shadowRadius = 5 * s
            t.shadowOffset = .zero
            layer?.addSublayer(t)
        }
    }

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: hexColor(opts.foreground, alpha: alpha),
        ])
    }

    func parallelogram(_ size: CGSize) -> CGPath {
        // skew >= 0: the top edge leans right, exactly as the Shape in the QML
        let p = CGMutablePath()
        p.move(to: CGPoint(x: skew, y: size.height))
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: size.width - skew, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }

    func layout(animated: Bool) {
        scrimLayer.frame = bounds
        let carouselX = (bounds.width - carouselW) / 2
        let chromeH = (opts.showLabels ? (opts.filterable ? 104 : 74) : (opts.filterable ? 60 : 30)) * s
        let cardH = expandedH + chromeH
        let cardY = (bounds.height - cardH) / 2 + chromeH
        frames.removeAll()

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        let here = selectedFilteredPosition
        for (i, item) in items.enumerated() {
            let visible = matches(i) && abs(filteredPosition(i) - here) <= 16
            guard visible else {
                item.holder.isHidden = true
                continue
            }
            let rel = filteredPosition(i) - here
            let isSelected = (i == selected)
            let w = isSelected ? expandedW : sliceW
            let h = isSelected ? expandedH : sliceH
            let x: CGFloat = isSelected ? 0
                : (rel < 0 ? CGFloat(rel) * step
                           : expandedW + spacing + CGFloat(rel - 1) * step)
            // Both sizes are centred in the same expandedH-tall band, so the
            // inset is the same number whichever way the axis runs.
            let y = isSelected ? 0 : (expandedH - sliceH) / 2
            let frame = CGRect(x: carouselX + (carouselW - expandedW) / 2 + x,
                               y: cardY + y, width: w, height: h)
            frames[i] = frame

            let appearing = item.holder.isHidden
            if appearing {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
            }
            item.holder.isHidden = false
            item.holder.frame = frame
            item.holder.zPosition = isSelected ? 100 : CGFloat(50 - min(abs(rel), 40))
            item.content.frame = CGRect(origin: .zero, size: frame.size)
            item.image.frame = item.content.bounds
            item.dim.frame = item.content.bounds
            item.dim.opacity = isSelected ? 0 : 0.42
            item.shape.frame = item.content.bounds
            item.shape.path = parallelogram(frame.size)
            item.border.frame = CGRect(origin: .zero, size: frame.size)
            item.border.path = parallelogram(frame.size)
            item.border.strokeColor = isSelected
                ? hexColor(opts.accent).cgColor
                : hexColor(opts.foreground, alpha: 0.28).cgColor
            item.border.lineWidth = isSelected ? 3 * s : 1 * s
            if appearing { CATransaction.commit() }
        }

        let labelY = cardY - 16 * s
        if opts.showLabels {
            labelLayer.string = text(currentLabel, size: 26 * s, weight: .semibold, alpha: 1)
            labelLayer.frame = CGRect(x: (bounds.width - expandedW) / 2, y: labelY - 34 * s,
                                      width: expandedW, height: 34 * s)
        }
        filterLayer.isHidden = filter.isEmpty
        filterLayer.string = text(filter, size: 17 * s, weight: .regular, alpha: 0.85)
        filterLayer.frame = CGRect(x: (bounds.width - expandedW) / 2, y: labelY - 62 * s,
                                   width: expandedW, height: 24 * s)
        // The hint sits over whatever the desktop happens to be, so it gets its
        // own backing rather than relying on the scrim alone to carry it.
        hintLayer.isHidden = opts.hint.isEmpty
        hintLayer.string = text(opts.hint, size: 13 * s, weight: .medium, alpha: 0.62)
        let hintW = 560 * s
        hintLayer.frame = CGRect(x: (bounds.width - hintW) / 2, y: 30 * s, width: hintW, height: 22 * s)
        hintBacking.isHidden = opts.hint.isEmpty
        hintBacking.frame = hintLayer.frame.insetBy(dx: -18 * s, dy: -7 * s)
        hintBacking.cornerRadius = hintBacking.frame.height / 2
        hintBacking.backgroundColor = hexColor(opts.background, alpha: 0.55).cgColor

        CATransaction.commit()
    }

    var currentLabel: String {
        guard !rows.isEmpty, matches(selected) else { return filter.isEmpty ? "" : "No matches" }
        return rows[selected].label
    }

    // MARK: image loading
    //
    // Nearest-first on a background queue: the expanded card is what you are
    // looking at, so it must not wait behind twenty slices.

    func loadNearby() {
        let order = (0..<rows.count).sorted { abs($0 - selected) < abs($1 - selected) }
        for i in order where !items[i].loaded {
            items[i].loaded = true
            load(i)
        }
    }

    func load(_ i: Int) {
        let row = rows[i]
        let scale = window?.backingScaleFactor ?? 2
        let target = CGSize(width: expandedW * scale, height: expandedH * scale)
        let paletteSig = row.palette.map { $0.description }.joined(separator: "-")
        let key = cacheKey([row.imagePath, row.value, "\(Int(target.width))x\(Int(target.height))",
                            opts.chrome ? "chrome" : "plain", paletteSig,
                            String(describing: try? FileManager.default
                                .attributesOfItem(atPath: row.imagePath)[.modificationDate])])
        let cached = thumbCache.appendingPathComponent("\(key).jpg")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var image = readCached(cached)
            if image == nil {
                let wallpaper = row.imagePath.isEmpty ? nil
                    : decodeThumbnail(row.imagePath, maxPixel: Int(max(target.width, target.height)))
                image = composeCard(wallpaper: wallpaper, palette: row.palette,
                                    size: target, chrome: self?.opts.chrome ?? false)
                if let image { writeJPEG(image, to: cached) }
            }
            guard let image else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.items[i].image.contents = image
                CATransaction.commit()
            }
        }
    }

    // MARK: input

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        let code = event.keyCode
        let cmd = event.modifierFlags.contains(.command)

        if let alt = opts.altKey, cmd, chars.lowercased() == String(alt) {
            finish(exitCode: 3); return
        }
        switch code {
        case 53:                                        // esc
            if !filter.isEmpty { updateFilter("") } else { cancel() }
        case 36, 76:                                    // return / enter
            finish(exitCode: 0)
        case 123: selectAdjacent(-1)                    // left
        case 124: selectAdjacent(1)                     // right
        case 48:                                        // tab / shift-tab
            selectAdjacent(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 51:                                        // delete
            if opts.filterable, !filter.isEmpty { updateFilter(String(filter.dropLast())) }
        default:
            guard opts.filterable, !cmd, !event.modifierFlags.contains(.control),
                  let scalar = chars.unicodeScalars.first,
                  scalar.value >= 32, scalar.value != 127 else { return }
            updateFilter(filter + chars)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Topmost first, so an overlapping slice does not steal the click.
        let hit = frames.sorted { ($0.key == selected ? 1 : 0) > ($1.key == selected ? 1 : 0) }
            .first { $0.value.contains(point) }
        guard let hit else { cancel(); return }
        if hit.key == selected { finish(exitCode: 0) } else { select(hit.key) }
    }

    override func scrollWheel(with event: NSEvent) {
        // A trackpad flick keeps delivering momentum long after your fingers
        // have left the glass; without this one swipe walks every theme.
        guard event.momentumPhase == [] else { return }
        wheelAccum += event.scrollingDeltaX + event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        while abs(wheelAccum) >= threshold {
            selectAdjacent(wheelAccum > 0 ? -1 : 1)
            wheelAccum -= wheelAccum > 0 ? threshold : -threshold
        }
    }

    func finish(exitCode: Int32) {
        guard !rows.isEmpty, matches(selected) else { cancel(); return }
        print(rows[selected].value)
        exit(exitCode)
    }
    func cancel() { exit(1) }
}

// ── Window ───────────────────────────────────────────────────────────────────

// A borderless NSPanel: AeroSpace only tiles windows whose accessibility
// subrole is AXStandardWindow, so a panel is left alone without needing a
// window rule for a binary that has no bundle id to match on.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

let opts = parseArgs()
let rows = readRows()
if rows.isEmpty { exit(1) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    ?? NSScreen.main ?? NSScreen.screens[0]

// NOT .nonactivatingPanel: that style mask is a promise never to activate the
// app, so the panel never becomes key and every arrow key goes to whatever was
// in front. Verified -- with it set, System Events still reported the terminal
// as frontmost with the picker covering the screen.
let panel = PickerPanel(contentRect: screen.frame, styleMask: [.borderless],
                        backing: .buffered, defer: false, screen: screen)
panel.level = .screenSaver
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
panel.setFrame(screen.frame, display: true)

let view = CarouselView(rows: rows, opts: opts, frame: NSRect(origin: .zero, size: screen.frame.size),
                        scale: screen.backingScaleFactor)
panel.contentView = view
if let i = rows.firstIndex(where: { $0.value == opts.selected }) { view.selected = i }

panel.orderFrontRegardless()
app.activate(ignoringOtherApps: true)
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(view)
view.layout(animated: false)
view.loadNearby()

// An .accessory app can be refused activation if it asks while the frontmost
// app is still settling -- a full-screen overlay that eats keystrokes without
// responding to them is the worst possible failure, so ask twice.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
    guard !panel.isKeyWindow else { return }
    app.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(view)
}

// OMARCHY_PICKER_DEBUG=1: say whether the overlay actually holds the keyboard.
// Focus is the one thing you cannot see in a screenshot.
if ProcessInfo.processInfo.environment["OMARCHY_PICKER_DEBUG"] == "1" {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        FileHandle.standardError.write(Data("""
        app.isActive=\(app.isActive) panel.isKey=\(panel.isKeyWindow) \
        policy=\(app.activationPolicy().rawValue) \
        bundle=\(Bundle.main.bundleIdentifier ?? "none") \
        firstResponder=\(String(describing: panel.firstResponder))

        """.utf8))
    }
}

app.run()
