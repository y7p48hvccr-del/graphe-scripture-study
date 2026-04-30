import Foundation

/// One-time bootstrapper that populates the "Advanced — Book Reader"
/// toggle defaults based on the Mac's CPU architecture.
///
/// On Apple Silicon (M1/M2/M3/M4), reference-detection and page caching
/// have a negligible performance cost, so both features default to ON.
/// On Intel Macs, they add noticeable load time to each chapter, so both
/// default to OFF. A "hasSetArchDefaults" flag in UserDefaults ensures
/// this only runs once per install — after that, the user's own choices
/// are respected even if they switch machines via migration.
enum ArchitectureDefaults {

    /// Call once at app launch — cheap, idempotent. Does nothing after
    /// the first run.
    static func applyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "hasSetArchDefaults") else { return }

        let isAppleSilicon = detectAppleSilicon()
        defaults.set(isAppleSilicon, forKey: "detectScriptureRefs")
        defaults.set(isAppleSilicon, forKey: "preCacheEpubPages")
        defaults.set(true, forKey: "hasSetArchDefaults")
    }

    /// Returns true when running natively on Apple Silicon, false on
    /// Intel. Also returns false when running under Rosetta on an
    /// Apple Silicon Mac, since Rosetta adds its own overhead and the
    /// conservative default is appropriate there too.
    private static func detectAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
