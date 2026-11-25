import Foundation

// MARK: - 1. SecureField (Password / Masked Echo Input)

/// Echo display mode for `SecureField`.
public enum SecureEchoMode: Equatable, Hashable, Sendable {
    /// Masks every character with `maskCharacter` (defaults to `•`).
    case masked(Character = "•")
    /// Hides input length completely (renders nothing while typing, like `sudo`).
    case hidden
}

internal struct SecureFieldWidgetState {
    var cursorIndex: Int = 0
    var scrollOffset: Int = 0
}

/// A single-line secure password/secret text input field supporting masked or hidden echo modes,
/// cursor navigation, keyboard editing, mouse focus, and submit handling. Matches SwiftUI's `SecureField`.
public struct SecureField: View, _PrimitiveView {
    public typealias Body = Never
    public let placeholder: String
    public let text: Binding<String>
    public let echoMode: SecureEchoMode
    public let focusID: AnyHashable?
    public var onSubmit: (@MainActor () -> Void)?

    public init(
        _ placeholder: String = "Password",
        text: Binding<String>,
        echoMode: SecureEchoMode = .masked("•"),
        id: AnyHashable? = nil,
        onSubmit: (@MainActor () -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self.text = text
        self.echoMode = echoMode
        self.focusID = id
        self.onSubmit = onSubmit
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let fieldPath = context.appending("SecureField").path
        let targetFocusID = focusID ?? AnyHashable(fieldPath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let binding = text
        let prompt = placeholder
        let mode = echoMode
        let submitHandler = onSubmit
        let theme = context.environment.theme

        return [
            RenderNode(
                id: fieldPath,
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? max(16, prompt.displayWidth + 4), height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    store.registerFocusableRect(rect, for: targetFocusID)
                    let isFocused = (store.activeFocusID == targetFocusID)
                    let chars = Array(binding.wrappedValue)

                    var state = store.widgetState(forPath: fieldPath, default: SecureFieldWidgetState(cursorIndex: chars.count))
                    state.cursorIndex = max(0, min(chars.count, state.cursorIndex))

                    let visibleW = max(1, rect.width)
                    if state.cursorIndex < state.scrollOffset {
                        state.scrollOffset = state.cursorIndex
                    } else if state.cursorIndex >= state.scrollOffset + visibleW {
                        state.scrollOffset = max(0, state.cursorIndex - visibleW + 1)
                    }
                    store.setWidgetState(state, forPath: fieldPath, markDirty: false)

                    let bg: Color = isFocused ? theme.surface : context.environment.backgroundColor
                    buffer.fill(rect, symbol: " ", style: CellStyle(fg: theme.primary, bg: bg))

                    if chars.isEmpty && !isFocused {
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            prompt,
                            style: CellStyle(fg: theme.muted, bg: bg, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                    } else {
                        switch mode {
                        case .masked(let maskChar):
                            let maskedCount = min(visibleW, max(0, chars.count - state.scrollOffset))
                            let display = String(repeating: maskChar, count: maskedCount)
                            buffer.writeString(
                                x: rect.minX,
                                y: rect.minY,
                                display,
                                style: CellStyle(fg: isFocused ? theme.primary : theme.secondary, bg: bg),
                                maxWidth: rect.width
                            )
                        case .hidden:
                            break
                        }
                    }

                    if isFocused {
                        let cursorOffset = (mode == .hidden) ? 0 : max(0, state.cursorIndex - state.scrollOffset)
                        let screenCursorX = min(rect.maxX - 1, rect.minX + cursorOffset)
                        buffer.cursorPosition = Point(x: screenCursorX, y: rect.minY)
                        buffer.cursorShape = .steadyBar
                        let cellSym: String
                        if case .masked(let maskChar) = mode, state.cursorIndex < chars.count {
                            cellSym = String(maskChar)
                        } else {
                            cellSym = " "
                        }
                        buffer.setCell(
                            x: screenCursorX,
                            y: rect.minY,
                            symbol: cellSym,
                            style: CellStyle(fg: .black, bg: theme.accent, modifiers: [.bold])
                        )
                    }

                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        var mutable = Array(binding.wrappedValue)
                        let idx = max(0, min(mutable.count, state.cursorIndex))

                        switch key.key {
                        case .enter:
                            submitHandler?()
                            store.markDirty()
                            return true
                        case .left:
                            if idx > 0 {
                                state.cursorIndex = idx - 1
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .right:
                            if idx < mutable.count {
                                state.cursorIndex = idx + 1
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .home:
                            state.cursorIndex = 0
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .end:
                            state.cursorIndex = mutable.count
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .backspace:
                            if idx > 0 {
                                mutable.remove(at: idx - 1)
                                binding.wrappedValue = String(mutable)
                                state.cursorIndex = idx - 1
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .delete:
                            if idx < mutable.count {
                                mutable.remove(at: idx)
                                binding.wrappedValue = String(mutable)
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .space where key.modifiers.isEmpty:
                            mutable.insert(" ", at: idx)
                            binding.wrappedValue = String(mutable)
                            state.cursorIndex = idx + 1
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .char(let ch) where key.modifiers.isEmpty || key.modifiers == [.shift]:
                            mutable.insert(ch, at: idx)
                            binding.wrappedValue = String(mutable)
                            state.cursorIndex = idx + 1
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .char("u") where key.modifiers == [.control]:
                            binding.wrappedValue = ""
                            state.cursorIndex = 0
                            state.scrollOffset = 0
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        default:
                            return false
                        }
                    }

                    interactions.registerMouseTarget(rect: rect, zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            store.activeFocusID = targetFocusID
                            if mode != .hidden {
                                let clicked = state.scrollOffset + (mouse.x - rect.minX)
                                state.cursorIndex = max(0, min(chars.count, clicked))
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            } else {
                                store.markDirty()
                            }
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - 2. SearchField & .searchable Modifier

/// A search input control featuring a leading search icon (`🔍`), live query editing, and a clear affordance (`×` / `Esc`).
public struct SearchField: View, _PrimitiveView {
    public typealias Body = Never
    public let prompt: String
    public let text: Binding<String>
    public let focusID: AnyHashable?
    public var onSubmit: (@MainActor () -> Void)?

    public init(
        _ prompt: String = "Search...",
        text: Binding<String>,
        id: AnyHashable? = nil,
        onSubmit: (@MainActor () -> Void)? = nil
    ) {
        self.prompt = prompt
        self.text = text
        self.focusID = id
        self.onSubmit = onSubmit
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let searchPath = context.appending("SearchField").path
        let targetFocusID = focusID ?? AnyHashable(searchPath)
        let store = context.store
        let binding = text
        let theme = context.environment.theme

        let innerField = TextField(prompt, text: binding, id: targetFocusID, onSubmit: onSubmit)
        let fieldNodes = resolveView(innerField, context: context.appending("Inner"))
        let fieldNode = fieldNodes[0]

        return [
            RenderNode(
                id: searchPath,
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? max(20, prompt.displayWidth + 6), height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == targetFocusID)
                    let bg: Color = isFocused ? theme.surface : context.environment.backgroundColor
                    buffer.fill(rect, symbol: " ", style: CellStyle(fg: theme.primary, bg: bg))

                    let prefix = "🔍 "
                    let prefixW = UnicodeWidth.width(of: prefix)
                    buffer.writeString(
                        x: rect.minX,
                        y: rect.minY,
                        prefix,
                        style: CellStyle(fg: isFocused ? theme.accent : theme.muted, bg: bg),
                        maxWidth: rect.width
                    )

                    let hasText = !binding.wrappedValue.isEmpty
                    let clearW = hasText ? 3 : 0
                    let fieldW = max(1, rect.width - prefixW - clearW)
                    let fieldRect = Rect(x: rect.minX + prefixW, y: rect.minY, width: fieldW, height: 1)
                    fieldNode.render(in: fieldRect, buffer: &buffer, interactions: interactions)

                    if hasText && rect.width >= prefixW + 4 {
                        let clearX = rect.maxX - 3
                        buffer.writeString(
                            x: clearX,
                            y: rect.minY,
                            " × ",
                            style: CellStyle(fg: theme.warning, bg: bg, modifiers: [.bold]),
                            maxWidth: 3
                        )
                        let clearRect = Rect(x: clearX, y: rect.minY, width: 3, height: 1)
                        interactions.registerMouseTarget(rect: clearRect, zIndex: 10) { mouse in
                            if case .down(.left) = mouse.kind {
                                binding.wrappedValue = ""
                                store.activeFocusID = targetFocusID
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }

                    if isFocused && hasText {
                        interactions.registerPriorityKeyInterceptor(zIndex: 40) { key in
                            if key.key == .escape {
                                binding.wrappedValue = ""
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }
                }
            )
        ]
    }
}

public struct _SearchableModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let text: Binding<String>
    public let prompt: String

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let searchBar = SearchField(prompt, text: text)
        let composed = VStack(alignment: .leading, spacing: 1) {
            searchBar
            content
        }
        return resolveView(composed, context: context.appending("Searchable"))
    }
}

extension View {
    /// Prepends a `SearchField` bound to `text` above this view. Matches SwiftUI's `.searchable(text:prompt:)`.
    public func searchable(text: Binding<String>, prompt: String = "Search...") -> some View {
        _SearchableModifier(content: self, text: text, prompt: prompt)
    }
}

// MARK: - 3. ProgressView (Determinate & Indeterminate)

/// A view that shows progress toward completion of a task, supporting both determinate bars
/// (`ProgressView("Syncing", value: 0.65)`) and indeterminate animated spinners (`ProgressView("Loading...")`).
/// Matches SwiftUI's `ProgressView`.
public struct ProgressView: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String?
    public let value: Double?
    public let total: Double
    public let color: Color?
    public let spinnerStyle: SpinnerStyle

    /// Creates a determinate progress bar (`value` out of `total`).
    public init(
        _ label: String? = nil,
        value: Double,
        total: Double = 1.0,
        color: Color? = nil
    ) {
        self.label = label
        self.value = value
        self.total = max(0.0001, total)
        self.color = color
        self.spinnerStyle = .dots
    }

    /// Creates an indeterminate progress spinner with an optional label.
    public init(
        _ label: String? = nil,
        spinnerStyle: SpinnerStyle = .dots,
        color: Color? = nil
    ) {
        self.label = label
        self.value = nil
        self.total = 1.0
        self.color = color
        self.spinnerStyle = spinnerStyle
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let theme = context.environment.theme
        let tint = color ?? theme.accent
        if let value {
            let ratio = max(0.0, min(1.0, value / total))
            let gauge = Gauge(label, value: ratio, color: tint)
            return resolveView(gauge, context: context.appending("ProgressBar"))
        } else {
            let spinner = Spinner(label, style: spinnerStyle, color: tint)
            return resolveView(spinner, context: context.appending("ProgressSpinner"))
        }
    }
}

// MARK: - 4. TabView (Tabbed Multi-Pane Container)

/// A single tab entry inside a `TabView`.
@MainActor
public struct TabItem<TabID: Hashable> {
    public let id: TabID
    public let title: String
    public let icon: String?
    public let badge: String?
    public let content: AnyView

    public init<Content: View>(
        id: TabID,
        title: String,
        icon: String? = nil,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.badge = badge
        self.content = AnyView(content())
    }
}

/// A SwiftUI-style container view that switches between multiple child views using a top `TabBar`
/// with keyboard (`←`/`→`) and mouse tab switching.
public struct TabView<SelectionValue: Hashable & Sendable>: View, _PrimitiveView {
    public typealias Body = Never
    public let selection: Binding<SelectionValue>
    public let tabs: [TabItem<SelectionValue>]
    public let focusID: AnyHashable?

    public init(
        selection: Binding<SelectionValue>,
        id: AnyHashable? = nil,
        tabs: [TabItem<SelectionValue>]
    ) {
        self.selection = selection
        self.focusID = id
        self.tabs = tabs
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let targetFocusID = focusID ?? AnyHashable("\(path).TabView.bar")
        store.registerFocusable(targetFocusID)

        let tabItems = tabs.map { TabBar<SelectionValue>.Item(id: $0.id, title: $0.title, icon: $0.icon, badge: $0.badge) }
        let tabIDs = tabs.map(\.id)
        let binding = selection
        let activeTab = tabs.first(where: { $0.id == selection.wrappedValue }) ?? tabs.first

        let header = TabBar(items: tabItems, selection: selection)
        let headerNodes = resolveView(header, context: context.appending("TabBar"))
        let wrappedHeader = RenderNode(
            id: "\(path).TabBarFocusHost",
            flexibleAxes: [.horizontal],
            measure: { proposal in
                headerNodes.first?.sizeThatFits(proposal) ?? Size(width: proposal.width ?? 20, height: 1)
            },
            render: { rect, buffer, interactions in
                store.registerFocusableRect(rect, for: targetFocusID)
                headerNodes.first?.render(in: rect, buffer: &buffer, interactions: interactions)
                interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                    guard !tabIDs.isEmpty else { return false }
                    let currentIdx = tabIDs.firstIndex(of: binding.wrappedValue) ?? 0
                    switch key.key {
                    case .left:
                        let prev = (currentIdx - 1 + tabIDs.count) % tabIDs.count
                        binding.wrappedValue = tabIDs[prev]
                        store.markDirty()
                        return true
                    case .right:
                        let next = (currentIdx + 1) % tabIDs.count
                        binding.wrappedValue = tabIDs[next]
                        store.markDirty()
                        return true
                    default:
                        return false
                    }
                }
            }
        )

        let contentNodes: [RenderNode] = activeTab.map { tab in
            resolveView(tab.content, context: context.appending("Tab[\(tab.id)]"))
        } ?? []

        let allChildren = [wrappedHeader] + contentNodes
        return [
            VStackLayoutEngine.makeNode(
                id: "\(path).TabView",
                alignment: .leading,
                spacing: 1,
                children: allChildren
            )
        ]
    }
}
