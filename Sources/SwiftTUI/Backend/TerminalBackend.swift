import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

/// Abstract interface for a terminal rendering and event backend (POSIX TTY, Linux Glibc, Windows ConPTY/WinSDK, Headless Test).
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
    /// Wakes a blocked `pollEvents(timeoutMs:)` call immediately (e.g. when async state changes).
    func wakeUp()
}

extension TerminalBackend {
    public func wakeUp() {}
}

/// Platform-native terminal backend alias (`POSIXTerminalBackend` on macOS/Linux, Win32 Virtual Terminal on Windows).
public typealias SystemTerminalBackend = POSIXTerminalBackend

#if canImport(WinSDK)

// MARK: - Windows Console Virtual Terminal Backend (Windows 10/11, Windows Terminal, PowerShell, ConPTY)

nonisolated(unsafe) private var savedWinInputMode: DWORD = 0
nonisolated(unsafe) private var savedWinOutputMode: DWORD = 0
nonisolated(unsafe) private var savedWinOutputCP: UINT = 0
nonisolated(unsafe) private var savedWinInputCP: UINT = 0
nonisolated(unsafe) private var winTerminalIsActive: Bool = false

private func emergencyRestoreWindowsConsole() {
    guard winTerminalIsActive else { return }
    let hIn = GetStdHandle(STD_INPUT_HANDLE)
    let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
    let resetSeq = "\u{1B}[0m\u{1B}[?2004l\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?25h\u{1B}[?1049l"
    let utf8 = Array(resetSeq.utf8)
    var written: DWORD = 0
    utf8.withUnsafeBufferPointer { ptr in
        if let base = ptr.baseAddress {
            _ = WriteFile(hOut, base, DWORD(utf8.count), &written, nil)
        }
    }
    if savedWinInputMode != 0 { _ = SetConsoleMode(hIn, savedWinInputMode) }
    if savedWinOutputMode != 0 { _ = SetConsoleMode(hOut, savedWinOutputMode) }
    if savedWinOutputCP != 0 { _ = SetConsoleOutputCP(savedWinOutputCP) }
    if savedWinInputCP != 0 { _ = SetConsoleCP(savedWinInputCP) }
    winTerminalIsActive = false
}

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
        let hIn = GetStdHandle(STD_INPUT_HANDLE)
        let hOut = GetStdHandle(STD_OUTPUT_HANDLE)

        savedWinOutputCP = GetConsoleOutputCP()
        savedWinInputCP = GetConsoleCP()
        _ = SetConsoleOutputCP(UINT(CP_UTF8))
        _ = SetConsoleCP(UINT(CP_UTF8))

        var inMode: DWORD = 0
        if GetConsoleMode(hIn, &inMode) {
            savedWinInputMode = inMode
            // Enable VT input, window resize events, and disable line/echo/QuickEdit (0x0040) so mouse clicks pass through
            let rawInMode: DWORD = DWORD(ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS)
            _ = SetConsoleMode(hIn, rawInMode)
        }

        var outMode: DWORD = 0
        if GetConsoleMode(hOut, &outMode) {
            savedWinOutputMode = outMode
            let rawOutMode: DWORD = outMode | DWORD(ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN)
            _ = SetConsoleMode(hOut, rawOutMode)
        }

        winTerminalIsActive = true
        atexit(emergencyRestoreWindowsConsole)

        var initSeq = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1004h\u{1B}[2J\u{1B}[H"
        if enableMouse {
            initSeq += "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
        }
        writeRaw(initSeq)
        lastKnownSize = size()
    }

    public func teardown() {
        emergencyRestoreWindowsConsole()
        previousBuffer = nil
    }

    public func size() -> Size {
        let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
        var csbi = CONSOLE_SCREEN_BUFFER_INFO()
        if GetConsoleScreenBufferInfo(hOut, &csbi) {
            let cols = Int(csbi.srWindow.Right - csbi.srWindow.Left + 1)
            let rows = Int(csbi.srWindow.Bottom - csbi.srWindow.Top + 1)
            if cols > 0 && rows > 0 {
                return Size(width: cols, height: rows)
            }
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
        let currentSz = size()
        if currentSz != lastKnownSize {
            lastKnownSize = currentSz
            previousBuffer = nil
            events.append(.resize(width: currentSz.width, height: currentSz.height))
        }

        let hIn = GetStdHandle(STD_INPUT_HANDLE)
        let waitRes = WaitForSingleObject(hIn, DWORD(max(0, timeoutMs)))
        if waitRes == WAIT_OBJECT_0 {
            var numEvents: DWORD = 0
            if GetNumberOfConsoleInputEvents(hIn, &numEvents), numEvents > 0 {
                var readBuf = [UInt8](repeating: 0, count: 4096)
                var bytesRead: DWORD = 0
                if ReadFile(hIn, &readBuf, DWORD(readBuf.count), &bytesRead, nil), bytesRead > 0 {
                    let slice = Array(readBuf[0..<Int(bytesRead)])
                    events.append(contentsOf: inputParser.parse(slice))
                }
            }
        }
        return events
    }

    private func writeRaw(_ string: String) {
        let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
        let utf8 = Array(string.utf8)
        var totalWritten = 0
        while totalWritten < utf8.count {
            var written: DWORD = 0
            let ok = utf8.withUnsafeBufferPointer { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                return WriteFile(hOut, base.advanced(by: totalWritten), DWORD(utf8.count - totalWritten), &written, nil)
            }
            if !ok || written == 0 { break }
            totalWritten += Int(written)
        }
    }
}

#else

// MARK: - POSIX Terminal Backend (macOS Darwin & Linux Glibc)

nonisolated(unsafe) private var globalSigwinchFlag: sig_atomic_t = 0
nonisolated(unsafe) private var globalTerminateSignal: sig_atomic_t = 0
nonisolated(unsafe) private var globalSuspendFlag: sig_atomic_t = 0
nonisolated(unsafe) private var globalResumeFlag: sig_atomic_t = 0
nonisolated(unsafe) private var savedOriginalTermios: termios? = nil
nonisolated(unsafe) private var savedRawTermios: termios? = nil
nonisolated(unsafe) private var terminalIsInRawMode: Bool = false

private func handleSigwinch(_ sig: Int32) {
    globalSigwinchFlag = 1
}

private func handleTerminateSignal(_ sig: Int32) {
    globalTerminateSignal = sig
    emergencyRestoreTerminal()
    signal(sig, SIG_DFL)
    raise(sig)
}

private func handleSuspendSignal(_ sig: Int32) {
    globalSuspendFlag = 1
    emergencyRestoreTerminal()
    signal(SIGTSTP, SIG_DFL)
    raise(SIGTSTP)
}

private func handleContinueSignal(_ sig: Int32) {
    globalResumeFlag = 1
    signal(SIGTSTP, handleSuspendSignal)
}

private func emergencyRestoreTerminal() {
    guard terminalIsInRawMode else { return }
    let resetSeq = "\u{1B}[<u\u{1B}[0m\u{1B}[?2004l\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?25h\u{1B}[?1049l"
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
    private let diffRenderer: DiffRenderer
    private let inputParser = ANSIInputParser()
    private var lastKnownSize: Size = Size(width: 80, height: 24)
    private let enableMouse: Bool
    public let viewportMode: ViewportMode
    public let enableKittyKeyboard: Bool
    public let capabilities: TerminalCapabilities
    private var wakeupReadFD: Int32 = -1
    private var wakeupWriteFD: Int32 = -1

    public init(
        enableMouse: Bool = true,
        viewportMode: ViewportMode = .alternateScreen,
        enableKittyKeyboard: Bool = false,
        capabilities: TerminalCapabilities = .detect()
    ) {
        self.enableMouse = enableMouse
        self.viewportMode = viewportMode
        self.enableKittyKeyboard = enableKittyKeyboard
        self.capabilities = capabilities
        self.diffRenderer = DiffRenderer(
            useSynchronizedOutput: capabilities.supportsSynchronizedOutput,
            colorCapability: capabilities.colorCapability
        )
    }

    deinit {
        closeWakeupPipe()
    }

    private func setupWakeupPipe() {
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 {
            wakeupReadFD = fds[0]
            wakeupWriteFD = fds[1]
            _ = fcntl(wakeupReadFD, F_SETFL, O_NONBLOCK)
            _ = fcntl(wakeupWriteFD, F_SETFL, O_NONBLOCK)
        }
    }

    private func closeWakeupPipe() {
        if wakeupReadFD >= 0 { close(wakeupReadFD); wakeupReadFD = -1 }
        if wakeupWriteFD >= 0 { close(wakeupWriteFD); wakeupWriteFD = -1 }
    }

    public func wakeUp() {
        guard wakeupWriteFD >= 0 else { return }
        var byte: UInt8 = 1
        _ = write(wakeupWriteFD, &byte, 1)
    }

    public func setup() throws {
        setupWakeupPipe()

        var orig = termios()
        if tcgetattr(STDIN_FILENO, &orig) == 0 {
            savedOriginalTermios = orig
            var raw = orig
            cfmakeraw(&raw)
            // Portable VMIN / VTIME indexing across Darwin (16/17) and Linux Glibc (6/5)
            withUnsafeMutableBytes(of: &raw.c_cc) { ccPtr in
                let vminIdx = Int(VMIN)
                let vtimeIdx = Int(VTIME)
                if vminIdx < ccPtr.count { ccPtr[vminIdx] = 0 }
                if vtimeIdx < ccPtr.count { ccPtr[vtimeIdx] = 0 }
            }
            savedRawTermios = raw
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
            terminalIsInRawMode = true
            atexit(emergencyRestoreTerminal)
        }

        signal(SIGWINCH, handleSigwinch)
        signal(SIGINT, handleTerminateSignal)
        signal(SIGTERM, handleTerminateSignal)
        signal(SIGHUP, handleTerminateSignal)
        signal(SIGTSTP, handleSuspendSignal)
        signal(SIGCONT, handleContinueSignal)

        writeInitSequences()
        lastKnownSize = size()
    }

    private func writeInitSequences() {
        var initSeq = ""
        switch viewportMode {
        case .alternateScreen:
            initSeq += "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1004h\u{1B}[2J\u{1B}[H"
        case .inline(let height):
            let reserved = max(1, height)
            // Reserve inline lines in normal scrollback buffer and move cursor back to top of inline region
            initSeq += String(repeating: "\n", count: reserved)
            initSeq += "\u{1B}[\(reserved)A\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1004h"
        }
        if enableMouse {
            initSeq += "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
        }
        if enableKittyKeyboard && capabilities.supportsKittyKeyboard {
            // Enable Kitty keyboard protocol (disambiguate escape codes + report event types)
            initSeq += "\u{1B}[>3u"
        }
        writeRaw(initSeq)
    }

    public func teardown() {
        closeWakeupPipe()
        if enableKittyKeyboard && capabilities.supportsKittyKeyboard {
            writeRaw("\u{1B}[<u")
        }
        if case .inline = viewportMode {
            // Restore cursor and disable modes without leaving alternate screen
            writeRaw("\u{1B}[0m\u{1B}[?2004l\u{1B}[?1004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?25h\n")
            if var orig = savedOriginalTermios {
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
            }
            terminalIsInRawMode = false
        } else {
            emergencyRestoreTerminal()
        }
        previousBuffer = nil
    }

    public func size() -> Size {
        let baseSize: Size
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            baseSize = Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        } else if ioctl(STDIN_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            baseSize = Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
        } else {
            let cols = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init) ?? 100
            let rows = ProcessInfo.processInfo.environment["LINES"].flatMap(Int.init) ?? 30
            baseSize = Size(width: cols, height: rows)
        }
        if case .inline(let h) = viewportMode {
            return Size(width: baseSize.width, height: max(1, min(baseSize.height, h)))
        }
        return baseSize
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

        if globalResumeFlag != 0 {
            globalResumeFlag = 0
            if var raw = savedRawTermios {
                tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
                terminalIsInRawMode = true
            }
            writeInitSequences()
            previousBuffer = nil
            let resumedSize = size()
            lastKnownSize = resumedSize
            events.append(.resize(width: resumedSize.width, height: resumedSize.height))
        }

        if globalSigwinchFlag != 0 {
            globalSigwinchFlag = 0
            let newSize = size()
            if newSize != lastKnownSize {
                lastKnownSize = newSize
                previousBuffer = nil
                events.append(.resize(width: newSize.width, height: newSize.height))
            }
        }

        var pfds: [pollfd] = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)]
        if wakeupReadFD >= 0 {
            pfds.append(pollfd(fd: wakeupReadFD, events: Int16(POLLIN), revents: 0))
        }

        let ready = poll(&pfds, nfds_t(pfds.count), Int32(max(0, timeoutMs)))
        if ready > 0 {
            // Drain self-pipe wakeup bytes if triggered
            if pfds.count > 1 && (pfds[1].revents & Int16(POLLIN)) != 0 {
                var drainBuf = [UInt8](repeating: 0, count: 64)
                while read(wakeupReadFD, &drainBuf, drainBuf.count) > 0 {}
            }
            if (pfds[0].revents & Int16(POLLIN)) != 0 {
                var readBuf = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(STDIN_FILENO, &readBuf, readBuf.count)
                if bytesRead > 0 {
                    let slice = Array(readBuf[0..<bytesRead])
                    events.append(contentsOf: inputParser.parse(slice))
                }
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
            if written < 0 {
                let err = errno
                if err == EINTR || err == EAGAIN {
                    continue
                }
                break
            }
            if written == 0 {
                break
            }
            totalWritten += written
        }
    }
}

#endif

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
