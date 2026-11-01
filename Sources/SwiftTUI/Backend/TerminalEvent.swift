import Foundation

/// Keyboard modifier flags.
public struct KeyModifiers: OptionSet, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift   = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let alt     = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Alias for SwiftUI `.keyboardShortcut` compatibility.
    public static let option  = KeyModifiers.alt

    public var description: String {
        var parts: [String] = []
        if contains(.control) { parts.append("Ctrl") }
        if contains(.alt)     { parts.append("Alt") }
        if contains(.shift)   { parts.append("Shift") }
        if contains(.command) { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }
}

/// Logical key codes recognized by the terminal input parser.
public enum KeyCode: Equatable, Hashable, Sendable, CustomStringConvertible {
    case char(Character)
    case enter
    case tab
    case backTab
    case backspace
    case delete
    case escape
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case insert
    case f(Int)
    case space
    case null

    public var description: String {
        switch self {
        case .char(let c): return String(c)
        case .enter: return "Enter"
        case .tab: return "Tab"
        case .backTab: return "Shift+Tab"
        case .backspace: return "Backspace"
        case .delete: return "Delete"
        case .escape: return "Esc"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "PageUp"
        case .pageDown: return "PageDown"
        case .insert: return "Insert"
        case .f(let n): return "F\(n)"
        case .space: return "Space"
        case .null: return "Null"
        }
    }
}

/// A keyboard event combining a `KeyCode` and active `KeyModifiers`.
public struct KeyEvent: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var key: KeyCode
    public var modifiers: KeyModifiers

    public init(_ key: KeyCode, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func char(_ c: Character, modifiers: KeyModifiers = []) -> KeyEvent {
        if c == " " && modifiers.isEmpty {
            return KeyEvent(.space)
        }
        return KeyEvent(.char(c), modifiers: modifiers)
    }

    public static func ctrl(_ c: Character) -> KeyEvent {
        if c == " " {
            return KeyEvent(.space, modifiers: [.control])
        }
        return KeyEvent(.char(Character(c.lowercased())), modifiers: [.control])
    }

    public var isCtrlSpace: Bool {
        (key == .space && modifiers.contains(.control)) || key == .null
    }

    public var description: String {
        if modifiers.isEmpty {
            return key.description
        }
        return "\(modifiers.description)+\(key.description)"
    }
}

/// Mouse buttons reported by SGR terminal mouse tracking.
public enum MouseButton: Equatable, Hashable, Sendable {
    case left
    case middle
    case right
    case none
}

/// Mouse interaction types.
public enum MouseEventKind: Equatable, Hashable, Sendable {
    case down(MouseButton)
    case up(MouseButton)
    case drag(MouseButton)
    case moved
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight
}

/// A terminal mouse event in 0-indexed `(x: column, y: row)` coordinates.
public struct MouseEvent: Equatable, Hashable, Sendable {
    public var kind: MouseEventKind
    public var x: Int
    public var y: Int
    public var modifiers: KeyModifiers

    public init(kind: MouseEventKind, x: Int, y: Int, modifiers: KeyModifiers = []) {
        self.kind = kind
        self.x = x
        self.y = y
        self.modifiers = modifiers
    }

    public var location: Point {
        Point(x: x, y: y)
    }
}

/// Top-level event delivered by a `TerminalBackend`.
public enum TerminalEvent: Equatable, Hashable, Sendable {
    case key(KeyEvent)
    case mouse(MouseEvent)
    case paste(String)
    case resize(width: Int, height: Int)
    case tick
}
