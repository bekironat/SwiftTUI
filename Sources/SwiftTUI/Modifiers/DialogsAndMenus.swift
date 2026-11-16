import Foundation

// MARK: - 1. Alert & Confirmation Dialog Models

/// Semantic role for an alert or confirmation dialog action button.
public enum AlertButtonRole: Equatable, Sendable {
    case `default`
    case destructive
    case cancel
}

/// An interactive button inside an `.alert(...)` or `.confirmationDialog(...)` modal.
public struct AlertButton: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let role: AlertButtonRole
    public let action: @MainActor @Sendable () -> Void

    public init(
        _ title: String,
        role: AlertButtonRole = .default,
        action: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.title = title
        self.role = role
        self.action = action
    }

    public static func `default`(_ title: String, action: @escaping @MainActor @Sendable () -> Void = {}) -> AlertButton {
        AlertButton(title, role: .default, action: action)
    }

    public static func destructive(_ title: String, action: @escaping @MainActor @Sendable () -> Void = {}) -> AlertButton {
        AlertButton(title, role: .destructive, action: action)
    }

    public static func cancel(_ title: String = "Cancel", action: @escaping @MainActor @Sendable () -> Void = {}) -> AlertButton {
        AlertButton(title, role: .cancel, action: action)
    }
}

// MARK: - 2. Alert Modifier (.alert)

public struct _AlertModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let title: String
    public let isPresented: Binding<Bool>
    public let message: String
    public let buttons: [AlertButton]

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        guard isPresented.wrappedValue else { return baseNodes }

        let store = context.store
        let selectedIdxKey = "\(context.path).alertBtnIdx"
        let btns = buttons.isEmpty ? [AlertButton.default("OK")] : buttons
        let binding = isPresented
        let alertTitle = title
        let alertMsg = message

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).alertHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    let selectedIdx: Int = store.widgetState(forPath: selectedIdxKey, default: 0)
                    let clampedIdx = max(0, min(btns.count - 1, selectedIdx))

                    interactions.registerPriorityKeyInterceptor(zIndex: 260) { key in
                        switch key.key {
                        case .escape:
                            binding.wrappedValue = false
                            store.markDirty()
                            return true
                        case .left, .char("h"), .backTab:
                            let prev = (clampedIdx - 1 + btns.count) % btns.count
                            store.setWidgetState(prev, forPath: selectedIdxKey)
                            return true
                        case .right, .char("l"), .tab:
                            let next = (clampedIdx + 1) % btns.count
                            store.setWidgetState(next, forPath: selectedIdxKey)
                            return true
                        case .enter, .space:
                            let btn = btns[clampedIdx]
                            binding.wrappedValue = false
                            btn.action()
                            store.markDirty()
                            return true
                        default:
                            return false
                        }
                    }

                    buffer.addOverlay(zIndex: 260) { overlayBuf in
                        let bounds = overlayBuf.bounds
                        let w = min(bounds.width - 4, max(44, min(64, UnicodeWidth.width(of: alertMsg) + 8)))
                        let wrappedMsg = UnicodeWidth.wrap(alertMsg, maxWidth: max(10, w - 6))
                        let h = min(bounds.height - 2, max(7, wrappedMsg.count + 5))
                        let x = max(0, (bounds.width - w) / 2)
                        let y = max(0, (bounds.height - h) / 2)
                        let alertRect = Rect(x: x, y: y, width: w, height: h)

                        let bgStyle = CellStyle(fg: .white, bg: .rgb(34, 26, 44))
                        overlayBuf.clear(alertRect, style: bgStyle)
                        overlayBuf.drawBorder(
                            alertRect,
                            style: .double,
                            borderCellStyle: CellStyle(fg: .brightYellow, bg: .rgb(34, 26, 44), modifiers: [.bold]),
                            title: "⚠ \(alertTitle)",
                            titleAlignment: .center,
                            bottomTitle: "←→:Select  ↵:Confirm  Esc:Cancel"
                        )

                        for (idx, line) in wrappedMsg.enumerated() {
                            let rowY = alertRect.minY + 2 + idx
                            if rowY >= alertRect.maxY - 2 { break }
                            overlayBuf.writeString(
                                x: alertRect.minX + 3,
                                y: rowY,
                                line,
                                style: CellStyle(fg: .brightWhite, bg: .rgb(34, 26, 44)),
                                maxWidth: w - 6
                            )
                        }

                        // Render horizontal buttons row
                        let btnRowY = alertRect.maxY - 2
                        let totalBtnsW = btns.reduce(0) { $0 + UnicodeWidth.width(of: $1.title) + 4 } + max(0, btns.count - 1) * 2
                        var btnX = alertRect.minX + max(2, (w - totalBtnsW) / 2)

                        for (i, btn) in btns.enumerated() {
                            let isSelected = (i == clampedIdx)
                            let label = isSelected ? "[▶ \(btn.title) ]" : "[  \(btn.title) ]"
                            let btnW = UnicodeWidth.width(of: label)
                            let roleColor: Color = {
                                switch btn.role {
                                case .destructive: return .brightRed
                                case .cancel:      return .brightYellow
                                case .default:     return .brightGreen
                                }
                            }()
                            let fg: Color = isSelected ? .black : roleColor
                            let bg: Color = isSelected ? roleColor : .rgb(46, 38, 60)
                            overlayBuf.writeString(
                                x: btnX,
                                y: btnRowY,
                                label,
                                style: CellStyle(fg: fg, bg: bg, modifiers: [.bold]),
                                maxWidth: max(0, alertRect.maxX - 1 - btnX)
                            )

                            let hitRect = Rect(x: btnX, y: btnRowY, width: btnW, height: 1)
                            interactions.registerMouseTarget(rect: hitRect, zIndex: 265) { mouse in
                                if case .down(.left) = mouse.kind {
                                    binding.wrappedValue = false
                                    btn.action()
                                    store.markDirty()
                                    return true
                                }
                                return false
                            }
                            btnX += btnW + 2
                        }
                    }
                }
            )
        }
    }
}

// MARK: - 3. Confirmation Dialog Modifier (.confirmationDialog)

public struct _ConfirmationDialogModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let title: String
    public let isPresented: Binding<Bool>
    public let message: String?
    public let buttons: [AlertButton]

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        guard isPresented.wrappedValue else { return baseNodes }

        let store = context.store
        let selectedIdxKey = "\(context.path).confirmIdx"
        let btns = buttons.isEmpty ? [AlertButton.cancel()] : buttons
        let binding = isPresented
        let dlgTitle = title
        let dlgMsg = message

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).confirmDialogHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    let selectedIdx: Int = store.widgetState(forPath: selectedIdxKey, default: 0)
                    let clampedIdx = max(0, min(btns.count - 1, selectedIdx))

                    interactions.registerPriorityKeyInterceptor(zIndex: 255) { key in
                        switch key.key {
                        case .escape:
                            binding.wrappedValue = false
                            store.markDirty()
                            return true
                        case .up, .char("k"):
                            let prev = (clampedIdx - 1 + btns.count) % btns.count
                            store.setWidgetState(prev, forPath: selectedIdxKey)
                            return true
                        case .down, .char("j"), .tab:
                            let next = (clampedIdx + 1) % btns.count
                            store.setWidgetState(next, forPath: selectedIdxKey)
                            return true
                        case .enter, .space:
                            let btn = btns[clampedIdx]
                            binding.wrappedValue = false
                            btn.action()
                            store.markDirty()
                            return true
                        default:
                            return false
                        }
                    }

                    buffer.addOverlay(zIndex: 255) { overlayBuf in
                        let bounds = overlayBuf.bounds
                        let maxBtnW = btns.map { UnicodeWidth.width(of: $0.title) }.max() ?? 16
                        let w = min(bounds.width - 4, max(42, max(maxBtnW + 10, UnicodeWidth.width(of: dlgTitle) + 8)))
                        let hasMsg = (dlgMsg != nil && !(dlgMsg?.isEmpty ?? true))
                        let h = min(bounds.height - 2, btns.count + (hasMsg ? 5 : 3))
                        let x = max(0, (bounds.width - w) / 2)
                        let y = max(0, (bounds.height - h) / 2)
                        let dlgRect = Rect(x: x, y: y, width: w, height: h)

                        let bgStyle = CellStyle(fg: .white, bg: .rgb(24, 30, 48))
                        overlayBuf.clear(dlgRect, style: bgStyle)
                        overlayBuf.drawBorder(
                            dlgRect,
                            style: .rounded,
                            borderCellStyle: CellStyle(fg: .brightCyan, bg: .rgb(24, 30, 48), modifiers: [.bold]),
                            title: dlgTitle,
                            titleAlignment: .center,
                            bottomTitle: "↑↓:Select  ↵:Choose  Esc:Cancel"
                        )

                        var startY = dlgRect.minY + 1
                        if let msg = dlgMsg, !msg.isEmpty {
                            overlayBuf.writeString(
                                x: dlgRect.minX + 2,
                                y: startY,
                                UnicodeWidth.truncate(msg, maxWidth: w - 4),
                                style: CellStyle(fg: .brightBlack, bg: .rgb(24, 30, 48)),
                                maxWidth: w - 4
                            )
                            startY += 2
                        }

                        for (i, btn) in btns.enumerated() {
                            let rowY = startY + i
                            if rowY >= dlgRect.maxY - 1 { break }
                            let isHi = (i == clampedIdx)
                            let roleFg: Color = {
                                switch btn.role {
                                case .destructive: return .brightRed
                                case .cancel:      return .brightYellow
                                case .default:     return .brightCyan
                                }
                            }()
                            let prefix = isHi ? " ▶ " : "   "
                            let rowText = UnicodeWidth.fit(prefix + btn.title, width: w - 2)
                            let rowStyle = CellStyle(
                                fg: isHi ? .black : roleFg,
                                bg: isHi ? roleFg : .rgb(24, 30, 48),
                                modifiers: [.bold]
                            )
                            overlayBuf.writeString(x: dlgRect.minX + 1, y: rowY, rowText, style: rowStyle, maxWidth: w - 2)

                            let hitRect = Rect(x: dlgRect.minX + 1, y: rowY, width: w - 2, height: 1)
                            interactions.registerMouseTarget(rect: hitRect, zIndex: 258) { mouse in
                                if case .down(.left) = mouse.kind {
                                    binding.wrappedValue = false
                                    btn.action()
                                    store.markDirty()
                                    return true
                                }
                                return false
                            }
                        }
                    }
                }
            )
        }
    }
}

// MARK: - 4. Context Menu Modifier (.contextMenu)

/// An item in a floating right-click / shortcut `.contextMenu(...)`.
public struct ContextMenuItem: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let shortcutHint: String?
    public let role: AlertButtonRole
    public let action: @MainActor @Sendable () -> Void

    public init(
        _ label: String,
        shortcutHint: String? = nil,
        role: AlertButtonRole = .default,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.label = label
        self.shortcutHint = shortcutHint
        self.role = role
        self.action = action
    }
}

public struct _ContextMenuModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let items: [ContextMenuItem]

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        guard !items.isEmpty else { return baseNodes }

        let store = context.store
        let path = context.path
        let isOpenKey = "\(path).ctxOpen"
        let anchorKey = "\(path).ctxAnchor"
        let selectedKey = "\(path).ctxSel"
        let menuItems = items

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).contextMenuHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    let isOpen: Bool = store.widgetState(forPath: isOpenKey, default: false)
                    let anchor: Point = store.widgetState(forPath: anchorKey, default: Point(x: rect.minX + 2, y: rect.minY + 1))
                    let selIdx: Int = store.widgetState(forPath: selectedKey, default: 0)
                    let clampedSel = max(0, min(menuItems.count - 1, selIdx))

                    // Trigger context menu on right-click (MouseButton.right) anywhere inside `rect`
                    interactions.registerMouseTarget(rect: rect, zIndex: 15) { mouse in
                        if case .down(.right) = mouse.kind {
                            store.setWidgetState(Point(x: mouse.x, y: mouse.y), forPath: anchorKey, markDirty: false)
                            store.setWidgetState(0, forPath: selectedKey, markDirty: false)
                            store.setWidgetState(true, forPath: isOpenKey)
                            return true
                        }
                        return false
                    }

                    // Also allow Ctrl+E keyboard shortcut to open context menu
                    interactions.registerShortcut(
                        matches: { ev in ev.key == .char("e") && ev.modifiers == [.control] },
                        action: {
                            store.setWidgetState(Point(x: rect.minX + 2, y: rect.minY + 1), forPath: anchorKey, markDirty: false)
                            store.setWidgetState(0, forPath: selectedKey, markDirty: false)
                            store.setWidgetState(!isOpen, forPath: isOpenKey)
                        }
                    )

                    if isOpen {
                        interactions.registerPriorityKeyInterceptor(zIndex: 240) { key in
                            switch key.key {
                            case .escape:
                                store.setWidgetState(false, forPath: isOpenKey)
                                return true
                            case .up, .char("k"):
                                let prev = (clampedSel - 1 + menuItems.count) % menuItems.count
                                store.setWidgetState(prev, forPath: selectedKey)
                                return true
                            case .down, .char("j"), .tab:
                                let next = (clampedSel + 1) % menuItems.count
                                store.setWidgetState(next, forPath: selectedKey)
                                return true
                            case .enter, .space:
                                let chosen = menuItems[clampedSel]
                                store.setWidgetState(false, forPath: isOpenKey, markDirty: false)
                                chosen.action()
                                store.markDirty()
                                return true
                            default:
                                return false
                            }
                        }

                        buffer.addOverlay(zIndex: 240) { overlayBuf in
                            let maxLabelW = menuItems.map {
                                UnicodeWidth.width(of: $0.label) + ($0.shortcutHint.map { UnicodeWidth.width(of: $0) + 3 } ?? 0)
                            }.max() ?? 16
                            let menuW = min(overlayBuf.width - 2, max(22, maxLabelW + 6))
                            let menuH = min(overlayBuf.height - 2, menuItems.count + 2)
                            let x = min(anchor.x, max(0, overlayBuf.width - menuW))
                            let y = min(anchor.y, max(0, overlayBuf.height - menuH))
                            let menuRect = Rect(x: x, y: y, width: menuW, height: menuH)

                            let bgStyle = CellStyle(fg: .white, bg: .rgb(26, 30, 46))
                            overlayBuf.clear(menuRect, style: bgStyle)
                            overlayBuf.drawBorder(
                                menuRect,
                                style: .rounded,
                                borderCellStyle: CellStyle(fg: .brightMagenta, bg: .rgb(26, 30, 46), modifiers: [.bold]),
                                title: "Actions"
                            )

                            for (i, item) in menuItems.enumerated() {
                                let rowY = menuRect.minY + 1 + i
                                if rowY >= menuRect.maxY - 1 { break }
                                let isHi = (i == clampedSel)
                                let itemColor: Color = item.role == .destructive ? .brightRed : .white
                                let rStyle = CellStyle(
                                    fg: isHi ? .black : itemColor,
                                    bg: isHi ? .brightCyan : .rgb(26, 30, 46),
                                    modifiers: isHi ? [.bold] : []
                                )
                                let hintStr = item.shortcutHint.map { " \($0)" } ?? ""
                                let availLabelW = max(4, menuW - 4 - UnicodeWidth.width(of: hintStr))
                                let fitted = UnicodeWidth.fit(" " + item.label, width: availLabelW) + hintStr + " "
                                overlayBuf.writeString(x: menuRect.minX + 1, y: rowY, fitted, style: rStyle, maxWidth: menuW - 2)

                                let itemRect = Rect(x: menuRect.minX + 1, y: rowY, width: menuW - 2, height: 1)
                                interactions.registerMouseTarget(rect: itemRect, zIndex: 245) { mouse in
                                    if case .down(.left) = mouse.kind {
                                        store.setWidgetState(false, forPath: isOpenKey, markDirty: false)
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

// MARK: - 5. Toast Notification Banner Modifier (.toast)

/// Visual severity style for a floating `.toast(...)` notification banner.
public enum ToastStyle: Equatable, Sendable {
    case info
    case success
    case warning
    case error

    public var icon: String {
        switch self {
        case .info:    return "ℹ"
        case .success: return "✓"
        case .warning: return "⚠"
        case .error:   return "✖"
        }
    }

    public var color: Color {
        switch self {
        case .info:    return .brightCyan
        case .success: return .brightGreen
        case .warning: return .brightYellow
        case .error:   return .brightRed
        }
    }
}

public struct _ToastModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let isPresented: Binding<Bool>
    public let style: ToastStyle
    public let message: String

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        guard isPresented.wrappedValue, !message.isEmpty else { return baseNodes }

        let toastStyle = style
        let toastMsg = message
        let binding = isPresented
        let store = context.store

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).toastHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    buffer.addOverlay(zIndex: 280) { overlayBuf in
                        let text = " \(toastStyle.icon) \(toastMsg) "
                        let w = min(overlayBuf.width - 4, max(20, UnicodeWidth.width(of: text) + 4))
                        let h = 3
                        let x = max(1, overlayBuf.width - w - 2)
                        let y = 1
                        let toastRect = Rect(x: x, y: y, width: w, height: h)

                        let bg = CellStyle(fg: .brightWhite, bg: .rgb(24, 28, 42), modifiers: [.bold])
                        overlayBuf.clear(toastRect, style: bg)
                        overlayBuf.drawBorder(
                            toastRect,
                            style: .rounded,
                            borderCellStyle: CellStyle(fg: toastStyle.color, bg: .rgb(24, 28, 42), modifiers: [.bold])
                        )
                        overlayBuf.writeString(
                            x: toastRect.minX + 1,
                            y: toastRect.minY + 1,
                            UnicodeWidth.truncate(text, maxWidth: w - 2),
                            style: CellStyle(fg: toastStyle.color, bg: .rgb(24, 28, 42), modifiers: [.bold]),
                            maxWidth: w - 2
                        )

                        interactions.registerMouseTarget(rect: toastRect, zIndex: 285) { mouse in
                            if case .down(.left) = mouse.kind {
                                binding.wrappedValue = false
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }
                }
            )
        }
    }
}

// MARK: - View Extensions for Dialogs, Context Menus & Toasts

extension View {
    /// Presents a modal alert dialog when `isPresented` is true.
    public func alert(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String = "",
        buttons: [AlertButton] = [.default("OK")]
    ) -> some View {
        _AlertModifier(content: self, title: title, isPresented: isPresented, message: message, buttons: buttons)
    }

    /// Presents a vertical action-sheet confirmation dialog when `isPresented` is true.
    public func confirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        buttons: [AlertButton]
    ) -> some View {
        _ConfirmationDialogModifier(content: self, title: title, isPresented: isPresented, message: message, buttons: buttons)
    }

    /// Attaches a right-click (`MouseButton.right`) and `Ctrl+E` floating context menu to this view.
    public func contextMenu(items: [ContextMenuItem]) -> some View {
        _ContextMenuModifier(content: self, items: items)
    }

    /// Displays a non-blocking floating toast notification banner in the top-right corner when `isPresented` is true.
    public func toast(
        isPresented: Binding<Bool>,
        style: ToastStyle = .info,
        message: String
    ) -> some View {
        _ToastModifier(content: self, isPresented: isPresented, style: style, message: message)
    }
}
