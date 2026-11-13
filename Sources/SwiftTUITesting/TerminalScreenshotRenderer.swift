import Foundation
import SwiftTUI

#if canImport(AppKit)
import AppKit
#endif

/// High-resolution terminal screenshot generator capable of rendering `SwiftTUI` `Buffer` instances into pixel-perfect PNG images (on macOS via AppKit) or SVG vector documents (cross-platform).
public enum TerminalScreenshotRenderer {

    #if canImport(AppKit)
    /// Renders a terminal `Buffer` into PNG image data with authentic macOS terminal window chrome, solid vector border lines, and crisp typography.
    @MainActor
    public static func renderToPNG(
        buffer: Buffer,
        title: String = "SwiftTUI Terminal",
        fontSize: CGFloat = 13.0,
        scale: CGFloat = 2.0
    ) -> Data? {
        let font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont(name: "Menlo-Bold", size: fontSize) ?? font
        let italicFont = NSFont(name: "Menlo-Italic", size: fontSize) ?? font

        let charAdvance = ("M" as NSString).size(withAttributes: [.font: font]).width
        let cellWidth: CGFloat = charAdvance
        let cellHeight: CGFloat = ceil(fontSize * 1.30)

        let marginX: CGFloat = 16.0
        let marginY: CGFloat = 14.0
        let titleBarHeight: CGFloat = 34.0

        let totalWidth = marginX * 2 + CGFloat(buffer.width) * cellWidth
        let totalHeight = titleBarHeight + marginY * 2 + CGFloat(buffer.height) * cellHeight

        let pixelWidth = Int(ceil(totalWidth * scale))
        let pixelHeight = Int(ceil(totalHeight * scale))

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)

        // 1. Window Background
        let windowBgColor = NSColor(srgbRed: 0.065, green: 0.075, blue: 0.115, alpha: 1.0)
        windowBgColor.setFill()
        cg.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        // 2. Title Bar
        let titleBarRect = CGRect(x: 0, y: totalHeight - titleBarHeight, width: totalWidth, height: titleBarHeight)
        let titleBarColor = NSColor(srgbRed: 0.11, green: 0.125, blue: 0.18, alpha: 1.0)
        titleBarColor.setFill()
        cg.fill(titleBarRect)

        // Title bar bottom divider
        NSColor(srgbRed: 0.18, green: 0.20, blue: 0.28, alpha: 1.0).setStroke()
        cg.setLineWidth(1.0)
        cg.strokeLineSegments(between: [
            CGPoint(x: 0, y: totalHeight - titleBarHeight),
            CGPoint(x: totalWidth, y: totalHeight - titleBarHeight)
        ])

        // 3. Traffic Lights
        let lightY = totalHeight - 22.0
        let lights: [(CGFloat, NSColor)] = [
            (16.0, NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1.0)),
            (34.0, NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1.0)),
            (52.0, NSColor(srgbRed: 0.15, green: 0.79, blue: 0.25, alpha: 1.0))
        ]
        for (lx, color) in lights {
            color.setFill()
            cg.fillEllipse(in: CGRect(x: lx, y: lightY, width: 11, height: 11))
        }

        // 4. Window Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.0, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.78, green: 0.82, blue: 0.90, alpha: 1.0)
        ]
        let titleAttrStr = NSAttributedString(string: "\(title) (\(buffer.width)×\(buffer.height))", attributes: titleAttrs)
        let titleSize = titleAttrStr.size()
        titleAttrStr.draw(at: CGPoint(x: (totalWidth - titleSize.width) / 2.0, y: totalHeight - 23.5))

        // 5. Pass 1: Render Cell Background Fills
        let contentTop = totalHeight - titleBarHeight - marginY

        for y in 0..<buffer.height {
            let rowY = contentTop - CGFloat(y + 1) * cellHeight
            var x = 0

            while x < buffer.width {
                guard let cell = buffer.cell(atX: x, y: y) else {
                    x += 1
                    continue
                }

                var endX = x + 1
                while endX < buffer.width {
                    if let nextCell = buffer.cell(atX: endX, y: y),
                       nextCell.bg == cell.bg,
                       nextCell.modifiers.contains(.reversed) == cell.modifiers.contains(.reversed) {
                        endX += 1
                    } else {
                        break
                    }
                }

                let spanLen = endX - x
                let cellRect = CGRect(
                    x: marginX + CGFloat(x) * cellWidth,
                    y: rowY,
                    width: CGFloat(spanLen) * cellWidth,
                    height: cellHeight
                )

                var bgNSColor: NSColor? = nil
                if cell.modifiers.contains(.reversed) {
                    bgNSColor = nsColor(for: cell.fg, isBackground: true)
                } else if cell.bg != .default {
                    bgNSColor = nsColor(for: cell.bg, isBackground: true)
                }

                if let bg = bgNSColor {
                    bg.setFill()
                    cg.fill(cellRect)
                }

                x = endX
            }
        }

        // 6. Pass 2: Render Foreground Glyphs & Solid Box Drawing Lines
        for y in 0..<buffer.height {
            let rowY = contentTop - CGFloat(y + 1) * cellHeight
            var x = 0

            while x < buffer.width {
                guard let cell = buffer.cell(atX: x, y: y) else {
                    x += 1
                    continue
                }

                if cell.isContinuation {
                    x += 1
                    continue
                }

                let sym = cell.symbol
                if sym.isEmpty || sym == " " {
                    x += 1
                    continue
                }

                var fgColor: NSColor
                if cell.modifiers.contains(.reversed) {
                    fgColor = nsColor(for: cell.bg, isBackground: false)
                } else {
                    fgColor = nsColor(for: cell.fg, isBackground: false)
                }
                if cell.modifiers.contains(.dim) {
                    fgColor = fgColor.withAlphaComponent(0.55)
                }

                let singleCellRect = CGRect(
                    x: marginX + CGFloat(x) * cellWidth,
                    y: rowY,
                    width: cellWidth,
                    height: cellHeight
                )

                // Check if this symbol is a box drawing or block glyph
                if renderBoxGlyph(symbol: sym, in: singleCellRect, color: fgColor, context: cg) {
                    x += 1
                    continue
                }

                // Check if this symbol is a wide character / emoji
                let symWidth = UnicodeWidth.width(of: sym)
                if symWidth >= 2 {
                    var activeFont = font
                    if cell.modifiers.contains(.bold) { activeFont = boldFont }
                    else if cell.modifiers.contains(.italic) { activeFont = italicFont }

                    let textAttrs: [NSAttributedString.Key: Any] = [
                        .font: activeFont,
                        .foregroundColor: fgColor
                    ]
                    let attrStr = NSAttributedString(string: sym, attributes: textAttrs)
                    let textY = rowY + (cellHeight - fontSize) / 2.0 - 1.0
                    attrStr.draw(at: CGPoint(x: marginX + CGFloat(x) * cellWidth, y: textY))
                    x += 1
                    continue
                }

                // Collect contiguous plain printable ASCII characters
                var asciiRun = sym
                var runEnd = x + 1
                while runEnd < buffer.width {
                    guard let nextCell = buffer.cell(atX: runEnd, y: y),
                          !nextCell.isContinuation,
                          nextCell.fg == cell.fg,
                          nextCell.bg == cell.bg,
                          nextCell.modifiers == cell.modifiers else { break }

                    let nextSym = nextCell.symbol
                    if isBoxGlyph(nextSym) || UnicodeWidth.width(of: nextSym) != 1 {
                        break
                    }
                    if let scalar = nextSym.unicodeScalars.first, scalar.value >= 0x20 && scalar.value < 0x7F {
                        asciiRun += nextSym
                        runEnd += 1
                    } else {
                        break
                    }
                }

                var activeFont = font
                if cell.modifiers.contains(.bold) { activeFont = boldFont }
                else if cell.modifiers.contains(.italic) { activeFont = italicFont }

                var textAttrs: [NSAttributedString.Key: Any] = [
                    .font: activeFont,
                    .foregroundColor: fgColor
                ]
                if cell.modifiers.contains(.underlined) {
                    textAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    textAttrs[.underlineColor] = fgColor
                }

                let trimmed = asciiRun.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let attrStr = NSAttributedString(string: asciiRun, attributes: textAttrs)
                    let textY = rowY + (cellHeight - fontSize) / 2.0 - 1.0
                    attrStr.draw(at: CGPoint(x: marginX + CGFloat(x) * cellWidth, y: textY))
                }

                x = runEnd
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Tests whether a symbol is a recognized box drawing or block glyph.
    private static func isBoxGlyph(_ sym: String) -> Bool {
        if let scalar = sym.unicodeScalars.first, sym.unicodeScalars.count == 1 {
            if scalar.value >= 0x2800 && scalar.value <= 0x28FF {
                return true
            }
        }
        switch sym {
        case "─", "━", "═", "│", "┃", "║",
             "┌", "┐", "└", "┘", "╭", "╮", "╰", "╯",
             "╔", "╗", "╚", "╝", "┏", "┓", "┗", "┛",
             "├", "┤", "┬", "┴", "┼",
             "╠", "╣", "╦", "╩", "╬",
             "┣", "┫", "┳", "┻", "╋",
             "█", " ", "▂", "▃", "▄", "▅", "▆", "▇",
             "▏", "▎", "▍", "▌", "▋", "▊", "▉":
            return true
        default:
            return false
        }
    }

    /// Programmatically renders a box drawing glyph as continuous, unbroken vector lines spanning 100% of the cell bounds.
    @MainActor
    private static func renderBoxGlyph(
        symbol: String,
        in rect: CGRect,
        color: NSColor,
        context cg: CGContext
    ) -> Bool {
        guard isBoxGlyph(symbol) else { return false }

        color.setStroke()
        color.setFill()
        cg.setLineWidth(1.0)

        let midX = rect.midX
        let midY = rect.midY
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let off: CGFloat = 1.5

        switch symbol {
        // Horizontals (spanning left to right edge)
        case "─":
            cg.strokeLineSegments(between: [CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY)])
        case "━":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY)])
        case "═":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY + off), CGPoint(x: maxX, y: midY + off),
                CGPoint(x: minX, y: midY - off), CGPoint(x: maxX, y: midY - off)
            ])

        // Verticals (spanning 100% from bottom to top edge without gap)
        case "│":
            cg.strokeLineSegments(between: [CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY)])
        case "┃":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY)])
        case "║":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: maxY),
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: maxY)
            ])

        // Corners (Single)
        case "┌":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┐":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])
        case "└":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┘":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])

        // Rounded Corners (Smooth Bezier)
        case "╭":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: midX, y: minY))
            path.addArc(tangent1End: CGPoint(x: midX, y: midY), tangent2End: CGPoint(x: maxX, y: midY), radius: 3.5)
            path.addLine(to: CGPoint(x: maxX, y: midY))
            cg.addPath(path)
            cg.strokePath()
        case "╮":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: midX, y: minY))
            path.addArc(tangent1End: CGPoint(x: midX, y: midY), tangent2End: CGPoint(x: minX, y: midY), radius: 3.5)
            path.addLine(to: CGPoint(x: minX, y: midY))
            cg.addPath(path)
            cg.strokePath()
        case "╰":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: midX, y: maxY))
            path.addArc(tangent1End: CGPoint(x: midX, y: midY), tangent2End: CGPoint(x: maxX, y: midY), radius: 3.5)
            path.addLine(to: CGPoint(x: maxX, y: midY))
            cg.addPath(path)
            cg.strokePath()
        case "╯":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: midX, y: maxY))
            path.addArc(tangent1End: CGPoint(x: midX, y: midY), tangent2End: CGPoint(x: minX, y: midY), radius: 3.5)
            path.addLine(to: CGPoint(x: minX, y: midY))
            cg.addPath(path)
            cg.strokePath()

        // Double Corners
        case "╔":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: midY + off),
                CGPoint(x: midX - off, y: midY + off), CGPoint(x: maxX, y: midY + off),
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: midY - off),
                CGPoint(x: midX + off, y: midY - off), CGPoint(x: maxX, y: midY - off)
            ])
        case "╗":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: midY + off),
                CGPoint(x: midX + off, y: midY + off), CGPoint(x: minX, y: midY + off),
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: midY - off),
                CGPoint(x: midX - off, y: midY - off), CGPoint(x: minX, y: midY - off)
            ])
        case "╚":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX - off, y: maxY), CGPoint(x: midX - off, y: midY - off),
                CGPoint(x: midX - off, y: midY - off), CGPoint(x: maxX, y: midY - off),
                CGPoint(x: midX + off, y: maxY), CGPoint(x: midX + off, y: midY + off),
                CGPoint(x: midX + off, y: midY + off), CGPoint(x: maxX, y: midY + off)
            ])
        case "╝":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX + off, y: maxY), CGPoint(x: midX + off, y: midY - off),
                CGPoint(x: midX + off, y: midY - off), CGPoint(x: minX, y: midY - off),
                CGPoint(x: midX - off, y: maxY), CGPoint(x: midX - off, y: midY + off),
                CGPoint(x: midX - off, y: midY + off), CGPoint(x: minX, y: midY + off)
            ])

        // Thick Corners
        case "┏":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┓":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])
        case "┗":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┛":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])

        // Tees & Crosses (Single)
        case "├":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┤":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])
        case "┬":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY)
            ])
        case "┴":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY)
            ])
        case "┼":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY)
            ])

        // Tees & Crosses (Double)
        case "╠":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: maxY),
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: midY - off),
                CGPoint(x: midX + off, y: midY - off), CGPoint(x: maxX, y: midY - off),
                CGPoint(x: midX + off, y: midY + off), CGPoint(x: maxX, y: midY + off)
            ])
        case "╣":
            cg.strokeLineSegments(between: [
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: maxY),
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: midY - off),
                CGPoint(x: midX - off, y: midY - off), CGPoint(x: minX, y: midY - off),
                CGPoint(x: midX - off, y: midY + off), CGPoint(x: minX, y: midY + off)
            ])
        case "╦":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY + off), CGPoint(x: maxX, y: midY + off),
                CGPoint(x: minX, y: midY - off), CGPoint(x: midX - off, y: midY - off),
                CGPoint(x: midX + off, y: midY - off), CGPoint(x: maxX, y: midY - off),
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: midY - off),
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: midY - off)
            ])
        case "╩":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY - off), CGPoint(x: maxX, y: midY - off),
                CGPoint(x: minX, y: midY + off), CGPoint(x: midX - off, y: midY + off),
                CGPoint(x: midX + off, y: midY + off), CGPoint(x: maxX, y: midY + off),
                CGPoint(x: midX - off, y: maxY), CGPoint(x: midX - off, y: midY + off),
                CGPoint(x: midX + off, y: maxY), CGPoint(x: midX + off, y: midY + off)
            ])
        case "╬":
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY + off), CGPoint(x: maxX, y: midY + off),
                CGPoint(x: minX, y: midY - off), CGPoint(x: maxX, y: midY - off),
                CGPoint(x: midX - off, y: minY), CGPoint(x: midX - off, y: maxY),
                CGPoint(x: midX + off, y: minY), CGPoint(x: midX + off, y: maxY)
            ])

        // Thick Tees & Crosses
        case "┣":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY),
                CGPoint(x: midX, y: midY), CGPoint(x: maxX, y: midY)
            ])
        case "┫":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY),
                CGPoint(x: midX, y: midY), CGPoint(x: minX, y: midY)
            ])
        case "┳":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: midY)
            ])
        case "┻":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: maxY), CGPoint(x: midX, y: midY)
            ])
        case "╋":
            cg.setLineWidth(2.0)
            cg.strokeLineSegments(between: [
                CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY)
            ])

        // Blocks & Sparklines
        case "█":
            cg.fill(rect)
        case " ":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.125))
        case "▂":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.25))
        case "▃":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.375))
        case "▄":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.50))
        case "▅":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.625))
        case "▆":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.75))
        case "▇":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.875))

        // Horizontal Fractional Blocks
        case "▏":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.125, height: rect.height))
        case "▎":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.25, height: rect.height))
        case "▍":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.375, height: rect.height))
        case "▌":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.50, height: rect.height))
        case "▋":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.625, height: rect.height))
        case "▊":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.75, height: rect.height))
        case "▉":
            cg.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.875, height: rect.height))

        default:
            // Programmatic sub-pixel Braille dots (U+2800 ... U+28FF)
            if let scalar = symbol.unicodeScalars.first, symbol.unicodeScalars.count == 1,
               scalar.value >= 0x2800 && scalar.value <= 0x28FF {
                let dotBits = scalar.value - 0x2800
                if dotBits == 0 { return true }
                color.setFill()
                let dotW = rect.width / 2.0
                let dotH = rect.height / 4.0
                let radius = max(1.0, min(dotW, dotH) * 0.35)

                let bitMap: [(bit: UInt32, dx: CGFloat, dy: CGFloat)] = [
                    (0x01, 0, 3),
                    (0x02, 0, 2),
                    (0x04, 0, 1),
                    (0x40, 0, 0),
                    (0x08, 1, 3),
                    (0x10, 1, 2),
                    (0x20, 1, 1),
                    (0x80, 1, 0)
                ]

                for entry in bitMap {
                    if (dotBits & entry.bit) != 0 {
                        let cx = rect.minX + (entry.dx + 0.5) * dotW
                        let cy = rect.minY + (entry.dy + 0.5) * dotH
                        cg.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2.0, height: radius * 2.0))
                    }
                }
                return true
            }
            return false
        }

        return true
    }

    /// Saves a terminal buffer screenshot to a local PNG file path.
    @MainActor
    public static func saveScreenshot(
        buffer: Buffer,
        to fileURL: URL,
        title: String = "SwiftTUI Terminal"
    ) throws {
        guard let data = renderToPNG(buffer: buffer, title: title) else {
            throw NSError(domain: "SwiftTUI.Screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG screenshot"])
        }
        try data.write(to: fileURL)
    }

    private static func nsColor(for color: SwiftTUI.Color, isBackground: Bool) -> NSColor {
        switch color {
        case .default:
            return isBackground
                ? NSColor(srgbRed: 0.07, green: 0.08, blue: 0.12, alpha: 1.0)
                : NSColor(srgbRed: 0.92, green: 0.94, blue: 0.97, alpha: 1.0)

        case .black:
            return NSColor(srgbRed: 0.14, green: 0.16, blue: 0.22, alpha: 1.0)
        case .red:
            return NSColor(srgbRed: 0.93, green: 0.35, blue: 0.38, alpha: 1.0)
        case .green:
            return NSColor(srgbRed: 0.40, green: 0.77, blue: 0.45, alpha: 1.0)
        case .yellow:
            return NSColor(srgbRed: 0.88, green: 0.73, blue: 0.38, alpha: 1.0)
        case .blue:
            return NSColor(srgbRed: 0.36, green: 0.65, blue: 0.95, alpha: 1.0)
        case .magenta:
            return NSColor(srgbRed: 0.78, green: 0.48, blue: 0.91, alpha: 1.0)
        case .cyan:
            return NSColor(srgbRed: 0.35, green: 0.74, blue: 0.82, alpha: 1.0)
        case .white:
            return NSColor(srgbRed: 0.82, green: 0.85, blue: 0.90, alpha: 1.0)

        case .brightBlack:
            return NSColor(srgbRed: 0.45, green: 0.49, blue: 0.58, alpha: 1.0)
        case .brightRed:
            return NSColor(srgbRed: 1.00, green: 0.45, blue: 0.48, alpha: 1.0)
        case .brightGreen:
            return NSColor(srgbRed: 0.48, green: 0.88, blue: 0.53, alpha: 1.0)
        case .brightYellow:
            return NSColor(srgbRed: 0.98, green: 0.84, blue: 0.45, alpha: 1.0)
        case .brightBlue:
            return NSColor(srgbRed: 0.46, green: 0.75, blue: 1.00, alpha: 1.0)
        case .brightMagenta:
            return NSColor(srgbRed: 0.88, green: 0.58, blue: 1.00, alpha: 1.0)
        case .brightCyan:
            return NSColor(srgbRed: 0.45, green: 0.85, blue: 0.92, alpha: 1.0)
        case .brightWhite:
            return NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)

        case .orange:
            return NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1.0)

        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)

        case .indexed(let idx):
            return ansi256Color(idx)
        }
    }

    private static func ansi256Color(_ idx: UInt8) -> NSColor {
        if idx < 16 {
            let standard16: [SwiftTUI.Color] = [
                .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
                .brightBlack, .brightRed, .brightGreen, .brightYellow, .brightBlue, .brightMagenta, .brightCyan, .brightWhite
            ]
            return nsColor(for: standard16[Int(idx)], isBackground: false)
        } else if idx >= 232 {
            let gray = CGFloat(idx - 232) * 10.0 + 8.0
            return NSColor(srgbRed: gray / 255.0, green: gray / 255.0, blue: gray / 255.0, alpha: 1.0)
        } else {
            let i = Int(idx - 16)
            let b = (i % 6) == 0 ? 0 : (i % 6) * 40 + 55
            let g = ((i / 6) % 6) == 0 ? 0 : ((i / 6) % 6) * 40 + 55
            let r = (i / 36) == 0 ? 0 : (i / 36) * 40 + 55
            return NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
        }
    }
    #endif

    /// Cross-platform vector SVG export for terminal buffers.
    public static func renderToSVG(
        buffer: Buffer,
        title: String = "SwiftTUI Terminal"
    ) -> String {
        let cellW: Double = 8.5
        let cellH: Double = 17.0
        let padX: Double = 16.0
        let padY: Double = 16.0
        let titleH: Double = 34.0

        let totalW = padX * 2 + Double(buffer.width) * cellW
        let totalH = titleH + padY * 2 + Double(buffer.height) * cellH

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(totalW) \(totalH)" width="\(totalW)" height="\(totalH)">
        <rect width="\(totalW)" height="\(totalH)" rx="10" fill="#12141F"/>
        <rect width="\(totalW)" height="\(titleH)" rx="10" fill="#1A1D2B"/>
        <circle cx="20" cy="17" r="5.5" fill="#FF5F56"/>
        <circle cx="38" cy="17" r="5.5" fill="#FFBD2E"/>
        <circle cx="56" cy="17" r="5.5" fill="#27C93F"/>
        <text x="\(totalW / 2)" y="22" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" font-size="12" font-weight="600" fill="#C9D1D9" text-anchor="middle">\(title)</text>
        <g font-family="'Menlo', 'SF Mono', 'Courier New', monospace" font-size="13">
        """

        for y in 0..<buffer.height {
            let rowY = titleH + padY + Double(y) * cellH + 13.0
            for x in 0..<buffer.width {
                guard let cell = buffer.cell(atX: x, y: y), !cell.isContinuation else { continue }
                let cellX = padX + Double(x) * cellW
                if cell.bg != .default {
                    let hex = hexColor(for: cell.bg)
                    svg += "<rect x=\"\(cellX)\" y=\"\(rowY - 13.0)\" width=\"\(cellW)\" height=\"\(cellH)\" fill=\"\(hex)\"/>\n"
                }
                if cell.symbol != " " && !cell.symbol.isEmpty {
                    let fgHex = hexColor(for: cell.fg)
                    let escaped = cell.symbol
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                    svg += "<text x=\"\(cellX)\" y=\"\(rowY)\" fill=\"\(fgHex)\">\(escaped)</text>\n"
                }
            }
        }

        svg += "</g></svg>"
        return svg
    }

    private static func hexColor(for color: SwiftTUI.Color) -> String {
        switch color {
        case .default: return "#E6EDF3"
        case .black: return "#161B22"
        case .red: return "#FF7B72"
        case .green: return "#3FB950"
        case .yellow: return "#D29922"
        case .blue: return "#58A6FF"
        case .magenta: return "#BC8CFF"
        case .cyan: return "#39C5CF"
        case .white: return "#C9D1D9"
        case .brightBlack: return "#6E7681"
        case .brightRed: return "#FFA198"
        case .brightGreen: return "#56D364"
        case .brightYellow: return "#E3B341"
        case .brightBlue: return "#79C0FF"
        case .brightMagenta: return "#D2A8FF"
        case .brightCyan: return "#56D4DD"
        case .brightWhite: return "#FFFFFF"
        case .orange: return "#FF9800"
        case .rgb(let r, let g, let b):
            return String(format: "#%02X%02X%02X", r, g, b)
        case .indexed:
            return "#ABB2BF"
        }
    }
}

extension TestHarness {
    #if canImport(AppKit)
    /// Captures the current harness buffer as a PNG image and saves it to disk.
    @MainActor
    public func saveScreenshot(to fileURL: URL, title: String = "SwiftTUI Terminal") throws {
        try TerminalScreenshotRenderer.saveScreenshot(buffer: self.buffer, to: fileURL, title: title)
    }
    #endif
}
