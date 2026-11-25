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

        // Bracketed Paste & Focus Reporting (Ratatui / Bubble Tea Parity)
        let pasteBytes = Array("\u{1B}[200~SELECT * FROM users;\u{1B}[201~".utf8)
        let pasteEvents = parser.parse(pasteBytes)
        XCTAssertEqual(pasteEvents, [.paste("SELECT * FROM users;")])

        let focusBytes = Array("\u{1B}[I\u{1B}[O".utf8)
        let focusEvents = parser.parse(focusBytes)
        XCTAssertEqual(focusEvents, [.focusGained, .focusLost])
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

    // MARK: - 4b. BarChart, Canvas (Braille Grid) & Spinner Tests (Ratatui & Bubble Tea Parity)

    func testBarChartAndCanvasVisualizations() {
        // Vertical BarChart
        let vItems = [
            BarChartItem("CPU", value: 80, color: .brightGreen),
            BarChartItem("MEM", value: 40, color: .brightRed)
        ]
        let vHarness = TestHarness(rootView: BarChart(vItems, orientation: .vertical, barWidth: 3, barGap: 1), width: 20, height: 6)
        XCTAssertTrue(vHarness.contains("CPU"))
        XCTAssertTrue(vHarness.contains("MEM"))
        // Check presence of block characters
        let vText = vHarness.snapshot()
        XCTAssertTrue(vText.contains("█") || vText.contains("▄") || vText.contains("▅"))

        // Horizontal BarChart
        let hItems = [
            BarChartItem("Swift", value: 100, color: .brightCyan),
            BarChartItem("Rust", value: 90, color: .brightYellow)
        ]
        let hHarness = TestHarness(rootView: BarChart(hItems, orientation: .horizontal), width: 30, height: 4)
        XCTAssertTrue(hHarness.contains("Swift │"))
        XCTAssertTrue(hHarness.contains("Rust │"))

        // Canvas (Sub-Pixel Braille Matrix U+2800..U+28FF)
        var capturedScalar: UInt32 = 0
        let canvasHarness = TestHarness(rootView: Canvas(width: 10, height: 4) { ctx in
            ctx.setPixel(x: 0, y: 0, color: .brightCyan) // dot 1 (0x01)
            ctx.setPixel(x: 1, y: 3, color: .brightCyan) // dot 8 (0x80)
            ctx.drawLine(x0: 2, y0: 2, x1: 8, y1: 12, color: .brightGreen)
            ctx.drawCircle(centerX: 10, centerY: 8, radius: 4, color: .brightMagenta)
        }, width: 12, height: 6)

        for y in 0..<canvasHarness.buffer.height {
            for x in 0..<canvasHarness.buffer.width {
                if let sym = canvasHarness.buffer.cell(atX: x, y: y)?.symbol,
                   let scalar = sym.unicodeScalars.first,
                   scalar.value >= 0x2800 && scalar.value <= 0x28FF && scalar.value != 0x2800 {
                    capturedScalar = scalar.value
                    break
                }
            }
            if capturedScalar != 0 { break }
        }
        XCTAssertGreaterThan(capturedScalar, 0x2800, "Canvas must generate valid Unicode Braille characters in U+2800..U+28FF")

        // Spinner
        let spinnerA = TestHarness(rootView: Spinner("Loading", style: .dots, frame: 0), width: 20, height: 1)
        XCTAssertTrue(spinnerA.contains("⠋ Loading"))
        let spinnerB = TestHarness(rootView: Spinner("Loading", style: .dots, frame: 1), width: 20, height: 1)
        XCTAssertTrue(spinnerB.contains("⠙ Loading"))
    }

    // MARK: - 4c. Animation & Interpolation Engine Tests

    func testAnimationAndTransitions() {
        // 1. Timing Curves Boundary Evaluation
        let linear = Animation.linear(duration: 1.0)
        XCTAssertEqual(linear.evaluate(progress: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(linear.evaluate(progress: 0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(linear.evaluate(progress: 1.0), 1.0, accuracy: 0.001)

        let easeInOut = Animation.easeInOut(duration: 1.0)
        XCTAssertEqual(easeInOut.evaluate(progress: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(easeInOut.evaluate(progress: 1.0), 1.0, accuracy: 0.001)
        // In easeInOut, slope at 0.5 is steeper than linear
        XCTAssertEqual(easeInOut.evaluate(progress: 0.5), 0.5, accuracy: 0.001)

        let spring = Animation.spring(response: 0.5, dampingRatio: 0.7)
        XCTAssertEqual(spring.evaluate(progress: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(spring.evaluate(progress: 1.0), 1.0, accuracy: 0.05)

        // 2. Vector Arithmetic & Lerp
        XCTAssertEqual(lerp(from: 0.0, to: 100.0, progress: 0.25), 25.0, accuracy: 0.001)
        XCTAssertEqual(lerp(from: 10, to: 20, progress: 0.5), 15)
        XCTAssertEqual(lerp(from: Point(x: 0, y: 10), to: Point(x: 20, y: 30), progress: 0.5), Point(x: 10, y: 20))
        XCTAssertEqual(lerp(from: Size(width: 10, height: 2), to: Size(width: 30, height: 6), progress: 0.5), Size(width: 20, height: 4))

        // 3. TrueColor 24-bit RGB Lerp
        let red = Color.rgb(200, 0, 0)
        let blue = Color.rgb(0, 0, 200)
        let midColor = red.interpolated(to: blue, progress: 0.5)
        if case .rgb(let r, let g, let b) = midColor {
            XCTAssertEqual(r, 100)
            XCTAssertEqual(g, 0)
            XCTAssertEqual(b, 100)
        } else {
            XCTFail("Expected .rgb color")
        }

        // 4. AnimationDriver Tick Execution
        var updatedVal: Double = 0.0
        var completed: Bool = false
        let animID = UUID()
        let driver = AnimationDriver.shared
        driver.cancelAll()

        let baseTime = Date().timeIntervalSinceReferenceDate
        driver.addAnimation(id: animID, animation: Animation.linear(duration: 1.0), update: { p in
            updatedVal = p
        }, completion: {
            completed = true
        })

        XCTAssertEqual(updatedVal, 0.0)
        XCTAssertFalse(completed)

        // Advance 0.5s
        driver.tick(now: baseTime + 0.5)
        XCTAssertEqual(updatedVal, 0.5, accuracy: 0.01)
        XCTAssertFalse(completed)

        // Advance 1.0s (completion)
        driver.tick(now: baseTime + 1.1)
        XCTAssertEqual(updatedVal, 1.0, accuracy: 0.01)
        XCTAssertTrue(completed)

        // 5. AnimatableValue & withAnimation
        let animVal = AnimatableValue<Double>(10.0)
        let animStartTime = Date().timeIntervalSinceReferenceDate
        withAnimation(.linear(duration: 1.0)) {
            animVal.setTarget(50.0)
        }
        XCTAssertEqual(animVal.value, 10.0)
        driver.tick(now: animStartTime + 0.5)
        XCTAssertEqual(animVal.value, 30.0, accuracy: 0.5)
        driver.tick(now: animStartTime + 1.1)
        XCTAssertEqual(animVal.value, 50.0, accuracy: 0.1)

        // 6. TimelineView Initial Render
        let timelineHarness = TestHarness(rootView: TimelineView(.periodic(by: 0.1)) { ctx in
            Text("Frame=\(ctx.frame)")
        }, width: 20, height: 2)
        XCTAssertTrue(timelineHarness.contains("Frame=0"))
    }

    // MARK: - 4d. NavigationStack, NavigationLink & TransitionContainer Tests

    struct NavigationDemoView: View {
        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Root Content")
                    NavigationLink("Go to Details") {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Details Content Screen")
                        }
                        .navigationTitle("Details")
                    }
                }
                .navigationTitle("Dashboard")
            }
        }
    }

    func testNavigationStackAndTransitions() {
        let harness = TestHarness(rootView: NavigationDemoView(), width: 60, height: 10)
        XCTAssertTrue(harness.contains("Dashboard"))
        XCTAssertTrue(harness.contains("Root Content"))
        XCTAssertTrue(harness.contains("Go to Details"))

        // Focus and activate NavigationLink via Enter key
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("Details Content Screen"))
        XCTAssertTrue(harness.contains("[< Back (Esc)]"))
        XCTAssertTrue(harness.contains("Dashboard > Details"))

        // Press Escape to pop back to root
        harness.sendKey(.escape)
        XCTAssertTrue(harness.contains("Root Content"))
        XCTAssertFalse(harness.contains("Details Content Screen"))
        XCTAssertFalse(harness.contains("[< Back (Esc)]"))

        // TransitionContainer test
        let transHarness = TestHarness(rootView: TransitionContainer(activeID: "screenA") {
            Text("Screen A Content")
        }, width: 30, height: 3)
        XCTAssertTrue(transHarness.contains("Screen A Content"))
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

        // 3. Switch to Visual Analytics tab and verify BarChart and Braille Canvas render
        vm.activeTopTab = .analytics
        harness.render()
        XCTAssertTrue(harness.contains("Table Row Distribution"))
        XCTAssertTrue(harness.contains("Query Latency Telemetry"))

        // 4. Open Help Modal (F1) and test internal NavigationStack push & pop
        harness.sendKey(.f(1))
        XCTAssertTrue(vm.showHelpModal)
        XCTAssertTrue(harness.contains("Shortcuts & Guide"))

        harness.activeFocusID = "nav.diag"
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("Shortcuts & Guide > Diagnostics"))
        XCTAssertTrue(harness.contains("WAL Mode Enabled"))

        // First Escape pops NavigationStack back to Help root
        harness.sendKey(.escape)
        XCTAssertTrue(vm.showHelpModal)
        XCTAssertFalse(harness.contains("WAL Mode Enabled"))

        // Second Escape dismisses the Help modal sheet
        harness.sendKey(.escape)
        XCTAssertFalse(vm.showHelpModal)
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
        let harness = TestHarness(rootView: GalleryMainView(viewModel: vm), width: 120, height: 36)

        // 1. Initial page: Typography
        XCTAssertTrue(harness.contains("🌟 SwiftTUI Component Catalog"))
        XCTAssertTrue(harness.contains("1. Text Formatting & Modifiers"))
        XCTAssertTrue(harness.contains("Plain"))
        XCTAssertTrue(harness.contains("Rounded"))

        // 2. Switch category to Charts & Gauges via Ctrl+5 shortcut
        harness.sendKey(.char("5"), modifiers: [.control])
        XCTAssertEqual(vm.selectedCategory, .charts)
        XCTAssertTrue(harness.contains("1. Gauges (ProgressView)"))
        XCTAssertTrue(harness.contains("2. Sparklines (Block Levels)"))
        XCTAssertTrue(harness.contains("3. Activity Spinners:"))
        XCTAssertTrue(harness.contains("Vertical Bars"))
        XCTAssertTrue(harness.contains("Horizontal Bars"))
        XCTAssertTrue(harness.contains("5. Sub-Pixel Braille Canvas"))

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

        // 5. Switch to Navigation & Animations via Ctrl+7 shortcut
        harness.sendKey(.char("7"), modifiers: [.control])
        XCTAssertEqual(vm.selectedCategory, .navigation)
        XCTAssertTrue(harness.contains("1. Hierarchical Navigation"))
        XCTAssertTrue(harness.contains("System Hub"))
        XCTAssertTrue(harness.contains("2. View Transition Containers"))
        XCTAssertTrue(harness.contains("Card A: Ease-Out Curve"))

        // Push level 1 in NavigationStack: Cluster Nodes
        harness.activeFocusID = "nav.cluster"
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("System Hub > Cluster Nodes"))
        XCTAssertTrue(harness.contains("Cluster Topology: 3 Active Nodes"))

        // Push level 2 in NavigationStack: Node #1
        harness.activeFocusID = "nav.node1"
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("System Hub > Cluster Nodes > Node #1"))
        XCTAssertTrue(harness.contains("Node #1 (us-east-primary)"))

        // Pop back twice via Escape
        harness.sendKey(.escape)
        XCTAssertTrue(harness.contains("Cluster Topology: 3 Active Nodes"))
        harness.sendKey(.escape)
        XCTAssertTrue(harness.contains("Root System Hub"))

        // Trigger Spring transition button
        vm.activeTransitionTab = "spring"
        vm.springTargetProgress = 0.88
        harness.render()
        XCTAssertTrue(harness.contains("Card B: Spring Physics"))
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

        // 4b. SwiftGrip Visual Analytics Tab
        gripVM.showCommandPalette = false
        gripVM.activeTopTab = .analytics
        gripHarness.render()
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_analytics.png", title: "SwiftGrip — Visual Analytics & Telemetry")

        // 4c. SwiftGrip Help Modal with Pushed NavigationStack Diagnostics
        gripVM.activeTopTab = .console
        gripHarness.sendKey(.f(1))
        gripHarness.activeFocusID = "nav.diag"
        gripHarness.sendKey(.enter)
        try saveBoth(buffer: gripHarness.buffer, filename: "swiftgrip_help_diagnostics.png", title: "SwiftGrip — Help Modal NavigationStack Diagnostics")

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

        // 11. SwiftTUIGallery - Navigation & Animations (Root State)
        galVM.isSheetPresented = false
        galVM.selectedCategory = .navigation
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_navigation.png", title: "SwiftTUIGallery — Navigation & Animations")

        // 12. SwiftTUIGallery - Navigation & Animations (Pushed Stack + Spring Transition State)
        galHarness.activeFocusID = "nav.cluster"
        galHarness.sendKey(.enter)
        galVM.activeTransitionTab = "spring"
        galVM.springTargetProgress = 0.88
        galHarness.render()
        try saveBoth(buffer: galHarness.buffer, filename: "gallery_navigation_pushed.png", title: "SwiftTUIGallery — Pushed NavigationStack & Spring Transition")
        #endif
    }

    // MARK: - 9. Security Hardening & Injection Prevention Audit Tests

    func testSecurityHardeningAndInjectionPrevention() throws {
        // 1. Terminal Escape Sequence Injection (C0/C1, ESC, OSC-52, NUL) Sanitization in Buffer & Cell
        var buf = Buffer(width: 40, height: 2)
        let maliciousString = "Safe\u{1B}]52;c;dGVzdA==\u{07}Text\u{00}\u{9B}2J"
        buf.writeString(x: 0, y: 0, maliciousString)
        let renderedLine = buf.line(at: 0)
        XCTAssertFalse(renderedLine.contains("\u{1B}"), "Buffer must strip raw ESC characters from user strings")
        XCTAssertFalse(renderedLine.contains("\u{07}"), "Buffer must strip BEL control characters")
        XCTAssertFalse(renderedLine.contains("\u{9B}"), "Buffer must strip C1 CSI control characters")
        XCTAssertTrue(renderedLine.hasPrefix("Safe]52;c;dGVzdA==Text2J"))

        let directCell = Cell(symbol: "\u{1B}[31m")
        XCTAssertFalse(directCell.symbol.contains("\u{1B}"), "Cell initializer must sanitize control characters")

        // 2. Stacked SQL Statement Injection Prevention in EXPLAIN QUERY PLAN
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        _ = db.explainQueryPlan("SELECT * FROM customers; DROP TABLE customers;")
        let countAfterExplain = db.execute("SELECT COUNT(*) FROM customers;").rows.first?.first ?? nil
        XCTAssertEqual(countAfterExplain, "8", "EXPLAIN QUERY PLAN must never execute stacked destructive statements")

        // 3. Parameterized Inline Cell Edit SQL Injection & NUL-Byte Truncation Prevention
        let vm = SwiftGripViewModel(database: db)
        let sqliPayload = "Ada'); DROP TABLE customers; --\0Tail"
        vm.stageCellEdit(row: 0, column: 1, newValue: sqliPayload)
        vm.commitStagedChanges()

        let verifyRes = db.execute("SELECT name FROM customers WHERE customer_id = 1;")
        XCTAssertEqual(verifyRes.rows.first?.first ?? nil, "Ada'); DROP TABLE customers; --Tail")
        let totalRows = db.execute("SELECT COUNT(*) FROM customers;").rows.first?.first ?? nil
        XCTAssertEqual(totalRows, "8", "Parameterized cell update must safely store literal payload without executing injected SQL")

        // 4. ANSIInputParser OSC Discard & Unterminated CSI Parameter DoS Bounds
        let parser = ANSIInputParser()
        // OSC title sequence followed by 'Z'
        let oscStream: [UInt8] = Array("\u{1B}]2;SpoofedTitle\u{07}Z".utf8)
        let oscEvents = parser.parse(oscStream)
        XCTAssertEqual(oscEvents, [.key(KeyEvent(.char("Z")))])

        // Oversized CSI sequence (> maxCSIParamBytes) without final byte
        let oversizedCSI: [UInt8] = [0x1B, UInt8(ascii: "[")] + Array(repeating: UInt8(ascii: "9"), count: 200)
        let csiEvents = parser.parse(oversizedCSI)
        XCTAssertFalse(csiEvents.isEmpty, "Oversized unterminated CSI must abort after maxCSIParamBytes without hanging")
    }

    // MARK: - 10. Phase 1 Extensions Tests (Grid, Picker, Stepper, Slider, Alert, ContextMenu, Toast, Markdown, Lifecycle)

    struct Phase1DemoView: View {
        @State var mode: String = "dark"
        @State var workers: Int = 4
        @State var gain: Double = 0.50
        @State var showAlert: Bool = false
        @State var showToast: Bool = true
        @State var appearCount: Int = 0
        @State var changeLog: String = ""

        var body: some View {
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sidebar Nav")
                    Markdown("# Guide\n- [x] `Grid` ready")
                }
            } detail: {
                VStack(alignment: .leading, spacing: 1) {
                    Grid(horizontalSpacing: 2, verticalSpacing: 0) {
                        GridRow {
                            Text("ColA")
                            Text("ColB")
                        }
                        GridRow {
                            Text("Val1")
                            Text("Val2")
                        }
                    }

                    Picker(
                        "Theme",
                        selection: $mode,
                        options: [
                            PickerOption("Dark", value: "dark"),
                            PickerOption("Light", value: "light")
                        ],
                        style: .segmented,
                        id: "pkr.demo"
                    )

                    Stepper("Threads", value: $workers, in: 1...16, id: "stp.demo")
                    Slider("Vol", value: $gain, in: 0.0...1.0, step: 0.10, trackWidth: 10, id: "sld.demo")
                    Text("Appeared: \(appearCount) Changed: \(changeLog)")
                }
                .onAppear {
                    appearCount += 1
                }
                .onChange(of: workers) { oldVal, newVal in
                    changeLog = "\(oldVal)->\(newVal)"
                }
            }
            .alert(
                "System Alert",
                isPresented: $showAlert,
                message: "Confirm action?",
                buttons: [.default("Confirm"), .cancel("Cancel")]
            )
            .toast(isPresented: $showToast, style: .success, message: "Toast Banner Active")
        }
    }

    func testPhase1ExtensionsGridPickerAlertMarkdownLifecycle() {
        let harness = TestHarness(rootView: Phase1DemoView(), width: 100, height: 24)
        // Re-render once so `@State` mutation from `onAppear` is reflected in the snapshot
        harness.render()

        // 1. Verify NavigationSplitView, Grid, and Markdown rendered
        XCTAssertTrue(harness.contains("Sidebar Nav"))
        XCTAssertTrue(harness.contains("◆ Guide"))
        XCTAssertTrue(harness.contains("[✓]"))
        XCTAssertTrue(harness.contains("ColA"))
        XCTAssertTrue(harness.contains("Val2"))
        XCTAssertTrue(harness.contains("Toast Banner Active"))
        XCTAssertTrue(harness.contains("Appeared: 1"))

        // 2. Test Picker (.segmented) keyboard interaction
        harness.activeFocusID = "pkr.demo"
        XCTAssertTrue(harness.contains("[● Dark]"))
        harness.sendKey(.right)
        XCTAssertTrue(harness.contains("[● Light]"))

        // 3. Test Stepper keyboard increment & .onChange hook
        harness.activeFocusID = "stp.demo"
        XCTAssertTrue(harness.contains("Threads: 4"))
        harness.sendKey(.right)
        harness.render()
        XCTAssertTrue(harness.contains("Threads: 5"))
        XCTAssertTrue(harness.contains("Changed: 4->5"))

        // 4. Test Slider keyboard stepping
        harness.activeFocusID = "sld.demo"
        XCTAssertTrue(harness.contains("50%"))
        harness.sendKey(.right)
        XCTAssertTrue(harness.contains("60%"))
    }

    // MARK: - 11. Category 5: Pixel Graphics & Image Protocol Encoders (Half-Block, Kitty, iTerm2 OSC 1337, Sixel)

    func testPixelGraphicsImageAndProtocolEncoders() {
        let bmp = PixelBitmap(width: 4, height: 2) { x, y in
            y == 0 ? PixelRGBA(r: 255, g: 80, b: 40) : PixelRGBA(r: 40, g: 160, b: 255)
        }

        // 1. Half-block 2x1 vertical sub-pixel rendering into Buffer
        let harness = TestHarness(rootView: Image(bitmap: bmp), width: 8, height: 2)
        XCTAssertEqual(harness.buffer.cell(atX: 0, y: 0)?.symbol, "▀")
        XCTAssertEqual(harness.buffer.cell(atX: 0, y: 0)?.fg, .rgb(255, 80, 40))
        XCTAssertEqual(harness.buffer.cell(atX: 0, y: 0)?.bg, .rgb(40, 160, 255))

        // 2. Kitty Graphics Protocol escape sequence encoding
        let kittySeq = bmp.encodeKittyEscapeSequence(columns: 4, rows: 1)
        XCTAssertTrue(kittySeq.hasPrefix("\u{1B}_Ga=T,f=32,s=4,v=2,c=4,r=1;"))
        XCTAssertTrue(kittySeq.hasSuffix("\u{1B}\\"))

        // 3. iTerm2 Inline Image (OSC 1337) escape sequence encoding
        let itermSeq = bmp.encodeITerm2EscapeSequence(columns: 4, rows: 1)
        XCTAssertTrue(itermSeq.hasPrefix("\u{1B}]1337;File=inline=1;preserveAspectRatio=1;width=4;height=1:"))
        XCTAssertTrue(itermSeq.hasSuffix("\u{07}"))

        // 4. DEC Sixel escape sequence encoding
        let sixelSeq = bmp.encodeSixelEscapeSequence()
        XCTAssertTrue(sixelSeq.hasPrefix("\u{1B}Pq\"1;1;4;2"))
        XCTAssertTrue(sixelSeq.hasSuffix("\u{1B}\\"))

        // 5. Terminal protocol auto-detection
        XCTAssertEqual(Image.detectTerminalProtocol(environment: ["KITTY_WINDOW_ID": "1"]), .kitty)
        XCTAssertEqual(Image.detectTerminalProtocol(environment: ["TERM_PROGRAM": "iTerm.app"]), .iterm2)
        XCTAssertEqual(Image.detectTerminalProtocol(environment: ["TERM": "xterm-sixel"]), .sixel)
        XCTAssertEqual(Image.detectTerminalProtocol(environment: [:]), .halfBlocks)
    }

    // MARK: - 12. Category 4: Terminal Protocols (OSC-52 System Clipboard & OSC-8 Clickable Hyperlinks)

    func testCategory4OSC52ClipboardAndOSC8Hyperlinks() {
        // 1. OSC-52 System Clipboard encoding (standard & tmux passthrough)
        let osc52 = TerminalClipboard.encodeOSC52WriteSequence("Hello, TUI!")
        XCTAssertEqual(osc52, "\u{1B}]52;c;SGVsbG8sIFRVSSH\u{07}".replacingOccurrences(of: "SGVsbG8sIFRVSSH", with: Data("Hello, TUI!".utf8).base64EncodedString()))

        let tmuxOsc52 = TerminalClipboard.encodeOSC52WriteSequence("tmux", isTmux: true)
        XCTAssertTrue(tmuxOsc52.hasPrefix("\u{1B}Ptmux;\u{1B}\u{1B}]52;c;"))
        XCTAssertTrue(tmuxOsc52.hasSuffix("\u{07}\u{1B}\\"))

        // 2. Link view rendering with OSC-8 cell metadata & DiffRenderer output
        let url = "https://github.com/bekironat/SwiftTUI"
        let harness = TestHarness(rootView: Link("SwiftTUI Docs", destination: url, id: "lnk.test"), width: 40, height: 2)
        XCTAssertTrue(harness.contains("SwiftTUI Docs"))
        XCTAssertEqual(harness.buffer.cell(atX: 0, y: 0)?.hyperlink, url)

        let diff = DiffRenderer(useSynchronizedOutput: false).render(previous: nil, current: harness.buffer)
        XCTAssertTrue(diff.contains("\u{1B}]8;;\(url)\u{1B}\\"))
        XCTAssertTrue(diff.contains("\u{1B}]8;;\u{1B}\\"))

        // 3. Activating focused Link copies URL via TerminalClipboard (OSC-52)
        harness.activeFocusID = "lnk.test"
        harness.sendKey(.enter)
        XCTAssertEqual(TerminalClipboard.shared.lastCopiedText, url)
    }

    // MARK: - 13. Spatial 2D Directional Panel Switching (Alt+Arrows, Ctrl+Arrows, Alt+hjkl)

    func testDirectionalSpatialFocusNavigationInSwiftGripAndGallery() throws {
        // 1. Verify ANSIInputParser decodes Alt+Arrows, Ctrl+Arrows, and Alt+hjkl
        let parser = ANSIInputParser()
        XCTAssertEqual(parser.parse(Array("\u{1B}[1;3C".utf8)), [.key(KeyEvent(.right, modifiers: [.alt]))])
        XCTAssertEqual(parser.parse(Array("\u{1B}[1;5B".utf8)), [.key(KeyEvent(.down, modifiers: [.control]))])
        XCTAssertEqual(parser.parse(Array("\u{1B}h".utf8)), [.key(KeyEvent(.char("h"), modifiers: [.alt]))])

        // 2. SwiftGrip 3-Pane IDE: Left (schemaTree) | Top-Right (sqlEditor) / Middle-Right (whereFilter) / Bottom-Right (dataGrid)
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: true)
        let gripVM = SwiftGripViewModel(database: db)
        let grip = TestHarness(rootView: SwiftGripMainView(viewModel: gripVM), width: 120, height: 34)

        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.schemaTree))

        // Left -> Right jumps from Database Explorer to top-right SQL Editor
        grip.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.sqlEditor))

        // Top -> Bottom jumps from SQL Editor -> WHERE filter -> Data Grid
        grip.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.whereFilter))

        grip.sendKey(.down, modifiers: [.control])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.dataGrid))

        // Bottom-Right -> Left jumps straight back to Database Explorer using Alt+h
        grip.sendKey(.char("h"), modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.schemaTree))

        // Pressing Alt+Left at the leftmost edge stays on schemaTree without leaking into Tree
        grip.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.schemaTree))

        // Reverse vertical climb using Alt+l, Alt+j, Alt+k
        grip.sendKey(.char("l"), modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.sqlEditor))
        grip.sendKey(.char("j"), modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.whereFilter))
        grip.sendKey(.char("j"), modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.dataGrid))
        grip.sendKey(.char("k"), modifiers: [.alt])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.whereFilter))
        grip.sendKey(.up, modifiers: [.control])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.sqlEditor))
        grip.sendKey(.left, modifiers: [.control])
        XCTAssertEqual(grip.activeFocusID, AnyHashable(SwiftGripViewModel.FocusTarget.schemaTree))

        // 3. SwiftTUIGallery: 2-Pane Split + Multi-Row/Column Controls
        let galleryVM = GalleryViewModel()
        galleryVM.selectedCategory = .typography
        let gallery = TestHarness(rootView: GalleryMainView(viewModel: galleryVM), width: 120, height: 34)

        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.sidebar.tree"))

        // Typography tab: Sidebar -> Link -> OSC-52 Button -> Link -> Sidebar
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("lnk.github"))
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("btn.osc52"))
        gallery.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("lnk.github"))
        gallery.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.sidebar.tree"))

        // Inputs tab: 2D grid of controls
        //   Row 1: btn.counter | btn.reset | tgl.notif | tgl.strict
        //   Row 2: pkr.theme   | stp.workers
        //   Row 3: sld.gain
        //   Row 4: txt.lang
        //   Row 5: txt.editor
        galleryVM.selectedCategory = .inputs
        gallery.activeFocusID = "gallery.sidebar.tree"

        // Right from sidebar lands on top-left control (btn.counter), then walks right across Row 1
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("btn.counter"))
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("btn.reset"))
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("tgl.notif"))

        // Down from tgl.notif lands directly on stp.workers (aligned below it), Left moves to pkr.theme
        gallery.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("stp.workers"))
        gallery.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("pkr.theme"))

        // Down walks pkr.theme -> sld.gain -> txt.lang -> txt.editor (even with autocomplete open on txt.lang!)
        gallery.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("sld.gain"))
        gallery.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("txt.lang"))
        gallery.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("txt.editor"))

        // Left from TextEditor jumps straight back to the sidebar (even inside a multi-line editor!)
        gallery.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.sidebar.tree"))

        // Tree & Table tab (VStack): Sidebar | Top: Project Navigator Tree / Bottom: Framework Comparison Table
        galleryVM.selectedCategory = .treeAndTable
        gallery.activeFocusID = "gallery.sidebar.tree"
        gallery.sendKey(.right, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.tree.preview"))
        gallery.sendKey(.down, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.table.preview"))
        gallery.sendKey(.up, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.tree.preview"))
        gallery.sendKey(.left, modifiers: [.alt])
        XCTAssertEqual(gallery.activeFocusID, AnyHashable("gallery.sidebar.tree"))
    }

    // MARK: - 14. Terminal Capabilities, Color Degradation, Styled Underlines, Cursor Shape, OSC 2/9;4 & Kitty Protocol

    func testTerminalCapabilitiesColorDegradationAndModernProtocols() {
        // 1. Capability detection
        let noColorCaps = TerminalCapabilities.detect(environment: ["NO_COLOR": "1", "COLORTERM": "truecolor"])
        XCTAssertEqual(noColorCaps.colorCapability, .none)

        let appleTermCaps = TerminalCapabilities.detect(environment: ["TERM_PROGRAM": "Apple_Terminal", "TERM": "xterm-256color"])
        XCTAssertEqual(appleTermCaps.colorCapability, .ansi256)
        XCTAssertFalse(appleTermCaps.supportsSynchronizedOutput)

        let ghosttyCaps = TerminalCapabilities.detect(environment: ["TERM_PROGRAM": "ghostty", "COLORTERM": "truecolor"])
        XCTAssertEqual(ghosttyCaps.colorCapability, .trueColor)
        XCTAssertTrue(ghosttyCaps.supportsKittyKeyboard)
        XCTAssertEqual(ghosttyCaps.preferredImageProtocol, .kitty)

        // 2. Color degradation (TrueColor -> ANSI-256 -> ANSI-16 -> None)
        let brightCoral = Color.rgb(255, 85, 85)
        XCTAssertEqual(brightCoral.degraded(to: .none), .default)
        if case .indexed(let idx) = brightCoral.degraded(to: .ansi256) {
            XCTAssertGreaterThanOrEqual(idx, 16)
        } else {
            XCTFail("Expected RGB to degrade to .indexed under .ansi256")
        }
        XCTAssertEqual(brightCoral.degraded(to: .ansi16), .brightRed)

        // 3. Styled & colored underlines (4:3 curly + 58;2;...) + CursorShape + OSC 2 + OSC 9;4
        var buf = Buffer(width: 20, height: 2)
        buf.windowTitle = "SwiftTUI App"
        buf.terminalProgress = .normal(75)
        buf.cursorPosition = Point(x: 2, y: 0)
        buf.cursorShape = .steadyBar
        buf.setCell(
            x: 0,
            y: 0,
            symbol: "E",
            style: CellStyle(fg: .brightRed, underlineColor: .rgb(255, 0, 0), underlineStyle: .curly, modifiers: [.underlined])
        )

        let ansi = DiffRenderer(useSynchronizedOutput: false, colorCapability: .trueColor).render(previous: nil, current: buf)
        XCTAssertTrue(ansi.contains("4:3"))
        XCTAssertTrue(ansi.contains("58;2;255;0;0"))
        XCTAssertTrue(ansi.contains("\u{1B}]2;SwiftTUI App\u{07}"))
        XCTAssertTrue(ansi.contains("\u{1B}]9;4;1;75\u{07}"))
        XCTAssertTrue(ansi.contains("\u{1B}[6 q"))

        // Under NO_COLOR, no RGB 38;2 sequences are emitted
        let monoAnsi = DiffRenderer(useSynchronizedOutput: false, colorCapability: .none).render(previous: nil, current: buf)
        XCTAssertFalse(monoAnsi.contains("38;2;"))

        // 4. Kitty keyboard protocol colon subparameters (key:shifted;mods:event_type u)
        let parser = ANSIInputParser()
        let releaseEvs = parser.parse(Array("\u{1B}[97;5:3u".utf8))
        XCTAssertEqual(releaseEvs, [.key(KeyEvent(.char("a"), modifiers: [.control], kind: .release))])

        let repeatEvs = parser.parse(Array("\u{1B}[97:65;2:2u".utf8))
        XCTAssertEqual(repeatEvs, [.key(KeyEvent(.char("A"), modifiers: [.shift], kind: .repeat))])

        // 5. Kitty Graphics 4096-byte chunking & Buffer passthrough
        let largeBmp = PixelBitmap(width: 40, height: 40) { x, y in
            PixelRGBA(r: UInt8(x * 6), g: UInt8(y * 6), b: 128)
        }
        let chunked = largeBmp.encodeKittyEscapeSequence(columns: 20, rows: 10, chunkSize: 1024)
        XCTAssertTrue(chunked.contains(",m=1;"))
        XCTAssertTrue(chunked.contains("\u{1B}_Gm=0;"))

        let imgHarness = TestHarness(rootView: Image(bitmap: PixelBitmap(width: 2, height: 2, fill: .white), protocol: .kitty), width: 10, height: 4)
        XCTAssertEqual(imgHarness.buffer.graphicsPlacements.count, 1)
        let imgDiff = DiffRenderer(useSynchronizedOutput: false).render(previous: nil, current: imgHarness.buffer)
        XCTAssertTrue(imgDiff.contains("\u{1B}_Ga=T,f=32"))
    }

    // MARK: - 15. Theme System & Enhanced UnicodeWidth

    func testThemeAndUnicodeWidthEnhancements() {
        struct ThemedLabel: View {
            @Environment(\.theme) var theme
            var body: some View {
                Text("Theme: \(theme.name)")
                    .foregroundStyle(theme.accent)
            }
        }

        let harness = TestHarness(rootView: ThemedLabel().theme(.catppuccinMocha), width: 32, height: 2)
        XCTAssertTrue(harness.contains("Theme: Catppuccin Mocha"))
        XCTAssertEqual(harness.buffer.cell(atX: 0, y: 0)?.fg, Theme.catppuccinMocha.accent)

        // Regional indicator flags, ZWJ emoji, and Hangul Jamo medial/final width
        XCTAssertEqual(UnicodeWidth.width(of: "🇺🇸"), 2)
        XCTAssertEqual(UnicodeWidth.width(of: "👨‍👩‍👧‍👦"), 2)
        XCTAssertEqual(UnicodeWidth.scalarWidth(Unicode.Scalar(0x1161)!), 0)

        // CJK spaceless wrapping
        let wrappedCJK = UnicodeWidth.wrap("日本語テスト文字列", maxWidth: 6)
        XCTAssertEqual(wrappedCJK.count, 3)
        XCTAssertTrue(wrappedCJK.allSatisfy { UnicodeWidth.width(of: $0) <= 6 })
    }

    // MARK: - 16. SecureField, SearchField (.searchable), ProgressView & TabView

    func testSecureFieldSearchFieldProgressViewAndTabView() {
        struct FormDemoView: View {
            @State var secret = ""
            @State var query = ""
            @State var submitted = false
            @State var selectedTab = "general"

            var body: some View {
                VStack(alignment: .leading, spacing: 1) {
                    SecureField("Enter API Key", text: $secret, id: "sec.field") {
                        submitted = true
                    }
                    Text("Len:\(secret.count) Sub:\(submitted ? "Y" : "N")")
                    ProgressView("Uploading", value: 0.5)
                    ProgressView("Connecting...")
                    TabView(
                        selection: $selectedTab,
                        id: "tab.demo",
                        tabs: [
                            TabItem(id: "general", title: "General") {
                                Text("General Settings Body").searchable(text: $query, prompt: "Filter settings...")
                            },
                            TabItem(id: "security", title: "Security") {
                                Text("Security Vault Body")
                            }
                        ]
                    )
                }
            }
        }

        let harness = TestHarness(rootView: FormDemoView(), width: 60, height: 14)

        // 1. SecureField masks typed text and does not leak plaintext into Buffer
        harness.activeFocusID = "sec.field"
        harness.type("s3cr3t")
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("••••••"))
        XCTAssertFalse(harness.contains("s3cr3t"))
        XCTAssertTrue(harness.contains("Len:6 Sub:Y"))

        // 2. ProgressView determinate & indeterminate
        XCTAssertTrue(harness.contains("Uploading 50%"))
        XCTAssertTrue(harness.contains("Connecting..."))

        // 3. TabView switches pane content
        XCTAssertTrue(harness.contains("General Settings Body"))
        XCTAssertTrue(harness.contains("🔍"))
        harness.activeFocusID = "tab.demo"
        harness.sendKey(.right)
        XCTAssertTrue(harness.contains("Security Vault Body"))
    }

    // MARK: - 17. CommandPalette, VirtualizedList (10,000 rows) & FilePicker

    func testCommandPaletteVirtualizedListAndFilePicker() throws {
        struct RowItem: Identifiable, Sendable {
            let id: Int
            let title: String
        }

        struct PaletteAndListView: View {
            @State var showPalette = false
            @State var lastExecuted = "none"
            @State var selectedID: Int? = 0
            @State var multiSelected: Set<Int> = []
            let items: [RowItem]

            var body: some View {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Executed: \(lastExecuted) Multi:\(multiSelected.count)")
                    VirtualizedList(
                        items,
                        selection: $selectedID,
                        multiSelection: $multiSelected,
                        focusID: "vlist.demo"
                    ) { item, isSelected in
                        Text("\(isSelected ? ">" : " ") #\(item.id) \(item.title)")
                    }
                }
                .commandPalette(
                    isPresented: $showPalette,
                    commands: [
                        CommandPaletteItem(title: "Toggle Theme", category: "View", shortcutHint: "⌘T") {
                            lastExecuted = "theme"
                        },
                        CommandPaletteItem(title: "Run Migration", category: "Database", shortcutHint: "⌘M") {
                            lastExecuted = "migrate"
                        },
                        CommandPaletteItem(title: "Export CSV", category: "Data") {
                            lastExecuted = "csv"
                        }
                    ]
                )
            }
        }

        // 1. VirtualizedList with 10,000 items renders instantaneously (only visible viewport rows)
        let tenThousand = (0..<10_000).map { RowItem(id: $0, title: "Row-\($0)") }
        let harness = TestHarness(rootView: PaletteAndListView(items: tenThousand), width: 64, height: 12)
        XCTAssertTrue(harness.contains("#0 Row-0"))
        XCTAssertFalse(harness.contains("#9999 Row-9999"))

        // Jump to end with End key and toggle multi-select with Space
        harness.activeFocusID = "vlist.demo"
        harness.sendKey(.end)
        harness.sendKey(.space)
        XCTAssertTrue(harness.contains("#9999 Row-9999"))
        XCTAssertTrue(harness.contains("Multi:1"))

        // 2. Open CommandPalette via Ctrl+P, fuzzy-filter "mig", press Enter
        harness.sendKey(.char("p"), modifiers: [.control])
        XCTAssertTrue(harness.contains("Command Palette"))
        XCTAssertTrue(harness.contains("Run Migration"))
        harness.type("mig")
        harness.sendKey(.enter)
        XCTAssertTrue(harness.contains("Executed: migrate"))

        // 3. FilePicker in a temporary directory
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftTUIFilePickerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let sampleFile = tmpDir.appendingPathComponent("schema.sql")
        let ignoredFile = tmpDir.appendingPathComponent("notes.txt")
        try "SELECT 1;".write(to: sampleFile, atomically: true, encoding: .utf8)
        try "ignore".write(to: ignoredFile, atomically: true, encoding: .utf8)

        let entries = FilePicker.listEntries(in: tmpDir, showHidden: false, allowedExtensions: ["sql"])
        XCTAssertTrue(entries.contains(where: { $0.name == "schema.sql" && !$0.isDirectory }))
        XCTAssertFalse(entries.contains(where: { $0.name == "notes.txt" }))

        var pickedURL: URL? = nil
        let pickerHarness = TestHarness(
            rootView: FilePicker(directory: tmpDir, allowedExtensions: ["sql"], id: "fp.demo") { url in
                pickedURL = url
            },
            width: 50,
            height: 8
        )
        XCTAssertTrue(pickerHarness.contains("schema.sql"))
        pickerHarness.activeFocusID = "fp.demo"
        // Row 0 is "..", Row 1 is "schema.sql"
        pickerHarness.sendKey(.down)
        pickerHarness.sendKey(.enter)
        XCTAssertEqual(pickedURL?.lastPathComponent, "schema.sql")
    }

    // MARK: - 18. Security, Stability & Performance Regression Suite

    func testSecurityStabilityAndPerformanceHardening() throws {
        // 1. Stateful ANSIInputParser: split bracketed paste (including split ESC[201~ end marker) must NEVER leak raw keypresses
        let parser = ANSIInputParser()
        let chunk1 = Array("\u{1B}[200~SELECT 1;".utf8)
        let chunk2 = Array(" DROP TABLE x;\u{1B}[20".utf8)
        let chunk3 = Array("1~a".utf8)
        XCTAssertTrue(parser.parse(chunk1).isEmpty, "Unfinished bracketed paste must buffer rather than emit keypresses")
        XCTAssertTrue(parser.parse(chunk2).isEmpty, "Split end marker must stay buffered")
        let finalEvents = parser.parse(chunk3)
        XCTAssertEqual(finalEvents, [.paste("SELECT 1; DROP TABLE x;"), .key(KeyEvent(.char("a")))])

        // 2. Stateful ANSIInputParser: split multi-byte UTF-8 sequence ("🚀" = F0 9F 9A 80)
        let rocketBytes = Array("🚀".utf8)
        XCTAssertEqual(rocketBytes.count, 4)
        XCTAssertTrue(parser.parse(Array(rocketBytes[0..<2])).isEmpty)
        let rocketEvents = parser.parse(Array(rocketBytes[2..<4]))
        XCTAssertEqual(rocketEvents, [.key(KeyEvent(.char("🚀")))])

        // 3. Cell post-init mutation sanitization invariant
        var cell = Cell(symbol: "A")
        cell.symbol = "\u{1B}[31m"
        XCTAssertFalse(cell.symbol.contains("\u{1B}"))
        cell.hyperlink = "https://ok.dev/\u{1B}]52;c;xx\u{07}"
        XCTAssertFalse(cell.hyperlink?.contains("\u{1B}") ?? true)
        XCTAssertFalse(cell.hyperlink?.contains("\u{07}") ?? true)

        // 4. OSC-8 label sanitization & OSC-52 payload cap
        let safeLink = TerminalClipboard.encodeOSC8Hyperlink(label: "Click\u{1B}[31mMe", url: "https://example.com")
        XCTAssertFalse(safeLink.contains("\u{1B}[31m"))
        let hugePayload = String(repeating: "A", count: 120_000)
        let cappedOSC52 = TerminalClipboard.encodeOSC52WriteSequence(hugePayload)
        // Base64 of 74,994 bytes is ~99,992 bytes + framing
        XCTAssertLessThan(cappedOSC52.utf8.count, 101_000)

        // 5. Buffer.flushOverlays() recursion guard terminates cleanly
        var overlayBuf = Buffer(width: 10, height: 4)
        var overlayPasses = 0
        func enqueueRecursive(_ buf: inout Buffer) {
            buf.addOverlay(zIndex: 10) { inner in
                overlayPasses += 1
                enqueueRecursive(&inner)
            }
        }
        enqueueRecursive(&overlayBuf)
        overlayBuf.flushOverlays()
        XCTAssertEqual(overlayPasses, 8)

        // 6. DiffRenderer no-op identical frame returns empty string (0 bytes written)
        var frameA = Buffer(width: 20, height: 4)
        frameA.writeString(x: 0, y: 0, "Static Frame")
        let frameB = frameA
        _ = TerminalClipboard.shared.drainPendingOSC52Sequence()
        let emptyDiff = DiffRenderer(useSynchronizedOutput: true).render(previous: frameA, current: frameB)
        XCTAssertEqual(emptyDiff, "")

        // 7. HSplitView multi-step mouse drag persists across re-renders
        let splitHarness = TestHarness(
            rootView: HSplitView(initialLeftRatio: 0.25, minLeftWidth: 10, minRightWidth: 10, showDivider: true) {
                Text("LeftPane")
            } right: {
                Text("RightPane")
            },
            width: 80,
            height: 10
        )
        // Initial divider is around x = 20
        splitHarness.application.handleEvent(.mouse(MouseEvent(kind: .down(.left), x: 20, y: 3)))
        splitHarness.application.handleEvent(.mouse(MouseEvent(kind: .drag(.left), x: 30, y: 3)))
        splitHarness.application.handleEvent(.mouse(MouseEvent(kind: .drag(.left), x: 40, y: 3)))
        splitHarness.application.handleEvent(.mouse(MouseEvent(kind: .up(.left), x: 40, y: 3)))
        // Divider should have moved to x = 40
        XCTAssertEqual(splitHarness.buffer.cell(atX: 40, y: 3)?.symbol, "│")

        // 8. StateStore evicts dead state after unmounting a view
        struct DynamicChild: View {
            @State var secretCounter = 42
            var body: some View { Text("Child:\(secretCounter)") }
        }
        struct LeakHostView: View {
            @State var showChild = true
            var body: some View {
                VStack {
                    Button("Toggle", id: "btn.toggle") { showChild.toggle() }
                    if showChild {
                        DynamicChild()
                    }
                }
            }
        }
        let leakHarness = TestHarness(rootView: LeakHostView(), width: 30, height: 5)
        let countWithChild = leakHarness.application.store.retainedValueCount
        leakHarness.activeFocusID = "btn.toggle"
        leakHarness.sendKey(.enter) // hides child (frame 1 without child)
        leakHarness.render()        // frame 2 without child -> evicts dead key
        let countWithoutChild = leakHarness.application.store.retainedValueCount
        XCTAssertLessThan(countWithoutChild, countWithChild)

        // 9. AnimationDriver repeatCount/autoreverses & Color.indexed RGB lookup
        let red256 = Color.indexed(196).rgbComponents
        XCTAssertEqual(red256.r, 255)
        XCTAssertEqual(red256.g, 0)
        XCTAssertEqual(red256.b, 0)

        var lastProg = -1.0
        var didComplete = false
        let driver = AnimationDriver.shared
        driver.cancelAll()
        let animID = AnyHashable("test.repeat")
        let now = Date().timeIntervalSinceReferenceDate
        driver.addAnimation(
            id: animID,
            animation: Animation.linear(duration: 1.0).repeatCount(2, autoreverses: true),
            update: { p in lastProg = p },
            completion: { didComplete = true }
        )
        driver.tick(now: now + 1.5) // halfway through reverse second cycle -> ~0.5
        XCTAssertFalse(didComplete)
        XCTAssertEqual(lastProg, 0.5, accuracy: 0.05)
        driver.tick(now: now + 2.1) // completed 2 autoreversing cycles -> 0.0
        XCTAssertTrue(didComplete)
        XCTAssertEqual(lastProg, 0.0, accuracy: 0.01)

        // 10. SQLiteDatabase row limit & safe BLOB formatting
        let db = try SQLiteDatabase(path: ":memory:", seedDemoIfEmpty: false)
        db.maxResultRows = 25
        _ = db.execute("CREATE TABLE blobs (id INTEGER, data BLOB);")
        _ = db.execute("INSERT INTO blobs VALUES (1, X'DEADBEEF');")
        let blobRes = db.execute("SELECT data FROM blobs;")
        XCTAssertEqual(blobRes.rows.first?.first ?? nil, "<BLOB 4 bytes>")

        let cteRes = db.execute("WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x < 500) SELECT x FROM cnt;")
        XCTAssertEqual(cteRes.rows.count, 25)
    }
}
