import Foundation
import Synchronization

/// Per-install cache of the last bucket this device resolved for each feature key, so a launch
/// that cannot reach `appstudio.tools` (offline, server hiccup) still assigns the same bucket it
/// assigned last time rather than falling all the way back to control. Same posture as
/// `InstallFlagStore` beside it — injectable so a unit test never touches `UserDefaults.standard`.
public protocol FeatureFlagStore: Sendable {
    func bucket(for featureKey: String) -> FeatureFlagBucket?
    func setBucket(_ bucket: FeatureFlagBucket, for featureKey: String)
}

/// The real store: one `UserDefaults` key per feature key, read/written on whatever thread the
/// owning actor (`FeatureFlagService`) happens to call in from — same non-`Sendable`-storage
/// posture as `UserDefaultsInstallFlagStore`.
public struct UserDefaultsFeatureFlagStore: FeatureFlagStore {
    public init() {}

    public func bucket(for featureKey: String) -> FeatureFlagBucket? {
        UserDefaults.standard.string(forKey: key(featureKey)).flatMap(FeatureFlagBucket.init(rawValue:))
    }

    public func setBucket(_ bucket: FeatureFlagBucket, for featureKey: String) {
        UserDefaults.standard.set(bucket.rawValue, forKey: key(featureKey))
    }

    private func key(_ featureKey: String) -> String {
        "com.gokberkince.lumen.flags.\(featureKey)"
    }
}

/// The preview/test double — same role as `InMemoryInstallFlagStore` beside it. Backed by a
/// `Mutex` rather than an actor for the same reason: the protocol it conforms to is synchronous
/// and is called from inside another actor (`FeatureFlagService`).
public final class InMemoryFeatureFlagStore: FeatureFlagStore, Sendable {
    private let state: Mutex<[String: FeatureFlagBucket]>

    public init(seed: [String: FeatureFlagBucket] = [:]) {
        state = Mutex(seed)
    }

    public func bucket(for featureKey: String) -> FeatureFlagBucket? {
        state.withLock { $0[featureKey] }
    }

    public func setBucket(_ bucket: FeatureFlagBucket, for featureKey: String) {
        state.withLock { $0[featureKey] = bucket }
    }
}
