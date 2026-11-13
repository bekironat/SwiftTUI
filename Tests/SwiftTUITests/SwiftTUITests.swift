import XCTest
@testable import SwiftTUI
import SwiftTUITesting
import SwiftGrip
import SwiftTUIGallery

@MainActor
final class SwiftTUITests: XCTestCase {

    // MARK: - 1. Unicode Display Width & Wrapping Tests

    func testUnicodeDisplayWidth() {
        XCTAssertEqual("Hello".displayWidth, 5)
        XCTAssertEqual("中文".displayWidth, 4)
        XCTAssertEqual("🗄".displayWidth, 2)
        XCTAssertEqual("A🗄B".displayWidth, 4)
        XCTAssertEqual(UnicodeWidth.truncate("Hello World", maxWidth: 6), "Hello…")
        XCTAssertEqual(UnicodeWidth.fit("Hi", width: 6, alignment: .center), "  Hi  ")
    }

    // MARK: - 2. Buffer Wide-Character Safety, Clipping & DiffRenderer Tests

    func testBufferWideCharOverwriteSafety() {
        var buf = Buffer(width: 10, height: 2)
        buf.writeString(x: 1, y: 0, "中")
        XCTAssertEqual(buf.cell(atX: 1, y: 0)?.symbol, "中")
        XCTAssertEqual(buf.cell(atX: 2, y: 0)?.isContinuation, true)

        // Overwriting the trailing continuation cell at x=2 must clean up the orphaned half at x=1
        buf.setCell(x: 2, y: 0, symbol: "X")
        XCTAssertEqual(buf.cell(atX: 1, y: 0)?.symbol, " ")
        XCTAssertEqual(buf.cell(atX: 2, y: 0)?.symbol, "X")
        XCTAssertEqual(buf.cell(atX: 2, y: 0)?.isContinuation, false)
    }

    func testDiffRendererMinimalOutput() {
        var first = Buffer(width: 20, height: 4)
        first.drawBorder(Rect(x: 0, y: 0, width: 20, height: 4), style: .rounded, title: "Demo")

        var second = first
        second.writeString(x: 2, y: 1, "OK", style: CellStyle(fg: .brightGreen, modifiers: [.bold]))

        let renderer = DiffRenderer(useSynchronizedOutput: true)
        let diffANSI = renderer.render(previous: first, current: second)

        XCTAssertTrue(diffANSI.contains("\u{1B}[?2026h"))
        XCTAssertTrue(diffANSI.contains("OK"))
        // Should not re-emit the unchanged border corners
        XCTAssertFalse(diffANSI.contains("╭"))
    }

    // MARK: - 3. ANSI Input Parser Tests

    func testANSIInputParser() {
        let parser = ANSIInputParser()

        // Ctrl+Space (0x00)
        let ctrlSpaceEvents = parser.parse([0x00])
        XCTAssertEqual(ctrlSpaceEvents, [.key(KeyEvent(.space, modifiers: [.control]))])
        if case .key(let ke) = ctrlSpaceEvents[0] {
            XCTAssertTrue(ke.isCtrlSpace)
        }

        // Arrow Up + F5 + SGR Mouse Click
        let rawBytes = Array("\u{1B}[A\u{1B}[15~\u{1B}[<0;12;5M".utf8)
        let parsed = parser.parse(rawBytes)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0], .key(KeyEvent(.up)))
        XCTAssertEqual(parsed[1], .key(KeyEvent(.f(5))))
        XCTAssertEqual(parsed[2], .mouse(MouseEvent(kind: .down(.left), x: 11, y: 4)))
    }

    // MARK: - 4. SwiftUI State Retention & Layout Tests

    struct CounterTestView: View {
        @State private var count: Int = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text("Counter=\(count)")
                Button("Increment", id: "btn.inc") {
                    count += 1
                }
            }
            .border(.rounded, title: "CounterBox")
        }
    }

    func testStateRetentionAndButtonInteraction() {
        let harness = TestHarness(rootView: CounterTestView(), width: 40, height: 10)
        XCTAssertTrue(harness.contains("Counter=0"))
        XCTAssertTrue(harness.contains("CounterBox"))

        // Press Enter on the focused Increment button
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("Counter=1"))

        harness.sendKey(.space)
        XCTAssertTrue(harness.contains("Counter=2"))
    }

    // MARK: - 5. Terminal Autocomplete Control Tests (TextField & TextEditor)

    struct AutocompleteSampleView: View {
        @State var queryText: String = "SEL"

        let items: [AutocompleteItem] = [
            AutocompleteItem(label: "SELECT", insertText: "SELECT ", kind: .keyword, detail: "SQL clause"),
            AutocompleteItem(label: "customers", insertText: "customers", kind: .table, detail: "table (8 rows)"),
            AutocompleteItem(label: "customer_id", insertText: "customer_id", kind: .column, detail: "INTEGER PK")
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text("SQL Input:")
                TextField("Enter SQL...", text: $queryText, id: "sql.input")
                    .autocomplete { ctx in
                        items.filter { $0.label.lowercased().hasPrefix(ctx.prefix.lowercased()) }
                    }
            }
            .padding(1)
        }
    }

    func testTerminalAutocompletePopupAndInsertion() {
        let harness = TestHarness(rootView: AutocompleteSampleView(), width: 60, height: 16)
        // Typing "E" onto "SEL" -> "SELE" should show the floating Completions popup with SELECT
        harness.type("E")
        XCTAssertTrue(harness.contains("Completions (1)"))
        XCTAssertTrue(harness.contains("KW "))
        XCTAssertTrue(harness.contains("SELECT"))

        // Pressing Tab accepts the completion and replaces "SELE" with "SELECT "
        harness.sendKey(.tab)
        XCTAssertFalse(harness.contains("Completions (1)"))
        XCTAssertTrue(harness.contains("SELECT "))
    }

    // MARK: - 6. SwiftGrip SQLite Engine, SQL Autocomplete & Full IDE Integration Tests

    func testSQLAutocompleteEngineContextAwareness() throws {
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        let schema = db.introspectSchema()

        // 1. After FROM, tables and views should rank at the top
        let fromLine = "SELECT * FROM cust"
        let fromCtx = AutocompleteContext.extract(
            fullText: fromLine,
            lineText: fromLine,
            lineIndex: 0,
            columnIndex: fromLine.count,
            isExplicitTrigger: false
        )
        let fromSuggestions = SQLAutocompleteEngine.completions(for: fromCtx, schema: schema)
        XCTAssertEqual(fromSuggestions.first?.label, "customers")
        XCTAssertEqual(fromSuggestions.first?.kind, .table)

        // 2. Alias dot-completion: `SELECT c.em FROM customers c`
        let aliasSQL = "SELECT c.em FROM customers c"
        let cursorCol = "SELECT c.em".count
        let aliasCtx = AutocompleteContext.extract(
            fullText: aliasSQL,
            lineText: aliasSQL,
            lineIndex: 0,
            columnIndex: cursorCol,
            isExplicitTrigger: false
        )
        XCTAssertEqual(aliasCtx.qualifier, "c")
        XCTAssertEqual(aliasCtx.prefix, "em")

        let colSuggestions = SQLAutocompleteEngine.completions(for: aliasCtx, schema: schema)
        XCTAssertEqual(colSuggestions.first?.label, "email")
        XCTAssertEqual(colSuggestions.first?.kind, .column)
    }

    func testSwiftGripEndToEndWorkflow() throws {
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        let vm = SwiftGripViewModel(database: db)
        let harness = TestHarness(rootView: SwiftGripMainView(viewModel: vm), width: 120, height: 34)

        // Verify initial 3-pane DataGrip UI rendered with seeded tables and rows
        XCTAssertTrue(harness.contains("Database Explorer"))
        XCTAssertTrue(harness.contains("customers"))
        XCTAssertTrue(harness.contains("Ada Lovelace"))
        XCTAssertTrue(harness.contains("Alan Turing"))

        // 1. Focus the WHERE filter field, type a column prefix, and verify autocomplete popup appears
        harness.activeFocusID = SwiftGripViewModel.FocusTarget.whereFilter
        harness.type("ti")
        XCTAssertTrue(harness.contains("Completions"))
        XCTAssertTrue(harness.contains("tier"))

        // Accept "tier" via Tab, finish typing ` = 'PRO'`, and press Enter to filter the table
        harness.sendKey(.tab)
        harness.type(" = 'PRO'")
        harness.sendKey(.enter)

        XCTAssertEqual(vm.gridRows.count, 3)
        XCTAssertTrue(harness.contains("Grace Hopper"))
        XCTAssertFalse(harness.contains("Ada Lovelace"))

        // Clear filter
        vm.whereFilterText = ""
        vm.loadTableData("customers")
        XCTAssertEqual(vm.gridRows.count, 8)

        // 2. Test inline cell editing + transaction commit (Ctrl+S)
        harness.activeFocusID = SwiftGripViewModel.FocusTarget.dataGrid
        // Move right to column 1 (`name`) on row 0 (`Ada Lovelace`)
        harness.sendKey(.right)
        harness.sendKey(.enter) // Enter inline edit mode
        harness.sendKey(.backspace)
        harness.type("e (Updated)")
        harness.sendKey(.enter) // Stage cell edit

        XCTAssertEqual(vm.stagedEdits.count, 1)
        XCTAssertTrue(harness.contains("TX: STAGED (1)"))

        // Commit transaction with Ctrl+S
        harness.sendCtrl("s")
        XCTAssertEqual(vm.stagedEdits.count, 0)
        XCTAssertTrue(harness.contains("Ada Lovelace (Updated)"))

        // Verify persisted in SQLite database
        let checkRes = db.execute("SELECT name FROM customers WHERE customer_id = 1;")
        XCTAssertEqual(checkRes.rows.first?.first ?? nil, "Ada Lovelace (Updated)")
    }

    func testSwiftGripSQLConsoleAutocompleteAndQueryExecution() throws {
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        let vm = SwiftGripViewModel(database: db)
        vm.sqlEditorText = "SELECT c. FROM customers c"
        let harness = TestHarness(rootView: SwiftGripMainView(viewModel: vm), width: 120, height: 34)

        // Focus the multi-line SQL Console TextEditor and move cursor right after `c.`
        harness.activeFocusID = SwiftGripViewModel.FocusTarget.sqlEditor
        for _ in 0..<"SELECT c.".count {
            harness.sendKey(.right)
        }
        // Type "em" -> "SELECT c.em FROM customers c"
        harness.type("em")

        // Verify the floating SQL Autocomplete popup appears anchored below the SQL editor cursor
        XCTAssertTrue(harness.contains("Completions"))
        XCTAssertTrue(harness.contains("COL"))
        XCTAssertTrue(harness.contains("email"))

        // Press Tab to accept `email`
        harness.sendKey(.tab)
        XCTAssertEqual(vm.sqlEditorText, "SELECT c.email FROM customers c")

        // Press F5 to execute the SQL query in the console
        harness.sendKey(.f(5))
        XCTAssertTrue(vm.isShowingCustomQueryResult)
        XCTAssertEqual(vm.gridColumns.map(\.title), ["email"])
        XCTAssertTrue(harness.contains("ada@analytical.org"))
    }

    // MARK: - 7. SwiftTUIGallery Component Catalog Tests

    func testSwiftTUIGallerySwitchingAndInteractions() {
        let vm = GalleryViewModel()
        let harness = TestHarness(rootView: GalleryMainView(viewModel: vm), width: 120, height: 34)

        // 1. Initial page: Typography
        XCTAssertTrue(harness.contains("🌟 SwiftTUI Component Catalog"))
        XCTAssertTrue(harness.contains("1. Text Formatting & Modifiers"))
        XCTAssertTrue(harness.contains("Plain"))
        XCTAssertTrue(harness.contains("Rounded"))

        // 2. Switch category to Charts & Gauges via Ctrl+5 shortcut
        harness.sendKey(.char("5"), modifiers: [.control])
        XCTAssertEqual(vm.selectedCategory, .charts)
        XCTAssertTrue(harness.contains("1. Gauges (Ratatui / ProgressView)"))
        XCTAssertTrue(harness.contains("2. Sparklines (Unicode Block Levels"))

        // Click randomize button on charts
        let prevGauge = vm.gaugeValueA
        harness.activeFocusID = "btn.rand"
        harness.sendKey(.enter)
        XCTAssertNotEqual(vm.gaugeValueA, prevGauge)

        // 3. Switch to Inputs & Autocomplete via Ctrl+3 shortcut
        harness.sendKey(.char("3"), modifiers: [.control])
        XCTAssertEqual(vm.selectedCategory, .inputs)
        XCTAssertTrue(harness.contains("1. Buttons & Reactive Toggles"))
        XCTAssertTrue(harness.contains("[Clicked: 0 times]"))

        // Click counter button
        harness.activeFocusID = "btn.counter"
        harness.sendKey(.enter)
        XCTAssertEqual(vm.buttonClickCount, 1)
        XCTAssertTrue(harness.contains("[Clicked: 1 times]"))

        // Toggle strict mode
        harness.activeFocusID = "tgl.strict"
        harness.sendKey(.enter)
        XCTAssertTrue(vm.toggleB)

        // 4. Switch to Modals via Ctrl+6 shortcut and test .sheet presentation
        harness.sendKey(.char("6"), modifiers: [.control])
        XCTAssertEqual(vm.selectedCategory, .modals)
        harness.activeFocusID = "btn.sheet"
        harness.sendKey(.enter)
        XCTAssertTrue(vm.isSheetPresented)
        XCTAssertTrue(harness.contains("Hello from SwiftTUI Sheet!"))

        // Dismiss sheet with Escape
        harness.sendKey(.escape)
        XCTAssertFalse(vm.isSheetPresented)
    }

    // MARK: - 8. Visual Screenshot Generation for Both Samples

    func testGenerateVisualScreenshots() throws {
        #if canImport(AppKit)
        let artifactDir = URL(fileURLWithPath: "/Users/bekironat/.gemini/antigravity/brain/ba415cf0-6572-435b-93c7-4e2bfa0e2c46")
        let repoScreenshotsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Screenshots")
        try? FileManager.default.createDirectory(at: repoScreenshotsDir, withIntermediateDirectories: true)

        func saveBoth(buffer: Buffer, filename: String, title: String) throws {
            let artURL = artifactDir.appendingPathComponent(filename)
            let repoURL = repoScreenshotsDir.appendingPathComponent(filename)
            try TerminalScreenshotRenderer.saveScreenshot(buffer: buffer, to: artURL, title: title)
            _ = try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.copyItem(at: artURL, to: repoURL)
        }

        // 1. SwiftGrip Main IDE
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        let gripVM = SwiftGripViewModel(database: db)
        let gripHarness = TestHarness(rootView: SwiftGripMainView(viewModel: gripVM), width: 120, height: 36)
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_main.png", title: "SwiftGrip — Terminal SQLite IDE")

        // 2. SwiftGrip with Autocomplete Popup
        gripHarness.activeFocusID = SwiftGripViewModel.FocusTarget.whereFilter
        gripHarness.type("ti")
        gripHarness.render()
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_autocomplete.png", title: "SwiftGrip — Cursor-Anchored Autocomplete")

        // 3. SwiftGrip with Staged Transaction
        gripHarness.sendKey(.escape)
        gripVM.whereFilterText = ""
        gripHarness.activeFocusID = SwiftGripViewModel.FocusTarget.dataGrid
        gripVM.stageCellEdit(row: 0, column: 1, newValue: "Ada Lovelace (DB Lead)")
        gripHarness.render()
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_staged_transaction.png", title: "SwiftGrip — Staged Transaction & Cell Editing")

        // 4. SwiftGrip Command Palette
        gripVM.revertStagedChanges()
        gripVM.showCommandPalette = true
        gripHarness.render()
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_command_palette.png", title: "SwiftGrip — Command Palette Modal")

        // 5. SwiftTUIGallery - Typography & Borders
        let galVM = GalleryViewModel()
        let galHarness = TestHarness(rootView: GalleryMainView(viewModel: galVM), width: 120, height: 36)
        galVM.selectedCategory = .typography
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_typography.png", title: "SwiftTUIGallery — Typography & Borders")

        // 6. SwiftTUIGallery - Layout & Containers
        galVM.selectedCategory = .layout
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_layout.png", title: "SwiftTUIGallery — Layout & Containers")

        // 7. SwiftTUIGallery - Inputs & Autocomplete
        galVM.selectedCategory = .inputs
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_inputs.png", title: "SwiftTUIGallery — Inputs & Autocomplete")

        // 8. SwiftTUIGallery - Tree & Table
        galVM.selectedCategory = .treeAndTable
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_tree_and_table.png", title: "SwiftTUIGallery — Tree & Table")

        // 9. SwiftTUIGallery - Charts & Gauges
        galVM.selectedCategory = .charts
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_charts.png", title: "SwiftTUIGallery — Charts & Gauges")

        // 10. SwiftTUIGallery - Modals & Overlays
        galVM.selectedCategory = .modals
        galVM.isSheetPresented = true
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_modal_sheet.png", title: "SwiftTUIGallery — Modal Sheets & Overlays")
        #endif
    }
}
