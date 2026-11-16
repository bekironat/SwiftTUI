import Foundation

// MARK: - 1. Picker (Segmented & Floating Dropdown Menu)

/// Visual style of a `Picker` control.
public enum PickerStyle: Equatable, Sendable {
    /// Inline horizontal segmented bar (`[● Option A] [  Option B]`).
    case segmented
    /// Compact button (`[ ▾ Selected Option ]`) that opens a floating dropdown overlay (`zIndex: 180`).
    case menu
}

/// An option item inside a `Picker`.
public struct PickerOption<Value: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public var id: Value { value }
    public let label: String
    public let value: Value

    public init(_ label: String, value: Value) {
        self.label = label
        self.value = value
    }
}

/// A control for selecting from a set of mutually exclusive values, supporting `.segmented` and `.menu` dropdown styles.
/// Matches SwiftUI's `Picker`.
public struct Picker<Value: Hashable & Sendable>: View, _PrimitiveView {
    public typealias Body = Never
    public let title: String
    public let selection: Binding<Value>
    public let options: [PickerOption<Value>]
    public let style: PickerStyle
    public let customID: AnyHashable?

    public init(
        _ title: String = "",
        selection: Binding<Value>,
        options: [PickerOption<Value>],
        style: PickerStyle = .segmented,
        id: AnyHashable? = nil
    ) {
        self.title = title
        self.selection = selection
        self.options = options
        self.style = style
        self.customID = id
    }

    public func pickerStyle(_ newStyle: PickerStyle) -> Picker<Value> {
        Picker(title, selection: selection, options: options, style: newStyle, id: customID)
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let focusID = customID ?? AnyHashable("\(path).Picker")
        store.registerFocusable(focusID)

        let openStateKey = "\(path).isOpen"
        let highlightedKey = "\(path).highlightIdx"
        let opts = options
        let selBinding = selection
        let lblTitle = title
        let pickerStyle = style

        let titlePrefix = lblTitle.isEmpty ? "" : "\(lblTitle): "
        let titleW = UnicodeWidth.width(of: titlePrefix)

        return [
            RenderNode(
                id: "\(path).Picker",
                measure: { _ in
                    switch pickerStyle {
                    case .segmented:
                        let segW = opts.reduce(0) { $0 + UnicodeWidth.width(of: $1.label) + 5 } + max(0, opts.count - 1)
                        return Size(width: titleW + segW, height: 1)
                    case .menu:
                        let maxOptW = opts.map { UnicodeWidth.width(of: $0.label) }.max() ?? 8
                        return Size(width: titleW + maxOptW + 6, height: 1)
                    }
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty, !opts.isEmpty else { return }
                    let isFocused = (store.activeFocusID == focusID)
                    let currentIdx = opts.firstIndex(where: { $0.value == selBinding.wrappedValue }) ?? 0

                    var curX = rect.minX
                    if !titlePrefix.isEmpty {
                        let tStyle = CellStyle(fg: isFocused ? .brightCyan : .white, bg: context.environment.backgroundColor, modifiers: isFocused ? [.bold] : [])
                        curX += buffer.writeString(x: curX, y: rect.minY, titlePrefix, style: tStyle, maxWidth: rect.width)
                    }

                    switch pickerStyle {
                    case .segmented:
                        for (idx, opt) in opts.enumerated() {
                            if curX >= rect.maxX { break }
                            let isSelected = (idx == currentIdx)
                            let text = isSelected ? "[● \(opt.label)]" : "[  \(opt.label)]"
                            let segW = UnicodeWidth.width(of: text)
                            let fg: Color = isSelected ? (isFocused ? .black : .brightCyan) : .white
                            let bg: Color = isSelected ? (isFocused ? .brightCyan : .rgb(34, 42, 64)) : context.environment.backgroundColor
                            let segStyle = CellStyle(fg: fg, bg: bg, modifiers: isSelected ? [.bold] : [])

                            buffer.writeString(x: curX, y: rect.minY, text, style: segStyle, maxWidth: rect.maxX - curX)
                            let hitRect = Rect(x: curX, y: rect.minY, width: min(segW, rect.maxX - curX), height: 1)
                            interactions.registerMouseTarget(rect: hitRect, zIndex: 5) { mouse in
                                if case .down(.left) = mouse.kind {
                                    store.activeFocusID = focusID
                                    selBinding.wrappedValue = opt.value
                                    store.markDirty()
                                    return true
                                }
                                return false
                            }
                            curX += segW + 1
                        }

                        interactions.registerFocusedKeyHandler(for: focusID) { key in
                            switch key.key {
                            case .left, .char("h"):
                                let nextIdx = (currentIdx - 1 + opts.count) % opts.count
                                selBinding.wrappedValue = opts[nextIdx].value
                                store.markDirty()
                                return true
                            case .right, .char("l"), .space, .enter:
                                let nextIdx = (currentIdx + 1) % opts.count
                                selBinding.wrappedValue = opts[nextIdx].value
                                store.markDirty()
                                return true
                            default:
                                return false
                            }
                        }

                    case .menu:
                        let isOpen: Bool = store.widgetState(forPath: openStateKey, default: false)
                        let hiIdx: Int = store.widgetState(forPath: highlightedKey, default: currentIdx)
                        let selectedLabel = opts[currentIdx].label
                        let maxOptW = opts.map { UnicodeWidth.width(of: $0.label) }.max() ?? 8
                        let padded = UnicodeWidth.fit(selectedLabel, width: maxOptW)
                        let btnText = "[ ▾ \(padded) ]"
                        let btnW = UnicodeWidth.width(of: btnText)

                        let fg: Color = isFocused ? .black : .brightCyan
                        let bg: Color = isFocused ? .brightCyan : .rgb(30, 36, 54)
                        buffer.writeString(x: curX, y: rect.minY, btnText, style: CellStyle(fg: fg, bg: bg, modifiers: [.bold]), maxWidth: rect.maxX - curX)

                        let btnRect = Rect(x: curX, y: rect.minY, width: min(btnW, rect.maxX - curX), height: 1)
                        interactions.registerMouseTarget(rect: btnRect, zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = focusID
                                store.setWidgetState(!isOpen, forPath: openStateKey)
                                store.setWidgetState(currentIdx, forPath: highlightedKey)
                                return true
                            }
                            return false
                        }

                        interactions.registerFocusedKeyHandler(for: focusID) { key in
                            if key.key == .enter || key.key == .space || key.key == .down {
                                store.setWidgetState(true, forPath: openStateKey)
                                store.setWidgetState(currentIdx, forPath: highlightedKey)
                                return true
                            }
                            return false
                        }

                        if isOpen {
                            interactions.registerPriorityKeyInterceptor(zIndex: 185) { key in
                                switch key.key {
                                case .escape:
                                    store.setWidgetState(false, forPath: openStateKey)
                                    return true
                                case .up:
                                    let prev = (hiIdx - 1 + opts.count) % opts.count
                                    store.setWidgetState(prev, forPath: highlightedKey)
                                    return true
                                case .down:
                                    let next = (hiIdx + 1) % opts.count
                                    store.setWidgetState(next, forPath: highlightedKey)
                                    return true
                                case .enter, .space:
                                    let clamped = max(0, min(opts.count - 1, hiIdx))
                                    selBinding.wrappedValue = opts[clamped].value
                                    store.setWidgetState(false, forPath: openStateKey)
                                    return true
                                default:
                                    return false
                                }
                            }

                            let menuX = curX
                            let menuY = rect.minY + 1
                            let menuW = maxOptW + 6
                            let menuH = opts.count + 2

                            buffer.addOverlay(zIndex: 180) { overlayBuf in
                                let clampedX = min(menuX, max(0, overlayBuf.width - menuW))
                                let clampedY = (menuY + menuH <= overlayBuf.height) ? menuY : max(0, rect.minY - menuH)
                                let popupRect = Rect(x: clampedX, y: clampedY, width: menuW, height: menuH)
                                let bgStyle = CellStyle(fg: .white, bg: .rgb(24, 28, 44))
                                overlayBuf.clear(popupRect, style: bgStyle)
                                overlayBuf.drawBorder(popupRect, style: .rounded, borderCellStyle: CellStyle(fg: .brightCyan, bg: .rgb(24, 28, 44)))

                                for (i, opt) in opts.enumerated() {
                                    let rowY = popupRect.minY + 1 + i
                                    let isHi = (i == hiIdx)
                                    let isSel = (i == currentIdx)
                                    let prefix = isSel ? "✓ " : "  "
                                    let lineText = prefix + UnicodeWidth.fit(opt.label, width: maxOptW)
                                    let rStyle = CellStyle(
                                        fg: isHi ? .black : (isSel ? .brightYellow : .white),
                                        bg: isHi ? .brightCyan : .rgb(24, 28, 44),
                                        modifiers: (isHi || isSel) ? [.bold] : []
                                    )
                                    overlayBuf.writeString(x: popupRect.minX + 1, y: rowY, lineText, style: rStyle, maxWidth: menuW - 2)
                                    let itemRect = Rect(x: popupRect.minX + 1, y: rowY, width: menuW - 2, height: 1)
                                    interactions.registerMouseTarget(rect: itemRect, zIndex: 185) { mouse in
                                        if case .down(.left) = mouse.kind {
                                            selBinding.wrappedValue = opt.value
                                            store.setWidgetState(false, forPath: openStateKey)
                                            return true
                                        }
                                        return false
                                    }
                                }
                            }
                        }
                    }
                }
            )
        ]
    }
}

// MARK: - 2. Stepper (Numeric Increment / Decrement Control)

/// A control that performs increment and decrement actions.
/// Matches SwiftUI's `Stepper`.
public struct Stepper: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String
    public let valueText: String
    public let customID: AnyHashable?
    public let onIncrement: @MainActor () -> Void
    public let onDecrement: @MainActor () -> Void

    public init(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        id: AnyHashable? = nil
    ) {
        self.label = label
        self.valueText = "\(value.wrappedValue)"
        self.customID = id
        self.onIncrement = {
            value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
        }
        self.onDecrement = {
            value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
        }
    }

    public init(
        _ label: String,
        valueText: String = "",
        id: AnyHashable? = nil,
        onIncrement: @escaping @MainActor () -> Void,
        onDecrement: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.valueText = valueText
        self.customID = id
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let focusID = customID ?? AnyHashable("\(path).Stepper")
        store.registerFocusable(focusID)

        let displayPrefix = valueText.isEmpty ? label : "\(label): \(valueText)"
        let prefixW = UnicodeWidth.width(of: displayPrefix)
        let inc = onIncrement
        let dec = onDecrement

        return [
            RenderNode(
                id: "\(path).Stepper",
                measure: { _ in
                    Size(width: prefixW + 10, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == focusID)
                    let baseBg = context.environment.backgroundColor

                    let labelStyle = CellStyle(fg: isFocused ? .brightCyan : .white, bg: baseBg, modifiers: isFocused ? [.bold] : [])
                    let written = buffer.writeString(x: rect.minX, y: rect.minY, displayPrefix, style: labelStyle, maxWidth: rect.width)

                    let minusX = rect.minX + written + 2
                    let plusX = minusX + 4
                    let btnStyle = CellStyle(
                        fg: isFocused ? .black : .brightYellow,
                        bg: isFocused ? .brightYellow : .rgb(36, 40, 58),
                        modifiers: [.bold]
                    )

                    if minusX + 3 <= rect.maxX {
                        buffer.writeString(x: minusX, y: rect.minY, "[-]", style: btnStyle, maxWidth: 3)
                        interactions.registerMouseTarget(rect: Rect(x: minusX, y: rect.minY, width: 3, height: 1), zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = focusID
                                dec()
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }

                    if plusX + 3 <= rect.maxX {
                        buffer.writeString(x: plusX, y: rect.minY, "[+]", style: btnStyle, maxWidth: 3)
                        interactions.registerMouseTarget(rect: Rect(x: plusX, y: rect.minY, width: 3, height: 1), zIndex: 5) { mouse in
                            if case .down(.left) = mouse.kind {
                                store.activeFocusID = focusID
                                inc()
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }

                    interactions.registerFocusedKeyHandler(for: focusID) { key in
                        switch key.key {
                        case .left, .char("-"), .char("h"):
                            dec()
                            store.markDirty()
                            return true
                        case .right, .char("+"), .char("="), .char("l"), .enter, .space:
                            inc()
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

// MARK: - 3. Slider (Interactive Horizontal Track Control)

/// A control for selecting a value from a bounded linear range of values.
/// Matches SwiftUI's `Slider`.
public struct Slider: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String
    public let value: Binding<Double>
    public let bounds: ClosedRange<Double>
    public let step: Double
    public let trackWidth: Int
    public let color: Color
    public let customID: AnyHashable?

    public init(
        _ label: String = "",
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0.0...1.0,
        step: Double = 0.05,
        trackWidth: Int = 20,
        color: Color = .brightCyan,
        id: AnyHashable? = nil
    ) {
        self.label = label
        self.value = value
        self.bounds = bounds
        self.step = max(0.001, step)
        self.trackWidth = max(6, trackWidth)
        self.color = color
        self.customID = id
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let store = context.store
        let path = context.path
        let focusID = customID ?? AnyHashable("\(path).Slider")
        store.registerFocusable(focusID)

        let prefix = label.isEmpty ? "" : "\(label): "
        let prefixW = UnicodeWidth.width(of: prefix)
        let tWidth = trackWidth
        let valBinding = value
        let range = bounds
        let stepAmt = step
        let accent = color

        return [
            RenderNode(
                id: "\(path).Slider",
                measure: { _ in
                    Size(width: prefixW + tWidth + 8, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == focusID)
                    let baseBg = context.environment.backgroundColor

                    var curX = rect.minX
                    if !prefix.isEmpty {
                        let lblStyle = CellStyle(fg: isFocused ? .brightCyan : .white, bg: baseBg, modifiers: isFocused ? [.bold] : [])
                        curX += buffer.writeString(x: curX, y: rect.minY, prefix, style: lblStyle, maxWidth: rect.width)
                    }

                    let span = max(0.0001, range.upperBound - range.lowerBound)
                    let clampedVal = min(range.upperBound, max(range.lowerBound, valBinding.wrappedValue))
                    let ratio = (clampedVal - range.lowerBound) / span
                    let availTrackW = min(tWidth, max(4, rect.maxX - curX - 6))
                    let knobIndex = min(availTrackW - 1, max(0, Int((ratio * Double(availTrackW - 1)).rounded())))

                    let activeStyle = CellStyle(fg: accent, bg: baseBg, modifiers: [.bold])
                    let knobStyle = CellStyle(fg: isFocused ? .brightYellow : .brightWhite, bg: baseBg, modifiers: [.bold])
                    let inactiveStyle = CellStyle(fg: .brightBlack, bg: baseBg)

                    for i in 0..<availTrackW {
                        let colX = curX + i
                        if colX >= rect.maxX { break }
                        if i == knobIndex {
                            buffer.setCell(x: colX, y: rect.minY, symbol: "●", style: knobStyle)
                        } else if i < knobIndex {
                            buffer.setCell(x: colX, y: rect.minY, symbol: "━", style: activeStyle)
                        } else {
                            buffer.setCell(x: colX, y: rect.minY, symbol: "─", style: inactiveStyle)
                        }
                    }

                    let pct = Int((ratio * 100.0).rounded())
                    let pctText = String(format: " %3d%%", pct)
                    buffer.writeString(
                        x: curX + availTrackW,
                        y: rect.minY,
                        pctText,
                        style: CellStyle(fg: isFocused ? .brightYellow : .white, bg: baseBg, modifiers: isFocused ? [.bold] : []),
                        maxWidth: max(0, rect.maxX - (curX + availTrackW))
                    )

                    let trackRect = Rect(x: curX, y: rect.minY, width: availTrackW, height: 1)
                    let updateFromMouseX: @MainActor (Int) -> Void = { mouseX in
                        let rel = Double(max(0, min(availTrackW - 1, mouseX - curX))) / Double(max(1, availTrackW - 1))
                        let rawVal = range.lowerBound + rel * span
                        let stepped = (rawVal / stepAmt).rounded() * stepAmt
                        valBinding.wrappedValue = min(range.upperBound, max(range.lowerBound, stepped))
                        store.markDirty()
                    }

                    interactions.registerMouseTarget(rect: trackRect, zIndex: 5) { mouse in
                        switch mouse.kind {
                        case .down(.left), .drag(.left):
                            store.activeFocusID = focusID
                            updateFromMouseX(mouse.x)
                            return true
                        default:
                            return false
                        }
                    }

                    interactions.registerFocusedKeyHandler(for: focusID) { key in
                        switch key.key {
                        case .left, .char("h"), .char("-"):
                            valBinding.wrappedValue = max(range.lowerBound, valBinding.wrappedValue - stepAmt)
                            store.markDirty()
                            return true
                        case .right, .char("l"), .char("+"), .char("="):
                            valBinding.wrappedValue = min(range.upperBound, valBinding.wrappedValue + stepAmt)
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
