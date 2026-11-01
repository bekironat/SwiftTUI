import Foundation
import SwiftTUI

/// Headless test driver for mounting, inspecting, and interacting with any `SwiftTUI` `View` in unit and integration tests.
@MainActor
public final class TestHarness<Root: View> {
    public let backend: HeadlessBackend
    public let application: TerminalApplication<Root>

    public init(rootView: Root, width: Int = 100, height: Int = 30) {
        self.backend = HeadlessBackend(width: width, height: height)
        self.application = TerminalApplication(rootView: rootView, backend: backend)
        self.application.renderFrame()
    }

    public var buffer: Buffer {
        backend.currentBuffer
    }

    public var activeFocusID: AnyHashable? {
        get { application.store.activeFocusID }
        set {
            application.store.activeFocusID = newValue
            application.renderFrame()
        }
    }

    public func snapshot(trimTrailingSpaces: Bool = true) -> String {
        buffer.snapshot(trimTrailingSpaces: trimTrailingSpaces)
    }

    public func contains(_ text: String) -> Bool {
        snapshot(trimTrailingSpaces: false).contains(text)
    }

    @discardableResult
    public func render() -> Buffer {
        application.renderFrame()
    }

    public func sendKey(_ key: KeyCode, modifiers: KeyModifiers = []) {
        application.handleEvent(.key(KeyEvent(key, modifiers: modifiers)))
    }

    public func sendCtrl(_ char: Character) {
        application.handleEvent(.key(.ctrl(char)))
    }

    public func sendCtrlSpace() {
        application.handleEvent(.key(KeyEvent(.space, modifiers: [.control])))
    }

    public func type(_ text: String) {
        for ch in text {
            if ch == "\n" {
                sendKey(.enter)
            } else if ch == " " {
                sendKey(.space)
            } else {
                sendKey(.char(ch))
            }
        }
    }

    public func click(x: Int, y: Int, button: MouseButton = .left) {
        application.handleEvent(.mouse(MouseEvent(kind: .down(button), x: x, y: y)))
        application.handleEvent(.mouse(MouseEvent(kind: .up(button), x: x, y: y)))
    }

    public func resize(width: Int, height: Int) {
        backend.terminalSize = Size(width: width, height: height)
        application.handleEvent(.resize(width: width, height: height))
    }
}
