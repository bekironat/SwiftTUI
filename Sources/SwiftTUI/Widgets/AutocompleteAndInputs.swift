import Foundation

// MARK: - Autocomplete Data Models & Provider API

/// Semantic category of an autocomplete suggestion, determining its badge text and color in the terminal popup.
public enum AutocompleteKind: Equatable, Hashable, Sendable {
    case keyword
    case table
    case view
    case column
    case function
    case index
    case snippet
    case custom(badge: String, color: Color)

    public var badge: String {
        switch self {
        case .keyword:  return "KW "
        case .table:    return "TBL"
        case .view:     return "VW "
        case .column:   return "COL"
        case .function: return "FN "
        case .index:    return "IDX"
        case .snippet:  return "SNP"
        case .custom(let b, _): return UnicodeWidth.fit(b, width: 3)
        }
    }

    public var color: Color {
        switch self {
        case .keyword:  return .brightMagenta
        case .table:    return .brightCyan
        case .view:     return .brightGreen
        case .column:   return .brightYellow
        case .function: return .brightBlue
        case .index:    return .orange
        case .snippet:  return .teal
        case .custom(_, let c): return c
        }
    }
}

/// A single suggestion displayed in an `AutocompletePopup`.
public struct AutocompleteItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let insertText: String
    public let kind: AutocompleteKind
    public let detail: String?
    public let documentation: String?
    public let sortPriority: Int

    public init(
        id: String? = nil,
        label: String,
        insertText: String? = nil,
        kind: AutocompleteKind = .keyword,
        detail: String? = nil,
        documentation: String? = nil,
        sortPriority: Int = 100
    ) {
        self.id = id ?? "\(kind.badge):\(label)"
        self.label = label
        self.insertText = insertText ?? label
        self.kind = kind
        self.detail = detail
        self.documentation = documentation
        self.sortPriority = sortPriority
    }
}

/// Cursor and token context passed to an autocomplete provider.
public struct AutocompleteContext: Equatable, Sendable {
    /// Complete text of the editor or field.
    public let fullText: String
    /// Current line text where the cursor resides.
    public let lineText: String
    /// 0-indexed line number of the cursor.
    public let lineIndex: Int
    /// 0-indexed character offset within `lineText`.
    public let columnIndex: Int
    /// Identifier prefix immediately before the cursor (e.g. `" sel"` -> `"sel"`).
    public let prefix: String
    /// Optional dot-qualifier before the prefix (e.g. `"c.nam"` -> qualifier `"c"`, prefix `"nam"`).
    public let qualifier: String?
    /// True if summoned explicitly via `Ctrl+Space`.
    public let isExplicitTrigger: Bool

    public init(
        fullText: String,
        lineText: String,
        lineIndex: Int,
        columnIndex: Int,
        prefix: String,
        qualifier: String?,
        isExplicitTrigger: Bool
    ) {
        self.fullText = fullText
        self.lineText = lineText
        self.lineIndex = lineIndex
        self.columnIndex = columnIndex
        self.prefix = prefix
        self.qualifier = qualifier
        self.isExplicitTrigger = isExplicitTrigger
    }

    /// Extracts the identifier prefix and optional dot qualifier (`alias.col`) immediately preceding `columnIndex` in `lineText`.
    public static func extract(
        fullText: String,
        lineText: String,
        lineIndex: Int,
        columnIndex: Int,
        isExplicitTrigger: Bool
    ) -> AutocompleteContext {
        let chars = Array(lineText)
        let clampedCol = max(0, min(chars.count, columnIndex))

        var start = clampedCol
        while start > 0 && isIdentifierChar(chars[start - 1]) {
            start -= 1
        }
        let prefix = String(chars[start..<clampedCol])

        var qualifier: String? = nil
        if start > 0 && chars[start - 1] == "." {
            var qStart = start - 1
            while qStart > 0 && isIdentifierChar(chars[qStart - 1]) {
                qStart -= 1
            }
            if qStart < start - 1 {
                qualifier = String(chars[qStart..<(start - 1)])
            }
        }

        return AutocompleteContext(
            fullText: fullText,
            lineText: lineText,
            lineIndex: lineIndex,
            columnIndex: clampedCol,
            prefix: prefix,
            qualifier: qualifier,
            isExplicitTrigger: isExplicitTrigger
        )
    }

    public static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }

    /// Fuzzy/prefix match helper scoring `candidate` against `query`. Returns `nil` if no match.
    public static func matchScore(candidate: String, query: String) -> Int? {
        if query.isEmpty { return 50 }
        let lowerCand = candidate.lowercased()
        let lowerQuery = query.lowercased()

        if lowerCand == lowerQuery {
            return 1000
        }
        if lowerCand.hasPrefix(lowerQuery) {
            return 800 - min(200, candidate.count)
        }
        if lowerCand.contains(lowerQuery) {
            return 500 - min(200, candidate.count)
        }

        // Subsequence fuzzy check
        var qIdx = lowerQuery.startIndex
        for ch in lowerCand {
            if ch == lowerQuery[qIdx] {
                qIdx = lowerQuery.index(after: qIdx)
                if qIdx == lowerQuery.endIndex {
                    return 200 - min(150, candidate.count)
                }
            }
        }
        return nil
    }
}

// MARK: - Cursor-Anchored Autocomplete Popup Renderer

internal struct AutocompletePopupState {
    var isVisible: Bool = false
    var isExplicit: Bool = false
    var selectedIndex: Int = 0
    var scrollOffset: Int = 0
    var dismissedAtPrefix: String? = nil
}

@MainActor
public enum AutocompletePopupRenderer {
    /// Renders a floating cursor-anchored completion menu in the top-level overlay pass.
    public static func renderOverlay(
        anchorScreenPoint: Point,
        items: [AutocompleteItem],
        prefix: String,
        selectedIndex: Int,
        scrollOffset: Int,
        maxVisibleRows: Int = 7,
        onSelectIndex: @escaping @MainActor (Int) -> Void,
        buffer: inout Buffer,
        interactions: InteractionRegistry
    ) {
        guard !items.isEmpty else { return }

        let visibleCount = min(maxVisibleRows, items.count)
        let hasDocFooter = items[min(max(0, selectedIndex), items.count - 1)].documentation != nil
        let popupHeight = visibleCount + 2 + (hasDocFooter ? 1 : 0)

        let maxLabelW = items.prefix(30).map { UnicodeWidth.width(of: $0.label) }.max() ?? 12
        let maxDetailW = items.prefix(30).compactMap { $0.detail.map { UnicodeWidth.width(of: $0) } }.max() ?? 0
        let contentWidth = max(28, min(58, 6 + maxLabelW + (maxDetailW > 0 ? maxDetailW + 3 : 2) + 3))
        let popupWidth = min(buffer.width - 2, contentWidth)
        guard popupWidth >= 14, buffer.height >= 4 else { return }

        // Choose below cursor if room, otherwise flip above cursor
        let spaceBelow = buffer.height - (anchorScreenPoint.y + 1)
        let popupY: Int
        if spaceBelow >= popupHeight || anchorScreenPoint.y < popupHeight {
            popupY = min(max(0, buffer.height - popupHeight), anchorScreenPoint.y + 1)
        } else {
            popupY = max(0, anchorScreenPoint.y - popupHeight)
        }

        let popupX = max(0, min(buffer.width - popupWidth, max(0, anchorScreenPoint.x - 4)))
        let popupRect = Rect(x: popupX, y: popupY, width: popupWidth, height: popupHeight)

        let bgColor = Color.rgb(26, 29, 44)
        let selectedBg = Color.rgb(54, 74, 130)
        let borderStyle = CellStyle(fg: .brightCyan, bg: bgColor)

        buffer.clear(popupRect, style: CellStyle(fg: .white, bg: bgColor))
        buffer.drawBorder(
            popupRect,
            style: .rounded,
            borderCellStyle: borderStyle,
            title: "Completions (\(items.count))",
            titleStyle: CellStyle(fg: .brightCyan, bg: bgColor, modifiers: [.bold]),
            titleAlignment: .leading,
            bottomTitle: "Tab/↵:Accept Esc:Close"
        )

        let innerW = max(1, popupWidth - 2)
        let clampedSelected = max(0, min(items.count - 1, selectedIndex))

        for rowIdx in 0..<visibleCount {
            let itemIdx = scrollOffset + rowIdx
            guard itemIdx < items.count else { break }
            let item = items[itemIdx]
            let isSelected = (itemIdx == clampedSelected)
            let rowY = popupRect.minY + 1 + rowIdx
            let rowBg = isSelected ? selectedBg : bgColor

            let rowRect = Rect(x: popupRect.minX + 1, y: rowY, width: innerW, height: 1)
            buffer.fill(rowRect, symbol: " ", style: CellStyle(fg: .white, bg: rowBg))

            // 1. Kind badge (e.g. KW, TBL, COL, FN)
            let badgeStyle = CellStyle(fg: item.kind.color, bg: rowBg, modifiers: [.bold])
            buffer.writeString(x: rowRect.minX, y: rowY, item.kind.badge, style: badgeStyle, maxWidth: 3)

            // 2. Label with highlighted matching prefix characters
            let labelStartX = rowRect.minX + 4
            let detailText = item.detail ?? ""
            let detailW = UnicodeWidth.width(of: detailText)
            let maxLabelAvail = max(4, innerW - 5 - (detailW > 0 ? min(18, detailW + 1) : 0))
            let truncatedLabel = UnicodeWidth.truncate(item.label, maxWidth: maxLabelAvail)

            let spans = highlightMatchSpans(
                label: truncatedLabel,
                query: prefix,
                normalStyle: CellStyle(fg: isSelected ? .brightWhite : .white, bg: rowBg, modifiers: isSelected ? [.bold] : []),
                matchStyle: CellStyle(fg: .brightYellow, bg: rowBg, modifiers: [.bold, .underlined])
            )
            buffer.writeSpans(x: labelStartX, y: rowY, spans, maxWidth: maxLabelAvail)

            // 3. Right-aligned detail metadata
            if !detailText.isEmpty {
                let truncDetail = UnicodeWidth.truncate(detailText, maxWidth: min(18, innerW / 2))
                let dw = UnicodeWidth.width(of: truncDetail)
                let detailX = max(labelStartX + UnicodeWidth.width(of: truncatedLabel) + 1, rowRect.maxX - dw - 1)
                if detailX < rowRect.maxX {
                    buffer.writeString(
                        x: detailX,
                        y: rowY,
                        truncDetail,
                        style: CellStyle(fg: isSelected ? .brightCyan : .brightBlack, bg: rowBg, modifiers: [.italic]),
                        maxWidth: rowRect.maxX - detailX
                    )
                }
            }

            // Mouse click to select and accept completion item
            let capturedIdx = itemIdx
            interactions.registerMouseTarget(rect: rowRect, zIndex: 160) { mouse in
                if case .down(.left) = mouse.kind {
                    onSelectIndex(capturedIdx)
                    return true
                }
                return false
            }
        }

        // Scrollbar on right border if items > visibleCount
        if items.count > visibleCount {
            let trackX = popupRect.maxX - 1
            let thumbH = max(1, (visibleCount * visibleCount) / items.count)
            let maxScroll = max(1, items.count - visibleCount)
            let thumbY = (scrollOffset * max(0, visibleCount - thumbH)) / maxScroll
            for r in 0..<visibleCount {
                let isThumb = r >= thumbY && r < (thumbY + thumbH)
                buffer.setCell(
                    x: trackX,
                    y: popupRect.minY + 1 + r,
                    symbol: isThumb ? "▐" : "│",
                    style: CellStyle(fg: isThumb ? .brightYellow : .brightCyan, bg: bgColor)
                )
            }
        }

        // Documentation line at bottom inside border if present
        if hasDocFooter, let doc = items[clampedSelected].documentation {
            let docY = popupRect.minY + 1 + visibleCount
            let docRect = Rect(x: popupRect.minX + 1, y: docY, width: innerW, height: 1)
            buffer.fill(docRect, symbol: " ", style: CellStyle(fg: .brightBlack, bg: Color.rgb(20, 22, 34)))
            buffer.writeString(
                x: docRect.minX,
                y: docY,
                "ℹ " + doc,
                style: CellStyle(fg: .brightWhite, bg: Color.rgb(20, 22, 34), modifiers: [.dim, .italic]),
                maxWidth: innerW
            )
        }
    }

    private static func highlightMatchSpans(
        label: String,
        query: String,
        normalStyle: CellStyle,
        matchStyle: CellStyle
    ) -> [StyledSpan] {
        guard !query.isEmpty else {
            return [StyledSpan(label, style: normalStyle)]
        }
        let lowerQuery = Array(query.lowercased())
        var qIdx = 0
        var spans: [StyledSpan] = []

        for ch in label {
            let lowerCh = Character(ch.lowercased())
            if qIdx < lowerQuery.count && lowerCh == lowerQuery[qIdx] {
                spans.append(StyledSpan(String(ch), style: matchStyle))
                qIdx += 1
            } else {
                spans.append(StyledSpan(String(ch), style: normalStyle))
            }
        }
        return spans
    }
}

// MARK: - TextField (Single-Line Input with Cursor & Autocomplete)

internal struct TextFieldWidgetState {
    var cursorIndex: Int = 0
    var scrollOffset: Int = 0
    var popup = AutocompletePopupState()
}

/// A single-line editable text input field with cursor navigation, submission handler, and optional terminal autocomplete popup.
public struct TextField: View, _PrimitiveView {
    public typealias Body = Never
    public let placeholder: String
    public let text: Binding<String>
    public let focusID: AnyHashable?
    public var onSubmit: (@MainActor () -> Void)?
    public var completionProvider: (@MainActor (AutocompleteContext) -> [AutocompleteItem])?

    public init(
        _ placeholder: String = "",
        text: Binding<String>,
        id: AnyHashable? = nil,
        onSubmit: (@MainActor () -> Void)? = nil,
        completionProvider: (@MainActor (AutocompleteContext) -> [AutocompleteItem])? = nil
    ) {
        self.placeholder = placeholder
        self.text = text
        self.focusID = id
        self.onSubmit = onSubmit
        self.completionProvider = completionProvider
    }

    public func autocomplete(
        _ provider: @escaping @MainActor (AutocompleteContext) -> [AutocompleteItem]
    ) -> TextField {
        var copy = self
        copy.completionProvider = provider
        return copy
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let fieldPath = context.appending("TextField").path
        let targetFocusID = focusID ?? AnyHashable(fieldPath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let binding = text
        let prompt = placeholder
        let submitHandler = onSubmit
        let provider = completionProvider

        return [
            RenderNode(
                id: fieldPath,
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? max(16, prompt.displayWidth + 2), height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == targetFocusID)
                    let currentText = binding.wrappedValue
                    let chars = Array(currentText)

                    var state = store.widgetState(forPath: fieldPath, default: TextFieldWidgetState(cursorIndex: chars.count))
                    state.cursorIndex = max(0, min(chars.count, state.cursorIndex))

                    // Keep cursor within visible horizontal scroll window
                    let visibleW = max(1, rect.width)
                    if state.cursorIndex < state.scrollOffset {
                        state.scrollOffset = state.cursorIndex
                    } else if state.cursorIndex >= state.scrollOffset + visibleW {
                        state.scrollOffset = max(0, state.cursorIndex - visibleW + 1)
                    }
                    store.setWidgetState(state, forPath: fieldPath, markDirty: false)

                    let bg: Color = isFocused ? .rgb(36, 40, 59) : context.environment.backgroundColor
                    buffer.fill(rect, symbol: " ", style: CellStyle(fg: .white, bg: bg))

                    if chars.isEmpty && !isFocused {
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            prompt,
                            style: CellStyle(fg: .brightBlack, bg: bg, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                    } else {
                        let visibleSlice = chars.dropFirst(state.scrollOffset).prefix(visibleW)
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            String(visibleSlice),
                            style: CellStyle(fg: isFocused ? .brightWhite : .white, bg: bg),
                            maxWidth: rect.width
                        )
                    }

                    let screenCursorX = min(rect.maxX - 1, rect.minX + max(0, state.cursorIndex - state.scrollOffset))
                    let screenCursorPoint = Point(x: screenCursorX, y: rect.minY)

                    if isFocused {
                        buffer.cursorPosition = screenCursorPoint
                        // Also highlight the cursor cell so it's visible even in headless snapshots
                        let charUnderCursor = state.cursorIndex < chars.count ? String(chars[state.cursorIndex]) : " "
                        buffer.setCell(
                            x: screenCursorX,
                            y: rect.minY,
                            symbol: charUnderCursor,
                            style: CellStyle(fg: .black, bg: .brightCyan, modifiers: [.bold])
                        )
                    }

                    // Compute autocomplete items if focused and provider exists
                    var activeItems: [AutocompleteItem] = []
                    var acContext: AutocompleteContext? = nil

                    if isFocused, let provider {
                        let ctx = AutocompleteContext.extract(
                            fullText: currentText,
                            lineText: currentText,
                            lineIndex: 0,
                            columnIndex: state.cursorIndex,
                            isExplicitTrigger: state.popup.isExplicit
                        )
                        acContext = ctx
                        let shouldQuery = state.popup.isExplicit || !ctx.prefix.isEmpty || ctx.qualifier != nil
                        if shouldQuery && state.popup.dismissedAtPrefix != "\(ctx.qualifier ?? "").\(ctx.prefix)" {
                            activeItems = provider(ctx)
                        }
                    }

                    let applyCompletion: @MainActor (AutocompleteItem) -> Void = { item in
                        guard let ctx = acContext else { return }
                        var mutableChars = Array(binding.wrappedValue)
                        let replaceStart = max(0, min(mutableChars.count, state.cursorIndex - ctx.prefix.count))
                        let replaceEnd = max(replaceStart, min(mutableChars.count, state.cursorIndex))
                        let insertedChars = Array(item.insertText)
                        mutableChars.replaceSubrange(replaceStart..<replaceEnd, with: insertedChars)
                        binding.wrappedValue = String(mutableChars)
                        state.cursorIndex = replaceStart + insertedChars.count
                        state.popup.isVisible = false
                        state.popup.isExplicit = false
                        state.popup.selectedIndex = 0
                        state.popup.scrollOffset = 0
                        store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                    }

                    if isFocused && !activeItems.isEmpty {
                        let clampedSel = max(0, min(activeItems.count - 1, state.popup.selectedIndex))
                        var scrollOff = state.popup.scrollOffset
                        let maxVis = 6
                        if clampedSel < scrollOff { scrollOff = clampedSel }
                        else if clampedSel >= scrollOff + maxVis { scrollOff = clampedSel - maxVis + 1 }
                        state.popup.selectedIndex = clampedSel
                        state.popup.scrollOffset = scrollOff
                        store.setWidgetState(state, forPath: fieldPath, markDirty: false)

                        let prefixStr = acContext?.prefix ?? ""
                        buffer.addOverlay(zIndex: 150) { overlayBuf in
                            AutocompletePopupRenderer.renderOverlay(
                                anchorScreenPoint: screenCursorPoint,
                                items: activeItems,
                                prefix: prefixStr,
                                selectedIndex: clampedSel,
                                scrollOffset: scrollOff,
                                maxVisibleRows: maxVis,
                                onSelectIndex: { idx in
                                    if idx >= 0 && idx < activeItems.count {
                                        applyCompletion(activeItems[idx])
                                    }
                                },
                                buffer: &overlayBuf,
                                interactions: interactions
                            )
                        }

                        // Priority key interceptor while autocomplete popup is open
                        interactions.registerPriorityKeyInterceptor(zIndex: 150) { key in
                            switch key.key {
                            case .down:
                                state.popup.selectedIndex = (clampedSel + 1) % activeItems.count
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                                return true
                            case .up:
                                state.popup.selectedIndex = (clampedSel - 1 + activeItems.count) % activeItems.count
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                                return true
                            case .char("n") where key.modifiers.contains(.control):
                                state.popup.selectedIndex = (clampedSel + 1) % activeItems.count
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                                return true
                            case .char("p") where key.modifiers.contains(.control):
                                state.popup.selectedIndex = (clampedSel - 1 + activeItems.count) % activeItems.count
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                                return true
                            case .tab, .enter:
                                applyCompletion(activeItems[clampedSel])
                                return true
                            case .escape:
                                state.popup.isExplicit = false
                                state.popup.dismissedAtPrefix = "\(acContext?.qualifier ?? "").\(acContext?.prefix ?? "")"
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                                return true
                            default:
                                return false
                            }
                        }
                    }

                    // Standard focused key handling for TextField
                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        if key.isCtrlSpace {
                            state.popup.isExplicit = true
                            state.popup.dismissedAtPrefix = nil
                            state.popup.selectedIndex = 0
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        }

                        var mutableChars = Array(binding.wrappedValue)
                        switch key.key {
                        case .left:
                            if state.cursorIndex > 0 {
                                state.cursorIndex -= 1
                                state.popup.isExplicit = false
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .right:
                            if state.cursorIndex < mutableChars.count {
                                state.cursorIndex += 1
                                state.popup.isExplicit = false
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .home:
                            state.cursorIndex = 0
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .end:
                            state.cursorIndex = mutableChars.count
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .backspace:
                            if state.cursorIndex > 0 {
                                mutableChars.remove(at: state.cursorIndex - 1)
                                state.cursorIndex -= 1
                                state.popup.dismissedAtPrefix = nil
                                binding.wrappedValue = String(mutableChars)
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .delete:
                            if state.cursorIndex < mutableChars.count {
                                mutableChars.remove(at: state.cursorIndex)
                                state.popup.dismissedAtPrefix = nil
                                binding.wrappedValue = String(mutableChars)
                                store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            }
                            return true
                        case .enter:
                            submitHandler?()
                            store.markDirty()
                            return true
                        case .space where key.modifiers.isEmpty:
                            mutableChars.insert(" ", at: state.cursorIndex)
                            state.cursorIndex += 1
                            state.popup.isExplicit = false
                            state.popup.dismissedAtPrefix = nil
                            binding.wrappedValue = String(mutableChars)
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        case .char(let ch) where key.modifiers.isEmpty || key.modifiers == [.shift]:
                            mutableChars.insert(ch, at: state.cursorIndex)
                            state.cursorIndex += 1
                            state.popup.dismissedAtPrefix = nil
                            state.popup.selectedIndex = 0
                            binding.wrappedValue = String(mutableChars)
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        default:
                            return false
                        }
                    }

                    interactions.registerMouseTarget(rect: rect, zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            store.activeFocusID = targetFocusID
                            let clickedCol = state.scrollOffset + max(0, mouse.x - rect.minX)
                            state.cursorIndex = max(0, min(chars.count, clickedCol))
                            store.setWidgetState(state, forPath: fieldPath, markDirty: true)
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - TextEditor (Multi-Line Code/SQL Editor with Line Numbers, Syntax Highlighting & Autocomplete)

internal struct TextEditorWidgetState {
    var cursorLine: Int = 0
    var cursorCol: Int = 0
    var scrollRow: Int = 0
    var scrollCol: Int = 0
    var popup = AutocompletePopupState()
}

/// Multi-line text and code editor with line numbers, syntax highlighting hook, cursor navigation, and cursor-anchored autocomplete.
public struct TextEditor: View, _PrimitiveView {
    public typealias Body = Never
    public let text: Binding<String>
    public let focusID: AnyHashable?
    public var showsLineNumbers: Bool = true
    public var syntaxHighlighter: (@MainActor (String) -> [StyledSpan])?
    public var completionProvider: (@MainActor (AutocompleteContext) -> [AutocompleteItem])?
    public var onExecuteShortcut: (@MainActor () -> Void)?

    public init(
        text: Binding<String>,
        id: AnyHashable? = nil,
        showsLineNumbers: Bool = true,
        syntaxHighlighter: (@MainActor (String) -> [StyledSpan])? = nil,
        completionProvider: (@MainActor (AutocompleteContext) -> [AutocompleteItem])? = nil,
        onExecuteShortcut: (@MainActor () -> Void)? = nil
    ) {
        self.text = text
        self.focusID = id
        self.showsLineNumbers = showsLineNumbers
        self.syntaxHighlighter = syntaxHighlighter
        self.completionProvider = completionProvider
        self.onExecuteShortcut = onExecuteShortcut
    }

    public func autocomplete(
        _ provider: @escaping @MainActor (AutocompleteContext) -> [AutocompleteItem]
    ) -> TextEditor {
        var copy = self
        copy.completionProvider = provider
        return copy
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let editorPath = context.appending("TextEditor").path
        let targetFocusID = focusID ?? AnyHashable(editorPath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let binding = text
        let showLines = showsLineNumbers
        let highlighter = syntaxHighlighter
        let provider = completionProvider
        let executeAction = onExecuteShortcut

        return [
            RenderNode(
                id: editorPath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 40, height: 8))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == targetFocusID)
                    let rawText = binding.wrappedValue
                    var lines = rawText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    if lines.isEmpty { lines = [""] }

                    var state = store.widgetState(forPath: editorPath, default: TextEditorWidgetState())
                    state.cursorLine = max(0, min(lines.count - 1, state.cursorLine))
                    let currentLineChars = Array(lines[state.cursorLine])
                    state.cursorCol = max(0, min(currentLineChars.count, state.cursorCol))

                    let gutterWidth = showLines ? max(3, String(lines.count).count + 1) + 1 : 0
                    let codeAreaX = rect.minX + gutterWidth
                    let codeAreaWidth = max(1, rect.width - gutterWidth)
                    let codeAreaHeight = max(1, rect.height)

                    // Adjust vertical and horizontal scroll to keep cursor visible
                    if state.cursorLine < state.scrollRow {
                        state.scrollRow = state.cursorLine
                    } else if state.cursorLine >= state.scrollRow + codeAreaHeight {
                        state.scrollRow = max(0, state.cursorLine - codeAreaHeight + 1)
                    }

                    if state.cursorCol < state.scrollCol {
                        state.scrollCol = state.cursorCol
                    } else if state.cursorCol >= state.scrollCol + codeAreaWidth {
                        state.scrollCol = max(0, state.cursorCol - codeAreaWidth + 1)
                    }
                    store.setWidgetState(state, forPath: editorPath, markDirty: false)

                    let editorBg = context.environment.backgroundColor
                    if editorBg != .default {
                        buffer.fill(rect, symbol: " ", style: CellStyle(bg: editorBg))
                    }

                    // Render visible lines
                    for visRow in 0..<codeAreaHeight {
                        let lineIdx = state.scrollRow + visRow
                        let rowY = rect.minY + visRow
                        guard lineIdx < lines.count else {
                            if showLines {
                                buffer.writeString(
                                    x: rect.minX,
                                    y: rowY,
                                    UnicodeWidth.fit("~", width: gutterWidth - 1, alignment: .trailing) + " ",
                                    style: CellStyle(fg: .brightBlack, bg: editorBg, modifiers: [.dim]),
                                    maxWidth: gutterWidth
                                )
                            }
                            continue
                        }

                        let isCurrentLine = (lineIdx == state.cursorLine) && isFocused
                        let lineBg: Color = isCurrentLine ? .rgb(30, 34, 52) : editorBg

                        if isCurrentLine {
                            buffer.fill(
                                Rect(x: codeAreaX, y: rowY, width: codeAreaWidth, height: 1),
                                symbol: " ",
                                style: CellStyle(bg: lineBg)
                            )
                        }

                        if showLines {
                            let numStr = UnicodeWidth.fit("\(lineIdx + 1)", width: gutterWidth - 2, alignment: .trailing) + "│"
                            let numColor: Color = isCurrentLine ? .brightYellow : .brightBlack
                            buffer.writeString(
                                x: rect.minX,
                                y: rowY,
                                numStr,
                                style: CellStyle(fg: numColor, bg: editorBg),
                                maxWidth: gutterWidth
                            )
                        }

                        let lineText = lines[lineIdx]
                        let visibleLineText = String(lineText.dropFirst(state.scrollCol))
                        if let highlighter {
                            let spans = highlighter(visibleLineText)
                            buffer.writeSpans(
                                x: codeAreaX,
                                y: rowY,
                                spans,
                                baseStyle: CellStyle(fg: .white, bg: lineBg),
                                maxWidth: codeAreaWidth
                            )
                        } else {
                            buffer.writeString(
                                x: codeAreaX,
                                y: rowY,
                                visibleLineText,
                                style: CellStyle(fg: .white, bg: lineBg),
                                maxWidth: codeAreaWidth
                            )
                        }
                    }

                    let screenCursorX = min(rect.maxX - 1, codeAreaX + max(0, state.cursorCol - state.scrollCol))
                    let screenCursorY = min(rect.maxY - 1, rect.minY + max(0, state.cursorLine - state.scrollRow))
                    let screenCursorPoint = Point(x: screenCursorX, y: screenCursorY)

                    if isFocused {
                        buffer.cursorPosition = screenCursorPoint
                        let charAtCursor = state.cursorCol < currentLineChars.count ? String(currentLineChars[state.cursorCol]) : " "
                        buffer.setCell(
                            x: screenCursorX,
                            y: screenCursorY,
                            symbol: charAtCursor,
                            style: CellStyle(fg: .black, bg: .brightCyan, modifiers: [.bold])
                        )
                    }

                    // Autocomplete evaluation
                    var activeItems: [AutocompleteItem] = []
                    var acContext: AutocompleteContext? = nil

                    if isFocused, let provider {
                        let ctx = AutocompleteContext.extract(
                            fullText: rawText,
                            lineText: lines[state.cursorLine],
                            lineIndex: state.cursorLine,
                            columnIndex: state.cursorCol,
                            isExplicitTrigger: state.popup.isExplicit
                        )
                        acContext = ctx
                        let shouldQuery = state.popup.isExplicit || !ctx.prefix.isEmpty || ctx.qualifier != nil
                        let dismissKey = "\(state.cursorLine):\(ctx.qualifier ?? "").\(ctx.prefix)"
                        if shouldQuery && state.popup.dismissedAtPrefix != dismissKey {
                            activeItems = provider(ctx)
                        }
                    }

                    let applyCompletion: @MainActor (AutocompleteItem) -> Void = { item in
                        guard let ctx = acContext else { return }
                        var editLines = binding.wrappedValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                        if editLines.isEmpty { editLines = [""] }
                        let lineIdx = max(0, min(editLines.count - 1, state.cursorLine))
                        var lineChars = Array(editLines[lineIdx])
                        let replaceStart = max(0, min(lineChars.count, state.cursorCol - ctx.prefix.count))
                        let replaceEnd = max(replaceStart, min(lineChars.count, state.cursorCol))
                        let inserted = Array(item.insertText)
                        lineChars.replaceSubrange(replaceStart..<replaceEnd, with: inserted)
                        editLines[lineIdx] = String(lineChars)
                        binding.wrappedValue = editLines.joined(separator: "\n")
                        state.cursorCol = replaceStart + inserted.count
                        state.popup.isExplicit = false
                        state.popup.selectedIndex = 0
                        state.popup.scrollOffset = 0
                        store.setWidgetState(state, forPath: editorPath, markDirty: true)
                    }

                    if isFocused && !activeItems.isEmpty {
                        let clampedSel = max(0, min(activeItems.count - 1, state.popup.selectedIndex))
                        var scrollOff = state.popup.scrollOffset
                        let maxVis = 7
                        if clampedSel < scrollOff { scrollOff = clampedSel }
                        else if clampedSel >= scrollOff + maxVis { scrollOff = clampedSel - maxVis + 1 }
                        state.popup.selectedIndex = clampedSel
                        state.popup.scrollOffset = scrollOff
                        store.setWidgetState(state, forPath: editorPath, markDirty: false)

                        let prefixStr = acContext?.prefix ?? ""
                        buffer.addOverlay(zIndex: 150) { overlayBuf in
                            AutocompletePopupRenderer.renderOverlay(
                                anchorScreenPoint: screenCursorPoint,
                                items: activeItems,
                                prefix: prefixStr,
                                selectedIndex: clampedSel,
                                scrollOffset: scrollOff,
                                maxVisibleRows: maxVis,
                                onSelectIndex: { idx in
                                    if idx >= 0 && idx < activeItems.count {
                                        applyCompletion(activeItems[idx])
                                    }
                                },
                                buffer: &overlayBuf,
                                interactions: interactions
                            )
                        }

                        interactions.registerPriorityKeyInterceptor(zIndex: 150) { key in
                            switch key.key {
                            case .down:
                                state.popup.selectedIndex = (clampedSel + 1) % activeItems.count
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                                return true
                            case .up:
                                state.popup.selectedIndex = (clampedSel - 1 + activeItems.count) % activeItems.count
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                                return true
                            case .char("n") where key.modifiers.contains(.control):
                                state.popup.selectedIndex = (clampedSel + 1) % activeItems.count
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                                return true
                            case .char("p") where key.modifiers.contains(.control):
                                state.popup.selectedIndex = (clampedSel - 1 + activeItems.count) % activeItems.count
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                                return true
                            case .tab, .enter:
                                applyCompletion(activeItems[clampedSel])
                                return true
                            case .escape:
                                state.popup.isExplicit = false
                                state.popup.dismissedAtPrefix = "\(state.cursorLine):\(acContext?.qualifier ?? "").\(acContext?.prefix ?? "")"
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                                return true
                            default:
                                return false
                            }
                        }
                    }

                    // Standard multi-line editor key handling
                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        if key.isCtrlSpace {
                            state.popup.isExplicit = true
                            state.popup.dismissedAtPrefix = nil
                            state.popup.selectedIndex = 0
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true
                        }

                        if (key.key == .f(5)) || (key.key == .char("r") && key.modifiers.contains(.control)) {
                            if let executeAction {
                                executeAction()
                                store.markDirty()
                                return true
                            }
                        }

                        var editLines = binding.wrappedValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                        if editLines.isEmpty { editLines = [""] }
                        state.cursorLine = max(0, min(editLines.count - 1, state.cursorLine))
                        var lineChars = Array(editLines[state.cursorLine])
                        state.cursorCol = max(0, min(lineChars.count, state.cursorCol))

                        switch key.key {
                        case .left:
                            if state.cursorCol > 0 {
                                state.cursorCol -= 1
                            } else if state.cursorLine > 0 {
                                state.cursorLine -= 1
                                state.cursorCol = editLines[state.cursorLine].count
                            }
                            state.popup.isExplicit = false
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .right:
                            if state.cursorCol < lineChars.count {
                                state.cursorCol += 1
                            } else if state.cursorLine + 1 < editLines.count {
                                state.cursorLine += 1
                                state.cursorCol = 0
                            }
                            state.popup.isExplicit = false
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .up:
                            if state.cursorLine > 0 {
                                state.cursorLine -= 1
                                state.cursorCol = min(state.cursorCol, editLines[state.cursorLine].count)
                                state.popup.isExplicit = false
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            }
                            return true

                        case .down:
                            if state.cursorLine + 1 < editLines.count {
                                state.cursorLine += 1
                                state.cursorCol = min(state.cursorCol, editLines[state.cursorLine].count)
                                state.popup.isExplicit = false
                                store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            }
                            return true

                        case .home:
                            state.cursorCol = 0
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .end:
                            state.cursorCol = lineChars.count
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .enter:
                            let leftPart = String(lineChars[0..<state.cursorCol])
                            let rightPart = String(lineChars[state.cursorCol..<lineChars.count])
                            editLines[state.cursorLine] = leftPart
                            editLines.insert(rightPart, at: state.cursorLine + 1)
                            state.cursorLine += 1
                            state.cursorCol = 0
                            state.popup.isExplicit = false
                            state.popup.dismissedAtPrefix = nil
                            binding.wrappedValue = editLines.joined(separator: "\n")
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .backspace:
                            if state.cursorCol > 0 {
                                lineChars.remove(at: state.cursorCol - 1)
                                editLines[state.cursorLine] = String(lineChars)
                                state.cursorCol -= 1
                            } else if state.cursorLine > 0 {
                                let prevLen = editLines[state.cursorLine - 1].count
                                editLines[state.cursorLine - 1] += String(lineChars)
                                editLines.remove(at: state.cursorLine)
                                state.cursorLine -= 1
                                state.cursorCol = prevLen
                            }
                            state.popup.dismissedAtPrefix = nil
                            binding.wrappedValue = editLines.joined(separator: "\n")
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .delete:
                            if state.cursorCol < lineChars.count {
                                lineChars.remove(at: state.cursorCol)
                                editLines[state.cursorLine] = String(lineChars)
                            } else if state.cursorLine + 1 < editLines.count {
                                editLines[state.cursorLine] += editLines[state.cursorLine + 1]
                                editLines.remove(at: state.cursorLine + 1)
                            }
                            state.popup.dismissedAtPrefix = nil
                            binding.wrappedValue = editLines.joined(separator: "\n")
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .space where key.modifiers.isEmpty:
                            lineChars.insert(" ", at: state.cursorCol)
                            editLines[state.cursorLine] = String(lineChars)
                            state.cursorCol += 1
                            state.popup.isExplicit = false
                            state.popup.dismissedAtPrefix = nil
                            binding.wrappedValue = editLines.joined(separator: "\n")
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        case .char(let ch) where key.modifiers.isEmpty || key.modifiers == [.shift]:
                            lineChars.insert(ch, at: state.cursorCol)
                            editLines[state.cursorLine] = String(lineChars)
                            state.cursorCol += 1
                            state.popup.dismissedAtPrefix = nil
                            state.popup.selectedIndex = 0
                            binding.wrappedValue = editLines.joined(separator: "\n")
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true

                        default:
                            return false
                        }
                    }

                    // Mouse click to focus and position cursor in editor
                    interactions.registerMouseTarget(rect: rect, zIndex: 5) { mouse in
                        switch mouse.kind {
                        case .down(.left):
                            store.activeFocusID = targetFocusID
                            let clickedLine = max(0, min(lines.count - 1, state.scrollRow + (mouse.y - rect.minY)))
                            let lineLen = lines[clickedLine].count
                            let clickedCol = max(0, min(lineLen, state.scrollCol + max(0, mouse.x - codeAreaX)))
                            state.cursorLine = clickedLine
                            state.cursorCol = clickedCol
                            state.popup.isExplicit = false
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true
                        case .scrollUp:
                            state.scrollRow = max(0, state.scrollRow - 2)
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true
                        case .scrollDown:
                            state.scrollRow = min(max(0, lines.count - 1), state.scrollRow + 2)
                            store.setWidgetState(state, forPath: editorPath, markDirty: true)
                            return true
                        default:
                            return false
                        }
                    }
                }
            )
        ]
    }
}
