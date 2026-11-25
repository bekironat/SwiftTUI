import Foundation

// MARK: - Command Palette Models & Fuzzy-Searchable Modal Overlay

/// A single executable command entry inside a `CommandPalette`.
public struct CommandPaletteItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String?
    public let shortcutHint: String?
    public let keywords: [String]
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String? = nil,
        title: String,
        category: String? = nil,
        shortcutHint: String? = nil,
        keywords: [String] = [],
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id ?? "\(category ?? ""):\(title)"
        self.title = title
        self.category = category
        self.shortcutHint = shortcutHint
        self.keywords = keywords
        self.action = action
    }

    /// Computes a fuzzy-match score against `query`, returning `nil` if no match.
    public func matchScore(query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 100 }
        var best: Int? = AutocompleteContext.matchScore(candidate: title, query: trimmed)
        if let cat = category, let s = AutocompleteContext.matchScore(candidate: "\(cat) \(title)", query: trimmed) {
            best = max(best ?? Int.min, s - 20)
        }
        for kw in keywords {
            if let s = AutocompleteContext.matchScore(candidate: kw, query: trimmed) {
                best = max(best ?? Int.min, s - 40)
            }
        }
        return best
    }
}

internal struct CommandPaletteState {
    var query: String = ""
    var selectedIndex: Int = 0
    var scrollOffset: Int = 0
}

public struct _CommandPaletteModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let isPresented: Binding<Bool>
    public let commands: [CommandPaletteItem]
    public let placeholder: String
    public let shortcutKey: KeyCode
    public let shortcutModifiers: KeyModifiers

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        let store = context.store
        let path = context.path
        let stateKey = "\(path).cmdPalette"
        let binding = isPresented
        let allCommands = commands
        let prompt = placeholder
        let scKey = shortcutKey
        let scMods = shortcutModifiers
        let theme = context.environment.theme

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).commandPaletteHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    // Global shortcut (default Ctrl+P) to toggle the Command Palette
                    interactions.registerShortcut(
                        matches: { ev in ev.key == scKey && ev.modifiers == scMods },
                        action: {
                            let opening = !binding.wrappedValue
                            binding.wrappedValue = opening
                            if opening {
                                store.setWidgetState(CommandPaletteState(), forPath: stateKey, markDirty: false)
                            }
                            store.markDirty()
                        }
                    )

                    guard binding.wrappedValue else { return }

                    var state = store.widgetState(forPath: stateKey, default: CommandPaletteState())

                    let filtered: [CommandPaletteItem] = allCommands
                        .compactMap { item -> (CommandPaletteItem, Int)? in
                            guard let score = item.matchScore(query: state.query) else { return nil }
                            return (item, score)
                        }
                        .sorted { a, b in
                            if a.1 != b.1 { return a.1 > b.1 }
                            return a.0.title < b.0.title
                        }
                        .map(\.0)

                    let maxVisibleRows = 8
                    if filtered.isEmpty {
                        state.selectedIndex = 0
                        state.scrollOffset = 0
                    } else {
                        state.selectedIndex = max(0, min(filtered.count - 1, state.selectedIndex))
                        if state.selectedIndex < state.scrollOffset {
                            state.scrollOffset = state.selectedIndex
                        } else if state.selectedIndex >= state.scrollOffset + maxVisibleRows {
                            state.scrollOffset = max(0, state.selectedIndex - maxVisibleRows + 1)
                        }
                    }
                    store.setWidgetState(state, forPath: stateKey, markDirty: false)

                    interactions.registerPriorityKeyInterceptor(zIndex: 270) { key in
                        switch key.key {
                        case .escape:
                            binding.wrappedValue = false
                            store.markDirty()
                            return true
                        case .up:
                            if !filtered.isEmpty {
                                state.selectedIndex = (state.selectedIndex - 1 + filtered.count) % filtered.count
                                store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            }
                            return true
                        case .down, .tab:
                            if !filtered.isEmpty {
                                state.selectedIndex = (state.selectedIndex + 1) % filtered.count
                                store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            }
                            return true
                        case .backTab:
                            if !filtered.isEmpty {
                                state.selectedIndex = (state.selectedIndex - 1 + filtered.count) % filtered.count
                                store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            }
                            return true
                        case .enter:
                            if !filtered.isEmpty {
                                let chosen = filtered[max(0, min(filtered.count - 1, state.selectedIndex))]
                                binding.wrappedValue = false
                                store.setWidgetState(CommandPaletteState(), forPath: stateKey, markDirty: false)
                                chosen.action()
                                store.markDirty()
                            } else {
                                binding.wrappedValue = false
                                store.markDirty()
                            }
                            return true
                        case .backspace:
                            if !state.query.isEmpty {
                                state.query.removeLast()
                                state.selectedIndex = 0
                                state.scrollOffset = 0
                                store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            }
                            return true
                        case .space where key.modifiers.isEmpty:
                            state.query.append(" ")
                            state.selectedIndex = 0
                            state.scrollOffset = 0
                            store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            return true
                        case .char(let ch) where key.modifiers.isEmpty || key.modifiers == [.shift]:
                            state.query.append(ch)
                            state.selectedIndex = 0
                            state.scrollOffset = 0
                            store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            return true
                        case .char("u") where key.modifiers == [.control]:
                            state.query = ""
                            state.selectedIndex = 0
                            state.scrollOffset = 0
                            store.setWidgetState(state, forPath: stateKey, markDirty: true)
                            return true
                        default:
                            return true // Capture keys while modal command palette is open
                        }
                    }

                    buffer.addOverlay(zIndex: 270) { overlayBuf in
                        let bounds = overlayBuf.bounds
                        let w = min(max(24, bounds.width - 4), 68)
                        let visibleCount = min(maxVisibleRows, max(1, filtered.count))
                        let h = min(max(6, bounds.height - 2), visibleCount + 4)
                        let x = max(0, (bounds.width - w) / 2)
                        let y = max(1, min(bounds.height - h, bounds.height / 6))
                        let paletteRect = Rect(x: x, y: y, width: w, height: h)

                        let bgStyle = CellStyle(fg: theme.primary, bg: theme.surface)
                        overlayBuf.clear(paletteRect, style: bgStyle)
                        overlayBuf.drawBorder(
                            paletteRect,
                            style: .rounded,
                            borderCellStyle: CellStyle(fg: theme.focusedBorder, bg: theme.surface, modifiers: [.bold]),
                            title: "⌘ Command Palette",
                            titleAlignment: .leading,
                            bottomTitle: "↑↓:Select  ↵:Run  Esc:Close"
                        )

                        // Search query row
                        let queryRowY = paletteRect.minY + 1
                        let innerW = max(1, w - 4)
                        let queryPrefix = "❯ "
                        overlayBuf.writeString(
                            x: paletteRect.minX + 2,
                            y: queryRowY,
                            queryPrefix,
                            style: CellStyle(fg: theme.accent, bg: theme.surface, modifiers: [.bold]),
                            maxWidth: 2
                        )
                        if state.query.isEmpty {
                            overlayBuf.writeString(
                                x: paletteRect.minX + 4,
                                y: queryRowY,
                                UnicodeWidth.truncate(prompt, maxWidth: max(1, innerW - 2)),
                                style: CellStyle(fg: theme.muted, bg: theme.surface, modifiers: [.italic]),
                                maxWidth: max(1, innerW - 2)
                            )
                            overlayBuf.cursorPosition = Point(x: paletteRect.minX + 4, y: queryRowY)
                        } else {
                            let truncQ = UnicodeWidth.truncate(state.query, maxWidth: max(1, innerW - 2))
                            overlayBuf.writeString(
                                x: paletteRect.minX + 4,
                                y: queryRowY,
                                truncQ,
                                style: CellStyle(fg: theme.primary, bg: theme.surface, modifiers: [.bold]),
                                maxWidth: max(1, innerW - 2)
                            )
                            let curX = min(paletteRect.maxX - 2, paletteRect.minX + 4 + UnicodeWidth.width(of: truncQ))
                            overlayBuf.cursorPosition = Point(x: curX, y: queryRowY)
                        }
                        overlayBuf.cursorShape = .steadyBar

                        // Separator line
                        let sepY = paletteRect.minY + 2
                        if sepY < paletteRect.maxY - 1 {
                            overlayBuf.drawHorizontalLine(
                                x: paletteRect.minX + 1,
                                y: sepY,
                                length: max(0, w - 2),
                                symbol: "─",
                                style: CellStyle(fg: theme.border, bg: theme.surface)
                            )
                        }

                        // Filtered command rows
                        let listStartY = paletteRect.minY + 3
                        if filtered.isEmpty {
                            if listStartY < paletteRect.maxY - 1 {
                                overlayBuf.writeString(
                                    x: paletteRect.minX + 2,
                                    y: listStartY,
                                    "No matching commands",
                                    style: CellStyle(fg: theme.muted, bg: theme.surface, modifiers: [.italic]),
                                    maxWidth: innerW
                                )
                            }
                        } else {
                            for rowIdx in 0..<visibleCount {
                                let itemIdx = state.scrollOffset + rowIdx
                                guard itemIdx < filtered.count else { break }
                                let rowY = listStartY + rowIdx
                                if rowY >= paletteRect.maxY - 1 { break }

                                let item = filtered[itemIdx]
                                let isSelected = (itemIdx == state.selectedIndex)
                                let rowBg = isSelected ? theme.selectionBackground : theme.surface
                                let rowFg = isSelected ? theme.selectionForeground : theme.primary
                                let rowRect = Rect(x: paletteRect.minX + 1, y: rowY, width: max(1, w - 2), height: 1)
                                overlayBuf.fill(rowRect, symbol: " ", style: CellStyle(fg: rowFg, bg: rowBg))

                                var curX = rowRect.minX + 1
                                if let cat = item.category, !cat.isEmpty {
                                    let badge = "[\(cat)] "
                                    let bw = UnicodeWidth.width(of: badge)
                                    overlayBuf.writeString(
                                        x: curX,
                                        y: rowY,
                                        badge,
                                        style: CellStyle(fg: isSelected ? theme.warning : theme.accent, bg: rowBg, modifiers: [.bold]),
                                        maxWidth: max(0, rowRect.maxX - curX)
                                    )
                                    curX += bw
                                }

                                let hint = item.shortcutHint ?? ""
                                let hintW = hint.isEmpty ? 0 : UnicodeWidth.width(of: hint) + 2
                                let availTitleW = max(4, rowRect.maxX - curX - hintW - 1)
                                overlayBuf.writeString(
                                    x: curX,
                                    y: rowY,
                                    UnicodeWidth.truncate(item.title, maxWidth: availTitleW),
                                    style: CellStyle(fg: rowFg, bg: rowBg, modifiers: isSelected ? [.bold] : []),
                                    maxWidth: availTitleW
                                )

                                if !hint.isEmpty {
                                    let hx = max(curX + 2, rowRect.maxX - hintW)
                                    overlayBuf.writeString(
                                        x: hx,
                                        y: rowY,
                                        hint,
                                        style: CellStyle(fg: isSelected ? theme.selectionForeground : theme.muted, bg: rowBg),
                                        maxWidth: max(0, rowRect.maxX - hx)
                                    )
                                }

                                interactions.registerMouseTarget(rect: rowRect, zIndex: 275) { mouse in
                                    if case .down(.left) = mouse.kind {
                                        binding.wrappedValue = false
                                        store.setWidgetState(CommandPaletteState(), forPath: stateKey, markDirty: false)
                                        item.action()
                                        store.markDirty()
                                        return true
                                    }
                                    return false
                                }
                            }
                        }
                    }
                }
            )
        }
    }
}

extension View {
    /// Attaches a fuzzy-searchable modal Command Palette (default shortcut `Ctrl+P`) to this view.
    public func commandPalette(
        isPresented: Binding<Bool>,
        commands: [CommandPaletteItem],
        placeholder: String = "Type a command...",
        shortcutKey: KeyCode = .char("p"),
        shortcutModifiers: KeyModifiers = [.control]
    ) -> some View {
        _CommandPaletteModifier(
            content: self,
            isPresented: isPresented,
            commands: commands,
            placeholder: placeholder,
            shortcutKey: shortcutKey,
            shortcutModifiers: shortcutModifiers
        )
    }
}
