import Foundation

// MARK: - Rich Text & Markdown View (Zero-Dependency Terminal Markdown Renderer)

/// Renders Markdown-formatted text (headings, inline bold/italic/code, bulleted/numbered/task lists, blockquotes, horizontal rules, and fenced code blocks) into styled terminal lines.
public struct Markdown: View, _PrimitiveView {
    public typealias Body = Never
    public let content: String

    public init(_ content: String) {
        self.content = content
    }

    internal func _buildNodes(context: BuildContext) -> [RenderNode] {
        let baseBg = context.environment.backgroundColor
        let parsedBlocks = Self.parseBlocks(content)

        return [
            RenderNode(
                id: "\(context.path).Markdown",
                flexibleAxes: [.horizontal],
                measure: { proposal in
                    let w = proposal.width ?? 72
                    let lines = Self.layoutLines(blocks: parsedBlocks, width: w, baseBg: baseBg)
                    return Size(width: w, height: max(1, lines.count))
                },
                render: { rect, buffer, _ in
                    guard !rect.isEmpty else { return }
                    let lines = Self.layoutLines(blocks: parsedBlocks, width: rect.width, baseBg: baseBg)
                    for (idx, line) in lines.enumerated() {
                        let rowY = rect.minY + idx
                        if rowY >= rect.maxY { break }
                        buffer.writeSpans(x: rect.minX, y: rowY, line.spans, baseStyle: CellStyle(fg: .white, bg: baseBg), maxWidth: rect.width)
                    }
                }
            )
        ]
    }

    // MARK: - Block & Inline Markdown Parser

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String, lines: [String])
        case blockquote(text: String)
        case listItem(prefix: String, prefixColor: Color, text: String)
        case horizontalRule
        case paragraph(text: String)
        case blank
    }

    private static func parseBlocks(_ raw: String) -> [MarkdownBlock] {
        let rawLines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block: ```lang ... ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < rawLines.count {
                    if rawLines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(rawLines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang, lines: codeLines))
                continue
            }

            if trimmed.isEmpty {
                blocks.append(.blank)
                i += 1
                continue
            }

            // Horizontal rule: --- or ***
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Headings: #, ##, ###
            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Blockquote: > text
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let qText = trimmed.count > 2 ? String(trimmed.dropFirst(2)) : ""
                blocks.append(.blockquote(text: qText))
                i += 1
                continue
            }

            // Task list item: - [x] or - [ ]
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                blocks.append(.listItem(prefix: " [✓] ", prefixColor: .brightGreen, text: String(trimmed.dropFirst(6))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                blocks.append(.listItem(prefix: " [ ] ", prefixColor: .brightBlack, text: String(trimmed.dropFirst(6))))
                i += 1
                continue
            }

            // Bullet list: - or *
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.listItem(prefix: " • ", prefixColor: .brightCyan, text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Numbered list: 1. 2. etc.
            if let dotIdx = trimmed.firstIndex(of: "."),
               dotIdx != trimmed.startIndex,
               let num = Int(trimmed[..<dotIdx]),
               trimmed.index(after: dotIdx) < trimmed.endIndex,
               trimmed[trimmed.index(after: dotIdx)] == " " {
                let rest = String(trimmed[trimmed.index(dotIdx, offsetBy: 2)...])
                blocks.append(.listItem(prefix: " \(num). ", prefixColor: .brightYellow, text: rest))
                i += 1
                continue
            }

            blocks.append(.paragraph(text: line))
            i += 1
        }

        return blocks
    }

    private static func layoutLines(blocks: [MarkdownBlock], width: Int, baseBg: Color) -> [StyledLine] {
        var out: [StyledLine] = []
        let safeW = max(8, width)

        for block in blocks {
            switch block {
            case .blank:
                out.append(StyledLine(""))

            case .horizontalRule:
                let rule = String(repeating: "─", count: safeW)
                out.append(StyledLine([StyledSpan(rule, style: CellStyle(fg: .brightBlack, bg: baseBg))]))

            case .heading(let level, let text):
                let color: Color = (level == 1) ? .brightCyan : ((level == 2) ? .brightYellow : .brightGreen)
                let prefix = (level == 1) ? "◆ " : ((level == 2) ? "▸ " : "▪ ")
                let hStyle = CellStyle(fg: color, bg: baseBg, modifiers: level == 1 ? [.bold, .underlined] : [.bold])
                out.append(StyledLine([StyledSpan(prefix + text, style: hStyle)]))

            case .blockquote(let text):
                let spans = [StyledSpan(" ┃ ", style: CellStyle(fg: .brightMagenta, bg: baseBg, modifiers: [.bold]))]
                    + parseInlineSpans(text, baseStyle: CellStyle(fg: .brightWhite, bg: baseBg, modifiers: [.italic]))
                out.append(StyledLine(spans))

            case .listItem(let prefix, let prefixColor, let text):
                let spans = [StyledSpan(prefix, style: CellStyle(fg: prefixColor, bg: baseBg, modifiers: [.bold]))]
                    + parseInlineSpans(text, baseStyle: CellStyle(fg: .white, bg: baseBg))
                out.append(StyledLine(spans))

            case .codeBlock(let lang, let codeLines):
                let codeBg = Color.rgb(26, 30, 46)
                let borderW = min(safeW, max(24, (codeLines.map { UnicodeWidth.width(of: $0) }.max() ?? 16) + 6))
                let titleStr = lang.isEmpty ? " code " : " \(lang) "
                let topDashCount = max(1, borderW - 3 - UnicodeWidth.width(of: titleStr))
                let topBorder = "╭─" + titleStr + String(repeating: "─", count: topDashCount) + "╮"
                out.append(StyledLine([StyledSpan(topBorder, style: CellStyle(fg: .brightBlue, bg: baseBg, modifiers: [.bold]))]))

                for cLine in codeLines {
                    let fitted = UnicodeWidth.fit(" " + cLine, width: max(1, borderW - 2))
                    out.append(StyledLine([
                        StyledSpan("│", style: CellStyle(fg: .brightBlue, bg: baseBg)),
                        StyledSpan(fitted, style: CellStyle(fg: .brightGreen, bg: codeBg)),
                        StyledSpan("│", style: CellStyle(fg: .brightBlue, bg: baseBg))
                    ]))
                }

                let bottomBorder = "╰" + String(repeating: "─", count: max(1, borderW - 2)) + "╯"
                out.append(StyledLine([StyledSpan(bottomBorder, style: CellStyle(fg: .brightBlue, bg: baseBg))]))

            case .paragraph(let text):
                out.append(StyledLine(parseInlineSpans(text, baseStyle: CellStyle(fg: .white, bg: baseBg))))
            }
        }

        return out
    }

    /// Parses inline Markdown spans (`**bold**`, `*italic*`, and `` `inline code` ``).
    public static func parseInlineSpans(_ text: String, baseStyle: CellStyle = .default) -> [StyledSpan] {
        var spans: [StyledSpan] = []
        let chars = Array(text)
        let n = chars.count
        var i = 0
        var currentPlain = ""

        func flushPlain() {
            if !currentPlain.isEmpty {
                spans.append(StyledSpan(currentPlain, style: baseStyle))
                currentPlain = ""
            }
        }

        while i < n {
            // Inline code: `...`
            if chars[i] == "`" {
                if let endIdx = chars[(i + 1)..<n].firstIndex(of: "`") {
                    flushPlain()
                    let codeText = String(chars[(i + 1)..<endIdx])
                    let codeStyle = CellStyle(
                        fg: .brightYellow,
                        bg: .rgb(36, 40, 58),
                        modifiers: [.bold]
                    )
                    spans.append(StyledSpan(" \(codeText) ", style: codeStyle))
                    i = endIdx + 1
                    continue
                }
            }

            // Bold: **...**
            if i + 1 < n && chars[i] == "*" && chars[i + 1] == "*" {
                var closeIdx: Int? = nil
                var scan = i + 2
                while scan + 1 < n {
                    if chars[scan] == "*" && chars[scan + 1] == "*" {
                        closeIdx = scan
                        break
                    }
                    scan += 1
                }
                if let end = closeIdx {
                    flushPlain()
                    let boldText = String(chars[(i + 2)..<end])
                    var bStyle = baseStyle.bold()
                    bStyle.fg = .brightWhite
                    spans.append(StyledSpan(boldText, style: bStyle))
                    i = end + 2
                    continue
                }
            }

            // Italic: *...*
            if chars[i] == "*" {
                if let endIdx = chars[(i + 1)..<n].firstIndex(of: "*") {
                    flushPlain()
                    let italicText = String(chars[(i + 1)..<endIdx])
                    spans.append(StyledSpan(italicText, style: baseStyle.italic()))
                    i = endIdx + 1
                    continue
                }
            }

            currentPlain.append(chars[i])
            i += 1
        }

        flushPlain()
        return spans.isEmpty ? [StyledSpan("", style: baseStyle)] : spans
    }
}
