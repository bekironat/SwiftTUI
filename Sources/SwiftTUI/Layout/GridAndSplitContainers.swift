import Foundation

// MARK: - 1. Grid & GridRow (2D Matrix Layout Container)

/// Internal marker protocol to allow `Grid` to extract cells from `GridRow` children.
@MainActor
internal protocol _GridRowExtractable {
    func _extractGridRowCells(context: BuildContext) -> [RenderNode]
}

/// A horizontal row of cells inside a `Grid` container.
/// Matches SwiftUI's `GridRow`.
public struct GridRow<Content: View>: View, _PrimitiveView, _GridRowExtractable {
    public typealias Body = Never
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    internal func _extractGridRowCells(context: BuildContext) -> [RenderNode] {
        resolveView(content, context: context.appending("GridRow"))
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let cells = _extractGridRowCells(context: context)
        return [
            HStackLayoutEngine.makeNode(
                id: "\(context.path).GridRowFallback",
                alignment: .center,
                spacing: 1,
                children: cells
            )
        ]
    }
}

/// A container view that arranges `GridRow` views in a two-dimensional aligned matrix.
/// Matches SwiftUI's `Grid`.
public struct Grid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let alignment: Alignment
    public let horizontalSpacing: Int
    public let verticalSpacing: Int
    public let content: Content

    public init(
        alignment: Alignment = .leading,
        horizontalSpacing: Int = 2,
        verticalSpacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = max(0, horizontalSpacing)
        self.verticalSpacing = max(0, verticalSpacing)
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let matrix = Self.extractMatrix(from: content, context: context.appending("Grid"))
        let rowCount = matrix.count
        let colCount = matrix.map(\.count).max() ?? 0
        guard rowCount > 0, colCount > 0 else { return [] }

        let hSpace = horizontalSpacing
        let vSpace = verticalSpacing
        let cellAlign = alignment

        return [
            RenderNode(
                id: "\(context.path).Grid",
                measure: { proposal in
                    let (colWidths, rowHeights) = Self.computeDimensions(
                        matrix: matrix,
                        rowCount: rowCount,
                        colCount: colCount
                    )
                    let totalW = colWidths.reduce(0, +) + max(0, colCount - 1) * hSpace
                    let totalH = rowHeights.reduce(0, +) + max(0, rowCount - 1) * vSpace
                    return Size(
                        width: min(proposal.width ?? totalW, totalW),
                        height: min(proposal.height ?? totalH, totalH)
                    )
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let (colWidths, rowHeights) = Self.computeDimensions(
                        matrix: matrix,
                        rowCount: rowCount,
                        colCount: colCount
                    )

                    var curY = rect.minY
                    for r in 0..<rowCount {
                        let rHeight = rowHeights[r]
                        if curY >= rect.maxY { break }
                        var curX = rect.minX
                        let rowCells = matrix[r]

                        for c in 0..<rowCells.count {
                            let cWidth = colWidths[c]
                            if curX >= rect.maxX { break }
                            let cellNode = rowCells[c]
                            let availW = min(cWidth, rect.maxX - curX)
                            let availH = min(rHeight, rect.maxY - curY)
                            let cellSize = cellNode.sizeThatFits(ProposedViewSize(width: availW, height: availH))

                            let offsetX: Int
                            switch cellAlign.horizontal {
                            case .leading:  offsetX = 0
                            case .center:   offsetX = max(0, (availW - cellSize.width) / 2)
                            case .trailing: offsetX = max(0, availW - cellSize.width)
                            }

                            let offsetY: Int
                            switch cellAlign.vertical {
                            case .top:    offsetY = 0
                            case .center: offsetY = max(0, (availH - cellSize.height) / 2)
                            case .bottom: offsetY = max(0, availH - cellSize.height)
                            }

                            let cellRect = Rect(
                                x: curX + offsetX,
                                y: curY + offsetY,
                                width: min(availW, max(1, cellSize.width)),
                                height: min(availH, max(1, cellSize.height))
                            )
                            cellNode.render(in: cellRect, buffer: &buffer, interactions: interactions)
                            curX += cWidth + hSpace
                        }
                        curY += rHeight + vSpace
                    }
                }
            )
        ]
    }

    private static func computeDimensions(
        matrix: [[RenderNode]],
        rowCount: Int,
        colCount: Int
    ) -> (colWidths: [Int], rowHeights: [Int]) {
        var colWidths = Array(repeating: 0, count: colCount)
        var rowHeights = Array(repeating: 1, count: rowCount)

        for r in 0..<rowCount {
            let row = matrix[r]
            for c in 0..<row.count {
                let sz = row[c].sizeThatFits(.unspecified)
                if sz.width > colWidths[c] {
                    colWidths[c] = sz.width
                }
                if sz.height > rowHeights[r] {
                    rowHeights[r] = sz.height
                }
            }
        }
        return (colWidths, rowHeights)
    }

    private static func extractMatrix<V: View>(from view: V, context: BuildContext) -> [[RenderNode]] {
        if let row = view as? any _GridRowExtractable {
            return [row._extractGridRowCells(context: context)]
        }
        let mirror = Mirror(reflecting: view)
        if String(describing: type(of: view)).hasPrefix("TupleView<"),
           let childrenTuple = mirror.descendant("value") {
            let tupleMirror = Mirror(reflecting: childrenTuple)
            var result: [[RenderNode]] = []
            for (idx, child) in tupleMirror.children.enumerated() {
                let subCtx = context.appending("r\(idx)")
                if let row = child.value as? any _GridRowExtractable {
                    result.append(row._extractGridRowCells(context: subCtx))
                } else if let anyV = child.value as? any View {
                    result.append(resolveAnyView(anyV, context: subCtx))
                }
            }
            return result
        }
        return [resolveView(view, context: context)]
    }

    private static func resolveAnyView(_ view: any View, context: BuildContext) -> [RenderNode] {
        func open<T: View>(_ v: T) -> [RenderNode] {
            resolveView(v, context: context)
        }
        return open(view)
    }
}

// MARK: - 2. GridItem & LazyVGrid (Responsive Multi-Column Grid)

/// A description of a single column in a `LazyVGrid`.
/// Matches SwiftUI's `GridItem`.
public struct GridItem: Equatable, Sendable {
    public enum Size: Equatable, Sendable {
        case fixed(Int)
        case flexible(minimum: Int = 8, maximum: Int = 120)
        case adaptive(minimum: Int, maximum: Int = 120)
    }

    public var size: Size
    public var spacing: Int?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: Int? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

/// A container view that arranges its child views in a vertical grid creating columns according to `[GridItem]`.
/// Matches SwiftUI's `LazyVGrid`.
public struct LazyVGrid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let columns: [GridItem]
    public let alignment: HorizontalAlignment
    public let spacing: Int
    public let content: Content

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .leading,
        spacing: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns.isEmpty ? [GridItem(.flexible())] : columns
        self.alignment = alignment
        self.spacing = max(0, spacing)
        self.content = content()
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("LazyVGrid"))
        guard !children.isEmpty else { return [] }

        let colsSpec = columns
        let vSpacing = spacing

        return [
            RenderNode(
                id: "\(context.path).LazyVGrid",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    let availW = proposal.width ?? 80
                    let resolvedCols = Self.resolveColumnWidths(columns: colsSpec, availableWidth: availW, defaultSpacing: 2)
                    let colCount = max(1, resolvedCols.widths.count)
                    let rowCount = (children.count + colCount - 1) / colCount

                    var totalH = 0
                    for r in 0..<rowCount {
                        var maxRowH = 1
                        for c in 0..<colCount {
                            let idx = r * colCount + c
                            guard idx < children.count else { break }
                            let sz = children[idx].sizeThatFits(ProposedViewSize(width: resolvedCols.widths[c], height: nil))
                            if sz.height > maxRowH { maxRowH = sz.height }
                        }
                        totalH += maxRowH
                    }
                    totalH += max(0, rowCount - 1) * vSpacing
                    return Size(width: availW, height: totalH)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let resolvedCols = Self.resolveColumnWidths(columns: colsSpec, availableWidth: rect.width, defaultSpacing: 2)
                    let colCount = max(1, resolvedCols.widths.count)
                    let rowCount = (children.count + colCount - 1) / colCount

                    var curY = rect.minY
                    for r in 0..<rowCount {
                        if curY >= rect.maxY { break }
                        var maxRowH = 1
                        for c in 0..<colCount {
                            let idx = r * colCount + c
                            guard idx < children.count else { break }
                            let sz = children[idx].sizeThatFits(ProposedViewSize(width: resolvedCols.widths[c], height: nil))
                            if sz.height > maxRowH { maxRowH = sz.height }
                        }

                        var curX = rect.minX
                        for c in 0..<colCount {
                            let idx = r * colCount + c
                            guard idx < children.count else { break }
                            let colW = resolvedCols.widths[c]
                            let cellRect = Rect(
                                x: curX,
                                y: curY,
                                width: min(colW, max(0, rect.maxX - curX)),
                                height: min(maxRowH, max(0, rect.maxY - curY))
                            )
                            if !cellRect.isEmpty {
                                children[idx].render(in: cellRect, buffer: &buffer, interactions: interactions)
                            }
                            curX += colW + resolvedCols.spacings[c]
                        }
                        curY += maxRowH + vSpacing
                    }
                }
            )
        ]
    }

    private static func resolveColumnWidths(
        columns: [GridItem],
        availableWidth: Int,
        defaultSpacing: Int
    ) -> (widths: [Int], spacings: [Int]) {
        // Expand adaptive items into concrete flexible items first
        var expanded: [GridItem] = []
        for item in columns {
            if case .adaptive(let minW, let maxW) = item.size {
                let gap = item.spacing ?? defaultSpacing
                let safeMin = max(4, minW)
                let count = max(1, (availableWidth + gap) / (safeMin + gap))
                for _ in 0..<count {
                    expanded.append(GridItem(.flexible(minimum: safeMin, maximum: maxW), spacing: item.spacing, alignment: item.alignment))
                }
            } else {
                expanded.append(item)
            }
        }

        let count = max(1, expanded.count)
        var spacings = Array(repeating: 0, count: count)
        var totalSpacing = 0
        for i in 0..<(count - 1) {
            let s = max(0, expanded[i].spacing ?? defaultSpacing)
            spacings[i] = s
            totalSpacing += s
        }

        var widths = Array(repeating: 0, count: count)
        var remaining = max(0, availableWidth - totalSpacing)
        var flexibleIndices: [Int] = []

        for (i, item) in expanded.enumerated() {
            switch item.size {
            case .fixed(let w):
                let clamped = min(remaining, max(1, w))
                widths[i] = clamped
                remaining -= clamped
            case .flexible, .adaptive:
                flexibleIndices.append(i)
            }
        }

        if !flexibleIndices.isEmpty {
            let share = max(1, remaining / flexibleIndices.count)
            for (offset, idx) in flexibleIndices.enumerated() {
                if case .flexible(let minW, let maxW) = expanded[idx].size {
                    let raw = (offset == flexibleIndices.count - 1) ? max(1, remaining - share * offset) : share
                    widths[idx] = max(minW, min(maxW, raw))
                } else {
                    widths[idx] = share
                }
            }
        }

        return (widths, spacings)
    }
}

// MARK: - 3. NavigationSplitView (2-Column & 3-Column Split Container)

/// Visibility state of the leading columns in a `NavigationSplitView`.
/// Matches SwiftUI's `NavigationSplitViewVisibility`.
public enum NavigationSplitViewVisibility: String, Equatable, Hashable, Sendable {
    case all
    case detailOnly
}

/// A view that presents views in two or three columns, where selections in leading columns control presentations in subsequent columns.
/// Matches SwiftUI's `NavigationSplitView`.
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
    public let columnVisibility: Binding<NavigationSplitViewVisibility>?
    public let sidebarWidthRatio: Double
    public let sidebar: Sidebar
    public let content: Content
    public let detail: Detail
    private let hasThreeColumns: Bool

    /// Creates a two-column split view (Sidebar + Detail).
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>? = nil,
        sidebarWidthRatio: Double = 0.28,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) where Content == EmptyView {
        self.columnVisibility = columnVisibility
        self.sidebarWidthRatio = sidebarWidthRatio
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
        self.hasThreeColumns = false
    }

    /// Creates a three-column split view (Sidebar + Content + Detail).
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>? = nil,
        sidebarWidthRatio: Double = 0.24,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.columnVisibility = columnVisibility
        self.sidebarWidthRatio = sidebarWidthRatio
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.hasThreeColumns = true
    }

    public var body: some View {
        let visibility = columnVisibility?.wrappedValue ?? .all
        if visibility == .detailOnly {
            detail
        } else if hasThreeColumns {
            HSplitView(initialLeftRatio: sidebarWidthRatio, minLeftWidth: 18, minRightWidth: 36, showDivider: true) {
                sidebar
            } right: {
                HSplitView(initialLeftRatio: 0.40, minLeftWidth: 18, minRightWidth: 20, showDivider: true) {
                    content
                } right: {
                    detail
                }
            }
        } else {
            HSplitView(initialLeftRatio: sidebarWidthRatio, minLeftWidth: 20, minRightWidth: 30, showDivider: true) {
                sidebar
            } right: {
                detail
            }
        }
    }
}
