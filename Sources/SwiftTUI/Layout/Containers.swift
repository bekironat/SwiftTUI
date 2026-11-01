import Foundation

// MARK: - VStack & HStack Layout Engines

@MainActor
internal enum VStackLayoutEngine {
    static func makeNode(
        id: String,
        alignment: HorizontalAlignment,
        spacing: Int,
        children: [RenderNode]
    ) -> RenderNode {
        let hasFlexibleHeight = children.contains { $0.isSpacer || $0.flexibleAxes.contains(.vertical) }
        let hasFlexibleWidth  = children.contains { !$0.isSpacer && $0.flexibleAxes.contains(.horizontal) }
        var flexAxes: Axis.Set = []
        if hasFlexibleHeight { flexAxes.insert(.vertical) }
        if hasFlexibleWidth  { flexAxes.insert(.horizontal) }

        return RenderNode(
            id: id,
            flexibleAxes: flexAxes,
            measure: { proposal in
                guard !children.isEmpty else { return .zero }
                let totalSpacing = max(0, (children.count - 1) * spacing)
                let layout = computeChildHeights(children: children, proposal: proposal, totalSpacing: totalSpacing)
                let maxWidth = layout.sizes.map(\.width).max() ?? 0
                let totalHeight = layout.sizes.reduce(0) { $0 + $1.height } + totalSpacing
                return Size(
                    width: proposal.width ?? maxWidth,
                    height: proposal.height ?? totalHeight
                )
            },
            render: { rect, buffer, interactions in
                guard !children.isEmpty, !rect.isEmpty else { return }
                let totalSpacing = max(0, (children.count - 1) * spacing)
                let proposal = ProposedViewSize(width: rect.width, height: rect.height)
                let layout = computeChildHeights(children: children, proposal: proposal, totalSpacing: totalSpacing)

                var curY = rect.minY
                for (idx, child) in children.enumerated() {
                    let childSize = layout.sizes[idx]
                    let childW = min(rect.width, child.flexibleAxes.contains(.horizontal) ? rect.width : childSize.width)
                    let childX: Int
                    switch alignment {
                    case .leading:
                        childX = rect.minX
                    case .center:
                        childX = rect.minX + max(0, (rect.width - childW) / 2)
                    case .trailing:
                        childX = rect.maxX - childW
                    }
                    let availH = max(0, min(childSize.height, rect.maxY - curY))
                    let childRect = Rect(x: childX, y: curY, width: childW, height: availH)
                    if !childRect.isEmpty {
                        child.render(in: childRect, buffer: &buffer, interactions: interactions)
                    }
                    curY += childSize.height + spacing
                }
            }
        )
    }

    private static func computeChildHeights(
        children: [RenderNode],
        proposal: ProposedViewSize,
        totalSpacing: Int
    ) -> (sizes: [Size], remaining: Int) {
        let count = children.count
        var sizes = Array(repeating: Size.zero, count: count)
        let proposedWidth = proposal.width

        guard let proposedHeight = proposal.height, proposedHeight < ProposedViewSize.infinityDimension else {
            for i in 0..<count {
                if children[i].isSpacer {
                    sizes[i] = Size(width: 0, height: children[i].minSpacerLength)
                } else {
                    sizes[i] = children[i].sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
                }
            }
            return (sizes, 0)
        }

        var remainingHeight = max(0, proposedHeight - totalSpacing)
        var flexibleIndices: [Int] = []

        // Pass 1: Measure inflexible children first (sorted by descending layoutPriority)
        let inflexibleIndices = (0..<count).filter { !children[$0].isSpacer && !children[$0].flexibleAxes.contains(.vertical) }
            .sorted { children[$0].layoutPriority > children[$1].layoutPriority }

        for i in inflexibleIndices {
            let measured = children[i].sizeThatFits(ProposedViewSize(width: proposedWidth, height: remainingHeight))
            let h = min(remainingHeight, measured.height)
            sizes[i] = Size(width: measured.width, height: h)
            remainingHeight = max(0, remainingHeight - h)
        }

        // Collect flexible children (spacers and vertically flexible views)
        for i in 0..<count {
            if children[i].isSpacer || children[i].flexibleAxes.contains(.vertical) {
                flexibleIndices.append(i)
            }
        }

        // If we have both non-spacer flexible views AND spacers, prioritize non-spacer flexible views if they have higher priority, or share evenly
        if !flexibleIndices.isEmpty {
            let sortedFlex = flexibleIndices.sorted { children[$0].layoutPriority > children[$1].layoutPriority }
            var flexLeft = sortedFlex.count
            for i in sortedFlex {
                let share = flexLeft > 0 ? (remainingHeight / flexLeft) : 0
                if children[i].isSpacer {
                    let h = max(children[i].minSpacerLength, share)
                    let clamped = min(remainingHeight, h)
                    sizes[i] = Size(width: 0, height: clamped)
                    remainingHeight = max(0, remainingHeight - clamped)
                } else {
                    let measured = children[i].sizeThatFits(ProposedViewSize(width: proposedWidth, height: share))
                    let h = min(remainingHeight, max(measured.height, share))
                    sizes[i] = Size(width: measured.width, height: h)
                    remainingHeight = max(0, remainingHeight - h)
                }
                flexLeft -= 1
            }
        }

        return (sizes, remainingHeight)
    }
}

@MainActor
internal enum HStackLayoutEngine {
    static func makeNode(
        id: String,
        alignment: VerticalAlignment,
        spacing: Int,
        children: [RenderNode]
    ) -> RenderNode {
        let hasFlexibleWidth  = children.contains { $0.isSpacer || $0.flexibleAxes.contains(.horizontal) }
        let hasFlexibleHeight = children.contains { !$0.isSpacer && $0.flexibleAxes.contains(.vertical) }
        var flexAxes: Axis.Set = []
        if hasFlexibleWidth  { flexAxes.insert(.horizontal) }
        if hasFlexibleHeight { flexAxes.insert(.vertical) }

        return RenderNode(
            id: id,
            flexibleAxes: flexAxes,
            measure: { proposal in
                guard !children.isEmpty else { return .zero }
                let totalSpacing = max(0, (children.count - 1) * spacing)
                let layout = computeChildWidths(children: children, proposal: proposal, totalSpacing: totalSpacing)
                let totalWidth = layout.sizes.reduce(0) { $0 + $1.width } + totalSpacing
                let maxHeight = layout.sizes.map(\.height).max() ?? 0
                return Size(
                    width: proposal.width ?? totalWidth,
                    height: proposal.height ?? maxHeight
                )
            },
            render: { rect, buffer, interactions in
                guard !children.isEmpty, !rect.isEmpty else { return }
                let totalSpacing = max(0, (children.count - 1) * spacing)
                let proposal = ProposedViewSize(width: rect.width, height: rect.height)
                let layout = computeChildWidths(children: children, proposal: proposal, totalSpacing: totalSpacing)

                var curX = rect.minX
                for (idx, child) in children.enumerated() {
                    let childSize = layout.sizes[idx]
                    let childH = min(rect.height, child.flexibleAxes.contains(.vertical) ? rect.height : childSize.height)
                    let childY: Int
                    switch alignment {
                    case .top:
                        childY = rect.minY
                    case .center:
                        childY = rect.minY + max(0, (rect.height - childH) / 2)
                    case .bottom:
                        childY = rect.maxY - childH
                    }
                    let availW = max(0, min(childSize.width, rect.maxX - curX))
                    let childRect = Rect(x: curX, y: childY, width: availW, height: childH)
                    if !childRect.isEmpty {
                        child.render(in: childRect, buffer: &buffer, interactions: interactions)
                    }
                    curX += childSize.width + spacing
                }
            }
        )
    }

    private static func computeChildWidths(
        children: [RenderNode],
        proposal: ProposedViewSize,
        totalSpacing: Int
    ) -> (sizes: [Size], remaining: Int) {
        let count = children.count
        var sizes = Array(repeating: Size.zero, count: count)
        let proposedHeight = proposal.height

        guard let proposedWidth = proposal.width, proposedWidth < ProposedViewSize.infinityDimension else {
            for i in 0..<count {
                if children[i].isSpacer {
                    sizes[i] = Size(width: children[i].minSpacerLength, height: 0)
                } else {
                    sizes[i] = children[i].sizeThatFits(ProposedViewSize(width: nil, height: proposedHeight))
                }
            }
            return (sizes, 0)
        }

        var remainingWidth = max(0, proposedWidth - totalSpacing)
        var flexibleIndices: [Int] = []

        let inflexibleIndices = (0..<count).filter { !children[$0].isSpacer && !children[$0].flexibleAxes.contains(.horizontal) }
            .sorted { children[$0].layoutPriority > children[$1].layoutPriority }

        for i in inflexibleIndices {
            let measured = children[i].sizeThatFits(ProposedViewSize(width: remainingWidth, height: proposedHeight))
            let w = min(remainingWidth, measured.width)
            sizes[i] = Size(width: w, height: measured.height)
            remainingWidth = max(0, remainingWidth - w)
        }

        for i in 0..<count {
            if children[i].isSpacer || children[i].flexibleAxes.contains(.horizontal) {
                flexibleIndices.append(i)
            }
        }

        if !flexibleIndices.isEmpty {
            let sortedFlex = flexibleIndices.sorted { children[$0].layoutPriority > children[$1].layoutPriority }
            var flexLeft = sortedFlex.count
            for i in sortedFlex {
                let share = flexLeft > 0 ? (remainingWidth / flexLeft) : 0
                if children[i].isSpacer {
                    let w = max(children[i].minSpacerLength, share)
                    let clamped = min(remainingWidth, w)
                    sizes[i] = Size(width: clamped, height: 0)
                    remainingWidth = max(0, remainingWidth - clamped)
                } else {
                    let measured = children[i].sizeThatFits(ProposedViewSize(width: share, height: proposedHeight))
                    let w = min(remainingWidth, max(measured.width, share))
                    sizes[i] = Size(width: w, height: measured.height)
                    remainingWidth = max(0, remainingWidth - w)
                }
                flexLeft -= 1
            }
        }

        return (sizes, remainingWidth)
    }
}

// MARK: - VStack, HStack, ZStack Views

/// Arranges child views vertically.
public struct VStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let alignment: HorizontalAlignment
    public let spacing: Int
    public let content: Content

    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let childContext = context.appending("VStack")
        let children = resolveView(content, context: childContext)
        return [
            VStackLayoutEngine.makeNode(
                id: childContext.path,
                alignment: alignment,
                spacing: spacing,
                children: children
            )
        ]
    }
}

/// Arranges child views horizontally.
public struct HStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let alignment: VerticalAlignment
    public let spacing: Int
    public let content: Content

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let childContext = context.appending("HStack")
        let children = resolveView(content, context: childContext)
        return [
            HStackLayoutEngine.makeNode(
                id: childContext.path,
                alignment: alignment,
                spacing: spacing,
                children: children
            )
        ]
    }
}

/// Overlays child views on top of each other along the Z axis.
public struct ZStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let alignment: Alignment
    public let content: Content

    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let childContext = context.appending("ZStack")
        let children = resolveView(content, context: childContext)
        var flexAxes: Axis.Set = []
        for c in children {
            flexAxes.formUnion(c.flexibleAxes)
        }

        return [
            RenderNode(
                id: childContext.path,
                flexibleAxes: flexAxes,
                measure: { proposal in
                    var maxW = 0
                    var maxH = 0
                    for c in children {
                        let s = c.sizeThatFits(proposal)
                        maxW = max(maxW, s.width)
                        maxH = max(maxH, s.height)
                    }
                    return Size(
                        width: proposal.width ?? maxW,
                        height: proposal.height ?? maxH
                    )
                },
                render: { rect, buffer, interactions in
                    for c in children {
                        let s = c.sizeThatFits(ProposedViewSize(rect.size))
                        let w = c.flexibleAxes.contains(.horizontal) ? rect.width : min(rect.width, s.width)
                        let h = c.flexibleAxes.contains(.vertical) ? rect.height : min(rect.height, s.height)
                        let x: Int
                        switch alignment.horizontal {
                        case .leading:  x = rect.minX
                        case .center:   x = rect.minX + max(0, (rect.width - w) / 2)
                        case .trailing: x = rect.maxX - w
                        }
                        let y: Int
                        switch alignment.vertical {
                        case .top:    y = rect.minY
                        case .center: y = rect.minY + max(0, (rect.height - h) / 2)
                        case .bottom: y = rect.maxY - h
                        }
                        c.render(in: Rect(x: x, y: y, width: w, height: h), buffer: &buffer, interactions: interactions)
                    }
                }
            )
        ]
    }
}

// MARK: - Spacer & Divider

/// A flexible space that expands along the major axis of its containing stack layout.
public struct Spacer: View, _PrimitiveView {
    public typealias Body = Never
    public let minLength: Int

    public init(minLength: Int = 0) {
        self.minLength = max(0, minLength)
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        [
            RenderNode(
                id: "\(context.path).Spacer",
                isSpacer: true,
                minSpacerLength: minLength,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    Size(
                        width: proposal.width ?? minLength,
                        height: proposal.height ?? minLength
                    )
                },
                render: { _, _, _ in }
            )
        ]
    }
}

/// A visual line separating content in a stack or pane.
public struct Divider: View, _PrimitiveView {
    public typealias Body = Never
    public var color: Color?

    public init(color: Color? = nil) {
        self.color = color
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let fg = color ?? (context.environment.foregroundColor == .default ? .brightBlack : context.environment.foregroundColor)
        let style = CellStyle(fg: fg, bg: context.environment.backgroundColor)
        return [
            RenderNode(
                id: "\(context.path).Divider",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    if let w = proposal.width, w < ProposedViewSize.infinityDimension {
                        return Size(width: w, height: 1)
                    }
                    return Size(width: 1, height: 1)
                },
                render: { rect, buffer, _ in
                    if rect.width >= rect.height {
                        buffer.drawHorizontalLine(x: rect.minX, y: rect.minY, length: rect.width, symbol: "─", style: style)
                    } else {
                        buffer.drawVerticalLine(x: rect.minX, y: rect.minY, length: rect.height, symbol: "│", style: style)
                    }
                }
            )
        ]
    }
}

// MARK: - GeometryReader

public struct GeometryProxy: Equatable, Sendable {
    public let size: Size
    public let frame: Rect

    public init(size: Size, frame: Rect) {
        self.size = size
        self.frame = frame
    }
}

/// A container view that defines its content as a function of its own allocated terminal size and coordinates.
public struct GeometryReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: @MainActor (GeometryProxy) -> Content

    public init(@ViewBuilder content: @escaping @MainActor (GeometryProxy) -> Content) {
        self.content = content
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let geoContext = context.appending("GeometryReader")
        return [
            RenderNode(
                id: geoContext.path,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 20, height: 5))
                },
                render: { rect, buffer, interactions in
                    let proxy = GeometryProxy(size: rect.size, frame: rect)
                    let childView = content(proxy)
                    let nodes = resolveView(childView, context: geoContext)
                    if nodes.count == 1 {
                        nodes[0].render(in: rect, buffer: &buffer, interactions: interactions)
                    } else if nodes.count > 1 {
                        let stack = VStackLayoutEngine.makeNode(id: "\(geoContext.path).stack", alignment: .leading, spacing: 0, children: nodes)
                        stack.render(in: rect, buffer: &buffer, interactions: interactions)
                    }
                }
            )
        ]
    }
}

// MARK: - ScrollView

/// A scrollable view container supporting vertical and/or horizontal scrolling with optional Ratatui-style scrollbar indicators.
public struct ScrollView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let axes: Axis.Set
    public let showsIndicators: Bool
    public let content: Content

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let scrollPath = context.appending("ScrollView").path
        let store = context.store
        let children = resolveView(content, context: context.appending("ScrollViewContent"))
        let contentNode = VStackLayoutEngine.makeNode(id: "\(scrollPath).inner", alignment: .leading, spacing: 0, children: children)

        return [
            RenderNode(
                id: scrollPath,
                flexibleAxes: axes,
                measure: { proposal in
                    let contentSize = contentNode.sizeThatFits(
                        ProposedViewSize(
                            width: axes.contains(.horizontal) ? nil : proposal.width,
                            height: axes.contains(.vertical) ? nil : proposal.height
                        )
                    )
                    return Size(
                        width: proposal.width ?? contentSize.width,
                        height: proposal.height ?? contentSize.height
                    )
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }

                    let contentProposal = ProposedViewSize(
                        width: axes.contains(.horizontal) ? nil : (showsIndicators ? max(1, rect.width - 1) : rect.width),
                        height: axes.contains(.vertical) ? nil : rect.height
                    )
                    let contentSize = contentNode.sizeThatFits(contentProposal)
                    let needsVScrollbar = showsIndicators && axes.contains(.vertical) && contentSize.height > rect.height
                    let viewportWidth = needsVScrollbar ? max(1, rect.width - 1) : rect.width
                    let viewportHeight = rect.height

                    let maxOffsetX = max(0, contentSize.width - viewportWidth)
                    let maxOffsetY = max(0, contentSize.height - viewportHeight)

                    var offset = store.widgetState(forPath: scrollPath, default: Point.zero)
                    offset.x = max(0, min(maxOffsetX, offset.x))
                    offset.y = max(0, min(maxOffsetY, offset.y))
                    store.setWidgetState(offset, forPath: scrollPath, markDirty: false)

                    let viewportRect = Rect(x: rect.minX, y: rect.minY, width: viewportWidth, height: viewportHeight)
                    let virtualRect = Rect(
                        x: rect.minX - offset.x,
                        y: rect.minY - offset.y,
                        width: max(viewportWidth, contentSize.width),
                        height: max(viewportHeight, contentSize.height)
                    )

                    buffer.withClip(viewportRect) { buf in
                        contentNode.render(in: virtualRect, buffer: &buf, interactions: interactions)
                    }

                    // Draw vertical scrollbar if needed
                    if needsVScrollbar {
                        let trackX = rect.maxX - 1
                        let trackH = rect.height
                        let thumbH = max(1, (trackH * viewportHeight) / max(1, contentSize.height))
                        let thumbTravel = max(0, trackH - thumbH)
                        let thumbY = maxOffsetY > 0 ? (offset.y * thumbTravel) / maxOffsetY : 0

                        for row in 0..<trackH {
                            let isThumb = row >= thumbY && row < (thumbY + thumbH)
                            let sym = isThumb ? "▐" : "░"
                            let fg: Color = isThumb ? .brightCyan : .brightBlack
                            buffer.setCell(x: trackX, y: rect.minY + row, symbol: sym, style: CellStyle(fg: fg))
                        }
                    }

                    // Register mouse wheel scrolling
                    interactions.registerMouseTarget(rect: rect, zIndex: 1) { mouse in
                        switch mouse.kind {
                        case .scrollUp:
                            if offset.y > 0 {
                                offset.y = max(0, offset.y - 2)
                                store.setWidgetState(offset, forPath: scrollPath, markDirty: true)
                                return true
                            }
                        case .scrollDown:
                            if offset.y < maxOffsetY {
                                offset.y = min(maxOffsetY, offset.y + 2)
                                store.setWidgetState(offset, forPath: scrollPath, markDirty: true)
                                return true
                            }
                        default:
                            break
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - Resizable HSplitView & VSplitView (IDE Pane Splitters)

/// A horizontally split two-pane container with a draggable vertical divider (`│` or space).
public struct HSplitView<Left: View, Right: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let initialLeftRatio: Double
    public let fixedLeftWidth: Int?
    public let minLeftWidth: Int
    public let minRightWidth: Int
    public let showDivider: Bool
    public let left: Left
    public let right: Right

    public init(
        initialLeftRatio: Double = 0.28,
        fixedLeftWidth: Int? = nil,
        minLeftWidth: Int = 16,
        minRightWidth: Int = 20,
        showDivider: Bool = false,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.initialLeftRatio = initialLeftRatio
        self.fixedLeftWidth = fixedLeftWidth
        self.minLeftWidth = minLeftWidth
        self.minRightWidth = minRightWidth
        self.showDivider = showDivider
        self.left = left()
        self.right = right()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let splitPath = context.appending("HSplitView").path
        let store = context.store
        let leftNodes = resolveView(left, context: context.appending("Left"))
        let rightNodes = resolveView(right, context: context.appending("Right"))
        let leftNode = VStackLayoutEngine.makeNode(id: "\(splitPath).left", alignment: .leading, spacing: 0, children: leftNodes)
        let rightNode = VStackLayoutEngine.makeNode(id: "\(splitPath).right", alignment: .leading, spacing: 0, children: rightNodes)

        return [
            RenderNode(
                id: splitPath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 80, height: 24))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let dividerW = showDivider ? 1 : 0
                    let usableW = max(1, rect.width - dividerW)

                    let defaultWidth = fixedLeftWidth ?? Int((Double(usableW) * initialLeftRatio).rounded())
                    var currentLeftW = store.widgetState(forPath: splitPath, default: defaultWidth)
                    let maxLeft = max(minLeftWidth, usableW - minRightWidth)
                    currentLeftW = max(min(minLeftWidth, usableW), min(maxLeft, currentLeftW))

                    let leftRect = Rect(x: rect.minX, y: rect.minY, width: currentLeftW, height: rect.height)
                    let divX = rect.minX + currentLeftW
                    let rightX = divX + dividerW
                    let rightW = max(0, rect.maxX - rightX)
                    let rightRect = Rect(x: rightX, y: rect.minY, width: rightW, height: rect.height)

                    leftNode.render(in: leftRect, buffer: &buffer, interactions: interactions)
                    if showDivider && divX < rect.maxX {
                        buffer.drawVerticalLine(x: divX, y: rect.minY, length: rect.height, symbol: "│", style: CellStyle(fg: .brightBlack))
                    }
                    rightNode.render(in: rightRect, buffer: &buffer, interactions: interactions)

                    // Allow mouse dragging on the boundary between left and right panes
                    let handleX = max(rect.minX, divX - 1)
                    let handleRect = Rect(x: handleX, y: rect.minY, width: 2 + dividerW, height: rect.height)
                    interactions.registerMouseTarget(rect: handleRect, zIndex: 10) { mouse in
                        if case .down(.left) = mouse.kind {
                            interactions.activeDragHandler = { dragEvent in
                                let newLeft = max(minLeftWidth, min(maxLeft, dragEvent.x - rect.minX))
                                store.setWidgetState(newLeft, forPath: splitPath, markDirty: true)
                                return true
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

/// A vertically split two-pane container with a draggable horizontal divider.
public struct VSplitView<Top: View, Bottom: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let initialTopRatio: Double
    public let fixedTopHeight: Int?
    public let minTopHeight: Int
    public let minBottomHeight: Int
    public let showDivider: Bool
    public let top: Top
    public let bottom: Bottom

    public init(
        initialTopRatio: Double = 0.45,
        fixedTopHeight: Int? = nil,
        minTopHeight: Int = 5,
        minBottomHeight: Int = 5,
        showDivider: Bool = false,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.initialTopRatio = initialTopRatio
        self.fixedTopHeight = fixedTopHeight
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.showDivider = showDivider
        self.top = top()
        self.bottom = bottom()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let splitPath = context.appending("VSplitView").path
        let store = context.store
        let topNodes = resolveView(top, context: context.appending("Top"))
        let bottomNodes = resolveView(bottom, context: context.appending("Bottom"))
        let topNode = VStackLayoutEngine.makeNode(id: "\(splitPath).top", alignment: .leading, spacing: 0, children: topNodes)
        let bottomNode = VStackLayoutEngine.makeNode(id: "\(splitPath).bottom", alignment: .leading, spacing: 0, children: bottomNodes)

        return [
            RenderNode(
                id: splitPath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 80, height: 24))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let dividerH = showDivider ? 1 : 0
                    let usableH = max(1, rect.height - dividerH)

                    let defaultHeight = fixedTopHeight ?? Int((Double(usableH) * initialTopRatio).rounded())
                    var currentTopH = store.widgetState(forPath: splitPath, default: defaultHeight)
                    let maxTop = max(minTopHeight, usableH - minBottomHeight)
                    currentTopH = max(min(minTopHeight, usableH), min(maxTop, currentTopH))

                    let topRect = Rect(x: rect.minX, y: rect.minY, width: rect.width, height: currentTopH)
                    let divY = rect.minY + currentTopH
                    let bottomY = divY + dividerH
                    let bottomH = max(0, rect.maxY - bottomY)
                    let bottomRect = Rect(x: rect.minX, y: bottomY, width: rect.width, height: bottomH)

                    topNode.render(in: topRect, buffer: &buffer, interactions: interactions)
                    if showDivider && divY < rect.maxY {
                        buffer.drawHorizontalLine(x: rect.minX, y: divY, length: rect.width, symbol: "─", style: CellStyle(fg: .brightBlack))
                    }
                    bottomNode.render(in: bottomRect, buffer: &buffer, interactions: interactions)

                    let handleY = max(rect.minY, divY - 1)
                    let handleRect = Rect(x: rect.minX, y: handleY, width: rect.width, height: 2 + dividerH)
                    interactions.registerMouseTarget(rect: handleRect, zIndex: 10) { mouse in
                        if case .down(.left) = mouse.kind {
                            interactions.activeDragHandler = { dragEvent in
                                let newTop = max(minTopHeight, min(maxTop, dragEvent.y - rect.minY))
                                store.setWidgetState(newTop, forPath: splitPath, markDirty: true)
                                return true
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
