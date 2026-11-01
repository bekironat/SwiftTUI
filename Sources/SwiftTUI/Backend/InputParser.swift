import Foundation

/// Stateful VT/ANSI byte stream parser converting raw terminal input bytes into `TerminalEvent` values.
public struct ANSIInputParser: Sendable {
    public init() {}

    public func parse(_ bytes: [UInt8]) -> [TerminalEvent] {
        var events: [TerminalEvent] = []
        var i = 0
        let count = bytes.count

        while i < count {
            let b = bytes[i]

            if b == 0x1B {
                // Escape sequence or bare ESC
                if i + 1 >= count {
                    events.append(.key(KeyEvent(.escape)))
                    i += 1
                    continue
                }

                let next = bytes[i + 1]
                if next == UInt8(ascii: "[") {
                    // Check for bracketed paste start: ESC [ 200 ~
                    if let (pasteText, consumed) = tryParseBracketedPaste(bytes, from: i) {
                        events.append(.paste(pasteText))
                        i += consumed
                        continue
                    }

                    // CSI sequence
                    let (event, consumed) = parseCSI(bytes, from: i + 2)
                    if let event {
                        events.append(event)
                    }
                    i += 2 + consumed
                    continue
                } else if next == UInt8(ascii: "O") {
                    // SS3 sequence: ESC O <final>
                    if i + 2 < count {
                        let code = bytes[i + 2]
                        if let ev = parseSS3(code) {
                            events.append(.key(ev))
                        }
                        i += 3
                        continue
                    } else {
                        events.append(.key(KeyEvent(.escape)))
                        i += 1
                        continue
                    }
                } else if next == 0x1B {
                    events.append(.key(KeyEvent(.escape)))
                    i += 1
                    continue
                } else {
                    // Alt + character
                    let (char, charLen) = decodeUTF8Character(bytes, from: i + 1)
                    if let char {
                        if char == "\u{7F}" || char == "\u{08}" {
                            events.append(.key(KeyEvent(.backspace, modifiers: [.alt])))
                        } else {
                            events.append(.key(KeyEvent(.char(char), modifiers: [.alt])))
                        }
                        i += 1 + charLen
                    } else {
                        events.append(.key(KeyEvent(.escape)))
                        i += 1
                    }
                    continue
                }
            }

            // Control codes
            switch b {
            case 0x00:
                // Ctrl+Space (NUL)
                events.append(.key(KeyEvent(.space, modifiers: [.control])))
                i += 1
            case 0x09:
                events.append(.key(KeyEvent(.tab)))
                i += 1
            case 0x0A, 0x0D:
                events.append(.key(KeyEvent(.enter)))
                i += 1
            case 0x7F, 0x08:
                events.append(.key(KeyEvent(.backspace)))
                i += 1
            case 0x01...0x1A:
                let scalar = UnicodeScalar(UInt32(b) - 1 + UInt32(UInt8(ascii: "a")))!
                events.append(.key(KeyEvent(.char(Character(scalar)), modifiers: [.control])))
                i += 1
            case 0x20:
                events.append(.key(KeyEvent(.space)))
                i += 1
            default:
                let (char, len) = decodeUTF8Character(bytes, from: i)
                if let char {
                    events.append(.key(KeyEvent(.char(char))))
                    i += max(1, len)
                } else {
                    i += 1
                }
            }
        }

        return events
    }

    // MARK: - Bracketed Paste

    private func tryParseBracketedPaste(_ bytes: [UInt8], from start: Int) -> (String, Int)? {
        let startMarker: [UInt8] = [0x1B, UInt8(ascii: "["), UInt8(ascii: "2"), UInt8(ascii: "0"), UInt8(ascii: "0"), UInt8(ascii: "~")]
        let endMarker: [UInt8] = [0x1B, UInt8(ascii: "["), UInt8(ascii: "2"), UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "~")]

        guard start + startMarker.count <= bytes.count else { return nil }
        for k in 0..<startMarker.count {
            if bytes[start + k] != startMarker[k] {
                return nil
            }
        }

        let contentStart = start + startMarker.count
        var scan = contentStart
        while scan + endMarker.count <= bytes.count {
            var matched = true
            for k in 0..<endMarker.count {
                if bytes[scan + k] != endMarker[k] {
                    matched = false
                    break
                }
            }
            if matched {
                let slice = Array(bytes[contentStart..<scan])
                let text = String(decoding: slice, as: UTF8.self)
                return (text, (scan + endMarker.count) - start)
            }
            scan += 1
        }

        // If end marker wasn't in the same packet, take remaining bytes as paste
        let slice = Array(bytes[contentStart..<bytes.count])
        let text = String(decoding: slice, as: UTF8.self)
        return (text, bytes.count - start)
    }

    // MARK: - CSI Sequences

    private func parseCSI(_ bytes: [UInt8], from start: Int) -> (TerminalEvent?, Int) {
        var idx = start
        let count = bytes.count

        // SGR mouse: ESC [ < btn ; col ; row M/m
        if idx < count && bytes[idx] == UInt8(ascii: "<") {
            idx += 1
            var paramBytes: [UInt8] = []
            while idx < count {
                let b = bytes[idx]
                if b == UInt8(ascii: "M") || b == UInt8(ascii: "m") {
                    let isRelease = (b == UInt8(ascii: "m"))
                    let paramStr = String(decoding: paramBytes, as: UTF8.self)
                    let parts = paramStr.split(separator: ";").compactMap { Int($0) }
                    if parts.count == 3 {
                        let ev = decodeSGRMouse(buttonCode: parts[0], col1Based: parts[1], row1Based: parts[2], isRelease: isRelease)
                        return (.mouse(ev), (idx + 1) - start)
                    }
                    return (nil, (idx + 1) - start)
                }
                paramBytes.append(b)
                idx += 1
            }
            return (nil, idx - start)
        }

        var paramBytes: [UInt8] = []
        while idx < count {
            let b = bytes[idx]
            if b >= 0x40 && b <= 0x7E {
                let finalByte = b
                let consumed = (idx + 1) - start
                let paramStr = String(decoding: paramBytes, as: UTF8.self)
                let ev = decodeCSIKey(paramStr: paramStr, finalByte: finalByte)
                return (ev.map { .key($0) }, consumed)
            }
            paramBytes.append(b)
            idx += 1
        }

        return (nil, idx - start)
    }

    private func decodeCSIKey(paramStr: String, finalByte: UInt8) -> KeyEvent? {
        let parts = paramStr.split(separator: ";").compactMap { Int($0) }
        let firstParam = parts.first ?? 1
        let modifierCode = parts.count >= 2 ? parts[1] : 1
        let modifiers = decodeModifiers(modifierCode)

        switch finalByte {
        case UInt8(ascii: "A"): return KeyEvent(.up, modifiers: modifiers)
        case UInt8(ascii: "B"): return KeyEvent(.down, modifiers: modifiers)
        case UInt8(ascii: "C"): return KeyEvent(.right, modifiers: modifiers)
        case UInt8(ascii: "D"): return KeyEvent(.left, modifiers: modifiers)
        case UInt8(ascii: "H"): return KeyEvent(.home, modifiers: modifiers)
        case UInt8(ascii: "F"): return KeyEvent(.end, modifiers: modifiers)
        case UInt8(ascii: "Z"): return KeyEvent(.backTab, modifiers: modifiers.union([.shift]))
        case UInt8(ascii: "P"): return KeyEvent(.f(1), modifiers: modifiers)
        case UInt8(ascii: "Q"): return KeyEvent(.f(2), modifiers: modifiers)
        case UInt8(ascii: "R"): return KeyEvent(.f(3), modifiers: modifiers)
        case UInt8(ascii: "S"): return KeyEvent(.f(4), modifiers: modifiers)
        case UInt8(ascii: "u"):
            // Kitty / CSI u keyboard protocol: ESC [ <unicode> ; <modifiers> u
            switch firstParam {
            case 9: return KeyEvent(.tab, modifiers: modifiers)
            case 13: return KeyEvent(.enter, modifiers: modifiers)
            case 27: return KeyEvent(.escape, modifiers: modifiers)
            case 32: return KeyEvent(.space, modifiers: modifiers)
            case 127: return KeyEvent(.backspace, modifiers: modifiers)
            default:
                if let scalar = UnicodeScalar(firstParam) {
                    return KeyEvent(.char(Character(scalar)), modifiers: modifiers)
                }
                return nil
            }
        case UInt8(ascii: "~"):
            switch firstParam {
            case 1, 7: return KeyEvent(.home, modifiers: modifiers)
            case 2:    return KeyEvent(.insert, modifiers: modifiers)
            case 3:    return KeyEvent(.delete, modifiers: modifiers)
            case 4, 8: return KeyEvent(.end, modifiers: modifiers)
            case 5:    return KeyEvent(.pageUp, modifiers: modifiers)
            case 6:    return KeyEvent(.pageDown, modifiers: modifiers)
            case 11:   return KeyEvent(.f(1), modifiers: modifiers)
            case 12:   return KeyEvent(.f(2), modifiers: modifiers)
            case 13:   return KeyEvent(.f(3), modifiers: modifiers)
            case 14:   return KeyEvent(.f(4), modifiers: modifiers)
            case 15:   return KeyEvent(.f(5), modifiers: modifiers)
            case 17:   return KeyEvent(.f(6), modifiers: modifiers)
            case 18:   return KeyEvent(.f(7), modifiers: modifiers)
            case 19:   return KeyEvent(.f(8), modifiers: modifiers)
            case 20:   return KeyEvent(.f(9), modifiers: modifiers)
            case 21:   return KeyEvent(.f(10), modifiers: modifiers)
            case 23:   return KeyEvent(.f(11), modifiers: modifiers)
            case 24:   return KeyEvent(.f(12), modifiers: modifiers)
            default:   return nil
            }
        default:
            return nil
        }
    }

    private func parseSS3(_ byte: UInt8) -> KeyEvent? {
        switch byte {
        case UInt8(ascii: "A"): return KeyEvent(.up)
        case UInt8(ascii: "B"): return KeyEvent(.down)
        case UInt8(ascii: "C"): return KeyEvent(.right)
        case UInt8(ascii: "D"): return KeyEvent(.left)
        case UInt8(ascii: "H"): return KeyEvent(.home)
        case UInt8(ascii: "F"): return KeyEvent(.end)
        case UInt8(ascii: "P"): return KeyEvent(.f(1))
        case UInt8(ascii: "Q"): return KeyEvent(.f(2))
        case UInt8(ascii: "R"): return KeyEvent(.f(3))
        case UInt8(ascii: "S"): return KeyEvent(.f(4))
        default: return nil
        }
    }

    private func decodeModifiers(_ code: Int) -> KeyModifiers {
        let bits = max(0, code - 1)
        var mods: KeyModifiers = []
        if (bits & 1) != 0 { mods.insert(.shift) }
        if (bits & 2) != 0 { mods.insert(.alt) }
        if (bits & 4) != 0 { mods.insert(.control) }
        if (bits & 8) != 0 { mods.insert(.command) }
        return mods
    }

    private func decodeSGRMouse(buttonCode: Int, col1Based: Int, row1Based: Int, isRelease: Bool) -> MouseEvent {
        let x = max(0, col1Based - 1)
        let y = max(0, row1Based - 1)

        var modifiers: KeyModifiers = []
        if (buttonCode & 4) != 0  { modifiers.insert(.shift) }
        if (buttonCode & 8) != 0  { modifiers.insert(.alt) }
        if (buttonCode & 16) != 0 { modifiers.insert(.control) }

        let isMotion = (buttonCode & 32) != 0
        let isWheel  = (buttonCode & 64) != 0
        let lowBits  = buttonCode & 3

        let kind: MouseEventKind
        if isWheel {
            switch lowBits {
            case 0: kind = .scrollUp
            case 1: kind = .scrollDown
            case 2: kind = .scrollLeft
            default: kind = .scrollRight
            }
        } else {
            let button: MouseButton
            switch lowBits {
            case 0: button = .left
            case 1: button = .middle
            case 2: button = .right
            default: button = .none
            }
            if isRelease {
                kind = .up(button)
            } else if isMotion {
                kind = button == .none ? .moved : .drag(button)
            } else {
                kind = .down(button)
            }
        }

        return MouseEvent(kind: kind, x: x, y: y, modifiers: modifiers)
    }

    // MARK: - UTF-8 Decoding

    private func decodeUTF8Character(_ bytes: [UInt8], from index: Int) -> (Character?, Int) {
        guard index < bytes.count else { return (nil, 0) }
        let first = bytes[index]
        let seqLen: Int
        if (first & 0x80) == 0 {
            seqLen = 1
        } else if (first & 0xE0) == 0xC0 {
            seqLen = 2
        } else if (first & 0xF0) == 0xE0 {
            seqLen = 3
        } else if (first & 0xF8) == 0xF0 {
            seqLen = 4
        } else {
            return (nil, 1)
        }

        let end = min(bytes.count, index + seqLen)
        let slice = Array(bytes[index..<end])
        let str = String(decoding: slice, as: UTF8.self)
        return (str.first, end - index)
    }
}
