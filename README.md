# SwiftTUI & SwiftGrip

**SwiftTUI** is a cross-platform Terminal User Interface (TUI) framework for Swift 6 inspired by **[Ratatui](https://ratatui.rs)** with a declarative **SwiftUI** API.

Included in this repository is **`SwiftGrip`**, an IntelliJ DataGrip-inspired terminal SQLite IDE built on `SwiftTUI` featuring a hierarchical Database Schema Explorer, multi-line SQL Console with syntax highlighting and **cursor-anchored SQL Autocomplete**, `EXPLAIN QUERY PLAN` inspector, and an interactive 2D Data Grid with inline cell editing and staged transactions.

```text
 🗄 SwiftGrip  SQLite 3.54.0                                            [▶ Run SQL (F5)] [⚡ Palette (^K)] [? Help (F1)]
╭ Database Explorer ──────────╮╭ Query Console & Inspector ────────────────────────────────────────────────────────────╮
│▾ 🗄 main (in-memory demo) SQ││ 📝 SQL Console (F5) │ 📜 DDL Schema (customers) │ 🧭 Explain Query Plan │             │
│  ▾ 📁 tables 5              ││ 1│ -- SwiftGrip SQL Console (Ctrl+Space for Autocomplete, F5 / Ctrl+R to Run)         │
│    ▸ ⊞ audit_log (7)        ││ 2│ SELECT c.customer_id, c.name, c.tier, c.country, COUNT(o.order_id) AS orders_count,│
│    ▾ ⊞ customers (8)        ││ 3│        COALESCE(SUM(o.total_amount), 0.0) AS total_spent                           │
│        🔑 customer_id INTEGE││ 4│ FROM customers c                                                                   │
│        • name TEXT NN       ││ 5│ LEFT JOIN orders o ON o.customer_id = c.customer_id                                │
│        • email TEXT NN      ││ 6│ GROUP BY c.customer_id                                                             │
│        • tier TEXT NN       ││ 7│ ORDER BY total_spent DESC;                                                         │
│        • country TEXT NN    ││  ~                                                                                    │
│        • created_at TEXT NN │╰ Ctrl+Space:SQL Autocomplete  F5/Ctrl+R:Execute ───────────────────────────────────────╯
│    ▸ ⊞ order_items (12)     │ WHERE  Filter customers rows (e.g. tier = 'ENTERPRISE' — Ctrl+Space for columns) [Apply]
│    ▸ ⊞ orders (7)           │╭ Table: customers (8 rows) ────────────────────────────────────────────────────────────╮
│    ▸ ⊞ products (6)         ││  #│ 🔑customer_id │ name              │ email                    │ tier       │ count…│
│  ▾ 📁 views 1               ││───┼───────────────┼───────────────────┼──────────────────────────┼────────────┼───────│
│    ▸ 👁 v_customer_revenue (││  1│             1 │ Ada Lovelace      │ ada@analytical.org       │ ENTERPRISE │ UK    │
│  ▸ 📁 indexes 3             ││  2│             2 │ Alan Turing       │ alan@bletchley.uk        │ ENTERPRISE │ UK    │
│  ▸ 📁 triggers 1            ││  3│             3 │ Grace Hopper      │ grace@navy.mil           │ PRO        │ USA   │
╰ ↵/Space:Open  ↑↓←→:Nav ─────╯╰ ↵/e:Edit Cell  s:Sort Column  hjkl/Arrows:Navigate ───────────────────────────────────╯
 TX: AUTO  ⊞ customers │ Row 1/8 • Col: customer_id  Tab:Switch Pane │ ^Space:Autocomplete │ F5:Run │ ^K:Palette │ ^Q:Qu
```

---

## Features

- **Zero External Dependencies**: Pure Swift 6 using only the Swift Standard Library, `Observation`, `Foundation`, `Darwin`/`Glibc` (`termios`/`ioctl`), and system `sqlite3`.
- **Ratatui-Grade Cell Buffer & Diff Renderer**:
  - Double-buffered 2D [`Buffer`](Sources/SwiftTUI/Rendering/Buffer.swift) with East Asian Wide / Emoji grapheme width calculation ([`UnicodeWidth`](Sources/SwiftTUI/Core/UnicodeWidth.swift)) and automatic orphaned half-cell cleanup.
  - Minimal ANSI/VT escape diffing ([`DiffRenderer`](Sources/SwiftTUI/Rendering/DiffRenderer.swift)) wrapped in synchronized output (`CSI ? 2026 h` / `l`).
  - Deferred top-level overlay z-layer so cursor-anchored popovers (`AutocompletePopup`) and modals (`.sheet`) float cleanly over split panes without clipping.
- **Declarative SwiftUI Subset**:
  - `App`, `Scene`, `WindowGroup`, `View`, and variadic parameter-pack `@ViewBuilder`.
  - Retained state reconciliation supporting `@State`, `@Binding`, `@Observable`, `@FocusState`, and `@Environment`.
  - Two-pass layout negotiation (`ProposedViewSize` -> `Size`) with `VStack`, `HStack`, `ZStack`, `Spacer`, `Divider`, `ScrollView`, `GeometryReader`, and mouse-draggable `HSplitView` / `VSplitView`.
- **Rich Terminal Widgets & Autocomplete**:
  - `TextField` and multi-line `TextEditor` (line numbers, syntax highlighting hook, cursor-anchored `AutocompletePopup`).
  - Hierarchical `Tree` and virtualized 2D `Table` with sorting, row/cell selection, and inline cell editing.
  - `TabBar`, `Button`, `Toggle`, `Gauge`, and `Sparkline`.
- **Headless Snapshot & Interaction Testing (`SwiftTUITesting`)**:
  - Drive any `View` in unit tests via [`TestHarness`](Sources/SwiftTUITesting/TestHarness.swift) with synthetic keyboard/mouse events and buffer assertions.

---

## Quick Start

### Run the `SwiftGrip` SQLite IDE

```bash
# Launch with the built-in relational e-commerce demo database:
swift run SwiftGrip

# Open or create a local SQLite database file:
swift run SwiftGrip path/to/database.sqlite

# Render a 120x34 headless snapshot to stdout:
swift run SwiftGrip --snapshot
```

### Run the Test Suite

```bash
swift test
```

### Minimal `SwiftTUI` App Example

```swift
import SwiftTUI

struct CounterApp: App {
    var body: some Scene {
        WindowGroup {
            CounterView()
        }
    }
}

struct CounterView: View {
    @State private var count = 0
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SwiftTUI Counter: \(count)")
                .bold()
                .foregroundStyle(.brightCyan)

            HStack(spacing: 2) {
                Button("Increment (+)") { count += 1 }
                Button("Decrement (-)") { count -= 1 }
            }

            TextField("Type SQL keyword...", text: $query)
                .autocomplete { ctx in
                    ["SELECT", "FROM", "WHERE", "JOIN", "GROUP BY", "ORDER BY"]
                        .filter { $0.lowercased().hasPrefix(ctx.prefix.lowercased()) }
                        .map { AutocompleteItem(label: $0, insertText: "\($0) ", kind: .keyword) }
                }
        }
        .padding(1)
        .border(.rounded, color: .brightCyan, title: "Demo")
    }
}
```
