import Foundation

// MARK: - Bar Chart

/// A data item displayed inside a `BarChart`.
public struct BarChartItem: Sendable, Equatable {
    public var label: String
    public var value: Double
    public var color: Color?

    public init(_ label: String, value: Double, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}

/// Rendering orientation for a `BarChart`.
public enum BarChartOrientation: Sendable, Equatable {
    case vertical
    case horizontal
}

/// A multi-bar chart supporting vertical and horizontal orientations, customizable bar widths, gaps,
/// fractional Unicode block resolution, and value annotations. Matches Ratatui's `BarChart`.
public struct BarChart: View, _PrimitiveView, Sendable {
    public typealias Body = Never

    public var items: [BarChartItem]
    public var orientation: BarChartOrientation
    public var maxValue: Double?
    public var barWidth: Int
    public var barGap: Int
    public var showValues: Bool
    public var defaultColor: Color

    private static let verticalBlocks: [String] = [" ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    private static let horizontalBlocks: [String] = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]

    public init(
        _ items: [BarChartItem],
        orientation: BarChartOrientation = .vertical,
        maxValue: Double? = nil,
        barWidth: Int = 4,
        barGap: Int = 2,
        showValues: Bool = true,
        defaultColor: Color = .brightCyan
    ) {
        self.items = items
        self.orientation = orientation
        self.maxValue = maxValue
        self.barWidth = max(1, barWidth)
        self.barGap = max(0, barGap)
        self.showValues = showValues
        self.defaultColor = defaultColor
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let chartItems = items
        let orient = orientation
        let maxV = maxValue ?? max(0.0001, chartItems.map(\.value).max() ?? 1.0)
        let bWidth = barWidth
        let bGap = barGap
        let showV = showValues
        let defColor = defaultColor

        return [
            RenderNode(
                id: "\(context.path).BarChart",
                flexibleAxes: orient == .vertical ? [.horizontal, .vertical] : [.horizontal],
                measure: { proposal in
                    switch orient {
                    case .vertical:
                        let totalW = chartItems.count * bWidth + max(0, chartItems.count - 1) * bGap
                        let preferredH = proposal.height ?? 8
                        return Size(width: proposal.width ?? max(1, totalW), height: max(3, preferredH))
                    case .horizontal:
                        let rows = max(1, chartItems.count)
                        return Size(width: proposal.width ?? 30, height: rows)
                    }
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty, !chartItems.isEmpty else { return }

                    switch orient {
                    case .vertical:
                        renderVertical(
                            items: chartItems,
                            maxVal: maxV,
                            rect: rect,
                            buffer: &buffer,
                            bWidth: bWidth,
                            bGap: bGap,
                            showValues: showV,
                            defaultColor: defColor
                        )
                    case .horizontal:
                        renderHorizontal(
                            items: chartItems,
                            maxVal: maxV,
                            rect: rect,
                            buffer: &buffer,
                            showValues: showV,
                            defaultColor: defColor
                        )
                    }
                }
            )
        ]
    }

    private func renderVertical(
        items: [BarChartItem],
        maxVal: Double,
        rect: Rect,
        buffer: inout Buffer,
        bWidth: Int,
        bGap: Int,
        showValues: Bool,
        defaultColor: Color
    ) {
        let labelRowY = rect.maxY - 1
        let barBottomY = labelRowY - 1
        let barTopY = showValues ? rect.minY + 1 : rect.minY
        let barHeightRows = max(1, barBottomY - barTopY + 1)

        var curX = rect.minX
        for item in items {
            if curX >= rect.maxX { break }
            let itemColor = item.color ?? defaultColor
            let norm = max(0.0, min(1.0, item.value / max(0.0001, maxVal)))
            let totalEighths = norm * Double(barHeightRows * 8)

            // Render bar columns
            for colOffset in 0..<bWidth {
                let x = curX + colOffset
                if x >= rect.maxX { break }

                for rowOffset in 0..<barHeightRows {
                    let y = barBottomY - rowOffset
                    let rowEighths = totalEighths - Double(rowOffset * 8)

                    let symbol: String
                    if rowEighths >= 8.0 {
                        symbol = Self.verticalBlocks[8] // "█"
                    } else if rowEighths > 0.0 {
                        let idx = max(1, min(8, Int(rowEighths.rounded())))
                        symbol = Self.verticalBlocks[idx]
                    } else {
                        symbol = " "
                    }

                    if symbol != " " {
                        buffer.setCell(x: x, y: y, symbol: symbol, style: CellStyle(fg: itemColor))
                    }
                }
            }

            // Render value label above bar
            if showValues && barTopY > rect.minY {
                let valStr = item.value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(item.value))" : String(format: "%.1f", item.value)
                let valW = UnicodeWidth.width(of: valStr)
                let valX = curX + max(0, (bWidth - valW) / 2)
                buffer.writeString(x: valX, y: rect.minY, valStr, style: CellStyle(fg: .white, modifiers: [.bold]), maxWidth: max(1, rect.maxX - valX))
            }

            // Render category label centered under bar
            let labelW = UnicodeWidth.width(of: item.label)
            let labelX = curX + max(0, (bWidth - labelW) / 2)
            buffer.writeString(x: labelX, y: labelRowY, item.label, style: CellStyle(fg: .brightBlack), maxWidth: max(1, rect.maxX - labelX))

            curX += bWidth + bGap
        }
    }

    private func renderHorizontal(
        items: [BarChartItem],
        maxVal: Double,
        rect: Rect,
        buffer: inout Buffer,
        showValues: Bool,
        defaultColor: Color
    ) {
        let maxLabelW = items.map { UnicodeWidth.width(of: $0.label) }.max() ?? 4
        let prefixW = maxLabelW + 3 // "Label │ "

        for (idx, item) in items.enumerated() {
            let y = rect.minY + idx
            if y >= rect.maxY { break }

            let itemColor = item.color ?? defaultColor
            let label = item.label
            let labelW = UnicodeWidth.width(of: label)
            let pad = String(repeating: " ", count: max(0, maxLabelW - labelW))

            buffer.writeString(x: rect.minX, y: y, "\(pad)\(label) │ ", style: CellStyle(fg: .brightBlack), maxWidth: rect.width)

            let valStr = showValues ? (item.value.truncatingRemainder(dividingBy: 1) == 0 ? " \(Int(item.value))" : String(format: " %.1f", item.value)) : ""
            let valW = UnicodeWidth.width(of: valStr)

            let barStartX = rect.minX + prefixW
            let availBarW = max(0, rect.width - prefixW - valW)
            let norm = max(0.0, min(1.0, item.value / max(0.0001, maxVal)))
            let totalEighths = norm * Double(availBarW * 8)

            for col in 0..<availBarW {
                let x = barStartX + col
                if x >= rect.maxX { break }
                let colEighths = totalEighths - Double(col * 8)

                let symbol: String
                if colEighths >= 8.0 {
                    symbol = Self.horizontalBlocks[8] // "█"
                } else if colEighths > 0.0 {
                    let bIdx = max(1, min(8, Int(colEighths.rounded())))
                    symbol = Self.horizontalBlocks[bIdx]
                } else {
                    symbol = " "
                }

                if symbol != " " {
                    buffer.setCell(x: x, y: y, symbol: symbol, style: CellStyle(fg: itemColor))
                }
            }

            if showValues && !valStr.isEmpty {
                let valX = min(rect.maxX - valW, barStartX + Int((Double(availBarW) * norm).rounded()))
                buffer.writeString(x: max(barStartX, valX), y: y, valStr, style: CellStyle(fg: .white, modifiers: [.bold]), maxWidth: max(0, rect.maxX - valX))
            }
        }
    }
}

// MARK: - Canvas & Sub-Pixel Braille Grid (Ratatui Parity)

/// 2D graphics drawing context providing a 2×4 sub-pixel Braille matrix (`U+2800..U+28FF`).
/// An 80×24 terminal window provides a 160×96 virtual sub-pixel drawing surface.
public struct CanvasContext: Sendable {
    public let cellWidth: Int
    public let cellHeight: Int

    /// Virtual sub-pixel resolution.
    public var pixelWidth: Int { cellWidth * 2 }
    public var pixelHeight: Int { cellHeight * 4 }

    private var dots: [UInt8]
    private var colors: [Color]

    public init(cellWidth: Int, cellHeight: Int) {
        self.cellWidth = max(1, cellWidth)
        self.cellHeight = max(1, cellHeight)
        let totalCells = self.cellWidth * self.cellHeight
        self.dots = [UInt8](repeating: 0, count: totalCells)
        self.colors = [Color](repeating: .white, count: totalCells)
    }

    /// Sets a single virtual sub-pixel at `(x, y)` in `[0..<pixelWidth, 0..<pixelHeight]`.
    public mutating func setPixel(x: Int, y: Int, color: Color = .white) {
        guard x >= 0, x < pixelWidth, y >= 0, y < pixelHeight else { return }
        let cx = x / 2
        let cy = y / 4
        let dx = x % 2
        let dy = y % 4

        // Braille dot bit indices:
        // dx=0 (col 0): dy=0 -> 0x01, dy=1 -> 0x02, dy=2 -> 0x04, dy=3 -> 0x40
        // dx=1 (col 1): dy=0 -> 0x08, dy=1 -> 0x10, dy=2 -> 0x20, dy=3 -> 0x80
        let bit: UInt8
        switch (dx, dy) {
        case (0, 0): bit = 0x01
        case (0, 1): bit = 0x02
        case (0, 2): bit = 0x04
        case (0, 3): bit = 0x40
        case (1, 0): bit = 0x08
        case (1, 1): bit = 0x10
        case (1, 2): bit = 0x20
        case (1, 3): bit = 0x80
        default:     bit = 0
        }

        let idx = cy * cellWidth + cx
        dots[idx] |= bit
        colors[idx] = color
    }

    /// Draws a continuous line using Bresenham's line algorithm.
    public mutating func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, color: Color = .white) {
        var x = x0
        var y = y0
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy

        while true {
            setPixel(x: x, y: y, color: color)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x += sx
            }
            if e2 <= dx {
                err += dx
                y += sy
            }
        }
    }

    /// Draws a rectangle in virtual sub-pixel coordinates.
    public mutating func drawRect(x: Int, y: Int, width: Int, height: Int, color: Color = .white, filled: Bool = false) {
        guard width > 0, height > 0 else { return }
        let right = x + width - 1
        let bottom = y + height - 1

        if filled {
            for py in y...bottom {
                drawLine(x0: x, y0: py, x1: right, y1: py, color: color)
            }
        } else {
            drawLine(x0: x, y0: y, x1: right, y1: y, color: color)
            drawLine(x0: right, y0: y, x1: right, y1: bottom, color: color)
            drawLine(x0: right, y0: bottom, x1: x, y1: bottom, color: color)
            drawLine(x0: x, y0: bottom, x1: x, y1: y, color: color)
        }
    }

    /// Draws a circle using the midpoint circle algorithm.
    public mutating func drawCircle(centerX: Int, centerY: Int, radius: Int, color: Color = .white) {
        guard radius > 0 else {
            setPixel(x: centerX, y: centerY, color: color)
            return
        }

        var x = radius
        var y = 0
        var err = 0

        while x >= y {
            setPixel(x: centerX + x, y: centerY + y, color: color)
            setPixel(x: centerX + y, y: centerY + x, color: color)
            setPixel(x: centerX - y, y: centerY + x, color: color)
            setPixel(x: centerX - x, y: centerY + y, color: color)
            setPixel(x: centerX - x, y: centerY - y, color: color)
            setPixel(x: centerX - y, y: centerY - x, color: color)
            setPixel(x: centerX + y, y: centerY - x, color: color)
            setPixel(x: centerX + x, y: centerY - y, color: color)

            if err <= 0 {
                y += 1
                err += 2 * y + 1
            }
            if err > 0 {
                x -= 1
                err -= 2 * x + 1
            }
        }
    }

    /// Plots a mathematical curve over the domain [0.0 ... 1.0] where normalized `f(t)` maps to `y`.
    public mutating func drawFunction(color: Color = .white, samples: Int? = nil, f: (Double) -> Double) {
        let sampleCount = samples ?? max(2, pixelWidth)
        var prevX: Int? = nil
        var prevY: Int? = nil

        for i in 0..<sampleCount {
            let t = Double(i) / Double(max(1, sampleCount - 1))
            let x = Int((t * Double(pixelWidth - 1)).rounded())
            let yVal = max(0.0, min(1.0, f(t)))
            // Invert y: yVal = 1.0 is top (y = 0), yVal = 0.0 is bottom
            let y = Int(((1.0 - yVal) * Double(pixelHeight - 1)).rounded())

            if let px = prevX, let py = prevY {
                drawLine(x0: px, y0: py, x1: x, y1: y, color: color)
            } else {
                setPixel(x: x, y: y, color: color)
            }
            prevX = x
            prevY = y
        }
    }

    /// Retrieves the generated Braille character and styling for terminal cell `(cx, cy)`.
    public func cellSymbolAndColor(cx: Int, cy: Int) -> (String, Color)? {
        guard cx >= 0, cx < cellWidth, cy >= 0, cy < cellHeight else { return nil }
        let idx = cy * cellWidth + cx
        let dotBits = dots[idx]
        if dotBits == 0 {
            return (" ", .default)
        }
        guard let scalar = UnicodeScalar(0x2800 + UInt32(dotBits)) else {
            return (" ", .default)
        }
        return (String(scalar), colors[idx])
    }
}

/// A high-resolution 2D terminal drawing canvas backed by Unicode Braille patterns (`U+2800..U+28FF`).
/// Provides sub-pixel resolution (2 horizontal dots × 4 vertical dots per cell).
public struct Canvas: View, _PrimitiveView, Sendable {
    public typealias Body = Never

    public var requestedWidth: Int?
    public var requestedHeight: Int?
    public var draw: @Sendable (inout CanvasContext) -> Void

    public init(
        width: Int? = nil,
        height: Int? = nil,
        draw: @escaping @Sendable (inout CanvasContext) -> Void
    ) {
        self.requestedWidth = width
        self.requestedHeight = height
        self.draw = draw
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let reqW = requestedWidth
        let reqH = requestedHeight
        let drawClosure = draw

        return [
            RenderNode(
                id: "\(context.path).Canvas",
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    let w = reqW ?? proposal.width ?? 30
                    let h = reqH ?? proposal.height ?? 10
                    return Size(width: max(1, w), height: max(1, h))
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }
                    var ctx = CanvasContext(cellWidth: rect.width, cellHeight: rect.height)
                    drawClosure(&ctx)

                    for cy in 0..<rect.height {
                        let y = rect.minY + cy
                        for cx in 0..<rect.width {
                            let x = rect.minX + cx
                            if let (sym, col) = ctx.cellSymbolAndColor(cx: cx, cy: cy), sym != " " {
                                buffer.setCell(x: x, y: y, symbol: sym, style: CellStyle(fg: col))
                            }
                        }
                    }
                }
            )
        ]
    }
}

// MARK: - Spinner (Bubble Tea Parity)

/// Animation animation preset frames matching Bubble Tea's `bubbles/spinner`.
public enum SpinnerStyle: Sendable, Equatable {
    case dots
    case line
    case pulse
    case arc
    case meter
    case custom([String])

    public var frames: [String] {
        switch self {
        case .dots:
            return ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        case .line:
            return ["-", "\\", "|", "/"]
        case .pulse:
            return ["█", "▓", "▒", "░", "▒", "▓"]
        case .arc:
            return ["◜", "◠", "◝", "◞", "◡", "◟"]
        case .meter:
            return ["▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱"]
        case .custom(let customFrames):
            return customFrames.isEmpty ? ["*"] : customFrames
        }
    }
}

/// An animated activity indicator for long-running CLI operations, matching Bubble Tea's `spinner`.
public struct Spinner: View, _PrimitiveView, Sendable {
    public typealias Body = Never

    public var label: String?
    public var style: SpinnerStyle
    public var frame: Int
    public var color: Color

    public init(
        _ label: String? = nil,
        style: SpinnerStyle = .dots,
        frame: Int = 0,
        color: Color = .brightCyan
    ) {
        self.label = label
        self.style = style
        self.frame = frame
        self.color = color
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let frames = style.frames
        let glyph = frames[abs(frame) % frames.count]
        let title = label
        let tint = color
        let text = title.map { "\(glyph) \($0)" } ?? glyph
        let width = UnicodeWidth.width(of: text)

        return [
            RenderNode(
                id: "\(context.path).Spinner",
                measure: { _ in
                    Size(width: width, height: 1)
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }
                    let glyphW = UnicodeWidth.width(of: glyph)
                    buffer.writeString(x: rect.minX, y: rect.minY, glyph, style: CellStyle(fg: tint, modifiers: [.bold]), maxWidth: rect.width)
                    if let title {
                        let startX = rect.minX + glyphW + 1
                        if startX < rect.maxX {
                            buffer.writeString(x: startX, y: rect.minY, title, style: CellStyle(fg: .white), maxWidth: max(0, rect.maxX - startX))
                        }
                    }
                }
            )
        ]
    }
}
