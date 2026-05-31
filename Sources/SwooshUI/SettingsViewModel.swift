import Foundation
import SwooshCore
import SwooshKit

/// Bridges the tested `SwooshSettings` value type to SwiftUI. Loads from the `SettingsStore` on
/// init and persists a `validated()` copy on every change, so the bounded surface (SPEC §5)
/// holds no matter what the UI lets the user enter.
@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var settings: SwooshSettings {
        didSet { persist() }
    }

    private let store: SettingsStore
    private var isLoading = false

    public init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.isLoading = true
        self.settings = store.load()
        self.isLoading = false
    }

    private func persist() {
        guard !isLoading else { return }
        store.save(settings)   // store.save validates; the model mirrors persisted intent
    }

    /// Clamp the in-memory settings to the bounded range (call after free-form edits).
    public func normalize() {
        settings = settings.validated()
    }
}
