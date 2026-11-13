import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Abstract interface for a terminal rendering and event backend (POSIX TTY, Headless Test, Windows ConPTY, Web/Wasm, Mobile).
public protocol TerminalBackend: AnyObject {
    /// Initializes raw mode, alternate screen, and mouse/paste protocols.
    func setup() throws
    /// Restores normal terminal state.
    func teardown()
    /// Queries the current terminal dimensions in columns and rows.
    func size() -> Size
    /// Renders `buffer` to the output device (typically using differential rendering).
    func flush(_ buffer: Buffer)
    /// Polls for pending keyboard, mouse, paste, or resize events up to `timeoutMs`.
    func pollEvents(timeoutMs: Int) -> [TerminalEvent]
}

// MARK: - POSIX Terminal Backend (macOS & Linux)

nonisolated(unsafe) private var globalSigwinchFlag: sig_atomic_t = 0
nonisolated(unsafe) private var savedOriginalTermios: termios? = nil
nonisolated(unsafe) private var terminalIsInRawMode: Bool = false

private func handleSigwinch(_ sig: Int32) {
    globalSigwinchFlag = 1
}

private func emergencyRestoreTerminal() {
    guard terminalIsInRawMode else { return }
    let resetSeq = "\u{1B}[0m\u{1B}[?2004l\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?25h\u{1B}[?1049l"
    _ = resetSeq.withCString { ptr in
        write(STDOUT_FILENO, ptr, strlen(ptr))
    }
    if var orig = savedOriginalTermios {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }
    terminalIsInRawMode = false
}

/// Native POSIX terminal backend for macOS (`Darwin`) and Linux (`Glibc`).
public final class POSIXTerminalBackend: TerminalBackend {
    private var previousBuffer: Buffer?
    private let diffRenderer = DiffRenderer(useSynchronizedOutput: true)
    private let inputParser = ANSIInputParser()
    private var lastKnownSize: Size = Size(width: 80, height: 24)
    private let enableMouse: Bool

    public init(enableMouse: Bool = true) {
        self.enableMouse = enableMouse
    }

    public func setup() throws {
        var orig = termios()
        if tcgetattr(STDIN_FILENO, &orig) == 0 {
            savedOriginalTermios = orig
            var raw = orig
            cfmakeraw(&raw)
            // Keep ISIG enabled so Ctrl+C / SIGTERM can still be caught cleanly if needed, or handle Ctrl+C in raw input
            raw.c_cc.16 = 0 // VMIN = 0
            raw.c_cc.17 = 0 // VTIME = 0
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
            terminalIsInRawMode = true
            atexit(emergencyRestoreTerminal)
        }

        signal(SIGWINCH, handleSigwinch)

        var initSeq = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1004h\u{1B}[2J\u{1B}[H"
        if enableMouse {
            initSeq += "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
        }
        writeRaw(initSeq)
        lastKnownSize = size()
    }

    public func teardown() {
        emergencyRestoreTerminal()
        previousBuffer = nil
    }

    public func size() -> Size {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        if ioctl(STDIN_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        let cols = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init) ?? 100
        let rows = ProcessInfo.processInfo.environment["LINES"].flatMap(Int.init) ?? 30
        return Size(width: cols, height: rows)
    }

    public func flush(_ buffer: Buffer) {
        let ansi = diffRenderer.render(previous: previousBuffer, current: buffer)
        if !ansi.isEmpty {
            writeRaw(ansi)
        }
        previousBuffer = buffer
    }

    public func pollEvents(timeoutMs: Int) -> [TerminalEvent] {
        var events: [TerminalEvent] = []

        if globalSigwinchFlag != 0 {
            globalSigwinchFlag = 0
            let newSize = size()
            if newSize != lastKnownSize {
                lastKnownSize = newSize
                previousBuffer = nil
                events.append(.resize(width: newSize.width, height: newSize.height))
            }
        }

        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, Int32(max(0, timeoutMs)))
        if ready > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
            var readBuf = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(STDIN_FILENO, &readBuf, readBuf.count)
            if bytesRead > 0 {
                let slice = Array(readBuf[0..<bytesRead])
                events.append(contentsOf: inputParser.parse(slice))
            }
        }

        return events
    }

    private func writeRaw(_ string: String) {
        let utf8 = Array(string.utf8)
        var totalWritten = 0
        while totalWritten < utf8.count {
            let written = utf8.withUnsafeBufferPointer { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return write(STDOUT_FILENO, base.advanced(by: totalWritten), utf8.count - totalWritten)
            }
            if written <= 0 {
                break
            }
            totalWritten += written
        }
    }
}

// MARK: - Headless / In-Memory Backend

/// In-memory terminal backend for headless execution, unit tests, and snapshot verification.
public final class HeadlessBackend: TerminalBackend {
    public var terminalSize: Size
    public private(set) var currentBuffer: Buffer
    public private(set) var flushCount: Int = 0
    public private(set) var isSetup: Bool = false
    private var queuedEvents: [TerminalEvent] = []
    private let inputParser = ANSIInputParser()

    public init(width: Int = 80, height: Int = 24) {
        let sz = Size(width: width, height: height)
        self.terminalSize = sz
        self.currentBuffer = Buffer(size: sz)
    }

    public func setup() throws {
        isSetup = true
    }

    public func teardown() {
        isSetup = false
    }

    public func size() -> Size {
        terminalSize
    }

    public func flush(_ buffer: Buffer) {
        currentBuffer = buffer
        flushCount += 1
    }

    public func pollEvents(timeoutMs: Int) -> [TerminalEvent] {
        guard !queuedEvents.isEmpty else { return [] }
        let evs = queuedEvents
        queuedEvents.removeAll()
        return evs
    }

    // MARK: - Synthetic Event Injection

    public func send(_ event: TerminalEvent) {
        if case .resize(let w, let h) = event {
            terminalSize = Size(width: w, height: h)
        }
        queuedEvents.append(event)
    }

    public func sendKey(_ key: KeyCode, modifiers: KeyModifiers = []) {
        queuedEvents.append(.key(KeyEvent(key, modifiers: modifiers)))
    }

    public func typeText(_ text: String) {
        for ch in text {
            if ch == "\n" {
                queuedEvents.append(.key(KeyEvent(.enter)))
            } else if ch == " " {
                queuedEvents.append(.key(KeyEvent(.space)))
            } else {
                queuedEvents.append(.key(KeyEvent(.char(ch))))
            }
        }
    }

    public func sendRawANSI(_ bytes: [UInt8]) {
        queuedEvents.append(contentsOf: inputParser.parse(bytes))
    }

    public func sendMouseClick(x: Int, y: Int, button: MouseButton = .left) {
        queuedEvents.append(.mouse(MouseEvent(kind: .down(button), x: x, y: y)))
        queuedEvents.append(.mouse(MouseEvent(kind: .up(button), x: x, y: y)))
    }
}
