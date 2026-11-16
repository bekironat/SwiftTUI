import Foundation

// MARK: - 7. View Lifecycle & Structured Concurrency Modifiers (.onAppear, .onDisappear, .onChange, .task)

public struct _OnAppearModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let action: @MainActor () -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        context.store.recordLifecyclePath("\(context.path).onAppear", onAppear: action)
        return resolveView(content, context: context)
    }
}

public struct _OnDisappearModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let action: @MainActor () -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        context.store.recordLifecyclePath("\(context.path).onDisappear", onDisappear: action)
        return resolveView(content, context: context)
    }
}

public struct _OnChangeModifier<Content: View, V: Equatable>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let initial: Bool
    public let action: @MainActor (V, V) -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let pathKey = "\(context.path).onChangeValue"
        let initializedKey = "\(context.path).onChangeInit"

        let wasInitialized: Bool = store.widgetState(forPath: initializedKey, default: false)
        if !wasInitialized {
            store.setWidgetState(true, forPath: initializedKey, markDirty: false)
            store.setWidgetState(value, forPath: pathKey, markDirty: false)
            if initial {
                action(value, value)
            }
        } else {
            let previous: V = store.widgetState(forPath: pathKey, default: value)
            if previous != value {
                store.setWidgetState(value, forPath: pathKey, markDirty: false)
                action(previous, value)
            }
        }

        return resolveView(content, context: context)
    }
}

public struct _TaskModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let taskID: AnyHashable
    public let priority: TaskPriority
    public let action: @MainActor @Sendable () async -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        context.store.registerTask(
            forPath: "\(context.path).task",
            id: taskID,
            priority: priority,
            action: action
        )
        return resolveView(content, context: context)
    }
}

// MARK: - View Extensions for Lifecycle & Async Tasks

extension View {
    /// Adds an action to perform before this view appears in the terminal hierarchy.
    public func onAppear(perform action: @escaping @MainActor () -> Void) -> some View {
        _OnAppearModifier(content: self, action: action)
    }

    /// Adds an action to perform after this view disappears from the terminal hierarchy.
    public func onDisappear(perform action: @escaping @MainActor () -> Void) -> some View {
        _OnDisappearModifier(content: self, action: action)
    }

    /// Adds an action to perform when the specified value changes between frames.
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping @MainActor (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        _OnChangeModifier(content: self, value: value, initial: initial, action: action)
    }

    /// Adds an action to perform when the specified value changes between frames (single-parameter overload).
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        perform action: @escaping @MainActor (_ newValue: V) -> Void
    ) -> some View {
        _OnChangeModifier(content: self, value: value, initial: initial) { _, newVal in
            action(newVal)
        }
    }

    /// Adds an asynchronous task to perform before this view appears, automatically cancelling the task when the view disappears.
    public func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        _TaskModifier(content: self, taskID: AnyHashable("defaultTask"), priority: priority, action: action)
    }

    /// Adds an asynchronous task that restarts whenever `id` changes and cancels when the view disappears.
    public func task<T: Equatable & Hashable>(
        id value: T,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        _TaskModifier(content: self, taskID: AnyHashable(value), priority: priority, action: action)
    }
}
