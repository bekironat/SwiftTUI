import Foundation

/// Calculates terminal column display widths of Unicode scalars, extended grapheme clusters,
/// and strings according to Unicode Standard Annex #11 (East Asian Width) and terminal emoji conventions.
public enum UnicodeWidth {

    /// Returns the terminal column width (0, 1, or 2) of a single `Unicode.Scalar`.
    @inlinable
    public static func scalarWidth(_ scalar: Unicode.Scalar) -> Int {
        let v = scalar.value

        // Fast path for printable ASCII
        if v >= 0x20 && v < 0x7F {
            return 1
        }

        // C0/C1 control characters and DEL
        if v < 0x20 || (v >= 0x7F && v < 0xA0) {
            return 0
        }

        // Zero-width spaces, joiners, directional marks, variation selectors, BOM
        if (v >= 0x0300 && v <= 0x036F) || // Combining Diacritical Marks
           (v >= 0x0483 && v <= 0x0489) || // Cyrillic combining
           (v >= 0x0591 && v <= 0x05BD) ||
           v == 0x05BF ||
           (v >= 0x05C1 && v <= 0x05C2) ||
           (v >= 0x05C4 && v <= 0x05C5) ||
           v == 0x05C7 ||
           (v >= 0x0600 && v <= 0x0605) ||
           (v >= 0x0610 && v <= 0x061A) ||
           (v >= 0x064B && v <= 0x065F) ||
           v == 0x0670 ||
           (v >= 0x06D6 && v <= 0x06DD) ||
           (v >= 0x06DF && v <= 0x06E4) ||
           (v >= 0x06E7 && v <= 0x06E8) ||
           (v >= 0x06EA && v <= 0x06ED) ||
           (v >= 0x1AB0 && v <= 0x1AFF) ||
           (v >= 0x1DC0 && v <= 0x1DFF) ||
           (v >= 0x200B && v <= 0x200F) || // ZWSP, ZWNJ, ZWJ, LRM, RLM
           (v >= 0x202A && v <= 0x202E) ||
           (v >= 0x2060 && v <= 0x206F) ||
           (v >= 0x20D0 && v <= 0x20FF) ||
           (v >= 0xFE00 && v <= 0xFE0F) || // Variation Selectors
           (v >= 0xFE20 && v <= 0xFE2F) ||
           v == 0xFEFF ||                  // ZWNBSP / BOM
           (v >= 0xFFF9 && v <= 0xFFFB) ||
           (v >= 0xE0100 && v <= 0xE01EF) {
            return 0
        }

        // Wide & Fullwidth ranges (CJK, Hangul, Emojis)
        if (v >= 0x1100 && v <= 0x115F) || // Hangul Choseong
           v == 0x231A || v == 0x231B ||   // Watch, Hourglass
           (v >= 0x2329 && v <= 0x232A) ||
           (v >= 0x23E9 && v <= 0x23F3) ||
           (v >= 0x23F8 && v <= 0x23FA) ||
           v == 0x25FD || v == 0x25FE ||
           (v >= 0x2614 && v <= 0x2615) ||
           (v >= 0x2648 && v <= 0x2653) ||
           v == 0x267F || v == 0x2693 || v == 0x26A1 ||
           (v >= 0x26AA && v <= 0x26AB) ||
           (v >= 0x26BD && v <= 0x26BE) ||
           (v >= 0x26C4 && v <= 0x26C5) ||
           v == 0x26CE || v == 0x26D4 || v == 0x26EA ||
           (v >= 0x26F2 && v <= 0x26F3) ||
           v == 0x26F5 || v == 0x26FA || v == 0x26FD ||
           v == 0x2705 || v == 0x270A || v == 0x270B ||
           v == 0x2728 || v == 0x274C || v == 0x274E ||
           (v >= 0x2753 && v <= 0x2755) ||
           v == 0x2757 ||
           (v >= 0x2795 && v <= 0x2797) ||
           v == 0x27B0 || v == 0x27BF ||
           (v >= 0x2B1B && v <= 0x2B1C) ||
           v == 0x2B50 || v == 0x2B55 ||
           (v >= 0x2E80 && v <= 0x303E) || // CJK Radicals, Kangxi, Ideographic
           (v >= 0x3040 && v <= 0xA4CF) || // Hiragana, Katakana, Bopomofo, CJK Unified, Yi
           (v >= 0xAC00 && v <= 0xD7A3) || // Hangul Syllables
           (v >= 0xF900 && v <= 0xFAFF) || // CJK Compatibility Ideographs
           (v >= 0xFE10 && v <= 0xFE19) ||
           (v >= 0xFE30 && v <= 0xFE6F) ||
           (v >= 0xFF01 && v <= 0xFF60) || // Fullwidth ASCII variants
           (v >= 0xFFE0 && v <= 0xFFE6) ||
           (v >= 0x1F000 && v <= 0x1FAFF) || // Mahjong, Domino, Playing Cards, Pictographs, Emojis
           (v >= 0x20000 && v <= 0x3FFFD) {  // Supplementary Ideographic Planes
            return 2
        }

        return 1
    }

    /// Returns the terminal column width (0, 1, or 2) of a Swift `Character` (extended grapheme cluster).
    @inlinable
    public static func width(of character: Character) -> Int {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return 0 }

        // Fast path for single-scalar ASCII
        if scalars.count == 1 && first.value >= 0x20 && first.value < 0x7F {
            return 1
        }

        // Check for explicit emoji presentation variation selector (U+FE0F)
        var hasEmojiPresentationSelector = false
        var hasTextPresentationSelector = false
        var maxWidth = 0

        for s in scalars {
            if s.value == 0xFE0F {
                hasEmojiPresentationSelector = true
            } else if s.value == 0xFE0E {
                hasTextPresentationSelector = true
            }
            let w = scalarWidth(s)
            if w > maxWidth {
                maxWidth = w
            }
        }

        if hasTextPresentationSelector && maxWidth <= 1 {
            return 1
        }
        if hasEmojiPresentationSelector && maxWidth > 0 {
            return 2
        }

        return maxWidth
    }

    /// Returns the total terminal column width of a `String`.
    @inlinable
    public static func width(of string: String) -> Int {
        var total = 0
        for ch in string {
            total += width(of: ch)
        }
        return total
    }

    /// Truncates a string so its terminal display width does not exceed `maxWidth`.
    public static func truncate(_ string: String, maxWidth: Int, ellipsis: String = "…") -> String {
        guard maxWidth > 0 else { return "" }
        let fullWidth = width(of: string)
        if fullWidth <= maxWidth {
            return string
        }

        let ellipsisWidth = width(of: ellipsis)
        if maxWidth <= ellipsisWidth {
            var prefix = ""
            var currentWidth = 0
            for ch in string {
                let w = width(of: ch)
                if currentWidth + w > maxWidth { break }
                prefix.append(ch)
                currentWidth += w
            }
            return prefix
        }

        let targetWidth = maxWidth - ellipsisWidth
        var result = ""
        var currentWidth = 0
        for ch in string {
            let w = width(of: ch)
            if currentWidth + w > targetWidth {
                break
            }
            result.append(ch)
            currentWidth += w
        }
        result.append(ellipsis)
        return result
    }

    /// Pads or truncates `string` to fit exactly `targetWidth` columns.
    public static func fit(
        _ string: String,
        width targetWidth: Int,
        alignment: HorizontalAlignment = .leading,
        ellipsis: String = "…"
    ) -> String {
        guard targetWidth > 0 else { return "" }
        let truncated = truncate(string, maxWidth: targetWidth, ellipsis: ellipsis)
        let currentWidth = width(of: truncated)
        let remaining = max(0, targetWidth - currentWidth)
        if remaining == 0 {
            return truncated
        }
        switch alignment {
        case .leading:
            return truncated + String(repeating: " ", count: remaining)
        case .trailing:
            return String(repeating: " ", count: remaining) + truncated
        case .center:
            let left = remaining / 2
            let right = remaining - left
            return String(repeating: " ", count: left) + truncated + String(repeating: " ", count: right)
        }
    }

    /// Word-wraps `string` into lines whose display width does not exceed `maxWidth`.
    public static func wrap(_ string: String, maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [] }
        let paragraphs = string.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [String] = []

        for paragraph in paragraphs {
            if paragraph.isEmpty {
                lines.append("")
                continue
            }

            var currentLine = ""
            var currentWidth = 0

            let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
            for (index, wordSub) in words.enumerated() {
                let word = String(wordSub)
                let wordW = width(of: word)
                let spaceNeeded = (index > 0 && !currentLine.isEmpty) ? 1 : 0

                if currentWidth + spaceNeeded + wordW <= maxWidth {
                    if spaceNeeded > 0 {
                        currentLine.append(" ")
                        currentWidth += 1
                    }
                    currentLine.append(word)
                    currentWidth += wordW
                } else if wordW > maxWidth {
                    // Break long word character by character
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                        currentLine = ""
                        currentWidth = 0
                    }
                    for ch in word {
                        let cw = width(of: ch)
                        if currentWidth + cw > maxWidth && currentWidth > 0 {
                            lines.append(currentLine)
                            currentLine = ""
                            currentWidth = 0
                        }
                        currentLine.append(ch)
                        currentWidth += cw
                    }
                } else {
                    if !currentLine.isEmpty {
                        lines.append(currentLine)
                    }
                    currentLine = word
                    currentWidth = wordW
                }
            }
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }
}

extension String {
    /// The terminal column display width of this string.
    public var displayWidth: Int {
        UnicodeWidth.width(of: self)
    }
}
