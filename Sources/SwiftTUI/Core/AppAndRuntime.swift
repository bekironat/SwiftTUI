import Foundation

// MARK: - Scene & WindowGroup

@MainActor
public protocol Scene {
    associatedtype Content: View
    var title: String? { get }
    var contentView: Content { get }
}

extension Scene {
    public var title: String? { nil }
}

@MainActor
public struct WindowGroup<Content: View>: Scene {
    public let title: String?
    public let contentView: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.contentView = content()
    }
}

// MARK: - App Protocol

@MainActor
public protocol App {
    associatedtype Body: Scene
    init()
    @MainActor var body: Self.Body { get }
}

extension App {
    @MainActor
    public static func main() throws {
        let appInstance = Self()
        let scene = appInstance.body
        let backend = POSIXTerminalBackend(enableMouse: true)
        let runtime = TerminalApplication(rootView: scene.contentView, backend: backend, windowTitle: scene.title)
        try runtime.run()
    }
}

// MARK: - TerminalApplication Runtime

/// Drives the render loop, state reconciliation, and event routing for a `SwiftTUI` view hierarchy.
@MainActor
public final class TerminalApplication<Root: View> {
    public let rootView: Root
    public let backend: TerminalBackend
    public let store: StateStore
    public private(set) var lastInteractions = InteractionRegistry()
    public private(set) var lastBuffer: Buffer = Buffer(width: 80, height: 24)
    public private(set) var isRunning: Bool = false

    /// Whether pressing `Ctrl+C` or `Ctrl+Q` automatically stops the run loop.
    public var quitOnCtrlC: Bool = true
    /// Optional terminal window/tab title emitted via OSC 2.
    public var windowTitle: String?
    /// Optional terminal taskbar/tab progress indicator emitted via OSC 9;4.
    public var terminalProgress: TerminalProgressState?

    public init(
        rootView: Root,
        backend: TerminalBackend = POSIXTerminalBackend(),
        store: StateStore? = nil,
        windowTitle: String? = nil
    ) {
        self.rootView = rootView
        self.backend = backend
        self.store = store ?? StateStore()
        self.windowTitle = windowTitle
        let capturedBackend = backend
        self.store.onDirty = {
            capturedBackend.wakeUp()
        }
    }

    public func stop() {
        isRunning = false
    }

    /// Performs a single layout + render + overlay pass and flushes the resulting `Buffer` to `backend`.
    @discardableResult
    public func renderFrame() -> Buffer {
        let termSize = backend.size()
        let rootRect = Rect(origin: .zero, size: termSize)
        var buffer = Buffer(size: termSize)
        let interactions = InteractionRegistry()
        // Preserve active mouse drag handler (e.g. HSplitView/VSplitView divider dragging) across frames
        interactions.activeDragHandler = lastInteractions.activeDragHandler

        store.beginFrameFocusPass()

        var env = EnvironmentValues()
        env.terminalSize = termSize
        env.dismiss = DismissAction { [weak self] in
            Task { @MainActor in
                self?.stop()
            }
        }

        let context = BuildContext(store: store, path: "root", environment: env)
        let nodes = resolveView(rootView, context: context)

        if nodes.count == 1 {
            nodes[0].render(in: rootRect, buffer: &buffer, interactions: interactions)
        } else if nodes.count > 1 {
            // Multiple root nodes behave as an implicit VStack
            let implicitStack = VStackLayoutEngine.makeNode(
                id: "root.implicitVStack",
                alignment: .center,
                spacing: 0,
                children: nodes
            )
            implicitStack.render(in: rootRect, buffer: &buffer, interactions: interactions)
        }

        // Execute deferred top-level overlays (AutocompletePopup, Picker dropdowns, Sheets, Alerts)
        buffer.flushOverlays()

        if buffer.windowTitle == nil, let windowTitle {
            buffer.windowTitle = windowTitle
        }
        if buffer.terminalProgress == nil, let terminalProgress {
            buffer.terminalProgress = terminalProgress
        }

        interactions.finalizeFrame()
        store.endFrameLifecyclePass()
        store.clearDirty()
        lastInteractions = interactions
        lastBuffer = buffer
        backend.flush(buffer)
        return buffer
    }

    /// Processes a single `TerminalEvent` and optionally re-renders if state became dirty.
    @discardableResult
    public func handleEvent(_ event: TerminalEvent, renderIfDirty: Bool = true) -> Bool {
        var handled = false
        switch event {
        case .resize:
            store.markDirty()
            handled = true

        case .key(let keyEvent):
            if quitOnCtrlC && keyEvent.modifiers.contains(.control) &&
                (keyEvent.key == .char("c") || keyEvent.key == .char("q")) {
                stop()
                return true
            }
            handled = lastInteractions.handleKeyEvent(keyEvent, store: store)

        case .mouse(let mouseEvent):
            handled = lastInteractions.handleMouseEvent(mouseEvent, store: store)

        case .paste(let pastedText):
            for ch in pastedText {
                if ch == "\n" || ch == "\r" {
                    _ = lastInteractions.handleKeyEvent(KeyEvent(.enter), store: store)
                } else {
                    _ = lastInteractions.handleKeyEvent(KeyEvent(.char(ch)), store: store)
                }
            }
            handled = true

        case .focusGained, .focusLost:
            store.markDirty()
            handled = true

        case .tick:
            break
        }

        if renderIfDirty && store.isDirty {
            renderFrame()
        }
        return handled
    }

    /// Runs the interactive terminal event loop until `stop()` is called or `Ctrl+C`/`Ctrl+Q` is pressed.
    public func run() throws {
        try backend.setup()
        defer {
            backend.teardown()
        }

        isRunning = true
        renderFrame()

        while isRunning {
            // Drain pending main runloop / Swift concurrency continuations
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))

            // Step active animations forward in time
            AnimationDriver.shared.tick(now: Date().timeIntervalSinceReferenceDate, store: store)

            if store.isDirty && isRunning {
                renderFrame()
            }

            // Sleep efficiently when idle (woken immediately by self-pipe on store.markDirty())
            let pollTimeout = AnimationDriver.shared.hasActiveAnimations ? 16 : 250
            let events = backend.pollEvents(timeoutMs: pollTimeout)
            for ev in events {
                if !isRunning { break }
                handleEvent(ev, renderIfDirty: false)
            }

            if store.isDirty && isRunning {
                renderFrame()
            }
        }
    }
}
