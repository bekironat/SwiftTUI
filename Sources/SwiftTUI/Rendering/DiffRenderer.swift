import Foundation

/// Computes the minimal ANSI/VT escape sequence stream to transition a terminal from `previous` buffer to `current` buffer.
public struct DiffRenderer: Sendable {
    public var useSynchronizedOutput: Bool

    public init(useSynchronizedOutput: Bool = true) {
        self.useSynchronizedOutput = useSynchronizedOutput
    }

    /// Generates the ANSI escape sequence string required to update the terminal screen.
    public func render(previous: Buffer?, current: Buffer) -> String {
        let sizeChanged = previous == nil || previous?.width != current.width || previous?.height != current.height

        var out = ""
        out.reserveCapacity(current.width * current.height)

        if useSynchronizedOutput {
            out.append("\u{1B}[?2026h")
        }

        // Hide cursor while drawing cells to avoid flicker
        out.append("\u{1B}[?25l")

        if sizeChanged {
            out.append("\u{1B}[0m\u{1B}[2J")
        }

        var trackedX: Int = -1
        var trackedY: Int = -1
        var activeStyle: CellStyle? = nil

        for y in 0..<current.height {
            for x in 0..<current.width {
                guard let cell = current.cell(atX: x, y: y) else { continue }

                // Continuation cells are already covered by the 2-column glyph emitted at (x - 1, y)
                if cell.isContinuation {
                    continue
                }

                if !sizeChanged, let prevCell = previous?.cell(atX: x, y: y), prevCell == cell {
                    continue
                }

                // Move cursor if not already at (x, y)
                if trackedX != x || trackedY != y {
                    out.append("\u{1B}[\(y + 1);\(x + 1)H")
                }

                // Update SGR style if changed
                let cellStyle = cell.style
                if activeStyle != cellStyle {
                    out.append(Self.sgrSequence(from: activeStyle, to: cellStyle))
                    activeStyle = cellStyle
                }

                out.append(cell.symbol)

                let advance = max(1, UnicodeWidth.width(of: cell.symbol))
                trackedX = x + advance
                trackedY = y
            }
        }

        // Reset SGR attributes at the end of the frame
        if activeStyle != nil {
            out.append("\u{1B}[0m")
        }

        // Position and show hardware cursor if an active input requested one
        if let cursor = current.cursorPosition,
           cursor.x >= 0, cursor.x < current.width,
           cursor.y >= 0, cursor.y < current.height {
            out.append("\u{1B}[\(cursor.y + 1);\(cursor.x + 1)H")
            out.append("\u{1B}[?25h")
        }

        if useSynchronizedOutput {
            out.append("\u{1B}[?2026l")
        }

        return out
    }

    /// Generates an SGR escape sequence transitioning to `target` style.
    public static func sgrSequence(from previous: CellStyle?, to target: CellStyle) -> String {
        var codes: [String] = ["0"]

        if target.modifiers.contains(.bold)          { codes.append("1") }
        if target.modifiers.contains(.dim)           { codes.append("2") }
        if target.modifiers.contains(.italic)        { codes.append("3") }
        if target.modifiers.contains(.underlined)    { codes.append("4") }
        if target.modifiers.contains(.slowBlink)     { codes.append("5") }
        if target.modifiers.contains(.rapidBlink)    { codes.append("6") }
        if target.modifiers.contains(.reversed)      { codes.append("7") }
        if target.modifiers.contains(.hidden)        { codes.append("8") }
        if target.modifiers.contains(.strikethrough) { codes.append("9") }

        if target.fg != .default {
            codes.append(target.fg.ansiSGRCode(isBackground: false))
        }
        if target.bg != .default {
            codes.append(target.bg.ansiSGRCode(isBackground: true))
        }

        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }
}
