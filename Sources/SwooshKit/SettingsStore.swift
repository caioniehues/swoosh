import Foundation
import SwooshCore

/// `UserDefaults`-backed persistence for `SwooshSettings` (SPEC §5: settings live in defaults,
/// not a config file). Always returns/saves a `validated()` value so the bounded surface holds
/// even if defaults were tampered with.
public final class SettingsStore {
    public static let defaultsKey = "settings"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SwooshSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(SwooshSettings.self, from: data) else {
            return .default
        }
        return settings.validated()
    }

    public func save(_ settings: SwooshSettings) {
        guard let data = try? JSONEncoder().encode(settings.validated()) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
