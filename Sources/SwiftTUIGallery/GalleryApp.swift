import Foundation
import Observation
import SwiftTUI

// MARK: - Gallery View Model

public enum GalleryCategory: String, CaseIterable, Identifiable, Sendable {
    case typography = "Typography & Borders"
    case layout = "Layout & Containers"
    case inputs = "Inputs & Autocomplete"
    case treeAndTable = "Tree & Table"
    case charts = "Charts & Gauges"
    case modals = "Modals & Overlays"
    case navigation = "Navigation & Animations"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .typography:   return "🔤"
        case .layout:       return "📐"
        case .inputs:       return "⌨️"
        case .treeAndTable: return "📊"
        case .charts:       return "📈"
        case .modals:       return "🪟"
        case .navigation:   return "🧭"
        }
    }
}

@Observable
@MainActor
public final class GalleryViewModel {
    public var selectedCategory: GalleryCategory = .typography

    // Typography & Borders state
    public var borderStyleIndex: Int = 1 // 0: plain, 1: rounded, 2: double, 3: thick, 4: ascii

    // Inputs state
    public var buttonClickCount: Int = 0
    public var toggleA: Bool = true
    public var toggleB: Bool = false
    public var textFieldValue: String = "Swift"
    public var textEditorValue: String = """
    // SwiftTUI Multi-Line Code Editor
    struct Greeting: View {
        var body: some View {
            Text("Hello, Terminal!")
                .foregroundStyle(.brightCyan)
                .bold()
        }
    }
    """

    // Tree & Table state
    public var selectedTreeID: String? = "src:core"
    public var tableSelectedRow: Int = 1
    public var tableSelectedCol: Int = 1
    public var tableSortCol: Int? = 0
    public var tableSortAsc: Bool = true
    public var stagedTableEdits: [TableCellCoordinate: String?] = [:]

    // Charts state
    public var gaugeValueA: Double = 0.42
    public var gaugeValueB: Double = 0.88
    public var sparklineDataA: [Double] = [12, 19, 3, 5, 2, 3, 20, 33, 25, 40, 35, 48, 55, 60]
    public var sparklineDataB: [Double] = [45, 42, 38, 50, 48, 52, 60, 58, 62, 70, 65, 75, 80]
    public var barChartVertical: [BarChartItem] = [
        BarChartItem("Web", value: 68, color: .brightCyan),
        BarChartItem("API", value: 92, color: .brightGreen),
        BarChartItem("DB", value: 45, color: .brightYellow),
        BarChartItem("Cache", value: 83, color: .brightMagenta),
        BarChartItem("Queue", value: 31, color: .brightRed)
    ]
    public var barChartHorizontal: [BarChartItem] = [
        BarChartItem("Swift 6", value: 98, color: .brightCyan),
        BarChartItem("Rust", value: 95, color: .brightGreen),
        BarChartItem("Go", value: 88, color: .brightYellow),
        BarChartItem("C++", value: 82, color: .brightMagenta),
        BarChartItem("Python", value: 64, color: .brightRed)
    ]
    public var spinnerFrame: Int = 3

    // Modals state
    public var isSheetPresented: Bool = false

    // Navigation & Animations state
    public var activeTransitionTab: String = "slide"
    public var springTargetProgress: Double = 0.72

    public init() {}

    public func randomizeCharts() {
        sparklineDataA = (0..<16).map { _ in Double.random(in: 2...80) }
        sparklineDataB = (0..<16).map { _ in Double.random(in: 10...95) }
        gaugeValueA = Double.random(in: 0.1...0.99)
        gaugeValueB = Double.random(in: 0.1...0.99)
        barChartVertical = [
            BarChartItem("Web", value: Double.random(in: 20...99), color: .brightCyan),
            BarChartItem("API", value: Double.random(in: 20...99), color: .brightGreen),
            BarChartItem("DB", value: Double.random(in: 20...99), color: .brightYellow),
            BarChartItem("Cache", value: Double.random(in: 20...99), color: .brightMagenta),
            BarChartItem("Queue", value: Double.random(in: 10...90), color: .brightRed)
        ]
        barChartHorizontal = [
            BarChartItem("Swift 6", value: Double.random(in: 50...100), color: .brightCyan),
            BarChartItem("Rust", value: Double.random(in: 50...100), color: .brightGreen),
            BarChartItem("Go", value: Double.random(in: 40...95), color: .brightYellow),
            BarChartItem("C++", value: Double.random(in: 40...90), color: .brightMagenta),
            BarChartItem("Python", value: Double.random(in: 30...85), color: .brightRed)
        ]
        spinnerFrame += 1
    }
}

// MARK: - Gallery Main View

public struct GalleryMainView: View {
    public let viewModel: GalleryViewModel

    public init(viewModel: GalleryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            headerBar

            // 2-Pane Split: Navigation Sidebar on Left, Component Preview on Right
            HSplitView(
                initialLeftRatio: 0.28,
                minLeftWidth: 26,
                minRightWidth: 50,
                showDivider: false
            ) {
                categorySidebar
            } right: {
                contentPane
            }
            .frame(maxWidth: ProposedViewSize.infinityDimension, maxHeight: ProposedViewSize.infinityDimension)

            // Bottom Status / Navigation Footer
            footerBar
        }
        .keyboardShortcut("1", modifiers: [.control]) { viewModel.selectedCategory = .typography }
        .keyboardShortcut("2", modifiers: [.control]) { viewModel.selectedCategory = .layout }
        .keyboardShortcut("3", modifiers: [.control]) { viewModel.selectedCategory = .inputs }
        .keyboardShortcut("4", modifiers: [.control]) { viewModel.selectedCategory = .treeAndTable }
        .keyboardShortcut("5", modifiers: [.control]) { viewModel.selectedCategory = .charts }
        .keyboardShortcut("6", modifiers: [.control]) { viewModel.selectedCategory = .modals }
        .keyboardShortcut("7", modifiers: [.control]) { viewModel.selectedCategory = .navigation }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isSheetPresented },
                set: { viewModel.isSheetPresented = $0 }
            ),
            title: "Modal Sheet Component (.sheet)",
            width: 56,
            height: 12
        ) {
            modalSheetContent
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 1) {
            Text(" 🌟 SwiftTUI Component Catalog ")
                .bold()
                .foregroundStyle(.black)
                .background(.brightCyan)

            Text("Interactive Preview & Dogfooding")
                .foregroundStyle(.brightYellow)

            Spacer()

            Text("Ctrl+1..7: Switch | Tab: Focus | ^Q: Quit ")
                .foregroundStyle(.brightBlack)
        }
        .background(Color.rgb(20, 24, 38))
        .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)
    }

    @ViewBuilder
    private var categorySidebar: some View {
        let treeRoots: [TreeNode] = [
            TreeNode(
                id: "root:gallery",
                label: "All Components",
                icon: "📦",
                iconColor: .brightYellow,
                isInitiallyExpanded: true,
                children: GalleryCategory.allCases.map { cat in
                    TreeNode(
                        id: "cat:\(cat.rawValue)",
                        label: cat.rawValue,
                        icon: cat.icon,
                        iconColor: (viewModel.selectedCategory == cat) ? .brightCyan : .white
                    )
                }
            )
        ]

        Tree(
            roots: treeRoots,
            selection: Binding(
                get: { "cat:\(viewModel.selectedCategory.rawValue)" },
                set: { newID in
                    guard let id = newID, id.hasPrefix("cat:") else { return }
                    let raw = String(id.dropFirst(4))
                    if let cat = GalleryCategory(rawValue: raw) {
                        viewModel.selectedCategory = cat
                    }
                }
            ),
            id: "gallery.sidebar.tree",
            onActivate: { node in
                guard node.id.hasPrefix("cat:") else { return }
                let raw = String(node.id.dropFirst(4))
                if let cat = GalleryCategory(rawValue: raw) {
                    viewModel.selectedCategory = cat
                }
            }
        )
        .frame(maxWidth: ProposedViewSize.infinityDimension, maxHeight: ProposedViewSize.infinityDimension)
        .border(
            .rounded,
            color: .brightCyan,
            background: Color.rgb(18, 20, 32),
            title: "Component Categories",
            titleColor: .brightCyan,
            bottomTitle: "↑↓:Select  ↵:Switch"
        )
    }

    @ViewBuilder
    private var contentPane: some View {
        TransitionContainer(transition: .slide, activeID: viewModel.selectedCategory) {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.selectedCategory {
                case .typography:
                    typographyPreview
                case .layout:
                    layoutPreview
                case .inputs:
                    inputsPreview
                case .treeAndTable:
                    treeAndTablePreview
                case .charts:
                    chartsPreview
                case .modals:
                    modalsPreview
                case .navigation:
                    navigationPreview
                }
            }
        }
        .frame(maxWidth: ProposedViewSize.infinityDimension, maxHeight: ProposedViewSize.infinityDimension)
        .border(
            .rounded,
            color: .brightBlue,
            background: Color.rgb(16, 18, 28),
            title: "Preview: \(viewModel.selectedCategory.icon) \(viewModel.selectedCategory.rawValue)",
            titleColor: .brightBlue,
            bottomTitle: "SwiftTUI View Engine"
        )
    }

    // MARK: - Category Preview Pages

    @ViewBuilder
    private var typographyPreview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                Text("1. Text Formatting & Modifiers")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 2) {
                    Text("Regular Text")
                    Text("Bold Text").bold()
                    Text("Italic Text").italic()
                    Text("Underlined").underline()
                    Text("Dimmed Text").dim()
                }

                HStack(spacing: 2) {
                    Text("Combined: ").dim()
                    Text("Bold + Underline + Color")
                        .bold()
                        .underline()
                        .foregroundStyle(.brightMagenta)
                        .background(Color.rgb(35, 25, 50))
                }

                Divider()

                Text("2. Text Concatenation (Text + Text)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                (Text("Prefix [")
                    .foregroundStyle(.brightBlack)
                 + Text("SUCCESS")
                    .bold()
                    .foregroundStyle(.brightGreen)
                 + Text("] Finished in ")
                    .foregroundStyle(.white)
                 + Text("1.42 ms")
                    .foregroundStyle(.brightCyan)
                    .italic())

                Divider()

                Text("3. Ratatui Box Border Styles")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 1) {
                    Text("Plain")
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(.plain, color: .white, title: "Plain")

                    Text("Rounded")
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(.rounded, color: .brightCyan, title: "Rounded")

                    Text("Double")
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(.double, color: .brightGreen, title: "Double")

                    Text("Thick")
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(.thick, color: .orange, title: "Thick")

                    Text("ASCII")
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(.ascii, color: .brightMagenta, title: "ASCII")
                }

                Divider()

                Text("4. Color Palette & Background Fills")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 1) {
                    Text(" Red ").background(.red).foregroundStyle(.white).bold()
                    Text(" Green ").background(.green).foregroundStyle(.black).bold()
                    Text(" Yellow ").background(.yellow).foregroundStyle(.black).bold()
                    Text(" Blue ").background(.blue).foregroundStyle(.white).bold()
                    Text(" Magenta ").background(.magenta).foregroundStyle(.white).bold()
                    Text(" Cyan ").background(.cyan).foregroundStyle(.black).bold()
                    Text(" TrueColor RGB ").background(Color.rgb(120, 80, 220)).foregroundStyle(.brightWhite).bold()
                }
            }
            .padding(1)
        }
    }

    @ViewBuilder
    private var layoutPreview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                Text("1. HStack & VStack Alignment + Spacing")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(alignment: .center, spacing: 2) {
                    Text("Item 1")
                        .padding(.horizontal, 1)
                        .border(.rounded, color: .brightCyan)

                    Text("Item 2 (Tall)\nLine 2")
                        .padding(.horizontal, 1)
                        .border(.rounded, color: .brightGreen)

                    Text("Item 3")
                        .padding(.horizontal, 1)
                        .border(.rounded, color: .brightYellow)

                    Spacer()

                    Text("Right Aligned (via Spacer)")
                        .foregroundStyle(.brightBlack)
                }

                Divider()

                Text("2. ZStack (Layered Views)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                ZStack(alignment: .center) {
                    Text(String(repeating: "░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░\n", count: 3))
                        .foregroundStyle(.brightBlack)

                    Text(" Centered in ZStack Overlay ")
                        .bold()
                        .foregroundStyle(.black)
                        .background(.brightYellow)
                }
                .border(.plain, color: .brightBlack)

                Divider()

                Text("3. GeometryReader (Live Dimensions)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Text("📐 Current Container Frame: \(proxy.size.width) cols × \(proxy.size.height) rows")
                            .bold()
                            .foregroundStyle(.brightCyan)
                        Text("(Origin: \(proxy.frame.origin.x), \(proxy.frame.origin.y))")
                            .foregroundStyle(.brightBlack)
                    }
                    .padding(1)
                    .border(.rounded, color: .brightCyan, title: "GeometryReader")
                }
                .frame(maxHeight: 3)
            }
            .padding(1)
        }
    }

    @ViewBuilder
    private var inputsPreview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                Text("1. Buttons & Reactive Toggles")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 2) {
                    Button("Clicked: \(viewModel.buttonClickCount) times", id: "btn.counter", color: .brightGreen) {
                        viewModel.buttonClickCount += 1
                    }

                    Button("Reset Count", id: "btn.reset", color: .brightRed) {
                        viewModel.buttonClickCount = 0
                    }

                    Toggle("Enable Notifications", isOn: Binding(
                        get: { viewModel.toggleA },
                        set: { viewModel.toggleA = $0 }
                    ), id: "tgl.notif")

                    Toggle("Strict Mode", isOn: Binding(
                        get: { viewModel.toggleB },
                        set: { viewModel.toggleB = $0 }
                    ), id: "tgl.strict")
                }

                Divider()

                Text("2. Single-Line TextField with Autocomplete (.autocomplete)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                Text("Type here or press Ctrl+Space for autocomplete suggestions:")
                    .dim()

                let keywords = ["Swift", "SwiftTUI", "SwiftUI", "Rust", "Ratatui", "Python", "Go", "WebAssembly"]
                TextField("Type language...", text: Binding(
                    get: { viewModel.textFieldValue },
                    set: { viewModel.textFieldValue = $0 }
                ), id: "txt.lang")
                .autocomplete { ctx in
                    keywords
                        .filter { $0.lowercased().hasPrefix(ctx.prefix.lowercased()) }
                        .map { AutocompleteItem(label: $0, insertText: "\($0) ", kind: .keyword, detail: "Language") }
                }
                .border(.rounded, color: .brightCyan, title: "TextField")

                Divider()

                Text("3. Multi-Line TextEditor with Line Numbers & Syntax Highlighting")
                    .bold()
                    .foregroundStyle(.brightYellow)

                TextEditor(
                    text: Binding(
                        get: { viewModel.textEditorValue },
                        set: { viewModel.textEditorValue = $0 }
                    ),
                    id: "txt.editor",
                    showsLineNumbers: true,
                    syntaxHighlighter: { line in
                        let kw = ["struct", "var", "some", "import", "func"]
                        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
                        return parts.map { part in
                            if kw.contains(String(part)) {
                                return StyledSpan(String(part) + " ", style: CellStyle(fg: .orange, modifiers: [.bold]))
                            } else if part.hasPrefix("\"") {
                                return StyledSpan(String(part) + " ", style: CellStyle(fg: .brightGreen))
                            }
                            return StyledSpan(String(part) + " ", style: CellStyle(fg: .white))
                        }
                    }
                )
                .frame(maxHeight: 7)
                .border(.rounded, color: .brightBlue, title: "TextEditor (Line Numbers + Syntax)")
            }
            .padding(1)
        }
    }

    @ViewBuilder
    private var treeAndTablePreview: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("1. Hierarchical Tree Component")
                .bold()
                .foregroundStyle(.brightYellow)

            let projectTree: [TreeNode] = [
                TreeNode(
                    id: "src:root",
                    label: "Sources",
                    icon: "📁",
                    iconColor: .brightCyan,
                    isInitiallyExpanded: true,
                    children: [
                        TreeNode(
                            id: "src:core",
                            label: "Core",
                            icon: "📁",
                            iconColor: .brightYellow,
                            isInitiallyExpanded: true,
                            children: [
                                TreeNode(id: "src:geom", label: "Geometry.swift", icon: "📄", iconColor: .white, detail: "180 lines"),
                                TreeNode(id: "src:style", label: "Style.swift", icon: "📄", iconColor: .white, detail: "240 lines"),
                                TreeNode(id: "src:width", label: "UnicodeWidth.swift", icon: "📄", iconColor: .white, detail: "195 lines")
                            ]
                        ),
                        TreeNode(
                            id: "src:render",
                            label: "Rendering",
                            icon: "📁",
                            iconColor: .brightGreen,
                            children: [
                                TreeNode(id: "src:buf", label: "Buffer.swift", icon: "📄", iconColor: .white),
                                TreeNode(id: "src:diff", label: "DiffRenderer.swift", icon: "📄", iconColor: .white)
                            ]
                        )
                    ]
                )
            ]

            Tree(
                roots: projectTree,
                selection: Binding(
                    get: { viewModel.selectedTreeID },
                    set: { viewModel.selectedTreeID = $0 }
                ),
                id: "gallery.tree.preview"
            )
            .frame(maxHeight: 6)
            .border(.rounded, color: .brightCyan, title: "Project Navigator Tree", bottomTitle: "Space/↵: Toggle")

            Divider()

            Text("2. Virtualized 2D Table with Sorting & Inline Cell Editing")
                .bold()
                .foregroundStyle(.brightYellow)

            let tableCols: [TableColumn] = [
                TableColumn(id: "id", title: "ID", isPrimaryKey: true, minWidth: 4, maxWidth: 6, alignment: .trailing),
                TableColumn(id: "name", title: "Framework", minWidth: 12, maxWidth: 16),
                TableColumn(id: "lang", title: "Language", minWidth: 10, maxWidth: 12),
                TableColumn(id: "paradigm", title: "Paradigm", minWidth: 14, maxWidth: 18),
                TableColumn(id: "stars", title: "Rating", minWidth: 8, maxWidth: 10, alignment: .trailing)
            ]

            let tableRows: [[String?]] = [
                ["1", "SwiftTUI", "Swift 6", "Declarative (SwiftUI)", "★★★★★"],
                ["2", "Ratatui", "Rust", "Immediate Buffer", "★★★★★"],
                ["3", "Bubbletea", "Go", "Elm Architecture", "★★★★☆"],
                ["4", "Textual", "Python", "Widget Tree (DOM)", "★★★★☆"],
                ["5", "Ink", "TypeScript", "React for CLI", "★★★★☆"]
            ]

            Table(
                columns: tableCols,
                rows: tableRows,
                selectedRow: Binding(
                    get: { viewModel.tableSelectedRow },
                    set: { viewModel.tableSelectedRow = $0 }
                ),
                selectedColumn: Binding(
                    get: { viewModel.tableSelectedCol },
                    set: { viewModel.tableSelectedCol = $0 }
                ),
                id: "gallery.table.preview",
                sortColumnIndex: viewModel.tableSortCol,
                sortAscending: viewModel.tableSortAsc,
                stagedEdits: viewModel.stagedTableEdits,
                onSortColumn: { col in
                    if viewModel.tableSortCol == col {
                        viewModel.tableSortAsc.toggle()
                    } else {
                        viewModel.tableSortCol = col
                        viewModel.tableSortAsc = true
                    }
                },
                onCommitCellEdit: { row, col, newVal in
                    viewModel.stagedTableEdits[TableCellCoordinate(row: row, column: col)] = newVal
                }
            )
            .border(.rounded, color: .brightGreen, title: "Framework Comparison Table", bottomTitle: "s:Sort  ↵/e:Edit Cell")
        }
        .padding(1)
    }

    @ViewBuilder
    private var chartsPreview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                // Header with Randomize button
                HStack(spacing: 2) {
                    Text("Visualization & Graphics Suite (Ratatui & Bubble Tea Parity)")
                        .bold()
                        .foregroundStyle(.brightYellow)

                    Spacer()

                    Button("🎲 Randomize All", id: "btn.rand", color: .brightMagenta) {
                        viewModel.randomizeCharts()
                    }
                }

                // 1. Gauges & Sparklines side-by-side in one compact row
                HStack(spacing: 3) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("1. Gauges (ProgressView)").bold().foregroundStyle(.brightCyan)
                        Gauge("CPU", value: viewModel.gaugeValueA, color: .brightGreen)
                        Gauge("RAM", value: viewModel.gaugeValueB, color: .brightRed)
                    }
                    .frame(maxWidth: 40)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("2. Sparklines (Block Levels)").bold().foregroundStyle(.brightYellow)
                        HStack(spacing: 1) {
                            Text("Disk:").foregroundStyle(.brightCyan).bold()
                            Sparkline(viewModel.sparklineDataA, color: .brightCyan)
                                .frame(maxWidth: 24, minHeight: 1, maxHeight: 1)
                        }
                        HStack(spacing: 1) {
                            Text("Net: ").foregroundStyle(.brightYellow).bold()
                            Sparkline(viewModel.sparklineDataB, color: .brightYellow)
                                .frame(maxWidth: 24, minHeight: 1, maxHeight: 1)
                        }
                    }
                }

                Divider()

                // 2. Animated Spinners (Bubble Tea Parity)
                HStack(spacing: 2) {
                    Text("3. Activity Spinners:").bold().foregroundStyle(.brightYellow)
                    Spinner("Deploying...", style: .dots, frame: viewModel.spinnerFrame, color: .brightCyan)
                    Spinner("Syncing...", style: .pulse, frame: viewModel.spinnerFrame, color: .brightGreen)
                    Spinner("Compiling...", style: .arc, frame: viewModel.spinnerFrame, color: .brightYellow)
                    Spinner("Buffering...", style: .meter, frame: viewModel.spinnerFrame, color: .brightMagenta)
                }

                Divider()

                // 3. Bar Charts (Ratatui BarChart Parity)
                HStack(spacing: 2) {
                    BarChart(
                        viewModel.barChartVertical,
                        orientation: .vertical,
                        barWidth: 4,
                        barGap: 2,
                        defaultColor: .brightCyan
                    )
                    .frame(maxWidth: 38, minHeight: 6, maxHeight: 6)
                    .border(.rounded, color: .brightCyan, title: "Vertical Bars", bottomTitle: "1/8th Blocks")

                    BarChart(
                        viewModel.barChartHorizontal,
                        orientation: .horizontal,
                        defaultColor: .brightGreen
                    )
                    .frame(minHeight: 6, maxHeight: 6)
                    .border(.rounded, color: .brightGreen, title: "Horizontal Bars", bottomTitle: "Sub-Char Precision")
                }

                Divider()

                // 4. Sub-Pixel Braille Canvas (Ratatui Canvas Parity)
                VStack(alignment: .leading, spacing: 0) {
                    Text("5. Sub-Pixel Braille Canvas (U+2800..U+28FF, 2×4 Dots Per Cell)")
                        .bold()
                        .foregroundStyle(.brightYellow)

                    Canvas(height: 6) { ctx in
                        // Draw dual trigonometric sine & cosine waves
                        ctx.drawFunction(color: .brightCyan) { t in
                            (sin(t * Double.pi * 3.0) + 1.0) / 2.0
                        }
                        ctx.drawFunction(color: .brightMagenta) { t in
                            (cos(t * Double.pi * 2.5) + 1.0) / 2.0
                        }
                        // Draw geometric shapes on right side of canvas
                        let w = ctx.pixelWidth
                        let h = ctx.pixelHeight
                        if w > 40 && h > 12 {
                            ctx.drawCircle(centerX: w - 24, centerY: h / 2, radius: 7, color: .brightGreen)
                            ctx.drawRect(x: w - 12, y: 3, width: 8, height: h - 6, color: .brightYellow)
                        }
                    }
                    .border(.rounded, color: .brightMagenta, title: "Waveform & Shape Synthesis", bottomTitle: "f(t) = sin(3πt) & cos(2.5πt)")
                }
            }
            .padding(1)
        }
    }

    @ViewBuilder
    private var modalsPreview: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("1. Modal Sheets (.sheet)")
                .bold()
                .foregroundStyle(.brightYellow)

            Text("SwiftTUI supports true floating modal sheets rendered via deferred overlay passes.")
                .dim()

            Button("Open Demo Sheet Dialog", id: "btn.sheet", color: .brightCyan) {
                viewModel.isSheetPresented = true
            }

            Divider()

            Text("2. Top-Level Overlays & Scissor Clipping")
                .bold()
                .foregroundStyle(.brightYellow)

            Text("Overlays bypass nested clipping bounds to draw popups and sheets across split panes cleanly.")
                .foregroundStyle(.white)

            HStack(spacing: 2) {
                Text("• Double-border modal chrome (╔═╗)")
                    .foregroundStyle(.brightCyan)
                Text("• TrueColor dark backdrop dimming")
                    .foregroundStyle(.brightGreen)
                Text("• Esc & @Environment(\\.dismiss)")
                    .foregroundStyle(.brightMagenta)
            }

            Spacer()
        }
        .padding(1)
    }

    @ViewBuilder
    private var navigationPreview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 1) {
                Text("1. Hierarchical Navigation (NavigationStack & NavigationLink)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                NavigationStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Root System Hub — Select a destination below (Enter to push, Esc to pop):")
                            .dim()

                        HStack(spacing: 3) {
                            NavigationLink("Cluster Nodes", id: "nav.cluster") {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Cluster Topology: 3 Active Nodes (us-east, eu-central, ap-south)")
                                        .bold()
                                        .foregroundStyle(.brightGreen)
                                    Gauge("Cluster Load", value: 0.64, color: .brightCyan)
                                        .frame(maxWidth: 42)
                                    NavigationLink("Inspect Primary Node #1", id: "nav.node1") {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("Node #1 (us-east-primary) — Uptime: 99.998% • Latency: 0.8ms")
                                                .bold()
                                                .foregroundStyle(.brightYellow)
                                            Sparkline([12, 15, 11, 14, 18, 13, 16, 12, 19, 14], color: .brightGreen)
                                                .frame(maxWidth: 32, minHeight: 1, maxHeight: 1)
                                        }
                                        .navigationTitle("Node #1")
                                    }
                                }
                                .navigationTitle("Cluster Nodes")
                            }

                            NavigationLink("Security Policies", id: "nav.security") {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Zero-Trust Terminal Security Active (TLS 1.3 + Hardware Attestation)")
                                        .bold()
                                        .foregroundStyle(.brightMagenta)
                                    Text("Press Esc or click [< Back (Esc)] in the navigation header to pop.")
                                        .dim()
                                }
                                .navigationTitle("Security")
                            }
                        }
                    }
                    .navigationTitle("System Hub")
                }
                .frame(minHeight: 8, maxHeight: 9)
                .border(.rounded, color: .brightCyan, title: "NavigationStack Container", bottomTitle: "↵:Push  Esc:Pop")

                Divider()

                Text("2. View Transition Containers (TransitionContainer & Spring Physics)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 2) {
                    Button("Slide (.easeOut)", id: "btn.trans.slide", color: .brightCyan) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            viewModel.activeTransitionTab = "slide"
                            viewModel.springTargetProgress = 0.45
                        }
                    }

                    Button("Spring (.spring)", id: "btn.trans.spring", color: .brightGreen) {
                        withAnimation(.spring(response: 0.4, dampingRatio: 0.65)) {
                            viewModel.activeTransitionTab = "spring"
                            viewModel.springTargetProgress = 0.88
                        }
                    }

                    Button("Bouncy (.bouncy)", id: "btn.trans.bouncy", color: .brightMagenta) {
                        withAnimation(.bouncy()) {
                            viewModel.activeTransitionTab = "bouncy"
                            viewModel.springTargetProgress = 0.96
                        }
                    }

                    Spinner("60fps Engine", style: .dots, frame: viewModel.spinnerFrame, color: .brightYellow)
                }

                TransitionContainer(transition: .slide, activeID: viewModel.activeTransitionTab) {
                    if viewModel.activeTransitionTab == "slide" {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("▶ Active Transition: Cubic Ease-Out Slide (.transition(.slide))")
                                .bold()
                                .foregroundStyle(.brightCyan)
                            Text("Interpolates horizontal cell column offsets & TrueColor 24-bit RGB channels.")
                                .dim()
                        }
                        .padding(1)
                        .border(.rounded, color: .brightCyan, title: "Card A: Ease-Out Curve")
                    } else if viewModel.activeTransitionTab == "spring" {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("▶ Active Transition: Damped Harmonic Oscillator (.spring)")
                                .bold()
                                .foregroundStyle(.brightGreen)
                            Text("Analytical under-damped spring physics with natural velocity preservation.")
                                .dim()
                        }
                        .padding(1)
                        .border(.rounded, color: .brightGreen, title: "Card B: Spring Physics")
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("▶ Active Transition: Low-Damping Elastic Bounce (.bouncy)")
                                .bold()
                                .foregroundStyle(.brightMagenta)
                            Text("Overshoots target slightly before settling into equilibrium.")
                                .dim()
                        }
                        .padding(1)
                        .border(.rounded, color: .brightMagenta, title: "Card C: Bouncy Spring")
                    }
                }

                Gauge("Animated Target", value: viewModel.springTargetProgress, color: .brightGreen)
                    .frame(maxWidth: 64)
            }
            .padding(1)
        }
    }

    @ViewBuilder
    private var modalSheetContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Hello from SwiftTUI Sheet!")
                .bold()
                .foregroundStyle(.brightCyan)

            Text("This modal is rendered in the top-level z-index overlay layer.")
                .foregroundStyle(.white)

            HStack(spacing: 2) {
                Button("Close Modal (Esc)", id: "btn.closeSheet", color: .brightGreen) {
                    viewModel.isSheetPresented = false
                }
            }
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        HStack(alignment: .center, spacing: 1) {
            Text(" SwiftTUI Gallery ")
                .bold()
                .foregroundStyle(.black)
                .background(.brightGreen)

            Text("Active: \(viewModel.selectedCategory.rawValue)")
                .foregroundStyle(.brightWhite)

            Spacer()

            Text("Tab: Next Control | Shift+Tab: Prev | Esc: Dismiss Modal ")
                .foregroundStyle(.brightBlack)
        }
        .background(Color.rgb(22, 26, 40))
        .frame(maxWidth: ProposedViewSize.infinityDimension, minHeight: 1, maxHeight: 1)
    }
}
