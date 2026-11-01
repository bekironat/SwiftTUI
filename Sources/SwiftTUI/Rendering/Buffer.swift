import Foundation

/// A single terminal grid cell, modeled after Ratatui's `buffer::Cell`.
public struct Cell: Equatable, Hashable, Sendable {
    public var symbol: String
    public var fg: Color
    public var bg: Color
    public var underlineColor: Color?
    public var modifiers: CellModifiers
    /// True when this cell is the right-hand trailing column of a 2-column wide character.
    public var isContinuation: Bool

    public static let empty = Cell()

    public init(
        symbol: String = " ",
        fg: Color = .default,
        bg: Color = .default,
        underlineColor: Color? = nil,
        modifiers: CellModifiers = [],
        isContinuation: Bool = false
    ) {
        self.symbol = symbol.isEmpty ? " " : symbol
        self.fg = fg
        self.bg = bg
        self.underlineColor = underlineColor
        self.modifiers = modifiers
        self.isContinuation = isContinuation
    }

    public init(symbol: String, style: CellStyle, isContinuation: Bool = false) {
        self.init(
            symbol: symbol,
            fg: style.fg,
            bg: style.bg,
            underlineColor: style.underlineColor,
            modifiers: style.modifiers,
            isContinuation: isContinuation
        )
    }

    public var style: CellStyle {
        get {
            CellStyle(fg: fg, bg: bg, underlineColor: underlineColor, modifiers: modifiers)
        }
        set {
            fg = newValue.fg
            bg = newValue.bg
            underlineColor = newValue.underlineColor
            modifiers = newValue.modifiers
        }
    }

    public mutating func reset(style: CellStyle = .default) {
        symbol = " "
        fg = style.fg
        bg = style.bg
        underlineColor = style.underlineColor
        modifiers = style.modifiers
        isContinuation = false
    }
}

/// A styled span of inline text (analogous to Ratatui's `Span`).
public struct StyledSpan: Equatable, Hashable, Sendable {
    public var text: String
    public var style: CellStyle

    public init(_ text: String, style: CellStyle = .default) {
        self.text = text
        self.style = style
    }

    public var displayWidth: Int {
        UnicodeWidth.width(of: text)
    }
}

/// A line composed of multiple styled spans (analogous to Ratatui's `Line`).
public struct StyledLine: Equatable, Hashable, Sendable {
    public var spans: [StyledSpan]

    public init(_ spans: [StyledSpan] = []) {
        self.spans = spans
    }

    public init(_ text: String, style: CellStyle = .default) {
        self.spans = [StyledSpan(text, style: style)]
    }

    public var displayWidth: Int {
        spans.reduce(0) { $0 + $1.displayWidth }
    }

    public var plainText: String {
        spans.map(\.text).joined()
    }
}

/// Deferred overlay rendering pass entry (used for cursor-anchored autocomplete popups, dropdowns, and modals).
public struct OverlayOperation {
    public let zIndex: Int
    public let render: (inout Buffer) -> Void

    public init(zIndex: Int = 100, render: @escaping (inout Buffer) -> Void) {
        self.zIndex = zIndex
        self.render = render
    }
}

/// A 2D grid of `Cell`s representing a single rendered terminal frame.
public struct Buffer {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var cells: [Cell]

    /// Hardware cursor position requested by the currently focused input control, if any.
    public var cursorPosition: Point?

    private var clipStack: [Rect]
    private var overlays: [OverlayOperation] = []

    public init(width: Int, height: Int, defaultCell: Cell = .empty) {
        let w = max(0, width)
        let h = max(0, height)
        self.width = w
        self.height = h
        self.cells = Array(repeating: defaultCell, count: w * h)
        self.clipStack = [Rect(x: 0, y: 0, width: w, height: h)]
    }

    public init(size: Size, defaultCell: Cell = .empty) {
        self.init(width: size.width, height: size.height, defaultCell: defaultCell)
    }

    public var bounds: Rect {
        Rect(x: 0, y: 0, width: width, height: height)
    }

    public var size: Size {
        Size(width: width, height: height)
    }

    public var currentClip: Rect {
        clipStack.last ?? bounds
    }

    // MARK: - Scissor / Clipping Stack

    public mutating func pushClip(_ rect: Rect) {
        let intersected = currentClip.intersection(rect)
        clipStack.append(intersected)
    }

    public mutating func popClip() {
        guard clipStack.count > 1 else { return }
        clipStack.removeLast()
    }

    public mutating func withClip(_ rect: Rect, _ body: (inout Buffer) -> Void) {
        pushClip(rect)
        body(&self)
        popClip()
    }

    // MARK: - Deferred Overlay Pass (Popovers, Autocomplete, Modals)

    /// Schedules a high-z-order overlay render callback to execute after the primary view tree finishes drawing.
    public mutating func addOverlay(zIndex: Int = 100, _ render: @escaping (inout Buffer) -> Void) {
        overlays.append(OverlayOperation(zIndex: zIndex, render: render))
    }

    /// Executes all queued overlays in ascending `zIndex` order with full-screen clip bounds.
    public mutating func flushOverlays() {
        guard !overlays.isEmpty else { return }
        // Allow overlays themselves to enqueue nested overlays if needed
        while !overlays.isEmpty {
            let batch = overlays.sorted { $0.zIndex < $1.zIndex }
            overlays.removeAll()
            let savedStack = clipStack
            clipStack = [bounds]
            for op in batch {
                op.render(&self)
            }
            clipStack = savedStack
        }
    }

    // MARK: - Cell Access & Mutation

    @inline(__always)
    private func index(x: Int, y: Int) -> Int? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return y * width + x
    }

    public func cell(atX x: Int, y: Int) -> Cell? {
        guard let idx = index(x: x, y: y) else { return nil }
        return cells[idx]
    }

    /// Writes a symbol & style at `(x, y)` respecting the active clip rect and wide-character continuation invariants.
    public mutating func setCell(
        x: Int,
        y: Int,
        symbol: String,
        style: CellStyle = .default,
        preserveBackgroundIfDefault: Bool = true
    ) {
        let clip = currentClip
        guard clip.contains(Point(x: x, y: y)), let idx = index(x: x, y: y) else { return }

        let symWidth = max(1, UnicodeWidth.width(of: symbol))
        // If a 2-column glyph won't fit inside the clip rect, write a space instead
        if symWidth == 2 && !clip.contains(Point(x: x + 1, y: y)) {
            var fallbackStyle = style
            if preserveBackgroundIfDefault && fallbackStyle.bg == .default {
                fallbackStyle.bg = cells[idx].bg
            }
            cleanUpWideOverlap(atX: x, y: y)
            cells[idx] = Cell(symbol: " ", style: fallbackStyle)
            return
        }

        cleanUpWideOverlap(atX: x, y: y)
        if symWidth == 2 {
            cleanUpWideOverlap(atX: x + 1, y: y)
        }

        var effectiveStyle = style
        if preserveBackgroundIfDefault && effectiveStyle.bg == .default {
            effectiveStyle.bg = cells[idx].bg
        }

        cells[idx] = Cell(symbol: symbol, style: effectiveStyle, isContinuation: false)

        if symWidth == 2, let nextIdx = index(x: x + 1, y: y) {
            var contStyle = style
            if preserveBackgroundIfDefault && contStyle.bg == .default {
                contStyle.bg = cells[nextIdx].bg
            }
            cells[nextIdx] = Cell(symbol: " ", style: contStyle, isContinuation: true)
        }
    }

    /// Cleans up orphaned halves when overwriting either the leading or trailing cell of a 2-column wide character.
    private mutating func cleanUpWideOverlap(atX x: Int, y: Int) {
        guard let idx = index(x: x, y: y) else { return }
        if cells[idx].isContinuation {
            // We are overwriting the trailing cell; blank out the leading wide character at x - 1
            if x > 0, let prevIdx = index(x: x - 1, y: y) {
                cells[prevIdx].symbol = " "
                cells[prevIdx].isContinuation = false
            }
            cells[idx].isContinuation = false
        } else if UnicodeWidth.width(of: cells[idx].symbol) == 2 {
            // We are overwriting the leading cell of a wide character; clear continuation flag at x + 1
            if x + 1 < width, let nextIdx = index(x: x + 1, y: y), cells[nextIdx].isContinuation {
                cells[nextIdx].symbol = " "
                cells[nextIdx].isContinuation = false
            }
        }
    }

    // MARK: - String & Span Drawing

    /// Writes a plain string starting at `(x, y)` and returns the number of columns advanced.
    @discardableResult
    public mutating func writeString(
        x: Int,
        y: Int,
        _ text: String,
        style: CellStyle = .default,
        maxWidth: Int? = nil
    ) -> Int {
        guard y >= currentClip.minY && y < currentClip.maxY else { return 0 }
        let limitX = maxWidth.map { min(currentClip.maxX, x + max(0, $0)) } ?? currentClip.maxX
        var curX = x

        for ch in text {
            if ch == "\n" || ch == "\r" { continue }
            let cw = max(1, UnicodeWidth.width(of: ch))
            if curX + cw > limitX {
                break
            }
            if curX >= currentClip.minX {
                setCell(x: curX, y: y, symbol: String(ch), style: style)
            }
            curX += cw
        }
        return max(0, curX - x)
    }

    /// Writes a sequence of styled spans starting at `(x, y)` and returns the number of columns advanced.
    @discardableResult
    public mutating func writeSpans(
        x: Int,
        y: Int,
        _ spans: [StyledSpan],
        baseStyle: CellStyle = .default,
        maxWidth: Int? = nil
    ) -> Int {
        guard y >= currentClip.minY && y < currentClip.maxY else { return 0 }
        let limitX = maxWidth.map { min(currentClip.maxX, x + max(0, $0)) } ?? currentClip.maxX
        var curX = x

        for span in spans {
            let merged = baseStyle.merging(span.style)
            let remaining = limitX - curX
            if remaining <= 0 { break }
            let written = writeString(x: curX, y: y, span.text, style: merged, maxWidth: remaining)
            curX += written
        }
        return max(0, curX - x)
    }

    // MARK: - Area Fill, Clear & Box Borders

    /// Fills a rectangular area with `symbol` and `style`, respecting the current clip region.
    public mutating func fill(_ rect: Rect, symbol: String = " ", style: CellStyle = .default) {
        let clipped = rect.intersection(currentClip)
        guard !clipped.isEmpty else { return }
        for row in clipped.minY..<clipped.maxY {
            for col in clipped.minX..<clipped.maxX {
                if let idx = index(x: col, y: row) {
                    var effectiveStyle = style
                    if effectiveStyle.bg == .default {
                        effectiveStyle.bg = cells[idx].bg
                    }
                    cells[idx] = Cell(symbol: symbol, style: effectiveStyle, isContinuation: false)
                }
            }
        }
    }

    /// Resets all cells in `rect` to spaces with `style` (overwriting any previous background/foreground), like Ratatui's `Clear` widget.
    public mutating func clear(_ rect: Rect, style: CellStyle = .default) {
        let clipped = rect.intersection(currentClip)
        guard !clipped.isEmpty else { return }
        for row in clipped.minY..<clipped.maxY {
            for col in clipped.minX..<clipped.maxX {
                cleanUpWideOverlap(atX: col, y: row)
                if let idx = index(x: col, y: row) {
                    cells[idx] = Cell(symbol: " ", style: style, isContinuation: false)
                }
            }
        }
    }

    public mutating func drawHorizontalLine(
        x: Int,
        y: Int,
        length: Int,
        symbol: String = "─",
        style: CellStyle = .default
    ) {
        guard length > 0 else { return }
        for col in x..<(x + length) {
            setCell(x: col, y: y, symbol: symbol, style: style)
        }
    }

    public mutating func drawVerticalLine(
        x: Int,
        y: Int,
        length: Int,
        symbol: String = "│",
        style: CellStyle = .default
    ) {
        guard length > 0 else { return }
        for row in y..<(y + length) {
            setCell(x: x, y: row, symbol: symbol, style: style)
        }
    }

    /// Draws a box border around `rect` with optional top and bottom titles.
    public mutating func drawBorder(
        _ rect: Rect,
        style borderStyle: BorderStyle,
        borderCellStyle: CellStyle = .default,
        title: String? = nil,
        titleStyle: CellStyle? = nil,
        titleAlignment: HorizontalAlignment = .leading,
        bottomTitle: String? = nil
    ) {
        guard rect.width >= 2, rect.height >= 2, let symbols = borderStyle.symbols else { return }

        let minX = rect.minX
        let maxX = rect.maxX - 1
        let minY = rect.minY
        let maxY = rect.maxY - 1

        // Corners
        setCell(x: minX, y: minY, symbol: symbols.topLeft, style: borderCellStyle)
        setCell(x: maxX, y: minY, symbol: symbols.topRight, style: borderCellStyle)
        setCell(x: minX, y: maxY, symbol: symbols.bottomLeft, style: borderCellStyle)
        setCell(x: maxX, y: maxY, symbol: symbols.bottomRight, style: borderCellStyle)

        // Top & Bottom horizontal edges
        if rect.width > 2 {
            drawHorizontalLine(x: minX + 1, y: minY, length: rect.width - 2, symbol: symbols.horizontalTop, style: borderCellStyle)
            drawHorizontalLine(x: minX + 1, y: maxY, length: rect.width - 2, symbol: symbols.horizontalBottom, style: borderCellStyle)
        }

        // Left & Right vertical edges
        if rect.height > 2 {
            drawVerticalLine(x: minX, y: minY + 1, length: rect.height - 2, symbol: symbols.verticalLeft, style: borderCellStyle)
            drawVerticalLine(x: maxX, y: minY + 1, length: rect.height - 2, symbol: symbols.verticalRight, style: borderCellStyle)
        }

        // Top Title
        if let title, !title.isEmpty, rect.width > 4 {
            let paddedTitle = " \(title) "
            let availWidth = rect.width - 2
            let truncated = UnicodeWidth.truncate(paddedTitle, maxWidth: availWidth)
            let titleW = UnicodeWidth.width(of: truncated)
            let startX: Int
            switch titleAlignment {
            case .leading:
                startX = minX + 1
            case .center:
                startX = minX + 1 + max(0, (availWidth - titleW) / 2)
            case .trailing:
                startX = maxX - titleW
            }
            let effectiveTitleStyle = titleStyle ?? borderCellStyle.bold()
            writeString(x: startX, y: minY, truncated, style: effectiveTitleStyle, maxWidth: availWidth)
        }

        // Bottom Title
        if let bottomTitle, !bottomTitle.isEmpty, rect.width > 4 {
            let paddedBottom = " \(bottomTitle) "
            let availWidth = rect.width - 2
            let truncated = UnicodeWidth.truncate(paddedBottom, maxWidth: availWidth)
            writeString(x: minX + 1, y: maxY, truncated, style: borderCellStyle, maxWidth: availWidth)
        }
    }

    // MARK: - Snapshot & Inspection Helpers

    /// Returns the plain text string of a given row (skipping continuation placeholder cells for wide characters).
    public func line(at row: Int) -> String {
        guard row >= 0 && row < height else { return "" }
        var result = ""
        result.reserveCapacity(width)
        for col in 0..<width {
            let c = cells[row * width + col]
            if !c.isContinuation {
                result.append(c.symbol)
            }
        }
        return result
    }

    /// Returns all rows as plain strings (with trailing spaces preserved for exact width checks, or trimmed).
    public func lines(trimTrailingSpaces: Bool = false) -> [String] {
        (0..<height).map { row in
            let raw = line(at: row)
            guard trimTrailingSpaces else { return raw }
            var trimmed = raw
            while trimmed.last == " " {
                trimmed.removeLast()
            }
            return trimmed
        }
    }

    /// Returns a multi-line textual snapshot of the entire buffer.
    public func snapshot(trimTrailingSpaces: Bool = false) -> String {
        lines(trimTrailingSpaces: trimTrailingSpaces).joined(separator: "\n")
    }
}
