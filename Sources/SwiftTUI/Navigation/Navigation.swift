import Foundation

// MARK: - Navigation Path & Entry

public struct NavigationEntry: @unchecked Sendable {
    public let id: UUID
    public let title: String
    public let view: AnyView

    public init(id: UUID = UUID(), title: String, view: AnyView) {
        self.id = id
        self.title = title
        self.view = view
    }
}

/// A type-erased navigation path matching SwiftUI's `NavigationPath`.
public struct NavigationPath: Equatable, Sendable {
    public private(set) var count: Int = 0

    public init() {}

    public var isEmpty: Bool {
        count == 0
    }

    public mutating func append<V: Hashable>(_ value: V) {
        count += 1
    }

    public mutating func removeLast(_ k: Int = 1) {
        count = max(0, count - k)
    }
}

// MARK: - Navigator Controller

@MainActor
public final class Navigator {
    public private(set) var stack: [NavigationEntry] = []
    public var rootTitle: String = "Home"
    private let onDirty: () -> Void

    public init(onDirty: @escaping () -> Void = {}) {
        self.onDirty = onDirty
    }

    public var depth: Int {
        stack.count
    }

    public var canPop: Bool {
        !stack.isEmpty
    }

    public func push(title: String = "", view: AnyView) {
        stack.append(NavigationEntry(title: title, view: view))
        onDirty()
    }

    public func pop() {
        guard !stack.isEmpty else { return }
        _ = stack.removeLast()
        onDirty()
    }

    public func popToRoot() {
        guard !stack.isEmpty else { return }
        stack.removeAll()
        onDirty()
    }

    public func updateTopTitle(_ title: String) {
        guard !stack.isEmpty else { return }
        let last = stack.removeLast()
        stack.append(NavigationEntry(id: last.id, title: title, view: last.view))
    }
}

// MARK: - Environment Keys for Navigation

private struct NavigatorKey: EnvironmentKey {
    static let defaultValue: Navigator? = nil
}

private struct NavigationTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    public var navigator: Navigator? {
        get { self[NavigatorKey.self] }
        set { self[NavigatorKey.self] = newValue }
    }

    public var navigationTitle: String? {
        get { self[NavigationTitleKey.self] }
        set { self[NavigationTitleKey.self] = newValue }
    }
}

// MARK: - NavigationStack

/// A view that displays a root view and enables pushing and popping destination views onto a hierarchical navigation stack.
/// Matches SwiftUI's `NavigationStack`.
public struct NavigationStack<Root: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let root: Root

    public init(@ViewBuilder root: () -> Root) {
        self.root = root()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let stackKey = "\(path).navStack"

        let navigator: Navigator = store.widgetState(forPath: stackKey, default: Navigator(onDirty: {
            store.markDirty()
        }))

        // Propagate navigator down the environment
        let navContext = context.withEnvironment { env in
            env.navigator = navigator
            let currentDepth = navigator.depth
            if currentDepth > 0 {
                env.dismiss = DismissAction {
                    Task { @MainActor in
                        navigator.pop()
                    }
                }
            }
        }

        let isAtRoot = navigator.stack.isEmpty
        let activeChildNode: RenderNode

        if isAtRoot {
            let rootNodes = resolveView(root, context: navContext.appending("Root"))
            activeChildNode = rootNodes.count == 1 ? rootNodes[0] : VStackLayoutEngine.makeNode(id: "\(path).rootStack", alignment: .leading, spacing: 0, children: rootNodes)
        } else {
            let topEntry = navigator.stack.last!
            let pushedNodes = resolveView(topEntry.view, context: navContext.appending("Pushed[\(topEntry.id)]"))
            activeChildNode = pushedNodes.count == 1 ? pushedNodes[0] : VStackLayoutEngine.makeNode(id: "\(path).pushedStack", alignment: .leading, spacing: 0, children: pushedNodes)
        }

        return [
            RenderNode(
                id: "\(path).NavigationStack",
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    let childSize = activeChildNode.sizeThatFits(proposal)
                    let w = proposal.width ?? childSize.width
                    let h = proposal.height ?? (childSize.height + 2)
                    return Size(width: w, height: h)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }

                    let rootTitle = navigator.rootTitle.isEmpty ? "Home" : navigator.rootTitle
                    let currentBreadcrumbs: [String] = [rootTitle] + navigator.stack.map { $0.title.isEmpty ? "Page" : $0.title }
                    let breadcrumbText = currentBreadcrumbs.joined(separator: " > ")

                    // Navigation Bar (Header)
                    let navBarHeight = 2
                    let navBarRect = Rect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)
                    let dividerRect = Rect(x: rect.minX, y: rect.minY + 1, width: rect.width, height: 1)
                    let contentRect = Rect(x: rect.minX, y: rect.minY + navBarHeight, width: rect.width, height: max(0, rect.height - navBarHeight))

                    // Draw Header Background
                    let headerStyle = CellStyle(fg: .white, bg: .rgb(24, 26, 38), modifiers: [.bold])
                    buffer.clear(navBarRect, style: headerStyle)

                    var cursorX = rect.minX + 1

                    // Render [< Back] Button if depth > 0
                    if navigator.canPop {
                        let backBtnText = "[< Back (Esc)] "
                        let btnW = UnicodeWidth.width(of: backBtnText)
                        buffer.writeString(x: cursorX, y: rect.minY, backBtnText, style: CellStyle(fg: .brightCyan, bg: .rgb(24, 26, 38), modifiers: [.bold]), maxWidth: btnW)

                        let backHitRect = Rect(x: cursorX, y: rect.minY, width: btnW, height: 1)
                        interactions.registerMouseTarget(rect: backHitRect, zIndex: 10) { mouse in
                            if case .down(.left) = mouse.kind {
                                navigator.pop()
                                return true
                            }
                            return false
                        }

                        // Intercept Escape to pop navigation (higher priority than modal sheet dismiss when stack depth > 0)
                        interactions.registerPriorityKeyInterceptor(zIndex: 250) { key in
                            if key.key == .escape {
                                navigator.pop()
                                return true
                            }
                            return false
                        }

                        cursorX += btnW + 1
                    }

                    // Render Breadcrumbs / Title
                    let titleStyle = CellStyle(fg: .brightYellow, bg: .rgb(24, 26, 38), modifiers: [.bold])
                    let availW = max(0, rect.maxX - cursorX - 1)
                    let displayTitle = UnicodeWidth.truncate(breadcrumbText, maxWidth: availW)
                    buffer.writeString(x: cursorX, y: rect.minY, displayTitle, style: titleStyle, maxWidth: availW)

                    // Draw Horizontal Divider below Navigation Bar
                    buffer.drawBorder(dividerRect, style: .plain, borderCellStyle: CellStyle(fg: .brightBlack))

                    // Render Active Content View
                    if !contentRect.isEmpty {
                        activeChildNode.render(in: contentRect, buffer: &buffer, interactions: interactions)
                    }
                }
            )
        ]
    }
}

// MARK: - NavigationLink

/// A control that initiates navigation to a destination view within an enclosing `NavigationStack`.
/// Matches SwiftUI's `NavigationLink`.
public struct NavigationLink<Label: View, Destination: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let customID: AnyHashable?
    public let destinationTitle: String
    public let destination: @MainActor @Sendable () -> Destination
    public let label: Label

    public init(
        _ titleKey: String,
        id: AnyHashable? = nil,
        @ViewBuilder destination: @escaping @MainActor @Sendable () -> Destination
    ) where Label == Text {
        self.customID = id
        self.destinationTitle = titleKey
        self.destination = destination
        self.label = Text(titleKey)
    }

    public init(
        id: AnyHashable? = nil,
        destination: @escaping @MainActor @Sendable () -> Destination,
        title: String = "",
        @ViewBuilder label: () -> Label
    ) {
        self.customID = id
        self.destinationTitle = title
        self.destination = destination
        self.label = label()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let pathID = customID ?? AnyHashable("\(context.path).NavigationLink")
        store.registerFocusable(pathID)

        let labelNodes = resolveView(label, context: context.appending("Label"))
        let labelNode = labelNodes.count == 1 ? labelNodes[0] : VStackLayoutEngine.makeNode(id: "\(context.path).labelStack", alignment: .leading, spacing: 0, children: labelNodes)
        let nav = context.environment.navigator
        let destClosure = destination
        let destTitle = destinationTitle

        return [
            RenderNode(
                id: "\(context.path).NavigationLink",
                measure: { proposal in
                    let size = labelNode.sizeThatFits(proposal)
                    return Size(width: size.width + 8, height: max(1, size.height))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == pathID)
                    let prefix = isFocused ? "▶ [" : "  ["
                    let suffix = isFocused ? "] ↵" : "]"
                    let prefixW = UnicodeWidth.width(of: prefix)
                    let suffixW = UnicodeWidth.width(of: suffix)

                    let fg: Color = isFocused ? .brightCyan : .white
                    let bg: Color = isFocused ? .rgb(36, 42, 60) : context.environment.backgroundColor
                    let style = CellStyle(fg: fg, bg: bg, modifiers: isFocused ? [.bold] : [])

                    buffer.writeString(x: rect.minX, y: rect.minY, prefix, style: style, maxWidth: rect.width)

                    let labelProposal = ProposedViewSize(width: max(0, rect.width - prefixW - suffixW), height: rect.height)
                    let labelSize = labelNode.sizeThatFits(labelProposal)
                    let labelW = min(labelSize.width, max(0, rect.width - prefixW - suffixW))
                    let innerRect = Rect(x: rect.minX + prefixW, y: rect.minY, width: labelW, height: rect.height)
                    if !innerRect.isEmpty {
                        labelNode.render(in: innerRect, buffer: &buffer, interactions: interactions)
                    }

                    buffer.writeString(x: innerRect.maxX, y: rect.minY, suffix, style: style, maxWidth: max(0, rect.maxX - innerRect.maxX))

                    let performNavigation = { @MainActor in
                        let destView = destClosure()
                        nav?.push(title: destTitle, view: AnyView(destView))
                    }

                    interactions.registerFocusedKeyHandler(for: pathID) { key in
                        if key.key == .enter || key.key == .space {
                            performNavigation()
                            return true
                        }
                        return false
                    }

                    interactions.registerMouseTarget(rect: rect, zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            store.activeFocusID = pathID
                            performNavigation()
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - Navigation Title Modifier

public struct _NavigationTitleModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let title: String

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        if let nav = context.environment.navigator {
            if nav.stack.isEmpty {
                nav.rootTitle = title
            } else {
                nav.updateTopTitle(title)
            }
        }
        let childContext = context.withEnvironment { env in
            env.navigationTitle = title
        }
        return resolveView(content, context: childContext)
    }
}

extension View {
    /// Sets the title displayed in the navigation bar when inside a `NavigationStack`.
    public func navigationTitle(_ title: String) -> some View {
        _NavigationTitleModifier(content: self, title: title)
    }
}

// MARK: - View Transition Container

/// Container that manages animated screen transitions (slide, fade, move) when switching views.
public struct TransitionContainer<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let transition: AnyTransition
    public let activeID: AnyHashable
    public let content: Content

    public init(
        transition: AnyTransition = .slide,
        activeID: AnyHashable,
        @ViewBuilder content: () -> Content
    ) {
        self.transition = transition
        self.activeID = activeID
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let animOffsetKey = "\(path).transitionOffset"

        let previousIDKey = "\(path).prevID"
        let previousID: AnyHashable? = store.value(forKey: previousIDKey, default: nil)

        // If ID changed, trigger slide animation when inside a `withAnimation` block
        if let prev = previousID, prev != activeID {
            store.setValue(activeID, forKey: previousIDKey)
            if let anim = AnimationContext.currentAnimation {
                let startOffset = 12
                store.setValue(startOffset, forKey: animOffsetKey)

                AnimationDriver.shared.addAnimation(
                    id: AnyHashable(path),
                    animation: anim,
                    update: { progress in
                        let clamped = max(0.0, min(1.0, progress))
                        let currentOffset = Int((Double(startOffset) * (1.0 - clamped)).rounded())
                        store.setValue(currentOffset, forKey: animOffsetKey)
                    }
                )
            } else {
                store.setValue(0, forKey: animOffsetKey)
            }
        } else if previousID == nil {
            store.setValue(activeID, forKey: previousIDKey)
            store.setValue(0, forKey: animOffsetKey)
        }

        let currentOffset: Int = store.value(forKey: animOffsetKey, default: 0)
        let childNodes = resolveView(content, context: context.appending("Content"))

        return childNodes.map { child in
            RenderNode(
                id: "\(child.id).transition",
                flexibleAxes: child.flexibleAxes,
                measure: child.sizeThatFits,
                render: { rect, buffer, interactions in
                    let shifted = Rect(x: rect.minX + currentOffset, y: rect.minY, width: rect.width, height: rect.height)
                    child.render(in: shifted, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}
