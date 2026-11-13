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

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .typography:   return "🔤"
        case .layout:       return "📐"
        case .inputs:       return "⌨️"
        case .treeAndTable: return "📊"
        case .charts:       return "📈"
        case .modals:       return "🪟"
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

    // Modals state
    public var isSheetPresented: Bool = false

    public init() {}

    public func randomizeCharts() {
        sparklineDataA = (0..<16).map { _ in Double.random(in: 2...80) }
        sparklineDataB = (0..<16).map { _ in Double.random(in: 10...95) }
        gaugeValueA = Double.random(in: 0.1...0.99)
        gaugeValueB = Double.random(in: 0.1...0.99)
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

            Text("Ctrl+1..6: Switch | Tab: Focus | ^Q: Quit ")
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
                HStack(spacing: 2) {
                    Text("1. Gauges (Ratatui / ProgressView)")
                        .bold()
                        .foregroundStyle(.brightYellow)

                    Spacer()

                    Button("🎲 Randomize All", id: "btn.rand", color: .brightMagenta) {
                        viewModel.randomizeCharts()
                    }
                }

                Gauge("CPU Utilization", value: viewModel.gaugeValueA, color: .brightGreen)
                Gauge("Memory Pressure", value: viewModel.gaugeValueB, color: .brightRed)

                Divider()

                Text("2. Sparklines (Unicode Block Levels: ▁▂▃▄▅▆▇█)")
                    .bold()
                    .foregroundStyle(.brightYellow)

                HStack(spacing: 2) {
                    Text("Disk I/O:")
                        .foregroundStyle(.brightCyan)
                        .bold()
                    Sparkline(viewModel.sparklineDataA, color: .brightCyan)
                        .frame(maxWidth: 30, minHeight: 1, maxHeight: 1)
                }

                HStack(spacing: 2) {
                    Text("Net In/Out:")
                        .foregroundStyle(.brightYellow)
                        .bold()
                    Sparkline(viewModel.sparklineDataB, color: .brightYellow)
                        .frame(maxWidth: 30, minHeight: 1, maxHeight: 1)
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

            Spacer()
        }
        .padding(1)
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
