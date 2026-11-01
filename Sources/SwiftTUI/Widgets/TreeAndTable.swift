import Foundation

// MARK: - Tree Widget (Hierarchical Schema & Outline Browser)

/// A node in a hierarchical `Tree` widget.
public struct TreeNode: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var icon: String
    public var iconColor: Color
    public var detail: String?
    public var children: [TreeNode]
    public var isInitiallyExpanded: Bool

    public init(
        id: String,
        label: String,
        icon: String = "•",
        iconColor: Color = .brightCyan,
        detail: String? = nil,
        isInitiallyExpanded: Bool = false,
        children: [TreeNode] = []
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.iconColor = iconColor
        self.detail = detail
        self.isInitiallyExpanded = isInitiallyExpanded
        self.children = children
    }

    public var isExpandable: Bool {
        !children.isEmpty
    }
}

internal struct TreeWidgetState {
    var expandedIDs: Set<String>
    var initialized: Bool = false
    var scrollOffset: Int = 0
}

/// Interactive hierarchical tree view supporting keyboard navigation (`Up`/`Down`/`Left`/`Right`/`Enter`/`Space`) and mouse clicks.
public struct Tree: View, _PrimitiveView {
    public typealias Body = Never
    public let roots: [TreeNode]
    public let selection: Binding<String?>
    public let focusID: AnyHashable?
    public var onActivate: (@MainActor (TreeNode) -> Void)?

    public init(
        roots: [TreeNode],
        selection: Binding<String?>,
        id: AnyHashable? = nil,
        onActivate: (@MainActor (TreeNode) -> Void)? = nil
    ) {
        self.roots = roots
        self.selection = selection
        self.focusID = id
        self.onActivate = onActivate
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let treePath = context.appending("Tree").path
        let targetFocusID = focusID ?? AnyHashable(treePath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let rootNodes = roots
        let selBinding = selection
        let activateHandler = onActivate

        return [
            RenderNode(
                id: treePath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 26, height: 12))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == targetFocusID)

                    var state = store.widgetState(forPath: treePath, default: TreeWidgetState(expandedIDs: []))
                    if !state.initialized {
                        Self.collectInitialExpanded(from: rootNodes, into: &state.expandedIDs)
                        state.initialized = true
                    }

                    let flatRows = Self.flatten(nodes: rootNodes, expandedIDs: state.expandedIDs, depth: 0)
                    guard !flatRows.isEmpty else {
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            "(empty)",
                            style: CellStyle(fg: .brightBlack, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                        return
                    }

                    // Ensure valid selection
                    var selectedIdx = flatRows.firstIndex(where: { $0.node.id == selBinding.wrappedValue }) ?? 0
                    selectedIdx = max(0, min(flatRows.count - 1, selectedIdx))
                    let currentSelectedNode = flatRows[selectedIdx].node
                    if selBinding.wrappedValue != currentSelectedNode.id {
                        selBinding.wrappedValue = currentSelectedNode.id
                    }

                    // Scroll viewport to keep selectedIdx visible
                    let visibleH = max(1, rect.height)
                    if selectedIdx < state.scrollOffset {
                        state.scrollOffset = selectedIdx
                    } else if selectedIdx >= state.scrollOffset + visibleH {
                        state.scrollOffset = max(0, selectedIdx - visibleH + 1)
                    }
                    store.setWidgetState(state, forPath: treePath, markDirty: false)

                    for visRow in 0..<visibleH {
                        let flatIdx = state.scrollOffset + visRow
                        guard flatIdx < flatRows.count else { break }
                        let item = flatRows[flatIdx]
                        let rowY = rect.minY + visRow
                        let isSelected = (flatIdx == selectedIdx)

                        let rowBg: Color
                        if isSelected {
                            rowBg = isFocused ? .rgb(45, 79, 138) : .rgb(36, 42, 64)
                        } else {
                            rowBg = context.environment.backgroundColor
                        }

                        let rowRect = Rect(x: rect.minX, y: rowY, width: rect.width, height: 1)
                        if rowBg != .default {
                            buffer.fill(rowRect, symbol: " ", style: CellStyle(bg: rowBg))
                        }

                        let indent = String(repeating: "  ", count: item.depth)
                        let disclosure: String
                        if item.node.isExpandable {
                            disclosure = state.expandedIDs.contains(item.node.id) ? "▾ " : "▸ "
                        } else {
                            disclosure = "  "
                        }

                        var spans: [StyledSpan] = [
                            StyledSpan(indent + disclosure, style: CellStyle(fg: .brightBlack, bg: rowBg)),
                            StyledSpan(item.node.icon + " ", style: CellStyle(fg: item.node.iconColor, bg: rowBg, modifiers: [.bold])),
                            StyledSpan(
                                item.node.label,
                                style: CellStyle(
                                    fg: isSelected ? .brightWhite : .white,
                                    bg: rowBg,
                                    modifiers: isSelected ? [.bold] : []
                                )
                            )
                        ]
                        if let detail = item.node.detail, !detail.isEmpty {
                            spans.append(StyledSpan(" \(detail)", style: CellStyle(fg: .brightBlack, bg: rowBg, modifiers: [.italic])))
                        }

                        buffer.writeSpans(x: rect.minX, y: rowY, spans, maxWidth: rect.width)

                        let capturedFlatIdx = flatIdx
                        interactions.registerMouseTarget(rect: rowRect, zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = targetFocusID
                                let clickedNode = flatRows[capturedFlatIdx].node
                                selBinding.wrappedValue = clickedNode.id
                                if clickedNode.isExpandable {
                                    if state.expandedIDs.contains(clickedNode.id) {
                                        state.expandedIDs.remove(clickedNode.id)
                                    } else {
                                        state.expandedIDs.insert(clickedNode.id)
                                    }
                                    store.setWidgetState(state, forPath: treePath, markDirty: true)
                                }
                                activateHandler?(clickedNode)
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }

                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        switch key.key {
                        case .up,
                             .char("k") where key.modifiers.isEmpty:
                            if selectedIdx > 0 {
                                let prevNode = flatRows[selectedIdx - 1].node
                                selBinding.wrappedValue = prevNode.id
                                store.markDirty()
                            }
                            return true

                        case .down,
                             .char("j") where key.modifiers.isEmpty:
                            if selectedIdx + 1 < flatRows.count {
                                let nextNode = flatRows[selectedIdx + 1].node
                                selBinding.wrappedValue = nextNode.id
                                store.markDirty()
                            }
                            return true

                        case .right:
                            if currentSelectedNode.isExpandable && !state.expandedIDs.contains(currentSelectedNode.id) {
                                state.expandedIDs.insert(currentSelectedNode.id)
                                store.setWidgetState(state, forPath: treePath, markDirty: true)
                            } else if selectedIdx + 1 < flatRows.count {
                                selBinding.wrappedValue = flatRows[selectedIdx + 1].node.id
                                store.markDirty()
                            }
                            return true

                        case .left:
                            if currentSelectedNode.isExpandable && state.expandedIDs.contains(currentSelectedNode.id) {
                                state.expandedIDs.remove(currentSelectedNode.id)
                                store.setWidgetState(state, forPath: treePath, markDirty: true)
                            } else if let parentID = flatRows[selectedIdx].parentID {
                                selBinding.wrappedValue = parentID
                                store.markDirty()
                            }
                            return true

                        case .space:
                            if currentSelectedNode.isExpandable {
                                if state.expandedIDs.contains(currentSelectedNode.id) {
                                    state.expandedIDs.remove(currentSelectedNode.id)
                                } else {
                                    state.expandedIDs.insert(currentSelectedNode.id)
                                }
                                store.setWidgetState(state, forPath: treePath, markDirty: true)
                            } else {
                                activateHandler?(currentSelectedNode)
                                store.markDirty()
                            }
                            return true

                        case .enter:
                            if currentSelectedNode.isExpandable && activateHandler == nil {
                                if state.expandedIDs.contains(currentSelectedNode.id) {
                                    state.expandedIDs.remove(currentSelectedNode.id)
                                } else {
                                    state.expandedIDs.insert(currentSelectedNode.id)
                                }
                                store.setWidgetState(state, forPath: treePath, markDirty: true)
                            } else {
                                activateHandler?(currentSelectedNode)
                                store.markDirty()
                            }
                            return true

                        default:
                            return false
                        }
                    }
                }
            )
        ]
    }

    private struct FlattenedRow {
        let node: TreeNode
        let depth: Int
        let parentID: String?
    }

    private static func collectInitialExpanded(from nodes: [TreeNode], into set: inout Set<String>) {
        for n in nodes {
            if n.isInitiallyExpanded {
                set.insert(n.id)
            }
            collectInitialExpanded(from: n.children, into: &set)
        }
    }

    private static func flatten(
        nodes: [TreeNode],
        expandedIDs: Set<String>,
        depth: Int,
        parentID: String? = nil
    ) -> [FlattenedRow] {
        var result: [FlattenedRow] = []
        for n in nodes {
            result.append(FlattenedRow(node: n, depth: depth, parentID: parentID))
            if n.isExpandable && expandedIDs.contains(n.id) {
                result.append(contentsOf: flatten(nodes: n.children, expandedIDs: expandedIDs, depth: depth + 1, parentID: n.id))
            }
        }
        return result
    }
}

// MARK: - Table Widget (2D Virtualized Data Grid with Sorting & Inline Cell Editing)

/// Identifies a specific `(row, column)` cell in a `Table`.
public struct TableCellCoordinate: Equatable, Hashable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Column definition for a `Table` widget.
public struct TableColumn: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var typeName: String?
    public var isPrimaryKey: Bool
    public var minWidth: Int
    public var maxWidth: Int
    public var alignment: HorizontalAlignment

    public init(
        id: String? = nil,
        title: String,
        typeName: String? = nil,
        isPrimaryKey: Bool = false,
        minWidth: Int = 6,
        maxWidth: Int = 36,
        alignment: HorizontalAlignment = .leading
    ) {
        self.id = id ?? title
        self.title = title
        self.typeName = typeName
        self.isPrimaryKey = isPrimaryKey
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.alignment = alignment
    }
}

internal struct TableWidgetState {
    var scrollRow: Int = 0
    var scrollCol: Int = 0
    var isEditingCell: Bool = false
    var editingText: String = ""
    var editingCursor: Int = 0
}

/// Interactive 2D data grid supporting virtualized scrolling, column sorting, cell selection, staged edit highlighting, and inline cell editing.
public struct Table: View, _PrimitiveView {
    public typealias Body = Never
    public let columns: [TableColumn]
    public let rows: [[String?]]
    public let selectedRow: Binding<Int>
    public let selectedColumn: Binding<Int>
    public let focusID: AnyHashable?
    public var sortColumnIndex: Int?
    public var sortAscending: Bool = true
    public var stagedEdits: [TableCellCoordinate: String?] = [:]
    public var deletedRows: Set<Int> = []
    public var onSortColumn: (@MainActor (Int) -> Void)?
    public var onCommitCellEdit: (@MainActor (Int, Int, String) -> Void)?

    public init(
        columns: [TableColumn],
        rows: [[String?]],
        selectedRow: Binding<Int>,
        selectedColumn: Binding<Int>,
        id: AnyHashable? = nil,
        sortColumnIndex: Int? = nil,
        sortAscending: Bool = true,
        stagedEdits: [TableCellCoordinate: String?] = [:],
        deletedRows: Set<Int> = [],
        onSortColumn: (@MainActor (Int) -> Void)? = nil,
        onCommitCellEdit: (@MainActor (Int, Int, String) -> Void)? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.selectedRow = selectedRow
        self.selectedColumn = selectedColumn
        self.focusID = id
        self.sortColumnIndex = sortColumnIndex
        self.sortAscending = sortAscending
        self.stagedEdits = stagedEdits
        self.deletedRows = deletedRows
        self.onSortColumn = onSortColumn
        self.onCommitCellEdit = onCommitCellEdit
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let tablePath = context.appending("Table").path
        let targetFocusID = focusID ?? AnyHashable(tablePath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let cols = columns
        let dataRows = rows
        let rowBinding = selectedRow
        let colBinding = selectedColumn
        let sortCol = sortColumnIndex
        let sortAsc = sortAscending
        let staged = stagedEdits
        let deleted = deletedRows
        let sortHandler = onSortColumn
        let editCommitHandler = onCommitCellEdit

        return [
            RenderNode(
                id: tablePath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 60, height: 12))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == targetFocusID)

                    guard !cols.isEmpty else {
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            "No columns to display.",
                            style: CellStyle(fg: .brightBlack, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                        return
                    }

                    var state = store.widgetState(forPath: tablePath, default: TableWidgetState())
                    let clampedRow = dataRows.isEmpty ? 0 : max(0, min(dataRows.count - 1, rowBinding.wrappedValue))
                    let clampedCol = max(0, min(cols.count - 1, colBinding.wrappedValue))
                    if !dataRows.isEmpty && rowBinding.wrappedValue != clampedRow {
                        rowBinding.wrappedValue = clampedRow
                    }
                    if colBinding.wrappedValue != clampedCol {
                        colBinding.wrappedValue = clampedCol
                    }

                    // Compute auto-sized column widths from header and sample rows
                    let colWidths: [Int] = cols.enumerated().map { cIdx, col in
                        var maxW = UnicodeWidth.width(of: col.title) + (col.isPrimaryKey ? 2 : 0) + (sortCol == cIdx ? 2 : 0)
                        let sampleLimit = min(dataRows.count, 50)
                        for rIdx in 0..<sampleLimit {
                            let coord = TableCellCoordinate(row: rIdx, column: cIdx)
                            let val: String?
                            if let stagedVal = staged[coord] {
                                val = stagedVal
                            } else if cIdx < dataRows[rIdx].count {
                                val = dataRows[rIdx][cIdx]
                            } else {
                                val = nil
                            }
                            let displayStr = val ?? "NULL"
                            maxW = max(maxW, UnicodeWidth.width(of: displayStr))
                        }
                        return max(col.minWidth, min(col.maxWidth, maxW + 2))
                    }

                    // Row number gutter
                    let rowNumWidth = max(4, String(max(1, dataRows.count)).count + 2)
                    let headerHeight = 2 // Header row + separator line
                    let bodyHeight = max(1, rect.height - headerHeight)

                    // Vertical & horizontal scroll adjustment
                    if clampedRow < state.scrollRow {
                        state.scrollRow = clampedRow
                    } else if clampedRow >= state.scrollRow + bodyHeight {
                        state.scrollRow = max(0, clampedRow - bodyHeight + 1)
                    }

                    if clampedCol < state.scrollCol {
                        state.scrollCol = clampedCol
                    } else {
                        // Ensure selected column is visible within horizontal viewport
                        var availW = max(1, rect.width - rowNumWidth)
                        var c = state.scrollCol
                        while c <= clampedCol && c < cols.count {
                            availW -= (colWidths[c] + 1)
                            if availW < 0 && c > state.scrollCol {
                                state.scrollCol += 1
                                availW = max(1, rect.width - rowNumWidth)
                                c = state.scrollCol
                                continue
                            }
                            c += 1
                        }
                    }
                    store.setWidgetState(state, forPath: tablePath, markDirty: false)

                    // 1. Render Header Row & Separator
                    let headerY = rect.minY
                    let sepY = rect.minY + 1
                    let headerBg = Color.rgb(32, 36, 54)
                    buffer.fill(Rect(x: rect.minX, y: headerY, width: rect.width, height: 1), symbol: " ", style: CellStyle(bg: headerBg))

                    buffer.writeString(
                        x: rect.minX,
                        y: headerY,
                        UnicodeWidth.fit("#", width: rowNumWidth - 1, alignment: .trailing) + "│",
                        style: CellStyle(fg: .brightBlack, bg: headerBg),
                        maxWidth: rowNumWidth
                    )
                    if sepY < rect.maxY {
                        buffer.drawHorizontalLine(x: rect.minX, y: sepY, length: rect.width, symbol: "─", style: CellStyle(fg: .brightBlack))
                        buffer.setCell(x: rect.minX + rowNumWidth - 1, y: sepY, symbol: "┼", style: CellStyle(fg: .brightBlack))
                    }

                    var curHeaderX = rect.minX + rowNumWidth
                    for cIdx in state.scrollCol..<cols.count {
                        guard curHeaderX < rect.maxX else { break }
                        let col = cols[cIdx]
                        let colW = min(colWidths[cIdx], rect.maxX - curHeaderX)
                        let isSelectedCol = (cIdx == clampedCol)

                        let sortSuffix: String
                        if sortCol == cIdx {
                            sortSuffix = sortAsc ? " ▲" : " ▼"
                        } else {
                            sortSuffix = ""
                        }
                        let pkPrefix = col.isPrimaryKey ? "🔑" : ""
                        let headerLabel = " \(pkPrefix)\(col.title)\(sortSuffix)"
                        let headerFg: Color = isSelectedCol ? .brightCyan : .brightWhite
                        buffer.writeString(
                            x: curHeaderX,
                            y: headerY,
                            UnicodeWidth.fit(headerLabel, width: colW, alignment: .leading),
                            style: CellStyle(fg: headerFg, bg: headerBg, modifiers: [.bold]),
                            maxWidth: colW
                        )

                        // Click on column header to sort
                        let headerCellRect = Rect(x: curHeaderX, y: headerY, width: colW, height: 1)
                        let capturedColIdx = cIdx
                        interactions.registerMouseTarget(rect: headerCellRect, zIndex: 6) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = targetFocusID
                                colBinding.wrappedValue = capturedColIdx
                                sortHandler?(capturedColIdx)
                                store.markDirty()
                                return true
                            }
                            return false
                        }

                        curHeaderX += colW
                        if curHeaderX < rect.maxX {
                            buffer.setCell(x: curHeaderX, y: headerY, symbol: "│", style: CellStyle(fg: .brightBlack, bg: headerBg))
                            if sepY < rect.maxY {
                                buffer.setCell(x: curHeaderX, y: sepY, symbol: "┼", style: CellStyle(fg: .brightBlack))
                            }
                            curHeaderX += 1
                        }
                    }

                    // 2. Render Visible Data Rows
                    if dataRows.isEmpty {
                        if rect.minY + 2 < rect.maxY {
                            buffer.writeString(
                                x: rect.minX + 2,
                                y: rect.minY + 2,
                                "(0 rows returned)",
                                style: CellStyle(fg: .brightBlack, modifiers: [.italic]),
                                maxWidth: rect.width - 2
                            )
                        }
                    } else {
                        for visIdx in 0..<bodyHeight {
                            let rIdx = state.scrollRow + visIdx
                            let rowY = rect.minY + headerHeight + visIdx
                            guard rIdx < dataRows.count, rowY < rect.maxY else { break }

                            let isRowSelected = (rIdx == clampedRow)
                            let isRowDeleted = deleted.contains(rIdx)
                            let baseRowBg: Color
                            if isRowDeleted {
                                baseRowBg = .rgb(70, 26, 32)
                            } else if isRowSelected {
                                baseRowBg = isFocused ? .rgb(38, 52, 82) : .rgb(30, 35, 52)
                            } else {
                                baseRowBg = (rIdx % 2 == 1) ? .rgb(20, 22, 34) : context.environment.backgroundColor
                            }

                            if baseRowBg != .default {
                                buffer.fill(Rect(x: rect.minX, y: rowY, width: rect.width, height: 1), symbol: " ", style: CellStyle(bg: baseRowBg))
                            }

                            // Row number gutter
                            let numText = UnicodeWidth.fit("\(rIdx + 1)", width: rowNumWidth - 1, alignment: .trailing) + "│"
                            buffer.writeString(
                                x: rect.minX,
                                y: rowY,
                                numText,
                                style: CellStyle(fg: isRowSelected ? .brightYellow : .brightBlack, bg: baseRowBg),
                                maxWidth: rowNumWidth
                            )

                            var curX = rect.minX + rowNumWidth
                            let rowData = dataRows[rIdx]

                            for cIdx in state.scrollCol..<cols.count {
                                guard curX < rect.maxX else { break }
                                let col = cols[cIdx]
                                let colW = min(colWidths[cIdx], rect.maxX - curX)
                                let isActiveCell = isRowSelected && (cIdx == clampedCol)
                                let coord = TableCellCoordinate(row: rIdx, column: cIdx)
                                let isStaged = staged.keys.contains(coord)

                                let rawCellVal: String?
                                if let stagedVal = staged[coord] {
                                    rawCellVal = stagedVal
                                } else if cIdx < rowData.count {
                                    rawCellVal = rowData[cIdx]
                                } else {
                                    rawCellVal = nil
                                }

                                let cellRect = Rect(x: curX, y: rowY, width: colW, height: 1)

                                if isActiveCell && state.isEditingCell && isFocused {
                                    // Render inline cell editor!
                                    let editBg = Color.rgb(65, 50, 20)
                                    buffer.fill(cellRect, symbol: " ", style: CellStyle(fg: .brightYellow, bg: editBg))
                                    let editText = " " + state.editingText
                                    buffer.writeString(
                                        x: curX,
                                        y: rowY,
                                        editText,
                                        style: CellStyle(fg: .brightWhite, bg: editBg, modifiers: [.bold]),
                                        maxWidth: colW
                                    )
                                    let cursorScreenX = min(cellRect.maxX - 1, curX + 1 + state.editingCursor)
                                    buffer.cursorPosition = Point(x: cursorScreenX, y: rowY)
                                    let editChars = Array(state.editingText)
                                    let chUnder = state.editingCursor < editChars.count ? String(editChars[state.editingCursor]) : " "
                                    buffer.setCell(
                                        x: cursorScreenX,
                                        y: rowY,
                                        symbol: chUnder,
                                        style: CellStyle(fg: .black, bg: .brightYellow, modifiers: [.bold])
                                    )
                                } else {
                                    let cellBg: Color
                                    if isActiveCell {
                                        cellBg = isFocused ? .rgb(64, 102, 175) : .rgb(48, 64, 96)
                                    } else if isStaged {
                                        cellBg = .rgb(24, 62, 42)
                                    } else {
                                        cellBg = baseRowBg
                                    }

                                    if cellBg != baseRowBg {
                                        buffer.fill(cellRect, symbol: " ", style: CellStyle(bg: cellBg))
                                    }

                                    let isNull = (rawCellVal == nil)
                                    let displayText = " " + (rawCellVal ?? "NULL") + " "
                                    let fitted = UnicodeWidth.fit(displayText, width: colW, alignment: col.alignment)

                                    var cellMods: CellModifiers = []
                                    if isNull { cellMods.insert(.italic); cellMods.insert(.dim) }
                                    if isActiveCell || isStaged { cellMods.insert(.bold) }
                                    if isRowDeleted { cellMods.insert(.strikethrough) }

                                    let cellFg: Color
                                    if isStaged {
                                        cellFg = .brightGreen
                                    } else if isNull {
                                        cellFg = isActiveCell ? .white : .brightBlack
                                    } else if isActiveCell {
                                        cellFg = .brightWhite
                                    } else {
                                        cellFg = .white
                                    }

                                    buffer.writeString(
                                        x: curX,
                                        y: rowY,
                                        fitted,
                                        style: CellStyle(fg: cellFg, bg: cellBg, modifiers: cellMods),
                                        maxWidth: colW
                                    )
                                }

                                let capturedRow = rIdx
                                let capturedCol = cIdx
                                interactions.registerMouseTarget(rect: cellRect, zIndex: 5) { mouse in
                                    if case .down(.left) = mouse.kind {
                                        store.activeFocusID = targetFocusID
                                        if rowBinding.wrappedValue == capturedRow && colBinding.wrappedValue == capturedCol && editCommitHandler != nil {
                                            // Second click on active cell enters inline edit mode
                                            state.isEditingCell = true
                                            state.editingText = rawCellVal ?? ""
                                            state.editingCursor = state.editingText.count
                                            store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                        } else {
                                            state.isEditingCell = false
                                            rowBinding.wrappedValue = capturedRow
                                            colBinding.wrappedValue = capturedCol
                                            store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                        }
                                        return true
                                    }
                                    return false
                                }

                                curX += colW
                                if curX < rect.maxX {
                                    buffer.setCell(x: curX, y: rowY, symbol: "│", style: CellStyle(fg: .brightBlack, bg: baseRowBg))
                                    curX += 1
                                }
                            }
                        }
                    }

                    // Priority key handler when inline cell editing is active
                    if isFocused && state.isEditingCell {
                        interactions.registerPriorityKeyInterceptor(zIndex: 140) { key in
                            var chars = Array(state.editingText)
                            state.editingCursor = max(0, min(chars.count, state.editingCursor))
                            switch key.key {
                            case .escape:
                                state.isEditingCell = false
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .enter:
                                let finalVal = state.editingText
                                state.isEditingCell = false
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                editCommitHandler?(clampedRow, clampedCol, finalVal)
                                return true
                            case .left:
                                state.editingCursor = max(0, state.editingCursor - 1)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .right:
                                state.editingCursor = min(chars.count, state.editingCursor + 1)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .home:
                                state.editingCursor = 0
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .end:
                                state.editingCursor = chars.count
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .backspace:
                                if state.editingCursor > 0 {
                                    chars.remove(at: state.editingCursor - 1)
                                    state.editingCursor -= 1
                                    state.editingText = String(chars)
                                    store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                }
                                return true
                            case .delete:
                                if state.editingCursor < chars.count {
                                    chars.remove(at: state.editingCursor)
                                    state.editingText = String(chars)
                                    store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                }
                                return true
                            case .space where key.modifiers.isEmpty:
                                chars.insert(" ", at: state.editingCursor)
                                state.editingCursor += 1
                                state.editingText = String(chars)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            case .char(let c) where key.modifiers.isEmpty || key.modifiers == [.shift]:
                                chars.insert(c, at: state.editingCursor)
                                state.editingCursor += 1
                                state.editingText = String(chars)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            default:
                                return true
                            }
                        }
                    }

                    // Standard table navigation & actions
                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        guard !dataRows.isEmpty else { return false }
                        switch key.key {
                        case .up,
                             .char("k") where key.modifiers.isEmpty:
                            if clampedRow > 0 {
                                rowBinding.wrappedValue = clampedRow - 1
                                store.markDirty()
                            }
                            return true
                        case .down,
                             .char("j") where key.modifiers.isEmpty:
                            if clampedRow + 1 < dataRows.count {
                                rowBinding.wrappedValue = clampedRow + 1
                                store.markDirty()
                            }
                            return true
                        case .left,
                             .char("h") where key.modifiers.isEmpty:
                            if clampedCol > 0 {
                                colBinding.wrappedValue = clampedCol - 1
                                store.markDirty()
                            }
                            return true
                        case .right,
                             .char("l") where key.modifiers.isEmpty:
                            if clampedCol + 1 < cols.count {
                                colBinding.wrappedValue = clampedCol + 1
                                store.markDirty()
                            }
                            return true
                        case .pageUp:
                            rowBinding.wrappedValue = max(0, clampedRow - bodyHeight)
                            store.markDirty()
                            return true
                        case .pageDown:
                            rowBinding.wrappedValue = min(dataRows.count - 1, clampedRow + bodyHeight)
                            store.markDirty()
                            return true
                        case .home:
                            rowBinding.wrappedValue = 0
                            store.markDirty()
                            return true
                        case .end:
                            rowBinding.wrappedValue = max(0, dataRows.count - 1)
                            store.markDirty()
                            return true
                        case .char("s") where key.modifiers.isEmpty:
                            sortHandler?(clampedCol)
                            store.markDirty()
                            return true
                        case .enter,
                             .char("e") where key.modifiers.isEmpty:
                            if editCommitHandler != nil {
                                let coord = TableCellCoordinate(row: clampedRow, column: clampedCol)
                                let currentVal: String
                                if let stagedVal = staged[coord] {
                                    currentVal = stagedVal ?? ""
                                } else if clampedCol < dataRows[clampedRow].count {
                                    currentVal = dataRows[clampedRow][clampedCol] ?? ""
                                } else {
                                    currentVal = ""
                                }
                                state.isEditingCell = true
                                state.editingText = currentVal
                                state.editingCursor = currentVal.count
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            }
                            return false
                        default:
                            return false
                        }
                    }

                    // Mouse wheel scrolling on table
                    interactions.registerMouseTarget(rect: rect, zIndex: 2) { mouse in
                        switch mouse.kind {
                        case .scrollUp:
                            if state.scrollRow > 0 {
                                state.scrollRow = max(0, state.scrollRow - 3)
                                rowBinding.wrappedValue = max(0, clampedRow - 3)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
                                return true
                            }
                        case .scrollDown:
                            if state.scrollRow + bodyHeight < dataRows.count {
                                state.scrollRow = min(max(0, dataRows.count - 1), state.scrollRow + 3)
                                rowBinding.wrappedValue = min(max(0, dataRows.count - 1), clampedRow + 3)
                                store.setWidgetState(state, forPath: tablePath, markDirty: true)
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

// MARK: - TabBar Widget

/// A horizontal tab strip for switching between editor tabs, table views, or tool panels.
public struct TabBar<TabID: Hashable>: View, _PrimitiveView {
    public typealias Body = Never
    public struct Item {
        public let id: TabID
        public let title: String
        public let icon: String?
        public let badge: String?

        public init(id: TabID, title: String, icon: String? = nil, badge: String? = nil) {
            self.id = id
            self.title = title
            self.icon = icon
            self.badge = badge
        }
    }

    public let items: [Item]
    public let selection: Binding<TabID>

    public init(items: [Item], selection: Binding<TabID>) {
        self.items = items
        self.selection = selection
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let tabItems = items
        let binding = selection
        let store = context.store

        return [
            RenderNode(
                id: "\(context.path).TabBar",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? 40, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let stripBg = Color.rgb(22, 24, 36)
                    buffer.fill(rect, symbol: " ", style: CellStyle(bg: stripBg))

                    var curX = rect.minX
                    for item in tabItems {
                        guard curX < rect.maxX else { break }
                        let isSelected = (item.id == binding.wrappedValue)
                        let iconStr = item.icon.map { "\($0) " } ?? ""
                        let badgeStr = item.badge.map { " (\($0))" } ?? ""
                        let tabText = " \(iconStr)\(item.title)\(badgeStr) "
                        let tabW = min(rect.maxX - curX, UnicodeWidth.width(of: tabText))

                        let fg: Color = isSelected ? .brightCyan : .brightBlack
                        let bg: Color = isSelected ? .rgb(42, 48, 74) : stripBg
                        let style = CellStyle(fg: fg, bg: bg, modifiers: isSelected ? [.bold, .underlined] : [])
                        buffer.writeString(x: curX, y: rect.minY, tabText, style: style, maxWidth: tabW)

                        let tabRect = Rect(x: curX, y: rect.minY, width: tabW, height: 1)
                        let capturedID = item.id
                        interactions.registerMouseTarget(rect: tabRect, zIndex: 8) { mouse in
                            if case .down(.left) = mouse.kind {
                                binding.wrappedValue = capturedID
                                store.markDirty()
                                return true
                            }
                            return false
                        }

                        curX += tabW
                        if curX < rect.maxX {
                            buffer.setCell(x: curX, y: rect.minY, symbol: "│", style: CellStyle(fg: .brightBlack, bg: stripBg))
                            curX += 1
                        }
                    }
                }
            )
        ]
    }
}
