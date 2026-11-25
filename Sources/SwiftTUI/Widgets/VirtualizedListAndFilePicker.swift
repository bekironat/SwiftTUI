import Foundation

// MARK: - 1. VirtualizedList (High-Performance Viewport-Virtualized Scrollable List)

internal struct VirtualizedListState {
    var highlightedIndex: Int = 0
    var scrollOffset: Int = 0
}

/// A viewport-virtualized scrollable list that only builds and renders rows currently visible
/// within the terminal viewport. Supports single or multi-selection, keyboard (`↑`/`↓`/`j`/`k`/`PageUp`/`PageDown`/`Home`/`End`),
/// mouse click/wheel scrolling, and automatic scrollbar rendering.
public struct VirtualizedList<Data: RandomAccessCollection, ID: Hashable, RowContent: View>: View, _PrimitiveView where Data.Index == Int {
    public typealias Body = Never
    public let data: Data
    public let idGenerator: (Data.Element) -> ID
    public let rowHeight: Int
    public let selection: Binding<ID?>?
    public let multiSelection: Binding<Set<ID>>?
    public let focusID: AnyHashable?
    public let showsIndicators: Bool
    public let onActivate: (@MainActor (Data.Element) -> Void)?
    public let rowContent: @MainActor (Data.Element, Bool) -> RowContent

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        rowHeight: Int = 1,
        selection: Binding<ID?>? = nil,
        multiSelection: Binding<Set<ID>>? = nil,
        focusID: AnyHashable? = nil,
        showsIndicators: Bool = true,
        onActivate: (@MainActor (Data.Element) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping @MainActor (Data.Element, Bool) -> RowContent
    ) {
        self.data = data
        self.idGenerator = { $0[keyPath: id] }
        self.rowHeight = max(1, rowHeight)
        self.selection = selection
        self.multiSelection = multiSelection
        self.focusID = focusID
        self.showsIndicators = showsIndicators
        self.onActivate = onActivate
        self.rowContent = rowContent
    }

    public init(
        _ data: Data,
        rowHeight: Int = 1,
        selection: Binding<ID?>? = nil,
        multiSelection: Binding<Set<ID>>? = nil,
        focusID: AnyHashable? = nil,
        showsIndicators: Bool = true,
        onActivate: (@MainActor (Data.Element) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping @MainActor (Data.Element, Bool) -> RowContent
    ) where Data.Element: Identifiable, Data.Element.ID == ID {
        self.data = data
        self.idGenerator = { $0.id }
        self.rowHeight = max(1, rowHeight)
        self.selection = selection
        self.multiSelection = multiSelection
        self.focusID = focusID
        self.showsIndicators = showsIndicators
        self.onActivate = onActivate
        self.rowContent = rowContent
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let listPath = context.appending("VirtualizedList").path
        let targetFocusID = focusID ?? AnyHashable(listPath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let items = data
        let count = items.count
        let rHeight = rowHeight
        let idGen = idGenerator
        let selBinding = selection
        let multiSelBinding = multiSelection
        let showScroll = showsIndicators
        let activateHandler = onActivate
        let builder = rowContent
        let theme = context.environment.theme

        return [
            RenderNode(
                id: listPath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    let desiredH = count * rHeight
                    return Size(
                        width: proposal.width ?? 32,
                        height: proposal.height.map { min($0, max(1, desiredH)) } ?? max(1, min(16, desiredH))
                    )
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    store.registerFocusableRect(rect, for: targetFocusID)
                    let isFocused = (store.activeFocusID == targetFocusID)

                    guard count > 0 else {
                        buffer.writeString(
                            x: rect.minX,
                            y: rect.minY,
                            "(empty)",
                            style: CellStyle(fg: theme.muted, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                        return
                    }

                    var state = store.widgetState(forPath: listPath, default: VirtualizedListState())
                    if let selID = selBinding?.wrappedValue,
                       let matchIdx = (0..<count).first(where: { idGen(items[items.startIndex + $0]) == selID }) {
                        state.highlightedIndex = matchIdx
                    }
                    state.highlightedIndex = max(0, min(count - 1, state.highlightedIndex))

                    let visibleRowSlots = max(1, rect.height / rHeight)
                    if state.highlightedIndex < state.scrollOffset {
                        state.scrollOffset = state.highlightedIndex
                    } else if state.highlightedIndex >= state.scrollOffset + visibleRowSlots {
                        state.scrollOffset = max(0, state.highlightedIndex - visibleRowSlots + 1)
                    }
                    let maxScroll = max(0, count - visibleRowSlots)
                    state.scrollOffset = max(0, min(maxScroll, state.scrollOffset))
                    store.setWidgetState(state, forPath: listPath, markDirty: false)

                    let needsScrollbar = showScroll && count > visibleRowSlots && rect.width > 2
                    let contentW = needsScrollbar ? (rect.width - 1) : rect.width

                    // Only resolve and render rows visible in [scrollOffset ..< scrollOffset + visibleRowSlots]
                    let startIdx = state.scrollOffset
                    let endIdx = min(count, startIdx + visibleRowSlots)

                    for i in startIdx..<endIdx {
                        let element = items[items.startIndex + i]
                        let elemID = idGen(element)
                        let visSlot = i - startIdx
                        let rowY = rect.minY + visSlot * rHeight
                        let rowRect = Rect(x: rect.minX, y: rowY, width: contentW, height: min(rHeight, rect.maxY - rowY))
                        if rowRect.isEmpty { break }

                        let isHighlighted = (i == state.highlightedIndex)
                        let isMultiSelected = multiSelBinding?.wrappedValue.contains(elemID) ?? false
                        let isSelected = isHighlighted || isMultiSelected

                        let rowBg: Color
                        if isHighlighted {
                            rowBg = isFocused ? theme.selectionBackground : theme.surface
                        } else if isMultiSelected {
                            rowBg = theme.surface
                        } else {
                            rowBg = context.environment.backgroundColor
                        }
                        if rowBg != .default {
                            buffer.fill(rowRect, symbol: " ", style: CellStyle(fg: theme.primary, bg: rowBg))
                        }

                        let rowCtx = context.appending("row[\(elemID)]").withEnvironment { env in
                            env.backgroundColor = rowBg
                            if isSelected {
                                env.foregroundColor = theme.selectionForeground
                            }
                        }
                        let rowView = builder(element, isSelected)
                        let nodes = resolveView(rowView, context: rowCtx)
                        buffer.withClip(rowRect) { buf in
                            if nodes.count == 1 {
                                nodes[0].render(in: rowRect, buffer: &buf, interactions: interactions)
                            } else if nodes.count > 1 {
                                let stack = HStackLayoutEngine.makeNode(id: "\(rowCtx.path).row", alignment: .center, spacing: 1, children: nodes)
                                stack.render(in: rowRect, buffer: &buf, interactions: interactions)
                            }
                        }

                        let capturedIndex = i
                        interactions.registerMouseTarget(rect: rowRect, zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = targetFocusID
                                state.highlightedIndex = capturedIndex
                                selBinding?.wrappedValue = elemID
                                if let multi = multiSelBinding {
                                    var set = multi.wrappedValue
                                    if set.contains(elemID) { set.remove(elemID) } else { set.insert(elemID) }
                                    multi.wrappedValue = set
                                }
                                store.setWidgetState(state, forPath: listPath, markDirty: true)
                                activateHandler?(element)
                                return true
                            }
                            return false
                        }
                    }

                    // Draw scrollbar if list overflows viewport
                    if needsScrollbar {
                        let trackX = rect.maxX - 1
                        let trackH = rect.height
                        let thumbH = max(1, (trackH * visibleRowSlots) / max(1, count))
                        let thumbTravel = max(0, trackH - thumbH)
                        let thumbY = maxScroll > 0 ? (state.scrollOffset * thumbTravel) / maxScroll : 0
                        for row in 0..<trackH {
                            let isThumb = row >= thumbY && row < (thumbY + thumbH)
                            buffer.setCell(
                                x: trackX,
                                y: rect.minY + row,
                                symbol: isThumb ? "▐" : "░",
                                style: CellStyle(fg: isThumb ? theme.accent : theme.muted)
                            )
                        }
                    }

                    // Mouse wheel scrolling
                    interactions.registerMouseTarget(rect: rect, zIndex: 2) { mouse in
                        switch mouse.kind {
                        case .scrollUp:
                            if state.scrollOffset > 0 {
                                state.scrollOffset = max(0, state.scrollOffset - 2)
                                state.highlightedIndex = min(state.highlightedIndex, state.scrollOffset + visibleRowSlots - 1)
                                store.setWidgetState(state, forPath: listPath, markDirty: true)
                                return true
                            }
                        case .scrollDown:
                            if state.scrollOffset < maxScroll {
                                state.scrollOffset = min(maxScroll, state.scrollOffset + 2)
                                state.highlightedIndex = max(state.highlightedIndex, state.scrollOffset)
                                store.setWidgetState(state, forPath: listPath, markDirty: true)
                                return true
                            }
                        default:
                            break
                        }
                        return false
                    }

                    // Keyboard navigation
                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        let moveTo: @MainActor (Int) -> Void = { newIdx in
                            var nextState = state
                            let clamped = max(0, min(count - 1, newIdx))
                            nextState.highlightedIndex = clamped
                            let el = items[items.startIndex + clamped]
                            selBinding?.wrappedValue = idGen(el)
                            store.setWidgetState(nextState, forPath: listPath, markDirty: true)
                        }

                        switch key.key {
                        case .up,
                             .char("k") where key.modifiers.isEmpty:
                            moveTo(state.highlightedIndex - 1)
                            return true
                        case .down,
                             .char("j") where key.modifiers.isEmpty:
                            moveTo(state.highlightedIndex + 1)
                            return true
                        case .pageUp:
                            moveTo(state.highlightedIndex - visibleRowSlots)
                            return true
                        case .pageDown:
                            moveTo(state.highlightedIndex + visibleRowSlots)
                            return true
                        case .home:
                            moveTo(0)
                            return true
                        case .end:
                            moveTo(count - 1)
                            return true
                        case .space:
                            let el = items[items.startIndex + state.highlightedIndex]
                            let elemID = idGen(el)
                            if let multi = multiSelBinding {
                                var set = multi.wrappedValue
                                if set.contains(elemID) { set.remove(elemID) } else { set.insert(elemID) }
                                multi.wrappedValue = set
                                store.markDirty()
                            } else {
                                activateHandler?(el)
                                store.markDirty()
                            }
                            return true
                        case .enter:
                            let el = items[items.startIndex + state.highlightedIndex]
                            selBinding?.wrappedValue = idGen(el)
                            activateHandler?(el)
                            store.markDirty()
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

/// SwiftUI-familiar alias for `VirtualizedList`.
public typealias List<Data: RandomAccessCollection, ID: Hashable, RowContent: View> = VirtualizedList<Data, ID, RowContent> where Data.Index == Int

// MARK: - 2. FilePicker (Interactive Terminal Directory & File Browser)

/// A single directory or file entry displayed in `FilePicker`.
public struct FilePickerEntry: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let fileSize: Int64?

    public init(name: String, url: URL, isDirectory: Bool, fileSize: Int64? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.fileSize = fileSize
    }
}

internal struct FilePickerWidgetState {
    var currentDirectory: URL
    var selectedIndex: Int = 0
    var scrollOffset: Int = 0
    var showHidden: Bool = false
}

/// An interactive terminal file & directory browser supporting keyboard traversal (`↑`/`↓`/`Enter`/`Backspace`/`h` to toggle hidden files),
/// extension filtering, and mouse clicks.
public struct FilePicker: View, _PrimitiveView {
    public typealias Body = Never
    public let initialDirectory: URL
    public let allowedExtensions: Set<String>?
    public let focusID: AnyHashable?
    public let onSelect: @MainActor (URL) -> Void

    public init(
        directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        allowedExtensions: [String]? = nil,
        id: AnyHashable? = nil,
        onSelect: @escaping @MainActor (URL) -> Void
    ) {
        self.initialDirectory = directory
        self.allowedExtensions = allowedExtensions.map { Set($0.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }) }
        self.focusID = id
        self.onSelect = onSelect
    }

    public static func listEntries(
        in directory: URL,
        showHidden: Bool,
        allowedExtensions: Set<String>?
    ) -> [FilePickerEntry] {
        var entries: [FilePickerEntry] = []
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path {
            entries.append(FilePickerEntry(name: "..", url: parent, isDirectory: true, fileSize: nil))
        }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isHiddenKey]
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        )) ?? []

        var dirs: [FilePickerEntry] = []
        var files: [FilePickerEntry] = []

        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let name = url.lastPathComponent
            if isDir {
                dirs.append(FilePickerEntry(name: name, url: url, isDirectory: true, fileSize: nil))
            } else {
                if let allowed = allowedExtensions, !allowed.isEmpty {
                    let ext = url.pathExtension.lowercased()
                    if !allowed.contains(ext) { continue }
                }
                let size = values?.fileSize.map(Int64.init)
                files.append(FilePickerEntry(name: name, url: url, isDirectory: false, fileSize: size))
            }
        }

        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        entries.append(contentsOf: dirs)
        entries.append(contentsOf: files)
        return entries
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let pickerPath = context.appending("FilePicker").path
        let targetFocusID = focusID ?? AnyHashable(pickerPath)
        let store = context.store
        store.registerFocusable(targetFocusID)

        let initDir = initialDirectory
        let exts = allowedExtensions
        let selectHandler = onSelect
        let theme = context.environment.theme

        return [
            RenderNode(
                id: pickerPath,
                flexibleAxes: [.horizontal, .vertical],
                measure: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: Size(width: 48, height: 14))
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    store.registerFocusableRect(rect, for: targetFocusID)
                    let isFocused = (store.activeFocusID == targetFocusID)

                    var state = store.widgetState(forPath: pickerPath, default: FilePickerWidgetState(currentDirectory: initDir))
                    let entries = Self.listEntries(in: state.currentDirectory, showHidden: state.showHidden, allowedExtensions: exts)

                    // Header breadcrumb
                    let headerText = "📁 \(state.currentDirectory.path)"
                    buffer.writeString(
                        x: rect.minX,
                        y: rect.minY,
                        UnicodeWidth.truncate(headerText, maxWidth: rect.width),
                        style: CellStyle(fg: theme.accent, bg: theme.surface, modifiers: [.bold]),
                        maxWidth: rect.width
                    )

                    let listStartY = rect.minY + 1
                    let listHeight = max(0, rect.height - 1)
                    guard listHeight > 0 else { return }

                    if entries.isEmpty {
                        buffer.writeString(
                            x: rect.minX,
                            y: listStartY,
                            "(empty directory)",
                            style: CellStyle(fg: theme.muted, modifiers: [.italic]),
                            maxWidth: rect.width
                        )
                        return
                    }

                    state.selectedIndex = max(0, min(entries.count - 1, state.selectedIndex))
                    if state.selectedIndex < state.scrollOffset {
                        state.scrollOffset = state.selectedIndex
                    } else if state.selectedIndex >= state.scrollOffset + listHeight {
                        state.scrollOffset = max(0, state.selectedIndex - listHeight + 1)
                    }
                    store.setWidgetState(state, forPath: pickerPath, markDirty: false)

                    for visRow in 0..<listHeight {
                        let idx = state.scrollOffset + visRow
                        guard idx < entries.count else { break }
                        let entry = entries[idx]
                        let rowY = listStartY + visRow
                        let isSel = (idx == state.selectedIndex)
                        let rowBg = isSel ? (isFocused ? theme.selectionBackground : theme.surface) : context.environment.backgroundColor
                        let rowFg = isSel ? theme.selectionForeground : (entry.isDirectory ? theme.accent : theme.primary)
                        let rowRect = Rect(x: rect.minX, y: rowY, width: rect.width, height: 1)
                        if rowBg != .default {
                            buffer.fill(rowRect, symbol: " ", style: CellStyle(fg: rowFg, bg: rowBg))
                        }

                        let icon = entry.isDirectory ? "▸ " : "  "
                        let suffix = entry.isDirectory ? "/" : (entry.fileSize.map { " (\($0) B)" } ?? "")
                        let line = "\(icon)\(entry.name)\(suffix)"
                        buffer.writeString(
                            x: rect.minX,
                            y: rowY,
                            UnicodeWidth.truncate(line, maxWidth: rect.width),
                            style: CellStyle(fg: rowFg, bg: rowBg, modifiers: isSel ? [.bold] : []),
                            maxWidth: rect.width
                        )

                        let capturedIdx = idx
                        interactions.registerMouseTarget(rect: rowRect, zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = targetFocusID
                                let chosen = entries[capturedIdx]
                                if chosen.isDirectory {
                                    state.currentDirectory = chosen.url
                                    state.selectedIndex = 0
                                    state.scrollOffset = 0
                                    store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                                } else {
                                    state.selectedIndex = capturedIdx
                                    store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                                    selectHandler(chosen.url)
                                }
                                return true
                            }
                            return false
                        }
                    }

                    interactions.registerFocusedKeyHandler(for: targetFocusID) { key in
                        switch key.key {
                        case .up,
                             .char("k") where key.modifiers.isEmpty:
                            if state.selectedIndex > 0 {
                                state.selectedIndex -= 1
                                store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                            }
                            return true
                        case .down,
                             .char("j") where key.modifiers.isEmpty:
                            if state.selectedIndex + 1 < entries.count {
                                state.selectedIndex += 1
                                store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                            }
                            return true
                        case .backspace, .left:
                            let parent = state.currentDirectory.deletingLastPathComponent()
                            if parent.path != state.currentDirectory.path {
                                state.currentDirectory = parent
                                state.selectedIndex = 0
                                state.scrollOffset = 0
                                store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                            }
                            return true
                        case .char(".") where key.modifiers.isEmpty:
                            state.showHidden.toggle()
                            state.selectedIndex = 0
                            state.scrollOffset = 0
                            store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                            return true
                        case .enter, .right:
                            let chosen = entries[state.selectedIndex]
                            if chosen.isDirectory {
                                state.currentDirectory = chosen.url
                                state.selectedIndex = 0
                                state.scrollOffset = 0
                                store.setWidgetState(state, forPath: pickerPath, markDirty: true)
                            } else {
                                selectHandler(chosen.url)
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
}
