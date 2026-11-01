import Foundation

// MARK: - Text

/// A view that displays one or more lines of read-only styled text in the terminal.
public struct Text: View, _PrimitiveView, Equatable, Sendable {
    public typealias Body = Never
    public var spans: [StyledSpan]
    public var alignment: HorizontalAlignment = .leading
    public var lineLimit: Int? = 1

    public init(_ content: String, style: CellStyle = .default) {
        self.spans = [StyledSpan(content, style: style)]
    }

    public init(spans: [StyledSpan], alignment: HorizontalAlignment = .leading, lineLimit: Int? = 1) {
        self.spans = spans
        self.alignment = alignment
        self.lineLimit = lineLimit
    }

    public var plainText: String {
        spans.map(\.text).joined()
    }

    /// Concatenates two `Text` views preserving each span's individual styling (SwiftUI `Text + Text`).
    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(spans: lhs.spans + rhs.spans, alignment: lhs.alignment, lineLimit: lhs.lineLimit ?? rhs.lineLimit)
    }

    public func bold(_ active: Bool = true) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            if active { st.modifiers.insert(.bold) } else { st.modifiers.remove(.bold) }
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func italic(_ active: Bool = true) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            if active { st.modifiers.insert(.italic) } else { st.modifiers.remove(.italic) }
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func underline(_ active: Bool = true) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            if active { st.modifiers.insert(.underlined) } else { st.modifiers.remove(.underlined) }
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func dim(_ active: Bool = true) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            if active { st.modifiers.insert(.dim) } else { st.modifiers.remove(.dim) }
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func foregroundStyle(_ color: Color) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            st.fg = color
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func foregroundColor(_ color: Color) -> Text {
        foregroundStyle(color)
    }

    public func background(_ color: Color) -> Text {
        var copy = self
        copy.spans = copy.spans.map { s in
            var st = s.style
            st.bg = color
            return StyledSpan(s.text, style: st)
        }
        return copy
    }

    public func multilineTextAlignment(_ alignment: HorizontalAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ limit: Int?) -> Text {
        var copy = self
        copy.lineLimit = limit
        return copy
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let envStyle = context.environment.effectiveCellStyle
        let currentSpans = spans
        let currentAlignment = alignment
        let currentLimit = lineLimit
        let rawText = plainText

        return [
            RenderNode(
                id: "\(context.path).Text",
                measure: { proposal in
                    let lines = rawText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    if currentLimit == 1 && lines.count <= 1 {
                        let w = UnicodeWidth.width(of: rawText)
                        let clampedW = proposal.width.map { min($0, w) } ?? w
                        return Size(width: clampedW, height: 1)
                    }
                    let wrapWidth = proposal.width ?? max(1, lines.map { UnicodeWidth.width(of: $0) }.max() ?? 1)
                    let wrapped = UnicodeWidth.wrap(rawText, maxWidth: max(1, wrapWidth))
                    let effectiveLines = currentLimit.map { Array(wrapped.prefix($0)) } ?? wrapped
                    let maxW = effectiveLines.map { UnicodeWidth.width(of: $0) }.max() ?? 0
                    return Size(width: maxW, height: max(1, effectiveLines.count))
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }

                    if (currentLimit == 1) && !rawText.contains("\n") {
                        let totalWidth = currentSpans.reduce(0) { $0 + $1.displayWidth }
                        let startX: Int
                        switch currentAlignment {
                        case .leading:
                            startX = rect.minX
                        case .center:
                            startX = rect.minX + max(0, (rect.width - min(rect.width, totalWidth)) / 2)
                        case .trailing:
                            startX = rect.maxX - min(rect.width, totalWidth)
                        }
                        buffer.writeSpans(x: startX, y: rect.minY, currentSpans, baseStyle: envStyle, maxWidth: rect.width)
                    } else {
                        let wrapped = UnicodeWidth.wrap(rawText, maxWidth: max(1, rect.width))
                        let effectiveLines = currentLimit.map { Array(wrapped.prefix($0)) } ?? wrapped
                        let mergedStyle = currentSpans.first.map { envStyle.merging($0.style) } ?? envStyle
                        for (idx, line) in effectiveLines.enumerated() {
                            let y = rect.minY + idx
                            if y >= rect.maxY { break }
                            let lineW = UnicodeWidth.width(of: line)
                            let startX: Int
                            switch currentAlignment {
                            case .leading:
                                startX = rect.minX
                            case .center:
                                startX = rect.minX + max(0, (rect.width - min(rect.width, lineW)) / 2)
                            case .trailing:
                                startX = rect.maxX - min(rect.width, lineW)
                            }
                            buffer.writeString(x: startX, y: y, line, style: mergedStyle, maxWidth: rect.width)
                        }
                    }
                }
            )
        ]
    }
}

// MARK: - Button

/// Interactive terminal button supporting focus, keyboard (`Enter`/`Space`), and mouse clicks.
public struct Button: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String
    public let focusID: AnyHashable?
    public let roleColor: Color?
    public let isFocusable: Bool
    public let action: @MainActor () -> Void

    public init(
        _ label: String,
        id: AnyHashable? = nil,
        color: Color? = nil,
        focusable: Bool = true,
        action: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.focusID = id
        self.roleColor = color
        self.isFocusable = focusable
        self.action = action
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let pathID = focusID ?? AnyHashable("\(context.path).Button[\(label)]")
        let store = context.store
        let text = "[\(label)]"
        let width = UnicodeWidth.width(of: text)

        if isFocusable {
            store.registerFocusable(pathID)
        }

        return [
            RenderNode(
                id: "\(context.path).Button",
                measure: { _ in
                    Size(width: width, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = isFocusable && (store.activeFocusID == pathID)
                    let fg: Color = isFocused ? .black : (roleColor ?? .brightCyan)
                    let bg: Color = isFocused ? .brightCyan : context.environment.backgroundColor
                    let style = CellStyle(fg: fg, bg: bg, modifiers: isFocused ? [.bold] : [])

                    buffer.writeString(x: rect.minX, y: rect.minY, text, style: style, maxWidth: rect.width)

                    if isFocusable {
                        interactions.registerFocusedKeyHandler(for: pathID) { key in
                            if key.key == .enter || key.key == .space {
                                action()
                                store.markDirty()
                                return true
                            }
                            return false
                        }
                    }

                    interactions.registerMouseTarget(rect: Rect(x: rect.minX, y: rect.minY, width: min(rect.width, width), height: 1), zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            if isFocusable {
                                store.activeFocusID = pathID
                            }
                            action()
                            store.markDirty()
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - Toggle

/// A checkbox/switch control that toggles a boolean binding.
public struct Toggle: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String
    public let isOn: Binding<Bool>
    public let focusID: AnyHashable?

    public init(_ label: String, isOn: Binding<Bool>, id: AnyHashable? = nil) {
        self.label = label
        self.isOn = isOn
        self.focusID = id
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let pathID = focusID ?? AnyHashable("\(context.path).Toggle[\(label)]")
        let store = context.store
        store.registerFocusable(pathID)

        let display = isOn.wrappedValue ? "[✓] \(label)" : "[ ] \(label)"
        let width = UnicodeWidth.width(of: display)
        let binding = isOn

        return [
            RenderNode(
                id: "\(context.path).Toggle",
                measure: { _ in
                    Size(width: width, height: 1)
                },
                render: { rect, buffer, interactions in
                    guard !rect.isEmpty else { return }
                    let isFocused = (store.activeFocusID == pathID)
                    let fg: Color = isFocused ? .brightYellow : (binding.wrappedValue ? .brightGreen : .white)
                    let style = CellStyle(fg: fg, bg: context.environment.backgroundColor, modifiers: isFocused ? [.bold] : [])
                    buffer.writeString(x: rect.minX, y: rect.minY, display, style: style, maxWidth: rect.width)

                    interactions.registerFocusedKeyHandler(for: pathID) { key in
                        if key.key == .enter || key.key == .space {
                            binding.wrappedValue.toggle()
                            store.markDirty()
                            return true
                        }
                        return false
                    }

                    interactions.registerMouseTarget(rect: Rect(x: rect.minX, y: rect.minY, width: min(rect.width, width), height: 1), zIndex: 5) { mouse in
                        if case .down(.left) = mouse.kind {
                            store.activeFocusID = pathID
                            binding.wrappedValue.toggle()
                            store.markDirty()
                            return true
                        }
                        return false
                    }
                }
            )
        ]
    }
}

// MARK: - Gauge / ProgressView & Sparkline (Ratatui Visualizations)

/// A horizontal progress bar / gauge modeled after Ratatui's `Gauge` and SwiftUI's `ProgressView`.
public struct Gauge: View, _PrimitiveView {
    public typealias Body = Never
    public let label: String?
    public let value: Double // 0.0 ... 1.0
    public let color: Color

    public init(_ label: String? = nil, value: Double, color: Color = .brightGreen) {
        self.label = label
        self.value = max(0.0, min(1.0, value))
        self.color = color
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let clamped = value
        let barColor = color
        let title = label
        return [
            RenderNode(
                id: "\(context.path).Gauge",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? 20, height: 1)
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }
                    let filledCount = Int((Double(rect.width) * clamped).rounded())
                    for i in 0..<rect.width {
                        let isFilled = i < filledCount
                        let sym = isFilled ? "█" : "░"
                        let fg = isFilled ? barColor : .brightBlack
                        buffer.setCell(x: rect.minX + i, y: rect.minY, symbol: sym, style: CellStyle(fg: fg))
                    }
                    let pctText = title.map { "\($0) \(Int(clamped * 100))%" } ?? "\(Int(clamped * 100))%"
                    let textW = UnicodeWidth.width(of: pctText)
                    if textW <= rect.width {
                        let startX = rect.minX + (rect.width - textW) / 2
                        buffer.writeString(
                            x: startX,
                            y: rect.minY,
                            pctText,
                            style: CellStyle(fg: .white, bg: .black, modifiers: [.bold])
                        )
                    }
                }
            )
        ]
    }
}

/// Renders a compact mini-chart using Unicode block levels (`▁▂▃▄▅▆▇█`), matching Ratatui's `Sparkline`.
public struct Sparkline: View, _PrimitiveView {
    public typealias Body = Never
    public let data: [Double]
    public let color: Color

    private static let bars: [String] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    public init(_ data: [Double], color: Color = .brightCyan) {
        self.data = data
        self.color = color
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let values = data
        let barColor = color
        return [
            RenderNode(
                id: "\(context.path).Sparkline",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    Size(width: proposal.width ?? max(1, values.count), height: 1)
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty, !values.isEmpty else { return }
                    let maxVal = max(values.max() ?? 1.0, 0.0001)
                    let minVal = min(values.min() ?? 0.0, 0.0)
                    let span = max(maxVal - minVal, 0.0001)
                    let count = min(rect.width, values.count)
                    let slice = values.suffix(count)

                    for (idx, val) in slice.enumerated() {
                        let norm = max(0.0, min(1.0, (val - minVal) / span))
                        let level = min(Self.bars.count - 1, Int((norm * Double(Self.bars.count - 1)).rounded()))
                        buffer.setCell(
                            x: rect.minX + idx,
                            y: rect.minY,
                            symbol: Self.bars[level],
                            style: CellStyle(fg: barColor)
                        )
                    }
                }
            )
        ]
    }
}
