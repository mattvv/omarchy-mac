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
    let isCurrent: Bool
}

struct Options {
    var selected     = ""
    var showLabels   = false
    var filterable   = false
    var chrome       = false     // compose a mock desktop over the wallpaper
    var hint         = ""
    var altKey: Character? = nil
    var workspace = ""          // AeroSpace workspace to return to on dismissal
    var menuBackend = ""        // path to menu.py -- presence selects list mode
    var corpusBackend = ""      // same script, asked for everything searchable
    var route = "root"          // which route the rows on stdin belong to
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
        case "--workspace":  o.workspace = next()
        case "--menu":       o.menuBackend = next()
        case "--corpus":     o.corpusBackend = next()
        case "--route":      o.route = next()
        case "--background": o.background = next()
        case "--foreground": o.foreground = next()
        case "--accent":     o.accent = next()
        case "--dark-background": o.darkBackground = next()
        default: break
        }
    }
    return o
}

/// Reads stdin to EOF, which can only ever happen once -- call it twice and the
/// second call returns nothing at all. It is called from exactly one place, on a
/// background queue, after the window is already up.
func parseRows(_ text: String) -> [Row] {
    return text.split(separator: "\n").compactMap { line in
        let f = line.components(separatedBy: "\t")
        guard let value = f.first, !value.isEmpty else { return nil }
        let image = f.count > 1 ? f[1] : ""
        let label = f.count > 2 ? f[2] : value
        let palette = (f.count > 3 ? f[3] : "")
            .split(separator: ",").map { hexColor(String($0)) }
        return Row(value: value, imagePath: image, label: label, palette: palette,
                   isCurrent: f.count > 4 && f[4] == "1")
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
    var rows: [Row] = []
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

    let scale: CGFloat

    init(opts: Options, frame: NSRect, scale: CGFloat) {
        self.opts = opts
        self.scale = scale
        // 768pt of preview is about half of a 1512pt laptop screen, which is
        // how it looks on omarchy's 1440p reference. Track the screen so an
        // external display does not shrink it into the middle.
        self.s = min(max(min(frame.width / 1512, frame.height / 982), 0.72), 1.9)
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsScale = scale
        build(scale: scale)
    }

    /// Rows arrive after the window is already on screen -- see the comment at
    /// the bottom of this file about why the overlay cannot wait for them.
    func setRows(_ newRows: [Row]) {
        rows = newRows
        for _ in rows {
            let item = ItemLayer(scale: scale)
            item.dim.backgroundColor = hexColor(opts.background).cgColor
            item.holder.isHidden = true
            layer?.insertSublayer(item.holder, above: scrimLayer)
            items.append(item)
        }
        if let i = rows.firstIndex(where: { $0.value == opts.selected })
            ?? rows.firstIndex(where: { $0.isCurrent }) { selected = i }
        layout(animated: false)
        loadNearby()
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
        // matches() indexes rows[], and rows arrive asynchronously now -- type
        // during the window between launch and the first row and this walks off
        // the end of an empty array. selectAdjacent and select are guarded;
        // this was not.
        guard !rows.isEmpty else { return }
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
        guard !rows.isEmpty else { return }       // still loading -- wait
        guard matches(selected) else { cancel(); return }
        dismiss(printing: rows[selected].value, code: exitCode)
    }
    func cancel() { dismiss(printing: nil, code: 1) }
}


// ── Menu mode ────────────────────────────────────────────────────────────────
//
// The same overlay, rendering a filterable list instead of a carousel: our
// stand-in for omarchy's `omarchy-menu`. Rows are NSTableView rather than the
// hand-drawn layers the carousel uses -- a list needs selection, scrolling,
// accessibility and text behaviour, all of which AppKit already has and none of
// which is worth reimplementing for forty rows.

struct MenuRow {
    let id: String, icon: String, label: String, kind: String, aliases: String
    // Optional trailing columns, used by the keybindings view: the chord shown
    // right-aligned, the section it belongs to, and the raw command behind it.
    let leading: String, group: String, detail: String
    var isSubmenu: Bool { kind == "submenu" }
    /// Reference rows exist to be read. Nothing runs them -- see menu.py, which
    /// refuses the same ids on its side.
    var isReference: Bool { kind == "reference" || kind == "disabled" }
    func matches(_ q: String) -> Bool {
        if q.isEmpty { return true }
        let n = q.lowercased()
        return label.lowercased().contains(n) || id.lowercased().contains(n)
            || aliases.lowercased().contains(n) || leading.lowercased().contains(n)
    }
}

func parseMenuRows(_ text: String) -> [MenuRow] {
    text.split(separator: "\n").compactMap { line in
        let f = line.components(separatedBy: "\t")
        guard let id = f.first, !id.isEmpty else { return nil }
        return MenuRow(id: id,
                       icon:  f.count > 1 ? f[1] : "",
                       label: f.count > 2 ? f[2] : id,
                       kind:  f.count > 3 ? f[3] : "action",
                       aliases: f.count > 4 ? f[4] : "",
                       leading: f.count > 5 ? f[5] : "",
                       group:   f.count > 6 ? f[6] : "",
                       detail:  f.count > 7 ? f[7] : "")
    }
}

/// Text input, routed the way AppKit expects: AppKit owns the field editor, and
/// navigation is intercepted in the delegate rather than by reading keystrokes.
/// Every branch checks `hasMarkedText()` first so an input method composing a
/// character keeps Return and Escape for itself.
final class MenuInput: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField(frame: .zero)
    var filterChanged: (String) -> Void = { _ in }
    var moveSelection: (Int) -> Void = { _ in }
    var acceptSelection: () -> Void = {}
    var escape: () -> Void = {}
    var back: () -> Void = {}

    override init() {
        super.init()
        field.placeholderString = "Search"
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
    }

    func controlTextDidChange(_ notification: Notification) {
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        filterChanged(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):       moveSelection(-1); return true
        case #selector(NSResponder.moveDown(_:)):     moveSelection(1);  return true
        case #selector(NSResponder.insertNewline(_:)): acceptSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)): escape();       return true
        case #selector(NSResponder.deleteBackward(_:)):
            // Empty backspace goes up a level. Left/Right stay with the editor:
            // making Left mean "parent" would break editing a query.
            if field.stringValue.isEmpty { back(); return true }
            return false
        default: return false
        }
    }
}

enum MenuLine {
    case group(String)
    case item(MenuRow)
}

final class MenuView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let opts: Options
    let s: CGFloat
    var rows: [MenuRow] = []
    var shown: [MenuRow] = []
    var lines: [MenuLine] = []
    var route = "root"
    /// Width of the chord column, measured over *every* row rather than the
    /// filtered ones, so the labels do not shuffle sideways while typing.
    var chordWidth: CGFloat = 0
    /// Everything searchable, loaded once in the background. A query looks here
    /// rather than at the current level: ⌘Space took the launcher's key, so
    /// typing "theme" must find the theme picker from anywhere, and typing an
    /// app name must find the app.
    var corpus: [MenuRow] = []
    var searchingEverything = false
    var isReferenceView: Bool { rows.contains { !$0.leading.isEmpty } }
    var stack: [(route: String, rows: [MenuRow], query: String)] = []

    let input = MenuInput()
    let table = NSTableView()
    let scroll = NSScrollView()
    let card = NSView()
    let title = NSTextField(labelWithString: "")
    let separator = NSView()
    let hint = NSTextField(labelWithString: "")

    init(opts: Options, frame: NSRect, scale: CGFloat) {
        self.opts = opts
        self.s = min(max(min(frame.width / 1512, frame.height / 982), 0.8), 1.6)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = hexColor(opts.background, alpha: 0.5).cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    var cardW: CGFloat { isReferenceView ? 800 * s : 560 * s }
    /// Chrome is title + field + separator above, hint below; the rest is rows,
    /// capped so a long list scrolls instead of running off the screen.
    func cardH(_ rowCount: Int) -> CGFloat {
        let rowsH = CGFloat(max(1, rowCount)) * (34 * s + 2 * s)
        return min(76 * s + rowsH + 54 * s, bounds.height * 0.75)
    }

    func layoutCard() {
        let w = cardW, h = cardH(shown.count)
        card.frame = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                            width: w, height: h)
        title.frame = NSRect(x: 20 * s, y: h - 30 * s, width: w - 40 * s, height: 16 * s)
        input.field.frame = NSRect(x: 14 * s, y: h - 68 * s, width: w - 28 * s, height: 30 * s)
        separator.frame = NSRect(x: 0, y: h - 76 * s, width: w, height: 1)
        scroll.frame = NSRect(x: 8 * s, y: 40 * s, width: w - 16 * s, height: h - 120 * s)
        hint.frame = NSRect(x: 0, y: 14 * s, width: w, height: 14 * s)
    }

    func build() {
        let w = 560 * s, h = 460 * s
        card.wantsLayer = true
        card.layer?.backgroundColor = hexColor(opts.darkBackground, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 12 * s
        card.layer?.borderWidth = 1 * s
        card.layer?.borderColor = hexColor(opts.accent, alpha: 0.7).cgColor
        card.frame = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        addSubview(card)

        title.font = .systemFont(ofSize: 12 * s, weight: .semibold)
        title.textColor = hexColor(opts.foreground, alpha: 0.45)
        title.frame = NSRect(x: 20 * s, y: h - 30 * s, width: w - 40 * s, height: 16 * s)
        card.addSubview(title)

        input.field.font = .systemFont(ofSize: 19 * s)
        input.field.textColor = hexColor(opts.foreground)
        input.field.frame = NSRect(x: 14 * s, y: h - 68 * s, width: w - 28 * s, height: 30 * s)
        card.addSubview(input.field)

        separator.frame = NSRect(x: 0, y: h - 76 * s, width: w, height: 1)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = hexColor(opts.foreground, alpha: 0.12).cgColor
        card.addSubview(separator)

        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 34 * s
        table.intercellSpacing = NSSize(width: 0, height: 2 * s)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row")))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.frame = NSRect(x: 8 * s, y: 40 * s, width: w - 16 * s, height: h - 120 * s)
        card.addSubview(scroll)

        hint.font = .systemFont(ofSize: 11 * s, weight: .medium)
        hint.textColor = hexColor(opts.foreground, alpha: 0.4)
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 14 * s, width: w, height: 14 * s)
        hint.stringValue = "↑↓ move    ⏎ select    ⌫ back    esc close"
        card.addSubview(hint)

        input.filterChanged = { [weak self] q in self?.applyFilter(q) }
        input.moveSelection = { [weak self] d in self?.move(d) }
        input.acceptSelection = { [weak self] in self?.accept() }
        input.escape = { [weak self] in self?.escapePressed() }
        input.back = { [weak self] in self?.pop() }
    }

    func setRows(_ newRows: [MenuRow], route: String) {
        self.rows = newRows
        self.route = route
        let font = NSFont.systemFont(ofSize: 13 * s, weight: .medium)
        chordWidth = newRows.map {
            $0.leading.isEmpty ? 0
                : ($0.leading as NSString)
                    .size(withAttributes: [.font: font]).width + 18 * s
        }.max() ?? 0
        title.stringValue = route == "root" ? "Omarchy  ⌘Space"
                                            : route.replacingOccurrences(of: ".", with: " › ")
        applyFilter(input.field.stringValue)
    }

    func applyFilter(_ q: String) {
        searchingEverything = !q.isEmpty && !corpus.isEmpty
        let source = searchingEverything ? corpus : rows
        shown = source.filter { $0.matches(q) }
        lines = []
        var lastGroup = ""
        for row in shown {
            if !row.group.isEmpty && row.group != lastGroup {
                lines.append(.group(row.group))
                lastGroup = row.group
            }
            lines.append(.item(row))
        }
        layoutCard()
        table.reloadData()
        selectFirstItem()
    }

    func selectFirstItem() {
        if let i = lines.firstIndex(where: { if case .item = $0 { return true }; return false }) {
            table.selectRowIndexes([i], byExtendingSelection: false)
            table.scrollRowToVisible(i)
        }
    }

    func itemAt(_ index: Int) -> MenuRow? {
        guard index >= 0, index < lines.count, case let .item(row) = lines[index] else { return nil }
        return row
    }

    func move(_ delta: Int) {
        guard !lines.isEmpty else { return }
        // Step over section headings rather than landing on them.
        var next = table.selectedRow + delta
        while next >= 0, next < lines.count, itemAt(next) == nil { next += delta }
        guard next >= 0, next < lines.count else { return }
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    func accept() {
        guard let row = itemAt(table.selectedRow) else { return }
        // A reference row is something to read, not something to run. Nothing
        // is printed, so nothing downstream can execute it either.
        if row.isReference { return }
        if row.isSubmenu { push(row.id) } else { dismiss(printing: row.id, code: 0) }
    }

    /// Descend in place rather than exiting and relaunching. Every overlay that
    /// closes costs a workspace excursion to correct (see CLAUDE.md), so a menu
    /// three levels deep would pay it three times.
    func push(_ newRoute: String) {
        stack.append((route, rows, input.field.stringValue))
        input.field.stringValue = ""
        loadRoute(newRoute)
    }

    func pop() {
        guard let previous = stack.popLast() else { return }
        input.field.stringValue = previous.query
        setRows(previous.rows, route: previous.route)
    }

    func escapePressed() {
        if !input.field.stringValue.isEmpty {
            input.field.stringValue = ""
            applyFilter("")            // back to the level, out of global search
        } else if !stack.isEmpty {
            pop()
        } else {
            dismiss(printing: nil, code: 1)
        }
    }

    func loadCorpus() {
        let backend = opts.corpusBackend
        guard !backend.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [backend, "corpus"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            task.standardInput = FileHandle.nullDevice
            do { try task.run() } catch { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return }
            let parsed = parseMenuRows(String(data: data, encoding: .utf8) ?? "")
            DispatchQueue.main.async {
                guard let self else { return }
                self.corpus = parsed
                // A query typed while this was still loading searched only the
                // current level; redo it now that there is more to search.
                if !self.input.field.stringValue.isEmpty {
                    self.applyFilter(self.input.field.stringValue)
                }
            }
        }
    }

    func loadRoute(_ newRoute: String) {
        let backend = opts.menuBackend
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            // /usr/bin/python3 explicitly: a GUI launch has no Homebrew on PATH,
            // and menu.py is written to run under the 3.9 that ships with macOS.
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [backend, "rows", newRoute]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardInput = FileHandle.nullDevice
            let errPipe = Pipe()
            task.standardError = errPipe
            do { try task.run() } catch {
                DispatchQueue.main.async { self?.showBackendError("cannot run \(backend)") }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            // A backend that dies must not look like an empty submenu. Keep what
            // is on screen and say so, rather than silently showing nothing.
            guard task.terminationStatus == 0 else {
                let message = String(data: errData, encoding: .utf8)?
                    .split(separator: "\n").last.map(String.init) ?? "backend failed"
                DispatchQueue.main.async { self?.showBackendError(message) }
                return
            }
            let parsed = parseMenuRows(String(data: data, encoding: .utf8) ?? "")
            DispatchQueue.main.async { self?.setRows(parsed, route: newRoute) }
        }
    }

    func showBackendError(_ message: String) {
        title.stringValue = "⚠︎  " + message
        title.textColor = hexColor(opts.foreground, alpha: 0.9)
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        itemAt(row) == nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        itemAt(row) != nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let item = itemAt(row) else {
            guard case let .group(name) = lines[row] else { return nil }
            let header = NSTableCellView()
            let text = NSTextField(labelWithString: name)
            text.font = .systemFont(ofSize: 11 * s, weight: .semibold)
            text.textColor = hexColor(opts.accent, alpha: 0.9)
            text.frame = NSRect(x: 12 * s, y: 8 * s, width: cardW - 40 * s, height: 16 * s)
            header.addSubview(text)
            return header
        }
        let cell = NSTableCellView()
        // Nerd Font on the icon only: a missing glyph must not take the label
        // down with it.
        let icon = NSTextField(labelWithString: item.icon)
        icon.font = NSFont(name: "Hack Nerd Font", size: 15 * s) ?? .systemFont(ofSize: 15 * s)
        icon.textColor = hexColor(opts.accent)
        icon.frame = NSRect(x: 12 * s, y: 7 * s, width: 24 * s, height: 20 * s)
        cell.addSubview(icon)

        let labelX = item.leading.isEmpty ? 42 * s : 12 * s + chordWidth
        let label = NSTextField(labelWithString: item.label)
        label.font = .systemFont(ofSize: 14 * s)
        // A disabled row is still listed -- it answers "why did that shortcut
        // stop working?" -- but it reads as inactive.
        label.textColor = hexColor(opts.foreground, alpha: item.kind == "disabled" ? 0.45 : 1)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: labelX, y: 7 * s,
                             width: cardW - labelX - 40 * s, height: 20 * s)
        cell.addSubview(label)

        if !item.leading.isEmpty {
            let chord = NSTextField(labelWithString: item.leading)
            chord.font = .systemFont(ofSize: 13 * s, weight: .medium)
            chord.textColor = hexColor(opts.accent)
            chord.alignment = .right
            chord.frame = NSRect(x: 12 * s, y: 7 * s, width: chordWidth - 12 * s, height: 20 * s)
            cell.addSubview(chord)
        }

        if item.isSubmenu {
            let chevron = NSTextField(labelWithString: "›")
            chevron.font = .systemFont(ofSize: 15 * s, weight: .medium)
            chevron.textColor = hexColor(opts.foreground, alpha: 0.35)
            chevron.alignment = .right
            chevron.frame = NSRect(x: scroll.frame.width - 34 * s, y: 7 * s,
                                   width: 20 * s, height: 20 * s)
            cell.addSubview(chevron)
        }
        return cell
    }

    override func mouseDown(with event: NSEvent) {
        // Outside the card closes, as the carousel's scrim does.
        let point = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(point) { dismiss(printing: nil, code: 1) }
    }
}

// ── Window ───────────────────────────────────────────────────────────────────

/// True once dismissal has begun. Delayed callbacks -- the activation retry,
/// the debug probes -- must not resurrect a panel during the 80ms it spends
/// handing focus back before the process exits.
var isFinishing = false

/// Put the keyboard back where it was.
///
/// Left to itself macOS hands focus to the next app in its own order when we
/// quit, and under AeroSpace that choice drags you to whichever workspace that
/// app's window lives on -- you ask for a theme and land on workspace 1.
func dismiss(printing value: String?, code: Int32) {
    isFinishing = true
    panel.orderOut(nil)

    // Measured: the workspace excursion happens the moment the window is
    // ordered out, not when the process exits (a picker held open for six
    // seconds after orderOut had already been moved). So it cannot be avoided
    // at the window level -- only corrected, and the correction is worth doing
    // here rather than waiting on a detached interpreter to start.
    if !opts.workspace.isEmpty {
        for path in ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
        where FileManager.default.isExecutableFile(atPath: path) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["workspace", opts.workspace]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            break
        }
    }
    // OMARCHY_PICKER_NO_HANDBACK=1 skips this. On a workspace with no windows
    // of its own the previously-frontmost app is, by definition, one whose
    // windows are elsewhere -- so handing focus back may be *requesting* the
    // very excursion the restore helper then spends seconds undoing.
    if !nonactivating,
       ProcessInfo.processInfo.environment["OMARCHY_PICKER_NO_HANDBACK"] != "1",
       let prev = previousApp,
       prev.processIdentifier != ProcessInfo.processInfo.processIdentifier {
        prev.activate(options: [])
    }
    if let value { print(value) }
    // OMARCHY_PICKER_LINGER=<seconds> holds the process open after the window
    // is gone. It answers one question: does the workspace excursion happen
    // when the window is ordered out, or when the process exits? If only at
    // exit, no amount of window-level fiddling helps and the answer is a
    // resident host -- which is what upstream has, since omarchy-shell is a
    // long-lived process whose menu is a plugin that shows and hides.
    let linger = Double(ProcessInfo.processInfo.environment["OMARCHY_PICKER_LINGER"] ?? "") ?? 0.08
    DispatchQueue.main.asyncAfter(deadline: .now() + linger) { exit(code) }
}

// A borderless NSPanel: AeroSpace only tiles windows whose accessibility
// subrole is AXStandardWindow, so a panel is left alone without needing a
// window rule for a binary that has no bundle id to match on.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // Main is what an *active application* has. A panel that never activates
    // its app must not claim it.
    override var canBecomeMain: Bool { !nonactivating }

    /// A hand-built process has no Edit menu, so ⌘A/C/X/V/Z reach nothing.
    /// Route them through the responder chain to the field editor by hand.
    /// Deliberately narrow: Return, Escape and ordinary characters are never
    /// touched here -- the input context must see those first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor,
              mods == [.command] || mods == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        let action: String? = mods == [.command, .shift]
            ? (key == "z" ? "redo:" : nil)
            : ["a": "selectAll:", "c": "copy:", "x": "cut:", "v": "paste:", "z": "undo:"][key]
        if let action, NSApp.sendAction(NSSelectorFromString(action), to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

let opts = parseArgs()

// OMARCHY_PICKER_NONACTIVATING=1 selects the other focus model: a panel that
// takes the keyboard without its application ever becoming active. The success
// state then reads app.isActive=false with panel.isKeyWindow=true, which looks
// like failure and is not.
let nonactivating = ProcessInfo.processInfo.environment["OMARCHY_PICKER_NONACTIVATING"] == "1"

// Captured before activating, while the answer is still someone else.
let previousApp = NSWorkspace.shared.frontmostApplication

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    ?? NSScreen.main ?? NSScreen.screens[0]

// NOT .nonactivatingPanel: that style mask is a promise never to activate the
// app, so the panel never becomes key and every arrow key goes to whatever was
// in front. Verified -- with it set, System Events still reported the terminal
// as frontmost with the picker covering the screen.
let panel = PickerPanel(contentRect: screen.frame,
                        styleMask: nonactivating ? [.borderless, .nonactivatingPanel]
                                                 : [.borderless],
                        backing: .buffered, defer: false, screen: screen)
panel.becomesKeyOnlyIfNeeded = false
panel.level = .screenSaver
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
panel.setFrame(screen.frame, display: true)

let isMenu = !opts.menuBackend.isEmpty
let carousel = isMenu ? nil : CarouselView(opts: opts,
                                           frame: NSRect(origin: .zero, size: screen.frame.size),
                                           scale: screen.backingScaleFactor)
let menu = isMenu ? MenuView(opts: opts, frame: NSRect(origin: .zero, size: screen.frame.size),
                             scale: screen.backingScaleFactor) : nil
let view: NSView = carousel ?? menu!
panel.contentView = view

panel.orderFrontRegardless()
// Asking to activate while wearing a nonactivating style mask is a
// contradiction -- it is the likeliest reason this model was written off here
// the first time.
if !nonactivating { app.activate(ignoringOtherApps: true) }
panel.makeKeyAndOrderFront(nil)
// The field editor is substituted by AppKit once the panel is key and the
// field is in the hierarchy -- in that order.
if let menu {
    panel.initialFirstResponder = menu.input.field
    panel.makeFirstResponder(menu.input.field)
} else {
    panel.makeFirstResponder(view)
}
carousel?.layout(animated: false)

// Read the rows only once the overlay is already up and holding the keyboard.
//
// Reading them first cost about half a second between the launcher starting
// this process and anything appearing, and under AeroSpace that gap is not
// merely ugly: Raycast dismisses its own window in it, focus falls to whatever
// app happens to own a window elsewhere, and the workspace goes with it. An
// overlay that is already key has nowhere for focus to fall.
DispatchQueue.global(qos: .userInitiated).async {
    let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    DispatchQueue.main.async {
        if let menu {
            let parsed = parseMenuRows(text)
            if parsed.isEmpty { exit(1) }
            // The rows on stdin belong to whichever route the caller asked for
            // -- labelling them "root" put the wrong heading on a submenu
            // opened directly, and told Escape it had nowhere to go back to.
            menu.setRows(parsed, route: opts.route)
            menu.loadCorpus()
        } else {
            let parsed = parseRows(text)
            if parsed.isEmpty { exit(1) }
            carousel!.setRows(parsed)
        }
    }
}

// An .accessory app can be refused activation if it asks while the frontmost
// app is still settling -- a full-screen overlay that eats keystrokes without
// responding to them is the worst possible failure, so ask twice.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
    guard !isFinishing, !nonactivating, !panel.isKeyWindow else { return }
    app.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(menu?.input.field ?? view)
}

// OMARCHY_PICKER_DEBUG_SELECT=1: apply the highlighted row unattended. Picking
// is the one path that cannot be screenshotted or driven without typing into
// someone's live session, and it is the path that moves focus.
if ProcessInfo.processInfo.environment["OMARCHY_PICKER_DEBUG_SELECT"] == "1" {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        guard !isFinishing else { return }
        if let menu { menu.accept() } else { carousel?.finish(exitCode: 0) }
    }
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
