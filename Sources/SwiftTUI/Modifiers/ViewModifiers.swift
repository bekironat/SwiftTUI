import Foundation

// MARK: - Padding Modifier

public struct _PaddingModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let insets: EdgeInsets

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("Pad"))
        return children.map { child in
            RenderNode(
                id: "\(child.id).pad",
                layoutPriority: child.layoutPriority,
                isSpacer: child.isSpacer,
                minSpacerLength: child.minSpacerLength,
                flexibleAxes: child.flexibleAxes,
                measure: { proposal in
                    let innerW = proposal.width.map { max(0, $0 - insets.horizontal) }
                    let innerH = proposal.height.map { max(0, $0 - insets.vertical) }
                    let innerSize = child.sizeThatFits(ProposedViewSize(width: innerW, height: innerH))
                    return Size(
                        width: innerSize.width + insets.horizontal,
                        height: innerSize.height + insets.vertical
                    )
                },
                render: { rect, buffer, interactions in
                    let innerRect = rect.inset(by: insets)
                    guard !innerRect.isEmpty else { return }
                    child.render(in: innerRect, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}

// MARK: - Frame Modifier

public struct _FrameModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let minWidth: Int?
    public let idealWidth: Int?
    public let maxWidth: Int?
    public let minHeight: Int?
    public let idealHeight: Int?
    public let maxHeight: Int?
    public let alignment: Alignment

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("Frame"))
        let singleChild: RenderNode
        if children.count == 1 {
            singleChild = children[0]
        } else {
            singleChild = VStackLayoutEngine.makeNode(id: "\(context.path).FrameStack", alignment: .leading, spacing: 0, children: children)
        }

        var flex = singleChild.flexibleAxes
        if let maxWidth {
            if maxWidth >= ProposedViewSize.infinityDimension {
                flex.insert(.horizontal)
            } else {
                flex.remove(.horizontal)
            }
        }
        if let maxHeight {
            if maxHeight >= ProposedViewSize.infinityDimension {
                flex.insert(.vertical)
            } else {
                flex.remove(.vertical)
            }
        }

        return [
            RenderNode(
                id: "\(singleChild.id).frame",
                layoutPriority: singleChild.layoutPriority,
                flexibleAxes: flex,
                measure: { proposal in
                    let targetW = idealWidth ?? proposal.width
                    let targetH = idealHeight ?? proposal.height
                    let childProposal = ProposedViewSize(
                        width: targetW.map { min($0, maxWidth ?? $0) },
                        height: targetH.map { min($0, maxHeight ?? $0) }
                    )
                    let childSize = singleChild.sizeThatFits(childProposal)

                    var w = idealWidth ?? childSize.width
                    if let maxW = maxWidth {
                        if maxW >= ProposedViewSize.infinityDimension, let propW = proposal.width {
                            w = propW
                        } else {
                            w = min(w, maxW)
                        }
                    }
                    if let minW = minWidth {
                        w = max(w, minW)
                    }

                    var h = idealHeight ?? childSize.height
                    if let maxH = maxHeight {
                        if maxH >= ProposedViewSize.infinityDimension, let propH = proposal.height {
                            h = propH
                        } else {
                            h = min(h, maxH)
                        }
                    }
                    if let minH = minHeight {
                        h = max(h, minH)
                    }

                    return Size(width: w, height: h)
                },
                render: { rect, buffer, interactions in
                    let childSize = singleChild.sizeThatFits(ProposedViewSize(rect.size))
                    let w = singleChild.flexibleAxes.contains(.horizontal) ? rect.width : min(rect.width, childSize.width)
                    let h = singleChild.flexibleAxes.contains(.vertical) ? rect.height : min(rect.height, childSize.height)

                    let x: Int
                    switch alignment.horizontal {
                    case .leading:  x = rect.minX
                    case .center:   x = rect.minX + max(0, (rect.width - w) / 2)
                    case .trailing: x = rect.maxX - w
                    }
                    let y: Int
                    switch alignment.vertical {
                    case .top:    y = rect.minY
                    case .center: y = rect.minY + max(0, (rect.height - h) / 2)
                    case .bottom: y = rect.maxY - h
                    }

                    singleChild.render(in: Rect(x: x, y: y, width: w, height: h), buffer: &buffer, interactions: interactions)
                }
            )
        ]
    }
}

// MARK: - Border / Block Modifier (Ratatui Block Equivalent)

public struct _BorderModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let borderStyle: BorderStyle
    public let borderColor: Color?
    public let backgroundFill: Color?
    public let title: String?
    public let titleColor: Color?
    public let titleAlignment: HorizontalAlignment
    public let bottomTitle: String?

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("Border"))
        let childNode: RenderNode
        if children.count == 1 {
            childNode = children[0]
        } else {
            childNode = VStackLayoutEngine.makeNode(id: "\(context.path).BorderStack", alignment: .leading, spacing: 0, children: children)
        }

        let inset = borderStyle == .none ? 0 : 1
        let fg = borderColor ?? (context.environment.foregroundColor == .default ? .brightBlack : context.environment.foregroundColor)
        let bg = backgroundFill ?? context.environment.backgroundColor
        let borderCellStyle = CellStyle(fg: fg, bg: bg)
        let titleStyle = titleColor.map { CellStyle(fg: $0, bg: bg, modifiers: [.bold]) }

        return [
            RenderNode(
                id: "\(childNode.id).border",
                layoutPriority: childNode.layoutPriority,
                flexibleAxes: childNode.flexibleAxes,
                measure: { proposal in
                    let innerW = proposal.width.map { max(0, $0 - inset * 2) }
                    let innerH = proposal.height.map { max(0, $0 - inset * 2) }
                    let innerSize = childNode.sizeThatFits(ProposedViewSize(width: innerW, height: innerH))
                    return Size(
                        width: innerSize.width + inset * 2,
                        height: innerSize.height + inset * 2
                    )
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    if bg != .default {
                        buffer.fill(rect, symbol: " ", style: CellStyle(fg: .default, bg: bg))
                    }
                    if borderStyle != .none {
                        buffer.drawBorder(
                            rect,
                            style: borderStyle,
                            borderCellStyle: borderCellStyle,
                            title: title,
                            titleStyle: titleStyle,
                            titleAlignment: titleAlignment,
                            bottomTitle: bottomTitle
                        )
                    }
                    let innerRect = rect.inset(dx: inset, dy: inset)
                    if !innerRect.isEmpty {
                        buffer.withClip(innerRect) { buf in
                            childNode.render(in: innerRect, buffer: &buf, interactions: interactions)
                        }
                    }
                }
            )
        ]
    }
}

// MARK: - Environment & Style Modifiers

public struct _EnvironmentModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let transform: (inout EnvironmentValues) -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let modifiedContext = context.withEnvironment(transform)
        return resolveView(content, context: modifiedContext)
    }
}

public struct _BackgroundFillModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let color: Color

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let updatedContext = context.withEnvironment { $0.backgroundColor = color }
        let children = resolveView(content, context: updatedContext)
        return children.map { child in
            RenderNode(
                id: "\(child.id).bg",
                layoutPriority: child.layoutPriority,
                isSpacer: child.isSpacer,
                minSpacerLength: child.minSpacerLength,
                flexibleAxes: child.flexibleAxes,
                measure: child.measureClosure,
                render: { rect, buffer, interactions in
                    if color != .default {
                        buffer.fill(rect, symbol: " ", style: CellStyle(bg: color))
                    }
                    child.render(in: rect, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}

// MARK: - Event, Focus & Lifecycle Modifiers

public struct _KeyPressModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let handler: @MainActor (KeyEvent) -> Bool

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context)
        return children.map { child in
            RenderNode(
                id: child.id,
                layoutPriority: child.layoutPriority,
                isSpacer: child.isSpacer,
                minSpacerLength: child.minSpacerLength,
                flexibleAxes: child.flexibleAxes,
                measure: child.measureClosure,
                render: { rect, buffer, interactions in
                    interactions.registerBubbleKeyHandler(handler)
                    child.render(in: rect, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}

public struct _KeyboardShortcutModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let key: KeyCode
    public let modifiers: KeyModifiers
    public let action: @MainActor () -> Void

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context)
        let targetKey = key
        let targetMods = modifiers
        return children.map { child in
            RenderNode(
                id: child.id,
                layoutPriority: child.layoutPriority,
                isSpacer: child.isSpacer,
                minSpacerLength: child.minSpacerLength,
                flexibleAxes: child.flexibleAxes,
                measure: child.measureClosure,
                render: { rect, buffer, interactions in
                    interactions.registerShortcut(
                        matches: { ev in
                            ev.key == targetKey && ev.modifiers == targetMods
                        },
                        action: action
                    )
                    child.render(in: rect, buffer: &buffer, interactions: interactions)
                }
            )
        }
    }
}

public struct _ModalSheetModifier<Content: View, SheetContent: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let isPresented: Binding<Bool>
    public let title: String?
    public let modalWidth: Int?
    public let modalHeight: Int?
    public let sheetContent: @MainActor () -> SheetContent

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseNodes = resolveView(content, context: context)
        guard isPresented.wrappedValue else { return baseNodes }

        let sheetContext = context.appending("Sheet").withEnvironment { env in
            let binding = isPresented
            env.dismiss = DismissAction {
                Task { @MainActor in
                    binding.wrappedValue = false
                }
            }
        }
        let sheetNodes = resolveView(sheetContent(), context: sheetContext)
        let sheetNode = VStackLayoutEngine.makeNode(id: "\(sheetContext.path).stack", alignment: .leading, spacing: 0, children: sheetNodes)
        let modalTitle = title
        let reqW = modalWidth
        let reqH = modalHeight
        let binding = isPresented

        return baseNodes.map { base in
            RenderNode(
                id: "\(base.id).sheetHost",
                layoutPriority: base.layoutPriority,
                flexibleAxes: base.flexibleAxes,
                measure: base.measureClosure,
                render: { rect, buffer, interactions in
                    base.render(in: rect, buffer: &buffer, interactions: interactions)

                    // Intercept Esc key to dismiss modal sheet
                    interactions.registerPriorityKeyInterceptor(zIndex: 200) { keyEvent in
                        if keyEvent.key == .escape {
                            binding.wrappedValue = false
                            context.store.markDirty()
                            return true
                        }
                        return false
                    }

                    buffer.addOverlay(zIndex: 200) { overlayBuf in
                        let bounds = overlayBuf.bounds
                        let w = min(bounds.width - 4, reqW ?? max(44, (bounds.width * 2) / 3))
                        let h = min(bounds.height - 2, reqH ?? max(14, (bounds.height * 2) / 3))
                        let x = max(0, (bounds.width - w) / 2)
                        let y = max(0, (bounds.height - h) / 2)
                        let modalRect = Rect(x: x, y: y, width: w, height: h)

                        let modalBg = CellStyle(fg: .white, bg: .rgb(30, 32, 48))
                        overlayBuf.clear(modalRect, style: modalBg)
                        overlayBuf.drawBorder(
                            modalRect,
                            style: .double,
                            borderCellStyle: CellStyle(fg: .brightCyan, bg: .rgb(30, 32, 48), modifiers: [.bold]),
                            title: modalTitle,
                            titleAlignment: .center,
                            bottomTitle: "Esc: Close"
                        )
                        let inner = modalRect.inset(dx: 2, dy: 1)
                        if !inner.isEmpty {
                            overlayBuf.withClip(inner) { clippedBuf in
                                sheetNode.render(in: inner, buffer: &clippedBuf, interactions: interactions)
                            }
                        }
                    }
                }
            )
        }
    }
}

// MARK: - View Extension API

extension View {
    public func padding(_ insets: EdgeInsets) -> some View {
        _PaddingModifier(content: self, insets: insets)
    }

    public func padding(_ length: Int = 1) -> some View {
        _PaddingModifier(content: self, insets: EdgeInsets(all: length))
    }

    public func padding(_ edges: Edge.Set, _ length: Int = 1) -> some View {
        let insets = EdgeInsets(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0
        )
        return _PaddingModifier(content: self, insets: insets)
    }

    public func frame(
        width: Int? = nil,
        height: Int? = nil,
        alignment: Alignment = .topLeading
    ) -> some View {
        _FrameModifier(
            content: self,
            minWidth: width,
            idealWidth: width,
            maxWidth: width,
            minHeight: height,
            idealHeight: height,
            maxHeight: height,
            alignment: alignment
        )
    }

    public func frame(
        minWidth: Int? = nil,
        idealWidth: Int? = nil,
        maxWidth: Int? = nil,
        minHeight: Int? = nil,
        idealHeight: Int? = nil,
        maxHeight: Int? = nil,
        alignment: Alignment = .topLeading
    ) -> some View {
        _FrameModifier(
            content: self,
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight,
            alignment: alignment
        )
    }

    public func foregroundStyle(_ color: Color) -> some View {
        _EnvironmentModifier(content: self) { $0.foregroundColor = color }
    }

    public func foregroundColor(_ color: Color) -> some View {
        foregroundStyle(color)
    }

    public func background(_ color: Color) -> some View {
        _BackgroundFillModifier(content: self, color: color)
    }

    public func bold(_ isActive: Bool = true) -> some View {
        _EnvironmentModifier(content: self) { env in
            if isActive { env.cellModifiers.insert(.bold) }
            else { env.cellModifiers.remove(.bold) }
        }
    }

    public func italic(_ isActive: Bool = true) -> some View {
        _EnvironmentModifier(content: self) { env in
            if isActive { env.cellModifiers.insert(.italic) }
            else { env.cellModifiers.remove(.italic) }
        }
    }

    public func underline(_ isActive: Bool = true) -> some View {
        _EnvironmentModifier(content: self) { env in
            if isActive { env.cellModifiers.insert(.underlined) }
            else { env.cellModifiers.remove(.underlined) }
        }
    }

    public func dim(_ isActive: Bool = true) -> some View {
        _EnvironmentModifier(content: self) { env in
            if isActive { env.cellModifiers.insert(.dim) }
            else { env.cellModifiers.remove(.dim) }
        }
    }

    public func border(
        _ style: BorderStyle = .rounded,
        color: Color? = nil,
        background: Color? = nil,
        title: String? = nil,
        titleColor: Color? = nil,
        titleAlignment: HorizontalAlignment = .leading,
        bottomTitle: String? = nil
    ) -> some View {
        _BorderModifier(
            content: self,
            borderStyle: style,
            borderColor: color,
            backgroundFill: background,
            title: title,
            titleColor: titleColor,
            titleAlignment: titleAlignment,
            bottomTitle: bottomTitle
        )
    }

    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        _EnvironmentModifier(content: self) { $0[keyPath: keyPath] = value }
    }

    public func onKeyPress(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> some View {
        _KeyPressModifier(content: self, handler: handler)
    }

    public func keyboardShortcut(_ key: KeyCode, modifiers: KeyModifiers = [], action: @escaping @MainActor () -> Void) -> some View {
        _KeyboardShortcutModifier(content: self, key: key, modifiers: modifiers, action: action)
    }

    public func keyboardShortcut(_ char: Character, modifiers: KeyModifiers = [.control], action: @escaping @MainActor () -> Void) -> some View {
        _KeyboardShortcutModifier(content: self, key: .char(Character(char.lowercased())), modifiers: modifiers, action: action)
    }

    public func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        @ViewBuilder content: @escaping @MainActor () -> SheetContent
    ) -> some View {
        _ModalSheetModifier(
            content: self,
            isPresented: isPresented,
            title: title,
            modalWidth: width,
            modalHeight: height,
            sheetContent: content
        )
    }

    public func layoutPriority(_ priority: Double) -> some View {
        _LayoutPriorityModifier(content: self, priority: priority)
    }
}

// MARK: - Layout Priority Modifier

public struct _LayoutPriorityModifier<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let priority: Double

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let children = resolveView(content, context: context.appending("Priority"))
        return children.map { child in
            var node = child
            node.layoutPriority = priority
            return node
        }
    }
}
