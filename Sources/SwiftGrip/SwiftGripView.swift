import Foundation
import Observation
import SwiftTUI

// MARK: - SwiftGrip IDE ViewModel (@Observable)

@Observable
@MainActor
public final class SwiftGripViewModel {
    public enum TopTab: String, CaseIterable, Hashable, Sendable {
        case console = "console"
        case ddl = "ddl"
        case explain = "explain"
    }

    public enum FocusTarget: String, Hashable, Sendable {
        case schemaTree = "focus.schemaTree"
        case sqlEditor = "focus.sqlEditor"
        case whereFilter = "focus.whereFilter"
        case dataGrid = "focus.dataGrid"
        case paletteInput = "focus.paletteInput"
    }

    public let database: SQLiteDatabase
    public var schema: SQLDatabaseSchema
    public var schemaTreeNodes: [TreeNode] = []

    public var selectedTreeID: String? = "tbl:customers"
    public var activeTableName: String = "customers"
    public var activeTopTab: TopTab = .console

    public var sqlEditorText: String = """
    -- SwiftGrip SQL Console (Ctrl+Space for Autocomplete, F5 / Ctrl+R to Run)
    SELECT c.customer_id, c.name, c.tier, c.country, COUNT(o.order_id) AS orders_count,
           COALESCE(SUM(o.total_amount), 0.0) AS total_spent
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id
    ORDER BY total_spent DESC;
    """

    public var whereFilterText: String = ""
    public var gridColumns: [TableColumn] = []
    public var gridRows: [[String?]] = []
    public var selectedRow: Int = 0
    public var selectedCol: Int = 0
    public var sortColumnIndex: Int? = nil
    public var sortAscending: Bool = true
    public var isShowingCustomQueryResult: Bool = false

    /// Uncommitted inline cell edits keyed by `(row, column)` in the current table view.
    public var stagedEdits: [TableCellCoordinate: String?] = [:]
    public var explainNodes: [TreeNode] = []
    public var selectedExplainNodeID: String? = nil

    public var serviceLogs: [String] = []
    public var latencyHistoryMs: [Double] = [1.2, 0.9, 1.5, 0.8, 1.1]
    public var lastExecutionMs: Double = 0.0

    public var showCommandPalette: Bool = false
    public var showHelpModal: Bool = false
    public var paletteQuery: String = ""

    public init(database: SQLiteDatabase) {
        self.database = database
        self.schema = database.introspectSchema()
        rebuildSchemaTree()
        appendLog("Connected to SQLite \(schema.sqliteVersion) (\(database.path)) — \(schema.tables.count) tables, \(schema.views.count) views")
        if schema.tables.contains(where: { $0.name == "customers" }) {
            loadTableData("customers")
        } else if let firstTable = schema.tables.first?.name {
            loadTableData(firstTable)
        }
    }

    // MARK: - Schema Tree Construction

    public func refreshSchema() {
        schema = database.introspectSchema()
        rebuildSchemaTree()
        appendLog("Schema refreshed (\(schema.tables.count) tables, \(schema.views.count) views)")
    }

    private func rebuildSchemaTree() {
        let tableNodes: [TreeNode] = schema.tables.map { tbl in
            let colChildren: [TreeNode] = tbl.columns.map { col in
                let fk = tbl.foreignKeys.first { $0.fromColumn == col.name }
                let icon = col.isPrimaryKey ? "🔑" : (fk != nil ? "🔗" : "•")
                let color: Color = col.isPrimaryKey ? .brightYellow : (fk != nil ? .brightMagenta : .brightCyan)
                let fkSuffix = fk.map { " → \($0.targetTable)" } ?? ""
                return TreeNode(
                    id: "col:\(tbl.name).\(col.name)",
                    label: col.name,
                    icon: icon,
                    iconColor: color,
                    detail: "\(col.summaryBadge)\(fkSuffix)"
                )
            }
            return TreeNode(
                id: "tbl:\(tbl.name)",
                label: tbl.name,
                icon: "⊞",
                iconColor: .brightCyan,
                detail: "(\(tbl.rowCount))",
                isInitiallyExpanded: tbl.name == activeTableName,
                children: colChildren
            )
        }

        let viewNodes: [TreeNode] = schema.views.map { vw in
            let colChildren: [TreeNode] = vw.columns.map { col in
                TreeNode(
                    id: "vcol:\(vw.name).\(col.name)",
                    label: col.name,
                    icon: "•",
                    iconColor: .brightGreen,
                    detail: col.type
                )
            }
            return TreeNode(
                id: "vw:\(vw.name)",
                label: vw.name,
                icon: "👁",
                iconColor: .brightGreen,
                detail: "(\(vw.rowCount))",
                children: colChildren
            )
        }

        let indexNodes: [TreeNode] = schema.indexes.map { idx in
            TreeNode(
                id: "idx:\(idx.name)",
                label: idx.name,
                icon: "⚡",
                iconColor: .orange,
                detail: "on \(idx.tableName)"
            )
        }

        let triggerNodes: [TreeNode] = schema.triggers.map { trg in
            TreeNode(
                id: "trg:\(trg.name)",
                label: trg.name,
                icon: "⚙",
                iconColor: .brightMagenta,
                detail: "on \(trg.tableName)"
            )
        }

        let dbLabel = (database.path == ":memory:") ? "main (in-memory demo)" : (database.path as NSString).lastPathComponent
        schemaTreeNodes = [
            TreeNode(
                id: "root:db",
                label: dbLabel,
                icon: "🗄",
                iconColor: .brightYellow,
                detail: "SQLite \(schema.sqliteVersion)",
                isInitiallyExpanded: true,
                children: [
                    TreeNode(
                        id: "folder:tables",
                        label: "tables",
                        icon: "📁",
                        iconColor: .brightCyan,
                        detail: "\(tableNodes.count)",
                        isInitiallyExpanded: true,
                        children: tableNodes
                    ),
                    TreeNode(
                        id: "folder:views",
                        label: "views",
                        icon: "📁",
                        iconColor: .brightGreen,
                        detail: "\(viewNodes.count)",
                        isInitiallyExpanded: true,
                        children: viewNodes
                    ),
                    TreeNode(
                        id: "folder:indexes",
                        label: "indexes",
                        icon: "📁",
                        iconColor: .orange,
                        detail: "\(indexNodes.count)",
                        isInitiallyExpanded: false,
                        children: indexNodes
                    ),
                    TreeNode(
                        id: "folder:triggers",
                        label: "triggers",
                        icon: "📁",
                        iconColor: .brightMagenta,
                        detail: "\(triggerNodes.count)",
                        isInitiallyExpanded: false,
                        children: triggerNodes
                    )
                ]
            )
        ]
    }

    // MARK: - Table Browsing, Filtering & Sorting

    public func handleTreeNodeActivation(_ node: TreeNode) {
        if node.id.hasPrefix("tbl:") {
            let tbl = String(node.id.dropFirst(4))
            whereFilterText = ""
            sortColumnIndex = nil
            loadTableData(tbl)
        } else if node.id.hasPrefix("vw:") {
            let vw = String(node.id.dropFirst(3))
            whereFilterText = ""
            sortColumnIndex = nil
            loadTableData(vw)
        } else if node.id.hasPrefix("col:") {
            let rest = String(node.id.dropFirst(4))
            if let dot = rest.firstIndex(of: ".") {
                let tbl = String(rest[..<dot])
                let col = String(rest[rest.index(after: dot)...])
                if activeTableName != tbl {
                    whereFilterText = ""
                    sortColumnIndex = nil
                    loadTableData(tbl)
                }
                if let colIdx = gridColumns.firstIndex(where: { $0.title == col }) {
                    selectedCol = colIdx
                }
            }
        }
    }

    public func loadTableData(_ relationName: String) {
        activeTableName = relationName
        isShowingCustomQueryResult = false
        stagedEdits.removeAll()

        let escapedTable = database.escapeIdent(relationName)
        var sql = "SELECT * FROM \"\(escapedTable)\""

        let trimmedFilter = whereFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFilter.isEmpty {
            sql += " WHERE \(trimmedFilter)"
        }

        let relSchema = schema.relation(named: relationName)
        if let sortIdx = sortColumnIndex, let relSchema, sortIdx < relSchema.columns.count {
            let sortColName = database.escapeIdent(relSchema.columns[sortIdx].name)
            sql += " ORDER BY \"\(sortColName)\" \(sortAscending ? "ASC" : "DESC")"
        }
        sql += " LIMIT 500;"

        let res = database.execute(sql)
        recordExecution(res)

        guard res.isSuccess else { return }

        if let relSchema {
            gridColumns = relSchema.columns.map { col in
                let isNumeric = col.type.uppercased().contains("INT") || col.type.uppercased().contains("REAL") || col.type.uppercased().contains("NUM")
                return TableColumn(
                    id: col.name,
                    title: col.name,
                    typeName: col.type,
                    isPrimaryKey: col.isPrimaryKey,
                    alignment: isNumeric ? .trailing : .leading
                )
            }
        } else {
            gridColumns = res.columns.map { TableColumn(title: $0) }
        }
        gridRows = res.rows
        selectedRow = 0
        selectedCol = min(selectedCol, max(0, gridColumns.count - 1))
        explainNodes = database.explainQueryPlan(sql)
    }

    public func toggleSort(columnIndex: Int) {
        if sortColumnIndex == columnIndex {
            sortAscending.toggle()
        } else {
            sortColumnIndex = columnIndex
            sortAscending = true
        }

        if isShowingCustomQueryResult {
            // Sort in-memory rows for custom query results
            gridRows.sort { a, b in
                let va = (columnIndex < a.count ? a[columnIndex] : nil) ?? ""
                let vb = (columnIndex < b.count ? b[columnIndex] : nil) ?? ""
                if let na = Double(va), let nb = Double(vb) {
                    return sortAscending ? (na < nb) : (na > nb)
                }
                return sortAscending ? (va < vb) : (va > vb)
            }
        } else {
            loadTableData(activeTableName)
        }
    }

    // MARK: - SQL Console Execution

    public func executeConsoleSQL() {
        let trimmed = sqlEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let res = database.execute(trimmed)
        recordExecution(res)
        explainNodes = database.explainQueryPlan(trimmed)

        if res.isSuccess {
            if !res.columns.isEmpty {
                isShowingCustomQueryResult = true
                stagedEdits.removeAll()
                gridColumns = res.columns.map { TableColumn(title: $0) }
                gridRows = res.rows
                selectedRow = 0
                selectedCol = 0
            } else {
                refreshSchema()
                loadTableData(activeTableName)
            }
        }
    }

    // MARK: - Staged Inline Cell Editing & Transactions (Ctrl+S Commit / Ctrl+Z Rollback)

    public func stageCellEdit(row: Int, column: Int, newValue: String) {
        guard !isShowingCustomQueryResult else {
            appendLog("⚠ Inline editing is available when browsing a table directly (select a table in Explorer).")
            return
        }
        guard row >= 0 && row < gridRows.count && column >= 0 && column < gridColumns.count else { return }
        let coord = TableCellCoordinate(row: row, column: column)
        let finalValue: String? = (newValue.uppercased() == "NULL") ? nil : newValue
        stagedEdits[coord] = finalValue
        let colName = gridColumns[column].title
        appendLog("✎ Staged edit on \(activeTableName)[\(row + 1)].\(colName) = \(finalValue.map { "'\($0)'" } ?? "NULL") (Ctrl+S to Commit, Ctrl+Z to Revert)")
    }

    public func commitStagedChanges() {
        guard !stagedEdits.isEmpty else {
            appendLog("ℹ No staged changes to commit.")
            return
        }
        guard let rel = schema.relation(named: activeTableName),
              let pkIdx = rel.primaryKeyColumnIndex else {
            appendLog("✖ Cannot commit inline edits: table '\(activeTableName)' has no primary key.")
            return
        }

        let pkColName = database.escapeIdent(rel.columns[pkIdx].name)
        let tableEscaped = database.escapeIdent(activeTableName)

        var statements: [String] = ["BEGIN TRANSACTION;"]
        for (coord, newVal) in stagedEdits {
            guard coord.row < gridRows.count,
                  coord.column < gridColumns.count,
                  pkIdx < gridRows[coord.row].count,
                  let pkValue = gridRows[coord.row][pkIdx] else { continue }

            let colEscaped = database.escapeIdent(gridColumns[coord.column].title)
            let sqlVal = newVal.map { database.escapeLiteral($0) } ?? "NULL"
            let sqlPK  = database.escapeLiteral(pkValue)
            statements.append("UPDATE \"\(tableEscaped)\" SET \"\(colEscaped)\" = \(sqlVal) WHERE \"\(pkColName)\" = \(sqlPK);")
        }
        statements.append("COMMIT;")

        let batchSQL = statements.joined(separator: "\n")
        let count = stagedEdits.count
        let res = database.execute(batchSQL)
        if res.isSuccess {
            stagedEdits.removeAll()
            appendLog("✓ Committed \(count) staged cell update(s) to '\(activeTableName)' in \(String(format: "%.2f", res.executionTimeMs)) ms")
            refreshSchema()
            loadTableData(activeTableName)
        } else {
            _ = database.execute("ROLLBACK;")
            appendLog("✖ Transaction failed and rolled back: \(res.error ?? "Unknown error")")
        }
    }

    public func revertStagedChanges() {
        guard !stagedEdits.isEmpty else { return }
        let count = stagedEdits.count
        stagedEdits.removeAll()
        appendLog("↺ Reverted \(count) uncommitted cell edit(s).")
    }

    // MARK: - DDL & Autocomplete Helpers

    public var currentDDLText: String {
        if let rel = schema.relation(named: activeTableName) {
            var parts: [String] = [
                "-- DDL for \(rel.kind.uppercased()): \(rel.name) (\(rel.rowCount) rows)",
                rel.ddl + ";"
            ]
            let idxList = schema.indexes.filter { $0.tableName == rel.name && !$0.ddl.isEmpty }
            if !idxList.isEmpty {
                parts.append("\n-- Indexes:")
                for idx in idxList { parts.append(idx.ddl + ";") }
            }
            let trgList = schema.triggers.filter { $0.tableName == rel.name && !$0.ddl.isEmpty }
            if !trgList.isEmpty {
                parts.append("\n-- Triggers:")
                for trg in trgList { parts.append(trg.ddl + ";") }
            }
            return parts.joined(separator: "\n")
        }
        return "-- Select a table or view to inspect its DDL."
    }

    public var schemaRelationNameSet: Set<String> {
        Set(schema.allRelations.map { $0.name.lowercased() })
    }

    private func recordExecution(_ result: SQLQueryResult) {
        lastExecutionMs = result.executionTimeMs
        latencyHistoryMs.append(max(0.1, result.executionTimeMs))
        if latencyHistoryMs.count > 24 {
            latencyHistoryMs.removeFirst(latencyHistoryMs.count - 24)
        }

        let cleanSQL = result.sql.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let shortSQL = UnicodeWidth.truncate(cleanSQL, maxWidth: 68)
        if let err = result.error {
            appendLog("✖ ERROR: \(err)  [\(shortSQL)]")
        } else if !result.columns.isEmpty {
            appendLog("✓ \(result.rows.count) row(s) fetched in \(String(format: "%.2f", result.executionTimeMs)) ms — \(shortSQL)")
        } else {
            appendLog("✓ \(result.rowsAffected) row(s) affected in \(String(format: "%.2f", result.executionTimeMs)) ms — \(shortSQL)")
        }
    }

    public func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        serviceLogs.append("[\(timestamp)] \(message)")
        if serviceLogs.count > 50 {
            serviceLogs.removeFirst(serviceLogs.count - 50)
        }
    }
}

// MARK: - SwiftGrip Root IDE View

public struct SwiftGripMainView: View {
    public let viewModel: SwiftGripViewModel

    public init(viewModel: SwiftGripViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Top Application Header & Toolbar
            topToolbar

            // 2. Main 3-Pane IDE Workspace (Left: Database Explorer, Right: Top SQL Console + Bottom Data Grid & Services)
            HSplitView(
                initialLeftRatio: 0.26,
                minLeftWidth: 24,
                minRightWidth: 40,
                showDivider: false
            ) {
                databaseExplorerSidebar
            } right: {
                VSplitView(
                    initialTopRatio: 0.42,
                    minTopHeight: 7,
                    minBottomHeight: 9,
                    showDivider: false
                ) {
                    topEditorPane
                } bottom: {
                    bottomResultsAndServicesPane
                }
            }
            .frame(maxWidth: ProposedViewSize.infinityDimension, maxHeight: ProposedViewSize.infinityDimension)

            // 3. Bottom Status Bar
            statusBar
        }
        // Global IDE Keyboard Shortcuts
        .keyboardShortcut(.f(5)) {
            viewModel.executeConsoleSQL()
        }
        .keyboardShortcut("r", modifiers: [.control]) {
            viewModel.executeConsoleSQL()
        }
        .keyboardShortcut("s", modifiers: [.control]) {
            viewModel.commitStagedChanges()
        }
        .keyboardShortcut("z", modifiers: [.control]) {
            viewModel.revertStagedChanges()
        }
        .keyboardShortcut("k", modifiers: [.control]) {
            viewModel.paletteQuery = ""
            viewModel.showCommandPalette.toggle()
        }
        .keyboardShortcut(.f(1)) {
            viewModel.showHelpModal.toggle()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.showCommandPalette },
                set: { viewModel.showCommandPalette = $0 }
            ),
            title: "⚡ SwiftGrip Command & Table Palette (Ctrl+K)",
            width: 64,
            height: 16
        ) {
            commandPaletteSheet
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.showHelpModal },
                set: { viewModel.showHelpModal = $0 }
            ),
            title: "❓ SwiftGrip Keyboard Shortcuts & Guide (F1)",
            width: 68,
            height: 18
        ) {
            helpModalSheet
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 1) {
            Text(" 🗄 SwiftGrip ")
                .bold()
                .foregroundStyle(.black)
                .background(.brightCyan)

            Text("SQLite \(viewModel.schema.sqliteVersion)")
                .foregroundStyle(.brightYellow)
                .bold()

            Spacer()

            Button("▶ Run SQL (F5)", color: .brightGreen, focusable: false) {
                viewModel.executeConsoleSQL()
            }

            if !viewModel.stagedEdits.isEmpty {
                Button("✓ Commit (\(viewModel.stagedEdits.count)) ^S", color: .brightYellow, focusable: false) {
                    viewModel.commitStagedChanges()
                }
                Button("↺ Revert ^Z", color: .brightRed, focusable: false) {
                    viewModel.revertStagedChanges()
                }
            }

            Button("⚡ Palette (^K)", color: .brightCyan, focusable: false) {
                viewModel.paletteQuery = ""
                viewModel.showCommandPalette = true
            }

            Button("? Help (F1)", color: .brightMagenta, focusable: false) {
                viewModel.showHelpModal = true
            }
        }
        .background(Color.rgb(20, 23, 36))
        .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)
    }

    @ViewBuilder
    private var databaseExplorerSidebar: some View {
        let relationSet = viewModel.schemaRelationNameSet
        let _ = relationSet // keep reference clean
        Tree(
            roots: viewModel.schemaTreeNodes,
            selection: Binding(
                get: { viewModel.selectedTreeID },
                set: { viewModel.selectedTreeID = $0 }
            ),
            id: SwiftGripViewModel.FocusTarget.schemaTree,
            onActivate: { node in
                viewModel.handleTreeNodeActivation(node)
            }
        )
        .border(
            .rounded,
            color: .brightCyan,
            background: Color.rgb(16, 18, 28),
            title: "Database Explorer",
            titleColor: .brightCyan,
            bottomTitle: "↵/Space:Open  ↑↓←→:Nav"
        )
    }

    @ViewBuilder
    private var topEditorPane: some View {
        let relNames = viewModel.schemaRelationNameSet
        let currentSchema = viewModel.schema

        VStack(alignment: .leading, spacing: 0) {
            TabBar(
                items: [
                    .init(id: SwiftGripViewModel.TopTab.console, title: "SQL Console", icon: "📝", badge: "F5"),
                    .init(id: SwiftGripViewModel.TopTab.ddl, title: "DDL Schema (\(viewModel.activeTableName))", icon: "📜"),
                    .init(id: SwiftGripViewModel.TopTab.explain, title: "Explain Query Plan", icon: "🧭")
                ],
                selection: Binding(
                    get: { viewModel.activeTopTab },
                    set: { viewModel.activeTopTab = $0 }
                )
            )

            switch viewModel.activeTopTab {
            case .console:
                TextEditor(
                    text: Binding(
                        get: { viewModel.sqlEditorText },
                        set: { viewModel.sqlEditorText = $0 }
                    ),
                    id: SwiftGripViewModel.FocusTarget.sqlEditor,
                    showsLineNumbers: true,
                    syntaxHighlighter: { line in
                        SQLSyntaxHighlighter.highlightLine(line, schemaRelationNames: relNames)
                    },
                    completionProvider: { ctx in
                        SQLAutocompleteEngine.completions(
                            for: ctx,
                            schema: currentSchema,
                            defaultTable: viewModel.activeTableName
                        )
                    },
                    onExecuteShortcut: {
                        viewModel.executeConsoleSQL()
                    }
                )
            case .ddl:
                ScrollView(.vertical) {
                    ForEach(Array(viewModel.currentDDLText.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { item in
                        Text(spans: SQLSyntaxHighlighter.highlightLine(String(item.element), schemaRelationNames: relNames))
                    }
                }
            case .explain:
                Tree(
                    roots: viewModel.explainNodes,
                    selection: Binding(
                        get: { viewModel.selectedExplainNodeID },
                        set: { viewModel.selectedExplainNodeID = $0 }
                    )
                )
            }
        }
        .border(
            .rounded,
            color: .brightBlue,
            background: Color.rgb(18, 20, 32),
            title: "Query Console & Inspector",
            titleColor: .brightBlue,
            bottomTitle: "Ctrl+Space:SQL Autocomplete  F5/Ctrl+R:Execute"
        )
    }

    @ViewBuilder
    private var bottomResultsAndServicesPane: some View {
        let currentSchema = viewModel.schema
        let currentTable = viewModel.activeTableName

        VStack(alignment: .leading, spacing: 0) {
            // Filter / WHERE bar with live column autocomplete!
            HStack(alignment: .center, spacing: 1) {
                Text(" WHERE ")
                    .bold()
                    .foregroundStyle(.orange)
                    .background(Color.rgb(32, 36, 54))

                TextField(
                    "Filter \(currentTable) rows (e.g. tier = 'ENTERPRISE' — Ctrl+Space for columns)...",
                    text: Binding(
                        get: { viewModel.whereFilterText },
                        set: { viewModel.whereFilterText = $0 }
                    ),
                    id: SwiftGripViewModel.FocusTarget.whereFilter,
                    onSubmit: {
                        viewModel.loadTableData(currentTable)
                    },
                    completionProvider: { ctx in
                        SQLAutocompleteEngine.completions(
                            for: ctx,
                            schema: currentSchema,
                            defaultTable: currentTable
                        )
                    }
                )

                Button("Apply", color: .brightGreen, focusable: false) {
                    viewModel.loadTableData(currentTable)
                }

                if !viewModel.whereFilterText.isEmpty {
                    Button("Clear", color: .brightRed, focusable: false) {
                        viewModel.whereFilterText = ""
                        viewModel.loadTableData(currentTable)
                    }
                }
            }
            .background(Color.rgb(24, 27, 42))
            .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)

            // Interactive 2D Data Grid
            let gridTitle = viewModel.isShowingCustomQueryResult
                ? "Query Result (\(viewModel.gridRows.count) rows)"
                : "Table: \(viewModel.activeTableName) (\(viewModel.gridRows.count) rows)"

            let gridBottomHint = viewModel.stagedEdits.isEmpty
                ? "↵/e:Edit Cell  s:Sort Column  hjkl/Arrows:Navigate"
                : "● \(viewModel.stagedEdits.count) Staged Edit(s) — Ctrl+S:Commit Transaction  Ctrl+Z:Revert"

            Table(
                columns: viewModel.gridColumns,
                rows: viewModel.gridRows,
                selectedRow: Binding(
                    get: { viewModel.selectedRow },
                    set: { viewModel.selectedRow = $0 }
                ),
                selectedColumn: Binding(
                    get: { viewModel.selectedCol },
                    set: { viewModel.selectedCol = $0 }
                ),
                id: SwiftGripViewModel.FocusTarget.dataGrid,
                sortColumnIndex: viewModel.sortColumnIndex,
                sortAscending: viewModel.sortAscending,
                stagedEdits: viewModel.stagedEdits,
                onSortColumn: { colIdx in
                    viewModel.toggleSort(columnIndex: colIdx)
                },
                onCommitCellEdit: { row, col, newVal in
                    viewModel.stageCellEdit(row: row, column: col, newValue: newVal)
                }
            )
            .border(
                .rounded,
                color: viewModel.stagedEdits.isEmpty ? .brightGreen : .brightYellow,
                background: Color.rgb(15, 17, 26),
                title: gridTitle,
                titleColor: .brightGreen,
                bottomTitle: gridBottomHint
            )

            // Compact Services / Execution Log & Latency Sparkline Bar
            HStack(alignment: .center, spacing: 1) {
                Text("LOG")
                    .bold()
                    .foregroundStyle(.black)
                    .background(.brightMagenta)
                Text(viewModel.serviceLogs.last ?? "Ready.")
                    .foregroundStyle(.brightWhite)
                Spacer()
                Text("Latency:")
                    .foregroundStyle(.brightBlack)
                Sparkline(viewModel.latencyHistoryMs, color: .brightCyan)
                    .frame(width: 10, height: 1)
            }
            .background(Color.rgb(20, 22, 34))
            .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        let modeText = viewModel.stagedEdits.isEmpty ? " TX: AUTO " : " TX: STAGED (\(viewModel.stagedEdits.count)) "
        let modeBg: Color = viewModel.stagedEdits.isEmpty ? .brightBlue : .brightYellow
        let rowInfo = viewModel.gridRows.isEmpty ? "0/0" : "\(viewModel.selectedRow + 1)/\(viewModel.gridRows.count)"
        let colName = (viewModel.selectedCol < viewModel.gridColumns.count) ? viewModel.gridColumns[viewModel.selectedCol].title : "-"

        HStack(alignment: .center, spacing: 1) {
            Text(modeText)
                .bold()
                .foregroundStyle(.black)
                .background(modeBg)

            Text("⊞ \(viewModel.activeTableName)")
                .bold()
                .foregroundStyle(.brightCyan)

            Text("│ Row \(rowInfo) • Col: \(colName)")
                .foregroundStyle(.white)

            Spacer()

            Text("Tab:Switch Pane │ ^Space:Autocomplete │ F5:Run │ ^K:Palette │ ^Q:Quit ")
                .foregroundStyle(.brightBlack)
        }
        .background(Color.rgb(26, 29, 44))
        .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)
    }

    // MARK: - Modals (Command Palette & Help)

    @ViewBuilder
    private var commandPaletteSheet: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 1) {
                Text("🔍 Search:")
                    .bold()
                    .foregroundStyle(.brightCyan)
                TextField(
                    "Type table name or action...",
                    text: Binding(
                        get: { viewModel.paletteQuery },
                        set: { viewModel.paletteQuery = $0 }
                    ),
                    id: SwiftGripViewModel.FocusTarget.paletteInput
                )
            }
            Divider()
            Text("Quick Jump to Tables & Views:")
                .bold()
                .foregroundStyle(.brightYellow)

            let filteredRelations = viewModel.schema.allRelations.filter { rel in
                viewModel.paletteQuery.isEmpty || rel.name.localizedCaseInsensitiveContains(viewModel.paletteQuery)
            }
            ForEach(filteredRelations) { rel in
                HStack(alignment: .center, spacing: 2) {
                    Button("Open \(rel.name)", color: .brightCyan) {
                        viewModel.loadTableData(rel.name)
                        viewModel.showCommandPalette = false
                    }
                    Text("\(rel.kind.uppercased()) • \(rel.rowCount) rows • \(rel.columns.count) cols")
                        .foregroundStyle(.brightBlack)
                }
            }
            Divider()
            HStack(alignment: .center, spacing: 2) {
                Button("Run Revenue Report Query", color: .brightGreen) {
                    viewModel.sqlEditorText = "SELECT * FROM v_customer_revenue;"
                    viewModel.executeConsoleSQL()
                    viewModel.showCommandPalette = false
                }
                Button("Refresh Schema", color: .orange) {
                    viewModel.refreshSchema()
                    viewModel.showCommandPalette = false
                }
            }
        }
    }

    @ViewBuilder
    private var helpModalSheet: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SwiftGrip — Terminal SQLite IDE built on SwiftTUI")
                .bold()
                .foregroundStyle(.brightCyan)
            Divider()
            Text("• Tab / Shift+Tab   Cycle focus between Explorer, SQL Console, Filter, and Data Grid")
            Text("• Ctrl+Space        Trigger SQL Autocomplete popup at cursor (Keywords, Tables, Columns)")
            Text("• Up/Down & Tab/↵   Navigate and accept SQL Autocomplete suggestion")
            Text("• F5 / Ctrl+R       Execute SQL query in the Query Console")
            Text("• Enter / e         Edit selected cell inline inside the Data Grid")
            Text("• s / Header Click  Sort table by column (ASC / DESC)")
            Text("• Ctrl+S / Ctrl+Z   Commit or Revert staged inline cell edits in a SQLite transaction")
            Text("• Ctrl+K            Open Quick Command & Table Palette")
            Text("• Ctrl+C / Ctrl+Q   Exit SwiftGrip")
            Divider()
            Button("Close Help (Esc)", color: .brightGreen) {
                viewModel.showHelpModal = false
            }
        }
    }
}
