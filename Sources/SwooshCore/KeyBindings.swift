import CoreGraphics

/// Keyboard modifier flags (SPEC §4.5). The Swish-compatible default prefix is `⌃⌥`.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let shift   = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let controlOption: KeyModifiers = [.control, .option]
}

/// A keyboard key, abstracted from any platform keycode (the keycode table lives in SwooshKit).
public enum Key: Hashable, Sendable {
    case left, right, up, down
    case letter(Character)   // a, d, w, s, f
    case digit(Int)          // 0…9
    case `return`
}

/// A modifier + key combination.
public struct KeyChord: Hashable, Sendable {
    public let modifiers: KeyModifiers
    public let key: Key
    public init(_ modifiers: KeyModifiers, _ key: Key) {
        self.modifiers = modifiers
        self.key = key
    }
}

/// What a shortcut does. `.swipe` reuses the swipe resolution (so ↑/↓ share the fullscreen /
/// restore toggles); `.snap` is an explicit target (grid digits, fullscreen).
public enum WindowAction: Equatable, Sendable {
    case swipe(Direction)
    case snap(SnapTarget)
    case restore
    case exitFullscreen
}

/// The default keyboard bindings (SPEC §4.5) and the numpad grid mapping. Pure — the live
/// keycode decode and focused-window execution live in SwooshKit.
public enum KeyBindings {
    /// Numpad layout: 1 = bottom-left … 9 = top-right (SPEC §4.5). Returns `nil` outside 1…9.
    public static func numpadGridCell(_ digit: Int) -> SnapTarget? {
        guard (1 ... 9).contains(digit) else { return nil }
        let index = digit - 1
        let row = 2 - index / 3   // digits 1–3 → bottom row (2); 7–9 → top row (0)
        let col = index % 3
        return .gridCell(row: row, col: col, rows: 3, cols: 3)
    }

    /// The default `⌃⌥`-prefixed bindings.
    public static let defaults: [KeyChord: WindowAction] = {
        let mod: KeyModifiers = .controlOption
        var bindings: [KeyChord: WindowAction] = [
            KeyChord(mod, .left):  .swipe(.left),
            KeyChord(mod, .right): .swipe(.right),
            KeyChord(mod, .up):    .swipe(.up),
            KeyChord(mod, .down):  .swipe(.down),
            KeyChord(mod, .letter("a")): .swipe(.left),
            KeyChord(mod, .letter("d")): .swipe(.right),
            KeyChord(mod, .letter("w")): .swipe(.up),
            KeyChord(mod, .letter("s")): .swipe(.down),
            KeyChord(mod, .digit(0)): .snap(.fullScreen),
            KeyChord(mod, .return):   .restore,
            KeyChord(mod, .letter("f")): .exitFullscreen,
        ]
        for digit in 1 ... 9 {
            bindings[KeyChord(mod, .digit(digit))] = .snap(numpadGridCell(digit)!)
        }
        return bindings
    }()

    /// The action bound to a chord, or `nil` if unbound.
    public static func action(for chord: KeyChord, in bindings: [KeyChord: WindowAction] = defaults) -> WindowAction? {
        bindings[chord]
    }
}
