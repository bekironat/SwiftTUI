import Foundation

// MARK: - Scene & WindowGroup

@MainActor
public protocol Scene {
    associatedtype Content: View
    var contentView: Content { get }
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
        let backend = POSIXTerminalBackend(enableMouse: true)
        let runtime = TerminalApplication(rootView: appInstance.body.contentView, backend: backend)
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

    public init(
        rootView: Root,
        backend: TerminalBackend = POSIXTerminalBackend(),
        store: StateStore? = nil
    ) {
        self.rootView = rootView
        self.backend = backend
        self.store = store ?? StateStore()
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

        store.clearDirty()
        lastInteractions = interactions
        lastBuffer = buffer
        backend.flush(buffer)
        return buffer
    }

    /// Processes a single `TerminalEvent` and re-renders if state became dirty.
    @discardableResult
    public func handleEvent(_ event: TerminalEvent) -> Bool {
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

        if store.isDirty {
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
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))

            // Step active animations forward in time
            AnimationDriver.shared.tick(now: Date().timeIntervalSinceReferenceDate, store: store)

            let pollTimeout = AnimationDriver.shared.hasActiveAnimations ? 16 : 50
            let events = backend.pollEvents(timeoutMs: pollTimeout)
            for ev in events {
                if !isRunning { break }
                handleEvent(ev)
            }

            if store.isDirty && isRunning {
                renderFrame()
            }
        }
    }
}
