import Foundation
import Synchronization

/// Per-install analytics state that is not a secret and so does not belong in either of this
/// project's two Keychain services: a stable id to attach to events, and whether attribution has
/// already been reported once. Injectable for the same reason `CredentialStore` is — a unit test
/// gets an in-memory store, never the real `UserDefaults.standard`.
public protocol InstallFlagStore: Sendable {
    /// Generated once and persisted on first read. Not the RevenueCat app-user-id and not a device
    /// identifier — purely a stable label this install's events and attribution report share.
    func installID() -> String
    var attributionReported: Bool { get }
    func markAttributionReported()
}

/// The real store: two `UserDefaults` keys, read/written on whatever thread the store's owner
/// (an actor) happens to call in from. `UserDefaults` is thread-safe on its own but the SDK does
/// not mark it `Sendable`, so it cannot be a stored property here — same posture as
/// `KeychainCredentialStore`, which holds zero stored properties and reaches the (also
/// thread-safe, also non-`Sendable`-marked) Keychain APIs fresh on every call instead.
public struct UserDefaultsInstallFlagStore: InstallFlagStore {
    private let installIDKey = "com.gokberkince.lumen.analytics.install_id"
    private let attributionReportedKey = "com.gokberkince.lumen.analytics.attribution_reported"

    public init() {}

    public func installID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: installIDKey)
        return generated
    }

    public var attributionReported: Bool {
        UserDefaults.standard.bool(forKey: attributionReportedKey)
    }

    public func markAttributionReported() {
        UserDefaults.standard.set(true, forKey: attributionReportedKey)
    }
}

/// The preview/test double — same role as `InMemoryCredentialStore` beside `CredentialStore`.
/// Backed by a `Mutex` rather than an actor: `installID()`/`markAttributionReported()` are called
/// from inside another actor (`AnalyticsTracker`/`AppleSearchAdsAttributionReporter`), and the
/// protocol they conform to is synchronous, so the store's own isolation has to be a lock, not a
/// second `await`.
public final class InMemoryInstallFlagStore: InstallFlagStore, Sendable {
    private let state: Mutex<State>

    private struct State {
        var installID: String?
        var attributionReported = false
    }

    public init(attributionReported: Bool = false) {
        state = Mutex(State(attributionReported: attributionReported))
    }

    public func installID() -> String {
        state.withLock { state in
            if let existing = state.installID { return existing }
            let generated = UUID().uuidString
            state.installID = generated
            return generated
        }
    }

    public var attributionReported: Bool {
        state.withLock { $0.attributionReported }
    }

    public func markAttributionReported() {
        state.withLock { $0.attributionReported = true }
    }
}
