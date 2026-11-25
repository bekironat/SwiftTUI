import Foundation

/// Computes the minimal ANSI/VT escape sequence stream to transition a terminal from `previous` buffer to `current` buffer.
public struct DiffRenderer: Sendable {
    public var useSynchronizedOutput: Bool
    public var colorCapability: ColorCapability

    public init(
        useSynchronizedOutput: Bool = true,
        colorCapability: ColorCapability = .trueColor
    ) {
        self.useSynchronizedOutput = useSynchronizedOutput
        self.colorCapability = colorCapability
    }

    /// Generates the ANSI escape sequence string required to update the terminal screen.
    public func render(previous: Buffer?, current: Buffer) -> String {
        let sizeChanged = previous == nil || previous?.width != current.width || previous?.height != current.height
        let pendingOSC52 = TerminalClipboard.shared.drainPendingOSC52Sequence()

        // Fast no-op exit: emit 0 bytes when nothing changed between frames (prevents unnecessary I/O and flicker)
        if !sizeChanged,
           let prev = previous,
           pendingOSC52 == nil,
           current.graphicsPlacements.isEmpty,
           current.windowTitle == prev.windowTitle,
           current.terminalProgress == prev.terminalProgress,
           current.cursorPosition == prev.cursorPosition,
           current.cursorShape == prev.cursorShape,
           prev.cells == current.cells {
            return ""
        }

        var out = ""
        let initialCap = sizeChanged ? (current.width * current.height) : min(4096, current.width * current.height)
        out.reserveCapacity(initialCap)

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

                // Update SGR style if changed (direct append without temporary String allocation)
                var sgrStyle = cell.style
                sgrStyle.hyperlink = nil
                if colorCapability != .trueColor {
                    sgrStyle.fg = sgrStyle.fg.degraded(to: colorCapability)
                    sgrStyle.bg = sgrStyle.bg.degraded(to: colorCapability)
                    if let uColor = sgrStyle.underlineColor {
                        sgrStyle.underlineColor = uColor.degraded(to: colorCapability)
                    }
                }
                if activeStyle != sgrStyle {
                    Self.appendSGRSequence(from: activeStyle, to: sgrStyle, into: &out)
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

        // Emit any native terminal graphics placements (Kitty / iTerm2 / Sixel)
        for placement in current.graphicsPlacements {
            if placement.origin.x >= 0, placement.origin.x < current.width,
               placement.origin.y >= 0, placement.origin.y < current.height {
                out.append("\u{1B}[\(placement.origin.y + 1);\(placement.origin.x + 1)H")
                out.append(placement.sequence)
            }
        }

        // Emit optional OSC 2 terminal window title if changed
        if let title = current.windowTitle, title != previous?.windowTitle {
            out.append(TerminalCapabilities.encodeWindowTitleSequence(title))
        }

        // Emit optional OSC 9;4 terminal progress state if changed
        if let progress = current.terminalProgress, progress != previous?.terminalProgress {
            out.append(progress.ansiSequence)
        }

        // Emit any queued OSC-52 clipboard write sequence
        if let osc52 = pendingOSC52 {
            out.append(osc52)
        }

        // Position and show hardware cursor if an active input requested one
        if let cursor = current.cursorPosition,
           cursor.x >= 0, cursor.x < current.width,
           cursor.y >= 0, cursor.y < current.height {
            if let shape = current.cursorShape, shape != previous?.cursorShape {
                out.append(shape.ansiSequence)
            }
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

    /// Generates a minimal SGR escape sequence transitioning from `previous` to `target` style.
    public static func sgrSequence(from previous: CellStyle?, to target: CellStyle) -> String {
        var seq = ""
        seq.reserveCapacity(24)
        appendSGRSequence(from: previous, to: target, into: &seq)
        return seq
    }

    /// Appends a minimal SGR escape sequence transitioning from `previous` to `target` directly into `out`.
    public static func appendSGRSequence(from previous: CellStyle?, to target: CellStyle, into out: inout String) {
        // Fast delta path: if previous style had the exact same modifiers & underline styling and only fg/bg changed
        if let prev = previous,
           prev.modifiers == target.modifiers,
           prev.underlineStyle == target.underlineStyle,
           prev.underlineColor == target.underlineColor {
            let fgChanged = (prev.fg != target.fg)
            let bgChanged = (prev.bg != target.bg)
            if fgChanged || bgChanged {
                out.append("\u{1B}[")
                if fgChanged {
                    out.append(target.fg.ansiSGRCode(isBackground: false))
                }
                if bgChanged {
                    if fgChanged { out.append(";") }
                    out.append(target.bg.ansiSGRCode(isBackground: true))
                }
                out.append("m")
                return
            }
        }

        out.append("\u{1B}[0")
        let mods = target.modifiers
        if !mods.isEmpty || target.underlineStyle != nil {
            if mods.contains(.bold)          { out.append(";1") }
            if mods.contains(.dim)           { out.append(";2") }
            if mods.contains(.italic)        { out.append(";3") }
            if let uStyle = target.underlineStyle {
                out.append(";")
                out.append(uStyle.ansiSGRCode)
            } else if mods.contains(.underlined) {
                out.append(";4")
            }
            if mods.contains(.slowBlink)     { out.append(";5") }
            if mods.contains(.rapidBlink)    { out.append(";6") }
            if mods.contains(.reversed)      { out.append(";7") }
            if mods.contains(.hidden)        { out.append(";8") }
            if mods.contains(.strikethrough) { out.append(";9") }
        }

        if let uColor = target.underlineColor {
            out.append(";")
            out.append(uColor.ansiUnderlineColorSGRCode())
        }

        if target.fg != .default {
            out.append(";")
            out.append(target.fg.ansiSGRCode(isBackground: false))
        }
        if target.bg != .default {
            out.append(";")
            out.append(target.bg.ansiSGRCode(isBackground: true))
        }
        out.append("m")
    }
}
