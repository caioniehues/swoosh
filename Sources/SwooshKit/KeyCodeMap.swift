import CoreGraphics
import SwooshCore

/// Translates a `CGEvent` key-down into the pure `KeyChord` the binding model understands.
/// The keycodes are the standard ANSI virtual keycodes (Carbon `kVK_*`).
enum KeyCodeMap {
    static func key(for keyCode: Int64) -> Key? {
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 36:  return .return
        case 0:   return .letter("a")
        case 1:   return .letter("s")
        case 2:   return .letter("d")
        case 13:  return .letter("w")
        case 3:   return .letter("f")
        case 29:  return .digit(0)
        case 18:  return .digit(1)
        case 19:  return .digit(2)
        case 20:  return .digit(3)
        case 21:  return .digit(4)
        case 23:  return .digit(5)
        case 22:  return .digit(6)
        case 26:  return .digit(7)
        case 28:  return .digit(8)
        case 25:  return .digit(9)
        default:  return nil
        }
    }

    static func modifiers(from flags: CGEventFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.maskControl)   { m.insert(.control) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskShift)     { m.insert(.shift) }
        if flags.contains(.maskCommand)   { m.insert(.command) }
        return m
    }

    static func chord(from event: CGEvent) -> KeyChord? {
        guard let k = key(for: event.getIntegerValueField(.keyboardEventKeycode)) else { return nil }
        return KeyChord(modifiers(from: event.flags), k)
    }
}
