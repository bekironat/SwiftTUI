import Foundation

/// A semantic color palette for `SwiftTUI` views, modals, inputs, and controls.
/// Propagated through `@Environment(\.theme)` and applied via `.theme(_:)`.
public struct Theme: Equatable, Hashable, Sendable {
    public var name: String
    public var colorScheme: ColorScheme
    public var background: Color
    public var surface: Color
    public var primary: Color
    public var secondary: Color
    public var accent: Color
    public var border: Color
    public var focusedBorder: Color
    public var selectionBackground: Color
    public var selectionForeground: Color
    public var success: Color
    public var warning: Color
    public var error: Color
    public var muted: Color

    public init(
        name: String,
        colorScheme: ColorScheme = .dark,
        background: Color = .default,
        surface: Color = .rgb(26, 30, 46),
        primary: Color = .brightWhite,
        secondary: Color = .white,
        accent: Color = .brightCyan,
        border: Color = .brightBlack,
        focusedBorder: Color = .brightCyan,
        selectionBackground: Color = .rgb(45, 79, 138),
        selectionForeground: Color = .brightWhite,
        success: Color = .brightGreen,
        warning: Color = .brightYellow,
        error: Color = .brightRed,
        muted: Color = .brightBlack
    ) {
        self.name = name
        self.colorScheme = colorScheme
        self.background = background
        self.surface = surface
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.border = border
        self.focusedBorder = focusedBorder
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.success = success
        self.warning = warning
        self.error = error
        self.muted = muted
    }

    // MARK: - Built-in Theme Presets

    public static let dark = Theme(
        name: "Dark",
        colorScheme: .dark
    )

    public static let light = Theme(
        name: "Light",
        colorScheme: .light,
        background: .rgb(248, 249, 252),
        surface: .rgb(235, 238, 245),
        primary: .rgb(24, 28, 36),
        secondary: .rgb(64, 72, 86),
        accent: .rgb(0, 102, 204),
        border: .rgb(180, 188, 200),
        focusedBorder: .rgb(0, 102, 204),
        selectionBackground: .rgb(0, 102, 204),
        selectionForeground: .brightWhite,
        success: .rgb(22, 130, 72),
        warning: .rgb(180, 110, 0),
        error: .rgb(200, 35, 51),
        muted: .rgb(120, 128, 142)
    )

    public static let catppuccinMocha = Theme(
        name: "Catppuccin Mocha",
        colorScheme: .dark,
        background: .hex(0x1E1E2E),
        surface: .hex(0x313244),
        primary: .hex(0xCDD6F4),
        secondary: .hex(0xBAC2DE),
        accent: .hex(0x89B4FA),
        border: .hex(0x585B70),
        focusedBorder: .hex(0x89B4FA),
        selectionBackground: .hex(0x45475A),
        selectionForeground: .hex(0xCDD6F4),
        success: .hex(0xA6E3A1),
        warning: .hex(0xF9E2AF),
        error: .hex(0xF38BA8),
        muted: .hex(0x6C7086)
    )

    public static let dracula = Theme(
        name: "Dracula",
        colorScheme: .dark,
        background: .hex(0x282A36),
        surface: .hex(0x343746),
        primary: .hex(0xF8F8F2),
        secondary: .hex(0xBD93F9),
        accent: .hex(0x8BE9FD),
        border: .hex(0x6272A4),
        focusedBorder: .hex(0xFF79C6),
        selectionBackground: .hex(0x44475A),
        selectionForeground: .hex(0xF8F8F2),
        success: .hex(0x50FA7B),
        warning: .hex(0xF1FA8C),
        error: .hex(0xFF5555),
        muted: .hex(0x6272A4)
    )

    public static let highContrast = Theme(
        name: "High Contrast",
        colorScheme: .dark,
        background: .black,
        surface: .black,
        primary: .brightWhite,
        secondary: .white,
        accent: .brightYellow,
        border: .brightWhite,
        focusedBorder: .brightYellow,
        selectionBackground: .brightYellow,
        selectionForeground: .black,
        success: .brightGreen,
        warning: .brightYellow,
        error: .brightRed,
        muted: .white
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

extension EnvironmentValues {
    /// Active semantic `Theme` for views and controls in this hierarchy.
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a semantic `Theme` (and updates `colorScheme`) for this view subtree.
    public func theme(_ theme: Theme) -> some View {
        _EnvironmentModifier(content: self) { env in
            env.theme = theme
            env.colorScheme = theme.colorScheme
        }
    }
}
