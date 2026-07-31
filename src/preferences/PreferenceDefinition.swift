import Foundation

/// Single-source-of-truth declaration for a macro preference: its key, default, and optional
/// Pro gate. Both the read-side (downgrade-on-lock) and the write-side (snapshot + restore)
/// go through this one definition — eliminating the duplicated Pro-gating logic that previously
/// lived in both `Preferences.swift` getters and `ProFeature.snapshotAndDowngradeStored` /
/// `restoreStored`.
struct PreferenceDefinition<T: MacroPreference & CaseIterable & Equatable> {
    let key: String
    let `default`: T

    /// Read the currently-stored value. The read passes through `CachedUserDefaults` so it's
    /// cheap on the hot path.
    func read() -> T {
        let stored: T = CachedUserDefaults.macroPref(key, Array(T.allCases))
        return stored
    }
}
