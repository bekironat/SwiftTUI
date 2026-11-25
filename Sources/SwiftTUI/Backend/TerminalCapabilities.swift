import Foundation

// MARK: - Color Capability & Automatic Color Degradation

/// Detected or configured color depth of the host terminal emulator.
public enum ColorCapability: Int, Equatable, Hashable, Comparable, Sendable {
    /// No ANSI color codes emitted (e.g. `NO_COLOR` is set or `TERM=dumb`).
    case none = 0
    /// Standard 16 ANSI colors (`30-37`, `90-97`).
    case ansi16 = 1
    /// 256-color xterm indexed palette (`38;5;n`).
    case ansi256 = 2
    /// Full 24-bit TrueColor RGB (`38;2;r;g;b`).
    case trueColor = 3

    public static func < (lhs: ColorCapability, rhs: ColorCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Hardware terminal cursor shape (`DECSCUSR` — `CSI <Ps> SP q`).
public enum CursorShape: Int, Equatable, Hashable, Sendable {
    case `default` = 0
    case blinkingBlock = 1
    case steadyBlock = 2
    case blinkingUnderline = 3
    case steadyUnderline = 4
    case blinkingBar = 5
    case steadyBar = 6

    /// Returns the ANSI `DECSCUSR` escape sequence for this cursor shape.
    public var ansiSequence: String {
        "\u{1B}[\(rawValue) q"
    }
}

/// Terminal taskbar/tab progress indicator state (`OSC 9;4` — supported by Windows Terminal, Ghostty, iTerm2, ConEmu, VTE).
public enum TerminalProgressState: Equatable, Hashable, Sendable {
    /// Hide / clear the progress bar (`OSC 9;4;0;0`).
    case hidden
    /// Normal progress percentage (`0...100`).
    case normal(Int)
    /// Error progress percentage (`0...100`).
    case error(Int)
    /// Indeterminate / pulsing progress indicator.
    case indeterminate
    /// Paused / warning progress percentage (`0...100`).
    case paused(Int)

    /// Returns the `OSC 9;4` escape sequence (`\e]9;4;<st>;<pr>\a`).
    public var ansiSequence: String {
        switch self {
        case .hidden:
            return "\u{1B}]9;4;0;0\u{07}"
        case .normal(let pct):
            return "\u{1B}]9;4;1;\(max(0, min(100, pct)))\u{07}"
        case .error(let pct):
            return "\u{1B}]9;4;2;\(max(0, min(100, pct)))\u{07}"
        case .indeterminate:
            return "\u{1B}]9;4;3;0\u{07}"
        case .paused(let pct):
            return "\u{1B}]9;4;4;\(max(0, min(100, pct)))\u{07}"
        }
    }
}

/// Terminal viewport rendering mode (full alternate screen vs. inline scrollback-preserving viewport).
public enum ViewportMode: Equatable, Hashable, Sendable {
    /// Standard full-screen alternate buffer (`CSI ? 1049 h`).
    case alternateScreen
    /// Inline viewport of `height` rows rendered directly in the terminal's normal scrollback buffer.
    case inline(height: Int)
}

/// Detected terminal emulator capabilities derived from standard environment variables (`NO_COLOR`, `COLORTERM`, `TERM`, `TERM_PROGRAM`, `KITTY_WINDOW_ID`, `WT_SESSION`).
public struct TerminalCapabilities: Equatable, Hashable, Sendable {
    public var colorCapability: ColorCapability
    public var supportsSynchronizedOutput: Bool
    public var supportsKittyKeyboard: Bool
    public var supportsOSC8Hyperlinks: Bool
    public var supportsOSC52Clipboard: Bool
    public var supportsStyledUnderlines: Bool
    public var preferredImageProtocol: TerminalImageProtocol

    public init(
        colorCapability: ColorCapability = .trueColor,
        supportsSynchronizedOutput: Bool = true,
        supportsKittyKeyboard: Bool = false,
        supportsOSC8Hyperlinks: Bool = true,
        supportsOSC52Clipboard: Bool = true,
        supportsStyledUnderlines: Bool = true,
        preferredImageProtocol: TerminalImageProtocol = .halfBlocks
    ) {
        self.colorCapability = colorCapability
        self.supportsSynchronizedOutput = supportsSynchronizedOutput
        self.supportsKittyKeyboard = supportsKittyKeyboard
        self.supportsOSC8Hyperlinks = supportsOSC8Hyperlinks
        self.supportsOSC52Clipboard = supportsOSC52Clipboard
        self.supportsStyledUnderlines = supportsStyledUnderlines
        self.preferredImageProtocol = preferredImageProtocol
    }

    /// Automatically detects host terminal capabilities from environment variables.
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalCapabilities {
        let term = (environment["TERM"] ?? "").lowercased()
        let colorTerm = (environment["COLORTERM"] ?? "").lowercased()
        let termProgram = environment["TERM_PROGRAM"] ?? ""
        let noColor = environment["NO_COLOR"]

        // 1. Color capability detection (respects https://no-color.org)
        let colorCap: ColorCapability
        if let noColor, !noColor.isEmpty {
            colorCap = .none
        } else if term == "dumb" {
            colorCap = .none
        } else if colorTerm == "truecolor" || colorTerm == "24bit" ||
                  environment["KITTY_WINDOW_ID"] != nil ||
                  environment["WT_SESSION"] != nil ||
                  termProgram == "iTerm.app" ||
                  termProgram == "WezTerm" ||
                  termProgram == "ghostty" ||
                  termProgram == "Alacritty" ||
                  termProgram == "vscode" ||
                  termProgram == "Hyper" ||
                  term == "xterm-kitty" ||
                  term == "xterm-ghostty" {
            colorCap = .trueColor
        } else if termProgram == "Apple_Terminal" || term.contains("256color") {
            colorCap = .ansi256
        } else {
            colorCap = .ansi16
        }

        // 2. Kitty keyboard protocol support
        let kittyKeyboard = (
            environment["KITTY_WINDOW_ID"] != nil ||
            term == "xterm-kitty" ||
            term == "xterm-ghostty" ||
            termProgram == "ghostty" ||
            termProgram == "WezTerm" ||
            termProgram == "Alacritty" ||
            termProgram == "iTerm.app"
        )

        // 3. Synchronized output (DECSET 2026)
        let syncOut = (term != "dumb" && termProgram != "Apple_Terminal")

        // 4. Styled/colored underlines (4:3, 58;...)
        let styledUnderlines = (
            colorCap == .trueColor &&
            termProgram != "Apple_Terminal"
        )

        // 5. Preferred graphics protocol
        let imgProto = Image.detectTerminalProtocol(environment: environment)

        return TerminalCapabilities(
            colorCapability: colorCap,
            supportsSynchronizedOutput: syncOut,
            supportsKittyKeyboard: kittyKeyboard,
            supportsOSC8Hyperlinks: term != "dumb",
            supportsOSC52Clipboard: term != "dumb",
            supportsStyledUnderlines: styledUnderlines,
            preferredImageProtocol: imgProto
        )
    }

    /// Encodes a sanitized OSC 2 terminal window title sequence (`\e]2;<title>\a`).
    public static func encodeWindowTitleSequence(_ title: String) -> String {
        let safe = Cell.sanitizeURL(title)
        return "\u{1B}]2;\(safe)\u{07}"
    }
}

// MARK: - Color Degradation Helpers

extension Color {
    /// Quantizes this color to fit within `capability` (`.trueColor`, `.ansi256`, `.ansi16`, or `.none`).
    public func degraded(to capability: ColorCapability) -> Color {
        switch capability {
        case .none:
            return .default
        case .trueColor:
            return self
        case .ansi256:
            switch self {
            case .rgb(let r, let g, let b):
                return .indexed(Self.nearestANSI256Index(r: r, g: g, b: b))
            default:
                return self
            }
        case .ansi16:
            switch self {
            case .rgb(let r, let g, let b):
                return Self.nearestANSI16Color(r: r, g: g, b: b)
            case .indexed(let idx):
                let rgb = Self.rgbFromANSI256(idx)
                return Self.nearestANSI16Color(r: rgb.r, g: rgb.g, b: rgb.b)
            default:
                return self
            }
        }
    }

    /// Maps an xterm 256-color index (`0...255`) to its approximate 24-bit RGB components.
    public static func rgbFromANSI256(_ index: UInt8) -> (r: UInt8, g: UInt8, b: UInt8) {
        let i = Int(index)
        if i < 16 {
            let ansi16Palette: [(UInt8, UInt8, UInt8)] = [
                (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
                (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
                (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
            ]
            return ansi16Palette[i]
        } else if i < 232 {
            let cube = i - 16
            let rIdx = cube / 36
            let gIdx = (cube % 36) / 6
            let bIdx = cube % 6
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            return (levels[rIdx], levels[gIdx], levels[bIdx])
        } else {
            let gray = UInt8(8 + (i - 232) * 10)
            return (gray, gray, gray)
        }
    }

    /// Maps a 24-bit RGB triplet to the closest xterm-256 color index (comparing the 6x6x6 cube and 24-step grayscale ramp).
    public static func nearestANSI256Index(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let levels: [Int] = [0, 95, 135, 175, 215, 255]

        func nearestCubeLevel(_ v: UInt8) -> Int {
            let iv = Int(v)
            var bestIdx = 0
            var bestDist = Int.max
            for (idx, lv) in levels.enumerated() {
                let d = abs(iv - lv)
                if d < bestDist {
                    bestDist = d
                    bestIdx = idx
                }
            }
            return bestIdx
        }

        let rIdx = nearestCubeLevel(r)
        let gIdx = nearestCubeLevel(g)
        let bIdx = nearestCubeLevel(b)
        let cubeIndex = UInt8(16 + 36 * rIdx + 6 * gIdx + bIdx)

        let cr = levels[rIdx]
        let cg = levels[gIdx]
        let cb = levels[bIdx]
        let cubeDist = (Int(r) - cr) * (Int(r) - cr) + (Int(g) - cg) * (Int(g) - cg) + (Int(b) - cb) * (Int(b) - cb)

        // Compare with grayscale ramp (232...255 -> 8, 18, ..., 238)
        let avg = (Int(r) + Int(g) + Int(b)) / 3
        let grayStep = max(0, min(23, (avg - 8 + 5) / 10))
        let grayVal = 8 + grayStep * 10
        let grayDist = (Int(r) - grayVal) * (Int(r) - grayVal) + (Int(g) - grayVal) * (Int(g) - grayVal) + (Int(b) - grayVal) * (Int(b) - grayVal)

        return grayDist < cubeDist ? UInt8(232 + grayStep) : cubeIndex
    }

    /// Maps a 24-bit RGB triplet to the closest standard ANSI 16 color.
    public static func nearestANSI16Color(r: UInt8, g: UInt8, b: UInt8) -> Color {
        let candidates: [(Color, Int, Int, Int)] = [
            (.black, 0, 0, 0),
            (.red, 170, 0, 0),
            (.green, 0, 170, 0),
            (.yellow, 170, 170, 0),
            (.blue, 0, 0, 170),
            (.magenta, 170, 0, 170),
            (.cyan, 0, 170, 170),
            (.white, 170, 170, 170),
            (.brightBlack, 85, 85, 85),
            (.brightRed, 255, 85, 85),
            (.brightGreen, 85, 255, 85),
            (.brightYellow, 255, 255, 85),
            (.brightBlue, 85, 85, 255),
            (.brightMagenta, 255, 85, 255),
            (.brightCyan, 85, 255, 255),
            (.brightWhite, 255, 255, 255)
        ]

        var bestColor: Color = .white
        var bestDist = Int.max
        let ir = Int(r), ig = Int(g), ib = Int(b)
        for (color, cr, cg, cb) in candidates {
            let dr = ir - cr
            let dg = ig - cg
            let db = ib - cb
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist {
                bestDist = dist
                bestColor = color
            }
        }
        return bestColor
    }
}
