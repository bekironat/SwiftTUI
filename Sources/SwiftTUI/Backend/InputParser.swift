import Foundation

/// Stateful VT/ANSI byte stream parser converting raw terminal input bytes into `TerminalEvent` values.
/// Safely reassembles split UTF-8 sequences and multi-chunk bracketed pastes across `read()` boundaries.
public final class ANSIInputParser: @unchecked Sendable {
    /// Maximum parameter byte length accepted for a single CSI sequence to prevent malformed stream DoS.
    public static let maxCSIParamBytes = 64
    /// Maximum payload size accepted in a single bracketed paste packet (64 KiB).
    public static let maxPasteBytes = 65_536

    private static let pasteStartMarker: [UInt8] = [0x1B, UInt8(ascii: "["), UInt8(ascii: "2"), UInt8(ascii: "0"), UInt8(ascii: "0"), UInt8(ascii: "~")]
    private static let pasteEndMarker: [UInt8]   = [0x1B, UInt8(ascii: "["), UInt8(ascii: "2"), UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "~")]

    private let lock = NSLock()
    private var inBracketedPaste: Bool = false
    private var pasteBuffer: [UInt8] = []
    private var pasteTailBuffer: [UInt8] = []
    private var pendingUTF8: [UInt8] = []

    public init() {}

    /// Resets any buffered partial UTF-8 or bracketed-paste state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        inBracketedPaste = false
        pasteBuffer.removeAll(keepingCapacity: false)
        pasteTailBuffer.removeAll(keepingCapacity: false)
        pendingUTF8.removeAll(keepingCapacity: false)
    }

    public func parse(_ incomingBytes: [UInt8]) -> [TerminalEvent] {
        lock.lock()
        defer { lock.unlock() }

        let bytes: [UInt8]
        if !pendingUTF8.isEmpty {
            bytes = pendingUTF8 + incomingBytes
            pendingUTF8.removeAll(keepingCapacity: true)
        } else {
            bytes = incomingBytes
        }

        var events: [TerminalEvent] = []
        var i = 0
        let count = bytes.count

        while i < count {
            if inBracketedPaste {
                let consumed = consumeBracketedPasteChunk(bytes, from: i, events: &events)
                i += consumed
                continue
            }

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
                    if matchesMarker(Self.pasteStartMarker, in: bytes, at: i) {
                        inBracketedPaste = true
                        pasteBuffer.removeAll(keepingCapacity: true)
                        pasteTailBuffer.removeAll(keepingCapacity: true)
                        i += Self.pasteStartMarker.count
                        continue
                    }

                    // CSI sequence
                    let (event, consumed) = parseCSI(bytes, from: i + 2)
                    if let event {
                        events.append(event)
                    }
                    i += 2 + consumed
                    continue
                } else if next == UInt8(ascii: "]") || next == UInt8(ascii: "P") || next == UInt8(ascii: "_") || next == UInt8(ascii: "^") {
                    // Safely consume and discard OSC (ESC ]), DCS (ESC P), APC (ESC _), or PM (ESC ^) sequences
                    // terminated by BEL (0x07) or ST (ESC \)
                    var scan = i + 2
                    let maxScan = min(count, scan + 1024)
                    while scan < maxScan {
                        if bytes[scan] == 0x07 {
                            scan += 1
                            break
                        }
                        if bytes[scan] == 0x1B && scan + 1 < count && bytes[scan + 1] == UInt8(ascii: "\\") {
                            scan += 2
                            break
                        }
                        scan += 1
                    }
                    i = scan
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
                    let expectedLen = utf8SequenceLength(bytes[i + 1])
                    if expectedLen > 1 && i + 1 + expectedLen > count {
                        pendingUTF8 = Array(bytes[i..<count])
                        break
                    }
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
                let expectedLen = utf8SequenceLength(b)
                if expectedLen > 1 && i + expectedLen > count {
                    // Incomplete multi-byte UTF-8 sequence split across reads: hold for next chunk
                    pendingUTF8 = Array(bytes[i..<count])
                    i = count
                    break
                }
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

    // MARK: - Stateful Bracketed Paste Reassembly

    private func matchesMarker(_ marker: [UInt8], in bytes: [UInt8], at start: Int) -> Bool {
        guard start + marker.count <= bytes.count else { return false }
        for k in 0..<marker.count {
            if bytes[start + k] != marker[k] {
                return false
            }
        }
        return true
    }

    private func consumeBracketedPasteChunk(_ bytes: [UInt8], from start: Int, events: inout [TerminalEvent]) -> Int {
        let endMarker = Self.pasteEndMarker
        let combined: [UInt8]
        let tailLen = pasteTailBuffer.count
        if tailLen > 0 {
            combined = pasteTailBuffer + bytes[start..<bytes.count]
            pasteTailBuffer.removeAll(keepingCapacity: true)
        } else {
            combined = Array(bytes[start..<bytes.count])
        }

        var scan = 0
        while scan + endMarker.count <= combined.count {
            if matchesMarker(endMarker, in: combined, at: scan) {
                appendSanitizedPasteBytes(combined[0..<scan])
                let text = String(decoding: pasteBuffer, as: UTF8.self)
                pasteBuffer.removeAll(keepingCapacity: false)
                inBracketedPaste = false
                events.append(.paste(text))
                let consumedFromCurrent = (scan + endMarker.count) - tailLen
                return max(0, consumedFromCurrent)
            }
            scan += 1
        }

        // Keep up to `endMarker.count - 1` trailing bytes in case the end marker is split across chunks
        let safeFlushEnd = max(0, combined.count - (endMarker.count - 1))
        if safeFlushEnd > 0 {
            appendSanitizedPasteBytes(combined[0..<safeFlushEnd])
        }
        if safeFlushEnd < combined.count {
            pasteTailBuffer = Array(combined[safeFlushEnd..<combined.count])
        }
        return bytes.count - start
    }

    private func appendSanitizedPasteBytes(_ slice: ArraySlice<UInt8>) {
        guard pasteBuffer.count < Self.maxPasteBytes else { return }
        for byte in slice {
            if pasteBuffer.count >= Self.maxPasteBytes { break }
            if byte == 0x0A || byte == 0x09 || (byte >= 0x20 && byte != 0x7F) {
                pasteBuffer.append(byte)
            }
        }
    }

    private func utf8SequenceLength(_ first: UInt8) -> Int {
        if (first & 0x80) == 0 { return 1 }
        if (first & 0xE0) == 0xC0 { return 2 }
        if (first & 0xF0) == 0xE0 { return 3 }
        if (first & 0xF8) == 0xF0 { return 4 }
        return 1
    }

    // MARK: - CSI Sequences

    private func parseCSI(_ bytes: [UInt8], from start: Int) -> (TerminalEvent?, Int) {
        var idx = start
        let count = bytes.count
        let maxIdx = min(count, start + Self.maxCSIParamBytes)

        // SGR mouse: ESC [ < btn ; col ; row M/m
        if idx < maxIdx && bytes[idx] == UInt8(ascii: "<") {
            idx += 1
            var paramBytes: [UInt8] = []
            while idx < maxIdx {
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
        while idx < maxIdx {
            let b = bytes[idx]
            if b >= 0x40 && b <= 0x7E {
                let finalByte = b
                let consumed = (idx + 1) - start
                // Terminal window focus reporting (CSI ? 1004 h)
                if finalByte == UInt8(ascii: "I") && paramBytes.isEmpty {
                    return (.focusGained, consumed)
                }
                if finalByte == UInt8(ascii: "O") && paramBytes.isEmpty {
                    return (.focusLost, consumed)
                }
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
        // Support Kitty keyboard protocol colon-separated subparameters:
        // e.g. `CSI key[:shifted[:base]];mods[:event_type] u`
        let rawParts = paramStr.split(separator: ";", omittingEmptySubsequences: false)
        let firstSubparts = rawParts.first.map { $0.split(separator: ":").compactMap { Int($0) } } ?? []
        let firstParam = firstSubparts.first ?? 1

        var modifierCode = 1
        var eventKind: KeyEventKind = .press
        if rawParts.count >= 2 {
            let modSubparts = rawParts[1].split(separator: ":").compactMap { Int($0) }
            if let modVal = modSubparts.first {
                modifierCode = modVal
            }
            if modSubparts.count >= 2 {
                switch modSubparts[1] {
                case 2: eventKind = .repeat
                case 3: eventKind = .release
                default: eventKind = .press
                }
            }
        }
        let modifiers = decodeModifiers(modifierCode)

        switch finalByte {
        case UInt8(ascii: "A"): return KeyEvent(.up, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "B"): return KeyEvent(.down, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "C"): return KeyEvent(.right, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "D"): return KeyEvent(.left, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "H"): return KeyEvent(.home, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "F"): return KeyEvent(.end, modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "Z"): return KeyEvent(.backTab, modifiers: modifiers.union([.shift]), kind: eventKind)
        case UInt8(ascii: "P"): return KeyEvent(.f(1), modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "Q"): return KeyEvent(.f(2), modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "R"): return KeyEvent(.f(3), modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "S"): return KeyEvent(.f(4), modifiers: modifiers, kind: eventKind)
        case UInt8(ascii: "u"):
            // Kitty / CSI u keyboard protocol: ESC [ <unicode>[:shifted] ; <modifiers>[:eventType] u
            switch firstParam {
            case 9: return KeyEvent(.tab, modifiers: modifiers, kind: eventKind)
            case 13: return KeyEvent(.enter, modifiers: modifiers, kind: eventKind)
            case 27: return KeyEvent(.escape, modifiers: modifiers, kind: eventKind)
            case 32: return KeyEvent(.space, modifiers: modifiers, kind: eventKind)
            case 127: return KeyEvent(.backspace, modifiers: modifiers, kind: eventKind)
            default:
                // If Shift is pressed and a shifted codepoint is provided, prefer it for printable chars
                let effectiveCodepoint = (modifiers.contains(.shift) && firstSubparts.count >= 2 && firstSubparts[1] >= 32)
                    ? firstSubparts[1]
                    : firstParam
                if let scalar = UnicodeScalar(effectiveCodepoint) {
                    return KeyEvent(.char(Character(scalar)), modifiers: modifiers, kind: eventKind)
                }
                return nil
            }
        case UInt8(ascii: "~"):
            switch firstParam {
            case 1, 7: return KeyEvent(.home, modifiers: modifiers, kind: eventKind)
            case 2:    return KeyEvent(.insert, modifiers: modifiers, kind: eventKind)
            case 3:    return KeyEvent(.delete, modifiers: modifiers, kind: eventKind)
            case 4, 8: return KeyEvent(.end, modifiers: modifiers, kind: eventKind)
            case 5:    return KeyEvent(.pageUp, modifiers: modifiers, kind: eventKind)
            case 6:    return KeyEvent(.pageDown, modifiers: modifiers, kind: eventKind)
            case 11:   return KeyEvent(.f(1), modifiers: modifiers, kind: eventKind)
            case 12:   return KeyEvent(.f(2), modifiers: modifiers, kind: eventKind)
            case 13:   return KeyEvent(.f(3), modifiers: modifiers, kind: eventKind)
            case 14:   return KeyEvent(.f(4), modifiers: modifiers, kind: eventKind)
            case 15:   return KeyEvent(.f(5), modifiers: modifiers, kind: eventKind)
            case 17:   return KeyEvent(.f(6), modifiers: modifiers, kind: eventKind)
            case 18:   return KeyEvent(.f(7), modifiers: modifiers, kind: eventKind)
            case 19:   return KeyEvent(.f(8), modifiers: modifiers, kind: eventKind)
            case 20:   return KeyEvent(.f(9), modifiers: modifiers, kind: eventKind)
            case 21:   return KeyEvent(.f(10), modifiers: modifiers, kind: eventKind)
            case 23:   return KeyEvent(.f(11), modifiers: modifiers, kind: eventKind)
            case 24:   return KeyEvent(.f(12), modifiers: modifiers, kind: eventKind)
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
