import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 1. OSC-52 System Clipboard Controller (TerminalClipboard)

/// Target selection buffer for OSC-52 clipboard operations.
public enum ClipboardTarget: String, Equatable, Hashable, Sendable {
    /// Standard system clipboard (`c`).
    case clipboard = "c"
    /// Primary X11/terminal selection buffer (`p`).
    case primarySelection = "p"
}

/// Manages OSC-52 terminal clipboard sequences (`\e]52;c;<base64>\a`) so `SwiftTUI` apps can copy text
/// to the user's host OS clipboard locally or over remote SSH / tmux sessions.
public final class TerminalClipboard: @unchecked Sendable {
    public static let shared = TerminalClipboard()

    private let lock = NSLock()
    private var _lastCopiedText: String? = nil
    private var _pendingOSC52Sequence: String? = nil

    public init() {}

    /// Most recent string copied via `copy(_:)`, useful for headless unit test verification.
    public var lastCopiedText: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastCopiedText
    }

    /// Copies `text` to the terminal clipboard by queueing an OSC-52 sequence for the next frame flush.
    public func copy(
        _ text: String,
        target: ClipboardTarget = .clipboard,
        isTmux: Bool = ProcessInfo.processInfo.environment["TMUX"] != nil,
        syncLocalPasteboard: Bool = false
    ) {
        let seq = Self.encodeOSC52WriteSequence(text, target: target, isTmux: isTmux)
        lock.lock()
        _lastCopiedText = text
        _pendingOSC52Sequence = seq
        lock.unlock()

        #if canImport(AppKit)
        if syncLocalPasteboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        #endif
    }

    /// Atomically drains and returns any pending OSC-52 escape sequence for `DiffRenderer`.
    public func drainPendingOSC52Sequence() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let seq = _pendingOSC52Sequence
        _pendingOSC52Sequence = nil
        return seq
    }

    /// Encodes `text` into an OSC-52 clipboard write sequence (`\e]52;c;<base64>\a`), with optional `tmux` DCS passthrough wrapping.
    public static func encodeOSC52WriteSequence(
        _ text: String,
        target: ClipboardTarget = .clipboard,
        isTmux: Bool = false
    ) -> String {
        let base64 = Data(text.utf8).base64EncodedString()
        let osc = "\u{1B}]52;\(target.rawValue);\(base64)\u{07}"
        if isTmux {
            return "\u{1B}Ptmux;\u{1B}\(osc)\u{1B}\\"
        }
        return osc
    }

    /// Encodes an OSC-8 hyperlink span (`\e]8;;<url>\e\\<label>\e]8;;\e\\`).
    public static func encodeOSC8Hyperlink(label: String, url: String) -> String {
        let cleanURL = Cell.sanitizeURL(url)
        return "\u{1B}]8;;\(cleanURL)\u{1B}\\\(label)\u{1B}]8;;\u{1B}\\"
    }
}

// MARK: - EnvironmentKey for TerminalClipboard

private struct ClipboardEnvironmentKey: EnvironmentKey {
    static let defaultValue: TerminalClipboard = .shared
}

extension EnvironmentValues {
    /// Accesses the terminal clipboard controller (`OSC-52`) from the environment.
    public var clipboard: TerminalClipboard {
        get { self[ClipboardEnvironmentKey.self] }
        set { self[ClipboardEnvironmentKey.self] = newValue }
    }
}

// MARK: - 2. OSC-8 Clickable Hyperlink View (Link)

/// A control for navigating to a URL, rendered with terminal OSC-8 clickable hyperlink metadata (`\e]8;;<url>\e\\`)
/// and keyboard/mouse activation support.
/// Matches SwiftUI's `Link`.
public struct Link: View, _PrimitiveView {
    public typealias Body = Never
    public let title: String
    public let destination: String
    public let customID: AnyHashable?
    public let onActivate: (@MainActor () -> Void)?

    public init(
        _ title: String,
        destination: String,
        id: AnyHashable? = nil,
        onActivate: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.destination = Cell.sanitizeURL(destination)
        self.customID = id
        self.onActivate = onActivate
    }

    public init(
        _ title: String,
        destination: URL,
        id: AnyHashable? = nil,
        onActivate: (@MainActor () -> Void)? = nil
    ) {
        self.init(title, destination: destination.absoluteString, id: id, onActivate: onActivate)
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let focusID = customID ?? AnyHashable("\(path).Link[\(title)]")
        store.registerFocusable(focusID)

        let displayText = "🔗 \(title) ↗"
        let displayW = UnicodeWidth.width(of: displayText)
        let targetURL = destination
        let customHandler = onActivate

        return [
            RenderNode(
                id: "\(path).Link",
                measure: { _ in
                    Size(width: displayW, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == focusID)
                    let fg: Color = isFocused ? .brightYellow : .brightCyan
                    let bg: Color = isFocused ? .rgb(30, 42, 64) : context.environment.backgroundColor
                    let linkStyle = CellStyle(
                        fg: fg,
                        bg: bg,
                        modifiers: isFocused ? [.bold, .underlined] : [.underlined],
                        hyperlink: targetURL
                    )

                    buffer.writeString(x: rect.minX, y: rect.minY, displayText, style: linkStyle, maxWidth: rect.width)

                    let triggerLink: @MainActor () -> Void = {
                        if let customHandler {
                            customHandler()
                        } else {
                            // Copy destination URL to OSC-52 clipboard as a safe universal fallback in terminal sessions
                            TerminalClipboard.shared.copy(targetURL)
                        }
                        store.markDirty()
                    }

                    interactions.registerFocusedKeyHandler(for: focusID) { key in
                        if key.key == .enter || key.key == .space {
                            triggerLink()
                            return true
                        }
                        return false
                    }

                    let hitRect = Rect(x: rect.minX, y: rect.minY, width: min(rect.width, displayW), height: 1)
                    interactions.registerMouseTarget(rect: hitRect, zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            store.activeFocusID = focusID
                            triggerLink()
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}
