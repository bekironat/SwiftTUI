import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 1. PixelRGBA & PixelBitmap (2D RGBA Image Buffer)

/// A 32-bit RGBA pixel used by `PixelBitmap` and `Image`.
public struct PixelRGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public static let clear = PixelRGBA(r: 0, g: 0, b: 0, a: 0)
    public static let black = PixelRGBA(r: 0, g: 0, b: 0, a: 255)
    public static let white = PixelRGBA(r: 255, g: 255, b: 255, a: 255)

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var color: Color {
        .rgb(r, g, b)
    }
}

/// Terminal graphics protocol used for rendering bitmap images.
public enum TerminalImageProtocol: String, Equatable, Hashable, Sendable {
    /// Universal 24-bit TrueColor half-block (`▀` / `▄`) sub-pixel rendering (2 vertical pixels per character cell). Works in 100% of terminals.
    case halfBlocks
    /// Kitty Graphics Protocol (`APC G a=T,f=32,...`).
    case kitty
    /// iTerm2 Inline Images Protocol (`OSC 1337;File=inline=1:...`).
    case iterm2
    /// DEC Sixel Graphics (`DCS q ... ST`).
    case sixel
    /// Automatically detects terminal capabilities (`KITTY_WINDOW_ID`, `TERM_PROGRAM`) with half-block buffer representation.
    case auto
}

/// A 2D bitmap of `PixelRGBA` pixels that can be rendered into the terminal via `Image`.
public struct PixelBitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [PixelRGBA]

    public init(width: Int, height: Int, fill: PixelRGBA = .clear) {
        let w = max(1, width)
        let h = max(1, height)
        self.width = w
        self.height = h
        self.pixels = Array(repeating: fill, count: w * h)
    }

    public init(width: Int, height: Int, generator: (Int, Int) -> PixelRGBA) {
        let w = max(1, width)
        let h = max(1, height)
        self.width = w
        self.height = h
        var buf: [PixelRGBA] = []
        buf.reserveCapacity(w * h)
        for y in 0..<h {
            for x in 0..<w {
                buf.append(generator(x, y))
            }
        }
        self.pixels = buf
    }

    #if canImport(AppKit)
    /// Loads a `PixelBitmap` from an image file URL (PNG, JPEG, TIFF) on macOS using CoreGraphics.
    public init?(contentsOf url: URL, maxDimension: Int = 64) {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = min(1.0, Double(maxDimension) / Double(max(srcW, srcH)))
        let w = max(1, Int((Double(srcW) * scale).rounded()))
        let h = max(1, Int((Double(srcH) * scale).rounded()))

        var rawData = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: &rawData,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.width = w
        self.height = h
        var out: [PixelRGBA] = []
        out.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let base = i * 4
            out.append(PixelRGBA(r: rawData[base], g: rawData[base + 1], b: rawData[base + 2], a: rawData[base + 3]))
        }
        self.pixels = out
    }
    #endif

    @inline(__always)
    public func pixel(x: Int, y: Int) -> PixelRGBA {
        guard x >= 0, x < width, y >= 0, y < height else { return .clear }
        return pixels[y * width + x]
    }

    public mutating func setPixel(x: Int, y: Int, _ pixel: PixelRGBA) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        pixels[y * width + x] = pixel
    }

    /// Resamples this bitmap to `(targetWidth, targetHeight)` using nearest-neighbor scaling.
    public func resized(width targetWidth: Int, height targetHeight: Int) -> PixelBitmap {
        let tw = max(1, targetWidth)
        let th = max(1, targetHeight)
        if tw == width && th == height { return self }
        return PixelBitmap(width: tw, height: th) { x, y in
            let srcX = min(width - 1, (x * width) / tw)
            let srcY = min(height - 1, (y * height) / th)
            return pixel(x: srcX, y: srcY)
        }
    }

    // MARK: - Protocol Escape Sequence Encoders (Kitty, iTerm2 OSC 1337, Sixel)

    /// Encodes this bitmap using the Kitty Graphics Protocol (`\e_Ga=T,f=32,s=<w>,v=<h>;<base64>\e\\`).
    public func encodeKittyEscapeSequence(columns: Int? = nil, rows: Int? = nil) -> String {
        var rawRGBA: [UInt8] = []
        rawRGBA.reserveCapacity(width * height * 4)
        for p in pixels {
            rawRGBA.append(p.r)
            rawRGBA.append(p.g)
            rawRGBA.append(p.b)
            rawRGBA.append(p.a)
        }
        let b64 = Data(rawRGBA).base64EncodedString()
        var params = "a=T,f=32,s=\(width),v=\(height)"
        if let cols = columns { params += ",c=\(cols)" }
        if let r = rows { params += ",r=\(r)" }
        return "\u{1B}_G\(params);\(b64)\u{1B}\\"
    }

    /// Encodes this bitmap using the iTerm2 Inline Image Protocol (`\e]1337;File=inline=1;width=<c>;height=<r>:<base64>\a`).
    public func encodeITerm2EscapeSequence(columns: Int? = nil, rows: Int? = nil) -> String {
        // Encode a compact binary PPM (P6) payload which iTerm2 and WezTerm decode natively
        let header = "P6\n\(width) \(height)\n255\n"
        var data = Data(header.utf8)
        data.reserveCapacity(data.count + width * height * 3)
        for p in pixels {
            data.append(p.r)
            data.append(p.g)
            data.append(p.b)
        }
        let b64 = data.base64EncodedString()
        var opts = "inline=1;preserveAspectRatio=1"
        if let cols = columns { opts += ";width=\(cols)" }
        if let r = rows { opts += ";height=\(r)" }
        return "\u{1B}]1337;File=\(opts):\(b64)\u{07}"
    }

    /// Encodes this bitmap using DEC Sixel graphics (`\ePq...\e\\`).
    public func encodeSixelEscapeSequence() -> String {
        var out = "\u{1B}Pq\"1;1;\(width);\(height)"
        // Quantize to a compact 16-color palette for fast Sixel band emission
        var palette: [PixelRGBA] = []
        var colorIndexMap: [PixelRGBA: Int] = [:]

        func quantize(_ p: PixelRGBA) -> PixelRGBA {
            PixelRGBA(r: (p.r / 32) * 32, g: (p.g / 32) * 32, b: (p.b / 32) * 32, a: p.a >= 128 ? 255 : 0)
        }

        for p in pixels {
            let q = quantize(p)
            guard q.a > 0 else { continue }
            if colorIndexMap[q] == nil && palette.count < 32 {
                let idx = palette.count
                palette.append(q)
                colorIndexMap[q] = idx
                let rPct = Int((Double(q.r) / 255.0 * 100.0).rounded())
                let gPct = Int((Double(q.g) / 255.0 * 100.0).rounded())
                let bPct = Int((Double(q.b) / 255.0 * 100.0).rounded())
                out += "#\(idx);2;\(rPct);\(gPct);\(bPct)"
            }
        }

        let bandCount = (height + 5) / 6
        for band in 0..<bandCount {
            let baseY = band * 6
            for (cIdx, color) in palette.enumerated() {
                var bandHasPixels = false
                var chars: [Character] = []
                chars.reserveCapacity(width)
                for x in 0..<width {
                    var bits: UInt8 = 0
                    for dy in 0..<6 where baseY + dy < height {
                        let q = quantize(pixel(x: x, y: baseY + dy))
                        if q == color {
                            bits |= (1 << dy)
                        }
                    }
                    if bits != 0 { bandHasPixels = true }
                    chars.append(Character(UnicodeScalar(63 + bits)))
                }
                if bandHasPixels {
                    out += "#\(cIdx)" + String(chars) + "$"
                }
            }
            out += "-"
        }
        out += "\u{1B}\\"
        return out
    }

    // MARK: - Built-in Procedural & Sprite Bitmaps

    /// Generates a vibrant 24-bit RGB color spectrum & plasma gradient bitmap.
    public static func colorSpectrum(width: Int = 24, height: Int = 10) -> PixelBitmap {
        PixelBitmap(width: width, height: height) { x, y in
            let nx = Double(x) / Double(max(1, width - 1))
            let ny = Double(y) / Double(max(1, height - 1))
            let r = UInt8(clamping: Int(((sin(nx * Double.pi) * 0.5 + 0.5) * 255.0).rounded()))
            let g = UInt8(clamping: Int(((cos(ny * Double.pi * 0.8) * 0.5 + 0.5) * 230.0).rounded()))
            let b = UInt8(clamping: Int(((nx * 0.7 + (1.0 - ny) * 0.3) * 255.0).rounded()))
            return PixelRGBA(r: r, g: g, b: b, a: 255)
        }
    }

    /// Generates a pixel-art Swift bird emblem on a deep indigo badge.
    public static func swiftEmblem(width: Int = 16, height: Int = 10) -> PixelBitmap {
        let pattern: [String] = [
            "................",
            "..OO.......OO...",
            "...OOO....OOO...",
            "..OOOOO..OOOO...",
            "....OOOOOOOOO...",
            ".....OOOOOOOO...",
            "...OOOOOOOOOO...",
            "..OOOOOOOOOOOO..",
            ".....OOOOOOO....",
            "................"
        ]
        let base = PixelBitmap(width: 16, height: 10) { x, y in
            let row = Array(pattern[y])
            if row[x] == "O" {
                let grad = UInt8(clamping: 255 - y * 12)
                return PixelRGBA(r: 255, g: grad / 2 + 40, b: 35, a: 255)
            } else {
                return PixelRGBA(r: 28, g: 34, b: 58, a: 255)
            }
        }
        return base.resized(width: width, height: height)
    }
}

// MARK: - 2. Image View (Universal Half-Block 2×1 Sub-Pixel & Terminal Protocol View)

/// A view that displays a `PixelBitmap` image in the terminal using 2×1 vertical half-block sub-pixels (`▀` / `▄`)
/// and supports encoding to Kitty, iTerm2 (`OSC 1337`), and Sixel graphics protocols.
/// Matches SwiftUI's `Image`.
public struct Image: View, _PrimitiveView {
    public typealias Body = Never
    public let bitmap: PixelBitmap
    public let imageProtocol: TerminalImageProtocol
    public let isResizable: Bool

    public init(bitmap: PixelBitmap, protocol imageProtocol: TerminalImageProtocol = .halfBlocks, resizable: Bool = false) {
        self.bitmap = bitmap
        self.imageProtocol = imageProtocol
        self.isResizable = resizable
    }

    public init(width: Int, height: Int, protocol imageProtocol: TerminalImageProtocol = .halfBlocks, generator: (Int, Int) -> PixelRGBA) {
        self.bitmap = PixelBitmap(width: width, height: height, generator: generator)
        self.imageProtocol = imageProtocol
        self.isResizable = false
    }

    /// Returns a resizable copy of this `Image` that scales its pixel bitmap to fit the proposed layout frame.
    public func resizable() -> Image {
        Image(bitmap: bitmap, protocol: imageProtocol, resizable: true)
    }

    /// Detects the active terminal emulator's preferred pixel graphics protocol from environment variables.
    public static func detectTerminalProtocol(environment: [String: String] = ProcessInfo.processInfo.environment) -> TerminalImageProtocol {
        if environment["KITTY_WINDOW_ID"] != nil || environment["TERM"] == "xterm-kitty" || environment["TERM_PROGRAM"] == "ghostty" {
            return .kitty
        }
        if let prog = environment["TERM_PROGRAM"], (prog == "iTerm.app" || prog == "WezTerm") {
            return .iterm2
        }
        if environment["TERM"]?.contains("sixel") == true {
            return .sixel
        }
        return .halfBlocks
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let srcBitmap = bitmap
        let scaleToFit = isResizable
        let fallbackBg = context.environment.backgroundColor

        return [
            RenderNode(
                id: "\(context.path).Image",
                flexibleAxes: scaleToFit ? [.horizontal, .vertical] : [],
                measure: { proposal in
                    let naturalCols = srcBitmap.width
                    let naturalRows = max(1, (srcBitmap.height + 1) / 2)
                    if scaleToFit {
                        return Size(
                            width: proposal.width ?? naturalCols,
                            height: proposal.height ?? naturalRows
                        )
                    }
                    return Size(
                        width: min(proposal.width ?? naturalCols, naturalCols),
                        height: min(proposal.height ?? naturalRows, naturalRows)
                    )
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }
                    let targetPixelW = scaleToFit ? rect.width : min(rect.width, srcBitmap.width)
                    let targetPixelH = scaleToFit ? (rect.height * 2) : min(rect.height * 2, srcBitmap.height)
                    let activeBitmap = (scaleToFit && (targetPixelW != srcBitmap.width || targetPixelH != srcBitmap.height))
                        ? srcBitmap.resized(width: targetPixelW, height: targetPixelH)
                        : srcBitmap

                    let cellCols = min(rect.width, activeBitmap.width)
                    let cellRows = min(rect.height, (activeBitmap.height + 1) / 2)

                    for row in 0..<cellRows {
                        let pyTop = row * 2
                        let pyBot = pyTop + 1
                        let screenY = rect.minY + row
                        if screenY >= rect.maxY { break }

                        for col in 0..<cellCols {
                            let screenX = rect.minX + col
                            if screenX >= rect.maxX { break }

                            let topPx = activeBitmap.pixel(x: col, y: pyTop)
                            let botPx = (pyBot < activeBitmap.height) ? activeBitmap.pixel(x: col, y: pyBot) : .clear

                            let topVis = topPx.a >= 64
                            let botVis = botPx.a >= 64

                            if topVis && botVis {
                                if topPx.r == botPx.r && topPx.g == botPx.g && topPx.b == botPx.b {
                                    buffer.setCell(
                                        x: screenX,
                                        y: screenY,
                                        symbol: "█",
                                        style: CellStyle(fg: topPx.color, bg: topPx.color)
                                    )
                                } else {
                                    buffer.setCell(
                                        x: screenX,
                                        y: screenY,
                                        symbol: "▀",
                                        style: CellStyle(fg: topPx.color, bg: botPx.color)
                                    )
                                }
                            } else if topVis {
                                buffer.setCell(
                                    x: screenX,
                                    y: screenY,
                                    symbol: "▀",
                                    style: CellStyle(fg: topPx.color, bg: fallbackBg)
                                )
                            } else if botVis {
                                buffer.setCell(
                                    x: screenX,
                                    y: screenY,
                                    symbol: "▄",
                                    style: CellStyle(fg: botPx.color, bg: fallbackBg)
                                )
                            }
                        }
                    }
                }
            )
        ]
    }
}
