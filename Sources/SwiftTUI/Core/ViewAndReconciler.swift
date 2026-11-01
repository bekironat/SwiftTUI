import Foundation
import Observation

// MARK: - Core View Protocol

/// A piece of terminal user interface in `SwiftTUI`, following SwiftUI's declarative paradigm.
@MainActor
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Self.Body { get }
}

extension Never: View {
    public typealias Body = Never
}

extension View where Body == Never {
    @MainActor public var body: Never {
        fatalError("\(Self.self) is a primitive view and its body should never be called directly.")
    }
}

/// Internal protocol adopted by primitive views and layout containers that build `RenderNode`s directly.
@MainActor
internal protocol _PrimitiveView {
    func _buildNodes(context: BuildContext) -> [RenderNode]
}

// MARK: - BuildContext & InteractionRegistry

/// Context passed down the view tree when resolving views into layout `RenderNode`s.
@MainActor
public struct BuildContext {
    public let store: StateStore
    public var path: String
    public var environment: EnvironmentValues

    public init(store: StateStore, path: String = "root", environment: EnvironmentValues = EnvironmentValues()) {
        self.store = store
        self.path = path
        self.environment = environment
    }

    public func appending(_ segment: String) -> BuildContext {
        var copy = self
        copy.path = "\(path).\(segment)"
        return copy
    }

    public func withEnvironment(_ transform: (inout EnvironmentValues) -> Void) -> BuildContext {
        var copy = self
        transform(&copy.environment)
        return copy
    }
}

/// Collects keyboard, mouse, focus, shortcut, and lifecycle handlers during a frame's render pass.
@MainActor
public final class InteractionRegistry {
    public struct KeyInterceptor {
        public let zIndex: Int
        public let handler: @MainActor (KeyEvent) -> Bool

        public init(zIndex: Int, handler: @escaping @MainActor (KeyEvent) -> Bool) {
            self.zIndex = zIndex
            self.handler = handler
        }
    }

    public struct MouseTarget {
        public let rect: Rect
        public let zIndex: Int
        public let handler: @MainActor (MouseEvent) -> Bool

        public init(rect: Rect, zIndex: Int = 0, handler: @escaping @MainActor (MouseEvent) -> Bool) {
            self.rect = rect
            self.zIndex = zIndex
            self.handler = handler
        }
    }

    public struct ShortcutEntry {
        public let matches: @MainActor (KeyEvent) -> Bool
        public let action: @MainActor () -> Void
    }

    /// High-priority key interceptors (e.g. open AutocompletePopup, active Alert/Modal) sorted by descending zIndex.
    public private(set) var priorityKeyInterceptors: [KeyInterceptor] = []
    /// Focus-specific key handlers keyed by `focusID`.
    public private(set) var focusedKeyHandlers: [AnyHashable: @MainActor (KeyEvent) -> Bool] = [:]
    /// General key press handlers (from `.onKeyPress`) evaluated in reverse registration order (innermost to outermost).
    public private(set) var bubbleKeyHandlers: [@MainActor (KeyEvent) -> Bool] = []
    /// Global keyboard shortcuts (from `.keyboardShortcut`).
    public private(set) var shortcuts: [ShortcutEntry] = []
    /// Mouse hit targets evaluated by descending `zIndex` and reverse registration order (topmost first).
    public private(set) var mouseTargets: [MouseTarget] = []
    /// Active drag handler when a mouse drag is in progress (e.g. `HSplitView` / `VSplitView` divider).
    public var activeDragHandler: (@MainActor (MouseEvent) -> Bool)?

    public init() {}

    public func registerPriorityKeyInterceptor(zIndex: Int = 100, handler: @escaping @MainActor (KeyEvent) -> Bool) {
        priorityKeyInterceptors.append(KeyInterceptor(zIndex: zIndex, handler: handler))
    }

    public func registerFocusedKeyHandler(for id: AnyHashable, handler: @escaping @MainActor (KeyEvent) -> Bool) {
        focusedKeyHandlers[id] = handler
    }

    public func registerBubbleKeyHandler(_ handler: @escaping @MainActor (KeyEvent) -> Bool) {
        bubbleKeyHandlers.append(handler)
    }

    public func registerShortcut(matches: @escaping @MainActor (KeyEvent) -> Bool, action: @escaping @MainActor () -> Void) {
        shortcuts.append(ShortcutEntry(matches: matches, action: action))
    }

    public func registerMouseTarget(rect: Rect, zIndex: Int = 0, handler: @escaping @MainActor (MouseEvent) -> Bool) {
        guard !rect.isEmpty else { return }
        mouseTargets.append(MouseTarget(rect: rect, zIndex: zIndex, handler: handler))
    }

    // MARK: - Event Dispatch

    /// Routes a `KeyEvent` through priority interceptors -> focused control -> bubble handlers -> shortcuts -> focus ring Tab navigation.
    public func handleKeyEvent(_ event: KeyEvent, store: StateStore) -> Bool {
        // 1. High-priority overlays (AutocompletePopup, Alert, Sheet)
        let sortedPriority = priorityKeyInterceptors.sorted { $0.zIndex > $1.zIndex }
        for interceptor in sortedPriority {
            if interceptor.handler(event) {
                return true
            }
        }

        // 2. Global keyboard shortcuts (if modifier key or function key is used)
        let isShortcutCandidate = !event.modifiers.isEmpty || {
            if case .f = event.key { return true }
            return false
        }()
        if isShortcutCandidate {
            for sc in shortcuts.reversed() {
                if sc.matches(event) {
                    sc.action()
                    store.markDirty()
                    return true
                }
            }
        }

        // 3. Focused control handler
        if let activeFocus = store.activeFocusID, let handler = focusedKeyHandlers[activeFocus] {
            if handler(event) {
                return true
            }
        }

        // 4. Bubble key handlers (.onKeyPress)
        for handler in bubbleKeyHandlers.reversed() {
            if handler(event) {
                return true
            }
        }

        // 5. Any remaining unmatched shortcuts (e.g. single-key shortcuts when no text input consumed them)
        if !isShortcutCandidate {
            for sc in shortcuts.reversed() {
                if sc.matches(event) {
                    sc.action()
                    store.markDirty()
                    return true
                }
            }
        }

        // 6. Standard Tab / Shift+Tab focus ring navigation
        if event.key == .tab && event.modifiers.isEmpty {
            store.moveFocusNext()
            return true
        }
        if event.key == .backTab || (event.key == .tab && event.modifiers.contains(.shift)) {
            store.moveFocusPrevious()
            return true
        }

        return false
    }

    /// Routes a `MouseEvent` to active drag handlers or topmost hit-tested mouse target.
    public func handleMouseEvent(_ event: MouseEvent, store: StateStore) -> Bool {
        if let dragHandler = activeDragHandler {
            let handled = dragHandler(event)
            if case .up = event.kind {
                activeDragHandler = nil
            }
            return handled
        }

        let point = event.location
        let candidates = mouseTargets.enumerated().sorted { a, b in
            if a.element.zIndex != b.element.zIndex {
                return a.element.zIndex > b.element.zIndex
            }
            return a.offset > b.offset
        }

        for (_, target) in candidates {
            if target.rect.contains(point) {
                if target.handler(event) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - RenderNode (Resolved Layout & Drawing Unit)

/// A resolved layout and rendering node produced from a `View`.
@MainActor
public struct RenderNode {
    public var id: String
    public var layoutPriority: Double
    public var isSpacer: Bool
    public var minSpacerLength: Int
    public var flexibleAxes: Axis.Set
    public var measureClosure: @MainActor (ProposedViewSize) -> Size
    public var renderClosure: @MainActor (Rect, inout Buffer, InteractionRegistry) -> Void

    public init(
        id: String,
        layoutPriority: Double = 0,
        isSpacer: Bool = false,
        minSpacerLength: Int = 0,
        flexibleAxes: Axis.Set = [],
        measure: @escaping @MainActor (ProposedViewSize) -> Size,
        render: @escaping @MainActor (Rect, inout Buffer, InteractionRegistry) -> Void
    ) {
        self.id = id
        self.layoutPriority = layoutPriority
        self.isSpacer = isSpacer
        self.minSpacerLength = minSpacerLength
        self.flexibleAxes = flexibleAxes
        self.measureClosure = measure
        self.renderClosure = render
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> Size {
        measureClosure(proposal)
    }

    public func render(in rect: Rect, buffer: inout Buffer, interactions: InteractionRegistry) {
        renderClosure(rect, &buffer, interactions)
    }
}

// MARK: - View Tree Resolution with @Observable Tracking

@MainActor
public func resolveView<V: View>(_ view: V, context: BuildContext) -> [RenderNode] {
    if let primitive = view as? _PrimitiveView {
        return primitive._buildNodes(context: context)
    }

    bindViewProperties(view, store: context.store, path: context.path, environment: context.environment)

    let store = context.store
    let childBody: V.Body = withObservationTracking {
        view.body
    } onChange: {
        Task { @MainActor in
            store.markDirty()
        }
    }

    let typeName = String(describing: V.self)
    return resolveView(childBody, context: context.appending(typeName))
}

// MARK: - @ViewBuilder

@resultBuilder
@MainActor
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }

    public static func buildOptional<Content: View>(_ content: Content?) -> Content? {
        content
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(first: TrueContent) -> ConditionalContent<TrueContent, FalseContent> {
        ConditionalContent(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent: View, FalseContent: View>(second: FalseContent) -> ConditionalContent<TrueContent, FalseContent> {
        ConditionalContent(storage: .falseContent(second))
    }

    public static func buildArray<Content: View>(_ components: [Content]) -> _ArrayView<Content> {
        _ArrayView(elements: components)
    }

    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> Content {
        content
    }
}

// MARK: - Structural Views (EmptyView, TupleView, ConditionalContent, Optional, Group, ForEach, AnyView)

public struct EmptyView: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        []
    }
}

public struct TupleView<T>: View, _PrimitiveView {
    public typealias Body = Never
    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        var nodes: [RenderNode] = []
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .tuple {
            for (idx, child) in mirror.children.enumerated() {
                if let resolvable = child.value as? any View {
                    nodes.append(contentsOf: resolveExistentialView(resolvable, context: context.appending("t\(idx)")))
                }
            }
        } else if let single = value as? any View {
            nodes.append(contentsOf: resolveExistentialView(single, context: context.appending("t0")))
        }
        return nodes
    }
}

@MainActor
internal func resolveExistentialView<V: View>(_ view: V, context: BuildContext) -> [RenderNode] {
    resolveView(view, context: context)
}

public struct ConditionalContent<TrueContent: View, FalseContent: View>: View, _PrimitiveView {
    public typealias Body = Never

    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        switch storage {
        case .trueContent(let view):
            return resolveView(view, context: context.appending("ifTrue"))
        case .falseContent(let view):
            return resolveView(view, context: context.appending("ifFalse"))
        }
    }
}

extension Optional: View, _PrimitiveView where Wrapped: View {
    public typealias Body = Never

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        switch self {
        case .some(let view):
            return resolveView(view, context: context.appending("some"))
        case .none:
            return []
        }
    }
}

public struct _ArrayView<Element: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let elements: [Element]

    public init(elements: [Element]) {
        self.elements = elements
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        var result: [RenderNode] = []
        for (idx, el) in elements.enumerated() {
            result.append(contentsOf: resolveView(el, context: context.appending("arr_\(idx)")))
        }
        return result
    }
}

public struct Group<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        resolveView(content, context: context.appending("Group"))
    }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let data: Data
    public let idGenerator: (Data.Element) -> ID
    public let content: @MainActor (Data.Element) -> Content

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
    ) {
        self.data = data
        self.idGenerator = { $0[keyPath: id] }
        self.content = content
    }

    public init(
        _ data: Data,
        @ViewBuilder content: @escaping @MainActor (Data.Element) -> Content
    ) where Data.Element: Identifiable, Data.Element.ID == ID {
        self.data = data
        self.idGenerator = { $0.id }
        self.content = content
    }

    public init(
        _ data: Range<Int>,
        @ViewBuilder content: @escaping @MainActor (Int) -> Content
    ) where Data == Range<Int>, ID == Int {
        self.data = data
        self.idGenerator = { $0 }
        self.content = content
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        var result: [RenderNode] = []
        for item in data {
            let itemID = idGenerator(item)
            let itemContext = context.appending("item[\(itemID)]")
            let childView = content(item)
            result.append(contentsOf: resolveView(childView, context: itemContext))
        }
        return result
    }
}

/// Type-erased wrapper around any `View`.
public struct AnyView: View, _PrimitiveView {
    public typealias Body = Never
    private let builder: @MainActor (BuildContext) -> [RenderNode]

    public init<V: View>(_ view: V) {
        self.builder = { ctx in
            resolveView(view, context: ctx)
        }
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        builder(context)
    }
}
