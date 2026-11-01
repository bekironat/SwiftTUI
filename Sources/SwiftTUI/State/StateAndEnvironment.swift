import Foundation
import Observation

// MARK: - Internal Protocols for Mirror-Based Property Wrapper Binding

internal protocol _StateProperty {
    func _bindState(store: StateStore, key: String)
}

internal protocol _EnvironmentProperty {
    func _bindEnvironment(_ values: EnvironmentValues)
}

internal protocol _FocusStateProperty {
    func _bindFocusState(store: StateStore, key: String)
}

// MARK: - StateStore (Retained State Across Frames)

/// Central retained store for `@State`, `@FocusState`, and internal widget state (scroll offsets, cursors, split ratios) keyed by structural view path.
@MainActor
public final class StateStore {
    private var values: [String: Any] = [:]
    private var focusValues: [String: AnyHashable] = [:]
    public private(set) var isDirty: Bool = true
    public var onDirty: (() -> Void)?

    /// Ordered list of focusable IDs registered during the most recent render pass.
    public private(set) var focusRing: [AnyHashable] = []
    /// Currently active global focus ID.
    public var activeFocusID: AnyHashable? {
        didSet {
            if oldValue != activeFocusID {
                syncFocusBindings()
                markDirty()
            }
        }
    }

    private var focusBindingCallbacks: [String: (AnyHashable?) -> Void] = [:]

    public init() {}

    public func markDirty() {
        isDirty = true
        onDirty?()
    }

    public func clearDirty() {
        isDirty = false
    }

    public func value<T>(forKey key: String, default defaultValue: @autoclosure () -> T) -> T {
        if let existing = values[key] as? T {
            return existing
        }
        let initial = defaultValue()
        values[key] = initial
        return initial
    }

    public func setValue<T>(_ newValue: T, forKey key: String) {
        values[key] = newValue
        markDirty()
    }

    /// Reads or initializes internal widget state without triggering a dirty mark on initial creation.
    public func widgetState<T>(forPath path: String, default defaultValue: @autoclosure () -> T) -> T {
        let key = "__widget.\(path)"
        if let existing = values[key] as? T {
            return existing
        }
        let initial = defaultValue()
        values[key] = initial
        return initial
    }

    public func setWidgetState<T>(_ newValue: T, forPath path: String, markDirty shouldMarkDirty: Bool = true) {
        let key = "__widget.\(path)"
        values[key] = newValue
        if shouldMarkDirty {
            markDirty()
        }
    }

    // MARK: - Focus Ring Management

    public func beginFrameFocusPass() {
        focusRing.removeAll(keepingCapacity: true)
    }

    public func registerFocusable(_ id: AnyHashable) {
        if !focusRing.contains(id) {
            focusRing.append(id)
        }
        if activeFocusID == nil {
            activeFocusID = id
        }
    }

    public func moveFocusNext() {
        guard !focusRing.isEmpty else { return }
        if let current = activeFocusID, let idx = focusRing.firstIndex(of: current) {
            activeFocusID = focusRing[(idx + 1) % focusRing.count]
        } else {
            activeFocusID = focusRing.first
        }
    }

    public func moveFocusPrevious() {
        guard !focusRing.isEmpty else { return }
        if let current = activeFocusID, let idx = focusRing.firstIndex(of: current) {
            activeFocusID = focusRing[(idx - 1 + focusRing.count) % focusRing.count]
        } else {
            activeFocusID = focusRing.last
        }
    }

    internal func registerFocusBinding(key: String, callback: @escaping (AnyHashable?) -> Void) {
        focusBindingCallbacks[key] = callback
    }

    private func syncFocusBindings() {
        for (_, cb) in focusBindingCallbacks {
            cb(activeFocusID)
        }
    }
}

// MARK: - @Binding

/// A two-way reference to a value owned by a source of truth (`@State`, `@Observable`, or parent view).
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value>: @unchecked Sendable {
    private let getter: () -> Value
    private let setter: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getter = get
        self.setter = set
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var copy = self.wrappedValue
                copy[keyPath: keyPath] = newValue
                self.wrappedValue = copy
            }
        )
    }
}

// MARK: - @State

/// A persistent state property wrapper managed by `SwiftTUI`'s view reconciler.
@MainActor
@propertyWrapper
public struct State<Value>: @preconcurrency _StateProperty {
    internal final class Box {
        var initialValue: Value
        var fallbackValue: Value
        weak var store: StateStore?
        var key: String?

        init(_ initialValue: Value) {
            self.initialValue = initialValue
            self.fallbackValue = initialValue
        }

        @MainActor
        func get() -> Value {
            guard let store, let key else {
                return fallbackValue
            }
            return store.value(forKey: key, default: initialValue)
        }

        @MainActor
        func set(_ newValue: Value) {
            fallbackValue = newValue
            guard let store, let key else { return }
            store.setValue(newValue, forKey: key)
        }
    }

    private let box: Box

    public init(wrappedValue value: Value) {
        self.box = Box(value)
    }

    public init(initialValue value: Value) {
        self.box = Box(value)
    }

    public var wrappedValue: Value {
        get { box.get() }
        nonmutating set { box.set(newValue) }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { box.get() },
            set: { box.set($0) }
        )
    }

    internal func _bindState(store: StateStore, key: String) {
        box.store = store
        box.key = key
        _ = store.value(forKey: key, default: box.initialValue)
    }
}

// MARK: - @FocusState

/// Property wrapper that reads and writes the active focus target within a view hierarchy.
@MainActor
@propertyWrapper
public struct FocusState<Value: Hashable>: @preconcurrency _FocusStateProperty {
    internal final class Box {
        weak var store: StateStore?
        var key: String?
        let isBoolean: Bool
        var defaultValue: Value

        init(defaultValue: Value, isBoolean: Bool) {
            self.defaultValue = defaultValue
            self.isBoolean = isBoolean
        }
    }

    private let box: Box

    public init() where Value == Bool {
        self.box = Box(defaultValue: false, isBoolean: true)
    }

    public init<T: Hashable>() where Value == T? {
        self.box = Box(defaultValue: nil, isBoolean: false)
    }

    public var wrappedValue: Value {
        get {
            guard let store = box.store else { return box.defaultValue }
            if box.isBoolean {
                let isFocused = (store.activeFocusID == AnyHashable(box.key ?? ""))
                return (isFocused as? Value) ?? box.defaultValue
            } else {
                if let active = store.activeFocusID, let typed = active.base as? Value {
                    return typed
                }
                return box.defaultValue
            }
        }
        nonmutating set {
            guard let store = box.store else { return }
            if box.isBoolean {
                if let b = newValue as? Bool {
                    if b {
                        store.activeFocusID = AnyHashable(box.key ?? "")
                    } else if store.activeFocusID == AnyHashable(box.key ?? "") {
                        store.activeFocusID = nil
                    }
                }
            } else {
                let mirror = Mirror(reflecting: newValue)
                if mirror.displayStyle == .optional && mirror.children.isEmpty {
                    store.activeFocusID = nil
                } else {
                    store.activeFocusID = AnyHashable(newValue)
                }
            }
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }

    internal func _bindFocusState(store: StateStore, key: String) {
        box.store = store
        box.key = key
    }
}

// MARK: - Environment & @Environment

/// Protocol for keys stored in `EnvironmentValues`.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

/// Collection of environment values propagated down the view hierarchy.
public struct EnvironmentValues {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            if let val = storage[ObjectIdentifier(key)] as? K.Value {
                return val
            }
            return K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }
}

// Built-in Environment Keys

public enum ColorScheme: Equatable, Hashable, Sendable {
    case dark
    case light
}

private struct ColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

private struct IsEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct ForegroundColorKey: EnvironmentKey {
    static let defaultValue: Color = .default
}

private struct BackgroundColorKey: EnvironmentKey {
    static let defaultValue: Color = .default
}

private struct CellModifiersKey: EnvironmentKey {
    static let defaultValue: CellModifiers = []
}

private struct TerminalSizeKey: EnvironmentKey {
    static let defaultValue: Size = Size(width: 80, height: 24)
}

public struct DismissAction: Sendable {
    private let handler: @Sendable () -> Void

    public init(_ handler: @escaping @Sendable () -> Void = {}) {
        self.handler = handler
    }

    public func callAsFunction() {
        handler()
    }
}

private struct DismissKey: EnvironmentKey {
    static let defaultValue = DismissAction()
}

extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }

    public var foregroundColor: Color {
        get { self[ForegroundColorKey.self] }
        set { self[ForegroundColorKey.self] = newValue }
    }

    public var backgroundColor: Color {
        get { self[BackgroundColorKey.self] }
        set { self[BackgroundColorKey.self] = newValue }
    }

    public var cellModifiers: CellModifiers {
        get { self[CellModifiersKey.self] }
        set { self[CellModifiersKey.self] = newValue }
    }

    public var terminalSize: Size {
        get { self[TerminalSizeKey.self] }
        set { self[TerminalSizeKey.self] = newValue }
    }

    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }

    public var effectiveCellStyle: CellStyle {
        CellStyle(
            fg: foregroundColor,
            bg: backgroundColor,
            modifiers: cellModifiers
        )
    }
}

/// Property wrapper that reads a value from `EnvironmentValues`.
@propertyWrapper
public struct Environment<Value>: _EnvironmentProperty {
    internal final class Box {
        let keyPath: KeyPath<EnvironmentValues, Value>
        var values: EnvironmentValues = EnvironmentValues()

        init(keyPath: KeyPath<EnvironmentValues, Value>) {
            self.keyPath = keyPath
        }
    }

    private let box: Box

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.box = Box(keyPath: keyPath)
    }

    public var wrappedValue: Value {
        box.values[keyPath: box.keyPath]
    }

    internal func _bindEnvironment(_ values: EnvironmentValues) {
        box.values = values
    }
}

// MARK: - Reflection Binder

@MainActor
internal func bindViewProperties<V>(_ view: V, store: StateStore, path: String, environment: EnvironmentValues) {
    let mirror = Mirror(reflecting: view)
    for (index, child) in mirror.children.enumerated() {
        let label = child.label ?? "prop_\(index)"
        let key = "\(path).\(label)"
        if let stateProp = child.value as? _StateProperty {
            stateProp._bindState(store: store, key: key)
        }
        if let envProp = child.value as? _EnvironmentProperty {
            envProp._bindEnvironment(environment)
        }
        if let focusProp = child.value as? _FocusStateProperty {
            focusProp._bindFocusState(store: store, key: key)
        }
    }
}
