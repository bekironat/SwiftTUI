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
        var activeHyperlink: String? = nil

        let w = current.width
        let h = current.height
        let curCells = current.cells
        let prevCells = previous?.cells

        for y in 0..<h {
            let rowBase = y * w
            for x in 0..<w {
                let idx = rowBase + x
                let cell = curCells[idx]

                // Continuation cells are already covered by the 2-column glyph emitted at (x - 1, y)
                if cell.isContinuation {
                    continue
                }

                if !sizeChanged, let prevCells, prevCells[idx] == cell {
                    continue
                }

                // Move cursor if not already at (x, y)
                if trackedX != x || trackedY != y {
                    out.append("\u{1B}[\(y + 1);\(x + 1)H")
                }

                // Update OSC-8 hyperlink state if changed
                if activeHyperlink != cell.hyperlink {
                    if let url = cell.hyperlink, !url.isEmpty {
                        out.append("\u{1B}]8;;\(url)\u{1B}\\")
                    } else {
                        out.append("\u{1B}]8;;\u{1B}\\")
                    }
                    activeHyperlink = cell.hyperlink
                }

                // Update SGR style if changed
                var sgrStyle = cell.style
                sgrStyle.hyperlink = nil
                if activeStyle != sgrStyle {
                    out.append(Self.sgrSequence(from: activeStyle, to: sgrStyle))
                    activeStyle = sgrStyle
                }

                out.append(cell.symbol)

                let isWide = (x + 1 < w && curCells[idx + 1].isContinuation)
                if isWide || Self.requiresCursorReanchor(cell.symbol) {
                    // Force an explicit CSI H cursor position after any wide emoji, symbol, or multi-scalar grapheme
                    // so terminal-specific glyph width differences can never shift subsequent text or borders on the same row.
                    trackedX = -1
                    trackedY = -1
                } else {
                    trackedX = x + 1
                    trackedY = y
                }
            }
        }

        // Close any active OSC-8 hyperlink at the end of the frame
        if activeHyperlink != nil {
            out.append("\u{1B}]8;;\u{1B}\\")
        }

        // Reset SGR attributes at the end of the frame
        if activeStyle != nil {
            out.append("\u{1B}[0m")
        }

        // Emit any queued OSC-52 clipboard write sequence
        if let osc52 = TerminalClipboard.shared.drainPendingOSC52Sequence() {
            out.append(osc52)
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

    /// Returns `true` if `symbol` is a non-ASCII symbol or multi-scalar sequence outside standard 1-column Box Drawing / Block / Braille ranges.
    @inline(__always)
    private static func requiresCursorReanchor(_ symbol: String) -> Bool {
        if symbol.utf8.count == 1 { return false }
        let scalars = symbol.unicodeScalars
        if scalars.count > 1 { return true }
        guard let v = scalars.first?.value else { return false }
        // Standard 1-column Box Drawing (0x2500..0x257F), Block Elements (0x2580..0x259F), and Braille (0x2800..0x28FF)
        if (v >= 0x2500 && v <= 0x259F) || (v >= 0x2800 && v <= 0x28FF) {
            return false
        }
        return v >= 0x2000
    }

    /// Generates a minimal SGR escape sequence transitioning from `previous` to `target` style without intermediate array allocations.
    public static func sgrSequence(from previous: CellStyle?, to target: CellStyle) -> String {
        // Fast delta path: if previous style had the exact same modifiers and only fg/bg changed
        if let prev = previous, prev.modifiers == target.modifiers {
            var delta = "\u{1B}["
            var hasCode = false

            if prev.fg != target.fg {
                delta.append(target.fg.ansiSGRCode(isBackground: false))
                hasCode = true
            }
            if prev.bg != target.bg {
                if hasCode { delta.append(";") }
                delta.append(target.bg.ansiSGRCode(isBackground: true))
                hasCode = true
            }
            if hasCode {
                delta.append("m")
                return delta
            }
        }

        var seq = "\u{1B}[0"
        let mods = target.modifiers
        if !mods.isEmpty {
            if mods.contains(.bold)          { seq.append(";1") }
            if mods.contains(.dim)           { seq.append(";2") }
            if mods.contains(.italic)        { seq.append(";3") }
            if mods.contains(.underlined)    { seq.append(";4") }
            if mods.contains(.slowBlink)     { seq.append(";5") }
            if mods.contains(.rapidBlink)    { seq.append(";6") }
            if mods.contains(.reversed)      { seq.append(";7") }
            if mods.contains(.hidden)        { seq.append(";8") }
            if mods.contains(.strikethrough) { seq.append(";9") }
        }

        if target.fg != .default {
            seq.append(";")
            seq.append(target.fg.ansiSGRCode(isBackground: false))
        }
        if target.bg != .default {
            seq.append(";")
            seq.append(target.bg.ansiSGRCode(isBackground: true))
        }
        seq.append("m")
        return seq
    }
}
