import Foundation

/// Terminal color supporting default, ANSI 16, 256-indexed, and 24-bit TrueColor RGB.
public enum Color: Equatable, Hashable, Sendable {
    case `default`
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)

    // MARK: - SwiftUI Semantic & Convenience Aliases

    public static let clear = Color.default
    public static let primary = Color.default
    public static let secondary = Color.brightBlack
    public static let gray = Color.brightBlack
    public static let accentColor = Color.brightBlue
    public static let orange = Color.rgb(255, 165, 0)
    public static let purple = Color.rgb(175, 135, 255)
    public static let pink = Color.rgb(255, 121, 198)
    public static let teal = Color.rgb(80, 250, 123)
    public static let indigo = Color.rgb(102, 126, 234)
    public static let mint = Color.rgb(139, 233, 253)

    /// Creates a 24-bit RGB color from a 24-bit hex integer (e.g. `0x89B4FA`).
    public static func hex(_ value: UInt32) -> Color {
        let r = UInt8((value >> 16) & 0xFF)
        let g = UInt8((value >> 8) & 0xFF)
        let b = UInt8(value & 0xFF)
        return .rgb(r, g, b)
    }

    /// Returns the ANSI SGR parameter string for foreground or background.
    public func ansiSGRCode(isBackground: Bool) -> String {
        let base = isBackground ? 40 : 30
        let brightBase = isBackground ? 100 : 90
        switch self {
        case .default:
            return isBackground ? "49" : "39"
        case .black:
            return "\(base + 0)"
        case .red:
            return "\(base + 1)"
        case .green:
            return "\(base + 2)"
        case .yellow:
            return "\(base + 3)"
        case .blue:
            return "\(base + 4)"
        case .magenta:
            return "\(base + 5)"
        case .cyan:
            return "\(base + 6)"
        case .white:
            return "\(base + 7)"
        case .brightBlack:
            return "\(brightBase + 0)"
        case .brightRed:
            return "\(brightBase + 1)"
        case .brightGreen:
            return "\(brightBase + 2)"
        case .brightYellow:
            return "\(brightBase + 3)"
        case .brightBlue:
            return "\(brightBase + 4)"
        case .brightMagenta:
            return "\(brightBase + 5)"
        case .brightCyan:
            return "\(brightBase + 6)"
        case .brightWhite:
            return "\(brightBase + 7)"
        case .indexed(let idx):
            return isBackground ? "48;5;\(idx)" : "38;5;\(idx)"
        case .rgb(let r, let g, let b):
            return isBackground ? "48;2;\(r);\(g);\(b)" : "38;2;\(r);\(g);\(b)"
        }
    }
}

/// Terminal text attribute flags matching Ratatui's `Modifier`.
public struct CellModifiers: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold          = CellModifiers(rawValue: 1 << 0)
    public static let dim           = CellModifiers(rawValue: 1 << 1)
    public static let italic        = CellModifiers(rawValue: 1 << 2)
    public static let underlined    = CellModifiers(rawValue: 1 << 3)
    public static let slowBlink     = CellModifiers(rawValue: 1 << 4)
    public static let rapidBlink    = CellModifiers(rawValue: 1 << 5)
    public static let reversed      = CellModifiers(rawValue: 1 << 6)
    public static let hidden        = CellModifiers(rawValue: 1 << 7)
    public static let strikethrough = CellModifiers(rawValue: 1 << 8)
}

/// Complete visual styling for a single cell or text span.
public struct CellStyle: Equatable, Hashable, Sendable {
    public var fg: Color
    public var bg: Color
    public var underlineColor: Color?
    public var modifiers: CellModifiers

    public static let `default` = CellStyle()

    public init(
        fg: Color = .default,
        bg: Color = .default,
        underlineColor: Color? = nil,
        modifiers: CellModifiers = []
    ) {
        self.fg = fg
        self.bg = bg
        self.underlineColor = underlineColor
        self.modifiers = modifiers
    }

    /// Merges `other` on top of `self`, preserving `self`'s colors where `other` uses `.default`.
    public func merging(_ other: CellStyle) -> CellStyle {
        CellStyle(
            fg: other.fg == .default ? fg : other.fg,
            bg: other.bg == .default ? bg : other.bg,
            underlineColor: other.underlineColor ?? underlineColor,
            modifiers: modifiers.union(other.modifiers)
        )
    }

    public func bold() -> CellStyle {
        var copy = self
        copy.modifiers.insert(.bold)
        return copy
    }

    public func dim() -> CellStyle {
        var copy = self
        copy.modifiers.insert(.dim)
        return copy
    }

    public func italic() -> CellStyle {
        var copy = self
        copy.modifiers.insert(.italic)
        return copy
    }

    public func underlined() -> CellStyle {
        var copy = self
        copy.modifiers.insert(.underlined)
        return copy
    }

    public func reversed() -> CellStyle {
        var copy = self
        copy.modifiers.insert(.reversed)
        return copy
    }
}

/// Box-drawing glyph set for borders, splits, and tables (matching Ratatui's `border::Set`).
public struct BorderSymbols: Equatable, Hashable, Sendable {
    public var topLeft: String
    public var topRight: String
    public var bottomLeft: String
    public var bottomRight: String
    public var horizontalTop: String
    public var horizontalBottom: String
    public var verticalLeft: String
    public var verticalRight: String
    public var teeLeft: String
    public var teeRight: String
    public var teeTop: String
    public var teeBottom: String
    public var cross: String

    public init(
        topLeft: String,
        topRight: String,
        bottomLeft: String,
        bottomRight: String,
        horizontalTop: String,
        horizontalBottom: String,
        verticalLeft: String,
        verticalRight: String,
        teeLeft: String = "├",
        teeRight: String = "┤",
        teeTop: String = "┬",
        teeBottom: String = "┴",
        cross: String = "┼"
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontalTop = horizontalTop
        self.horizontalBottom = horizontalBottom
        self.verticalLeft = verticalLeft
        self.verticalRight = verticalRight
        self.teeLeft = teeLeft
        self.teeRight = teeRight
        self.teeTop = teeTop
        self.teeBottom = teeBottom
        self.cross = cross
    }

    public static let plain = BorderSymbols(
        topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘",
        horizontalTop: "─", horizontalBottom: "─", verticalLeft: "│", verticalRight: "│",
        teeLeft: "├", teeRight: "┤", teeTop: "┬", teeBottom: "┴", cross: "┼"
    )

    public static let rounded = BorderSymbols(
        topLeft: "╭", topRight: "╮", bottomLeft: "╰", bottomRight: "╯",
        horizontalTop: "─", horizontalBottom: "─", verticalLeft: "│", verticalRight: "│",
        teeLeft: "├", teeRight: "┤", teeTop: "┬", teeBottom: "┴", cross: "┼"
    )

    public static let double = BorderSymbols(
        topLeft: "╔", topRight: "╗", bottomLeft: "╚", bottomRight: "╝",
        horizontalTop: "═", horizontalBottom: "═", verticalLeft: "║", verticalRight: "║",
        teeLeft: "╠", teeRight: "╣", teeTop: "╦", teeBottom: "╩", cross: "╬"
    )

    public static let thick = BorderSymbols(
        topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛",
        horizontalTop: "━", horizontalBottom: "━", verticalLeft: "┃", verticalRight: "┃",
        teeLeft: "┣", teeRight: "┫", teeTop: "┳", teeBottom: "┻", cross: "╋"
    )

    public static let ascii = BorderSymbols(
        topLeft: "+", topRight: "+", bottomLeft: "+", bottomRight: "+",
        horizontalTop: "-", horizontalBottom: "-", verticalLeft: "|", verticalRight: "|",
        teeLeft: "+", teeRight: "+", teeTop: "+", teeBottom: "+", cross: "+"
    )
}

/// High-level border style selection for views and blocks.
public enum BorderStyle: Equatable, Hashable, Sendable {
    case none
    case plain
    case rounded
    case double
    case thick
    case ascii
    case custom(BorderSymbols)

    public var symbols: BorderSymbols? {
        switch self {
        case .none: return nil
        case .plain: return .plain
        case .rounded: return .rounded
        case .double: return .double
        case .thick: return .thick
        case .ascii: return .ascii
        case .custom(let s): return s
        }
    }
}
