import Foundation

/// The one thing a `ViewModel`/feature site calls to resolve or read back an A/B bucket. An actor
/// for the same reason `AnalyticsTracker` is: `resolve`/`override` both read-then-write the same
/// `buckets` dictionary, and two calls issued back-to-back must not race each other into it.
///
/// Every resolve re-fetches from `appstudio.tools` rather than trusting a stale cache — a flag
/// flipped server-side (or a rollout percentage changed) must be reflected the *next* cold start,
/// not stuck forever at whatever bucket this install first saw. This is ToneAdapt's own posture
/// (`docs/claude/toneadapt.md`, "A/B Altyapısı"); this type is its Swift/actor equivalent.
public actor FeatureFlagService {
    private let transport: any FeatureFlagTransport
    private let config: FeatureFlagConfig
    private let installFlagStore: any InstallFlagStore
    private let flagStore: any FeatureFlagStore
    private let analytics: AnalyticsTracker
    private var buckets: [String: FeatureFlagBucket] = [:]

    public init(transport: any FeatureFlagTransport, config: FeatureFlagConfig,
                installFlagStore: any InstallFlagStore,
                flagStore: any FeatureFlagStore = UserDefaultsFeatureFlagStore(),
                analytics: AnalyticsTracker) {
        self.transport = transport
        self.config = config
        self.installFlagStore = installFlagStore
        self.flagStore = flagStore
        self.analytics = analytics
    }

    /// What every environment gets before a real `FeatureFlagConfig` is resolved: previews, unit
    /// tests elsewhere in the app, a build without the flag layer wired in. `resolve` still
    /// works, it just always lands on the cached-or-control bucket instead of asking a server.
    public static func disabled() -> FeatureFlagService {
        FeatureFlagService(
            transport: NullFeatureFlagTransport(),
            config: FeatureFlagConfig(appId: ""),
            installFlagStore: UserDefaultsInstallFlagStore(),
            flagStore: InMemoryFeatureFlagStore(),
            analytics: .disabled())
    }

    /// Resolves the bucket for one feature key, publishing it to `analytics` as `ab_<featureKey>`
    /// either way — a caller that only ever sees the fallback path still wants its events sliced
    /// by that fallback bucket, not left unlabelled.
    @discardableResult
    public func resolve(featureKey: String) async -> FeatureFlagBucket {
        let userID = installFlagStore.installID()
        let bucket: FeatureFlagBucket
        if let remote = await transport.assign(appId: config.appId, featureKey: featureKey,
                                               userID: userID) {
            bucket = remote
        } else {
            // Network down, server error, or a bucket value this build doesn't know about yet:
            // keep whatever this install last resolved, and only default to control (`.a`) the
            // very first time it has ever asked.
            bucket = flagStore.bucket(for: featureKey) ?? .a
        }
        buckets[featureKey] = bucket
        flagStore.setBucket(bucket, for: featureKey)
        await analytics.setFlagBucket(featureKey: featureKey, bucket: bucket.rawValue)
        return bucket
    }

    /// The bucket most recently resolved for this key in this process, without a network round
    /// trip — a view that renders behind a flag calls `resolve` once (at launch or on appear) and
    /// reads this back out for every render after that.
    public func currentBucket(featureKey: String) -> FeatureFlagBucket? {
        buckets[featureKey]
    }

    /// The on-device debug flip (Flay-style): persists the override server-side first, and only
    /// applies it locally once appstudio confirms — an override this device believes but the
    /// server rejected would disagree with itself on the next cold start's `resolve`.
    @discardableResult
    public func override(featureKey: String, bucket: FeatureFlagBucket) async -> Bool {
        let userID = installFlagStore.installID()
        guard await transport.selfOverride(appId: config.appId, featureKey: featureKey,
                                           userID: userID, bucket: bucket)
        else { return false }
        buckets[featureKey] = bucket
        flagStore.setBucket(bucket, for: featureKey)
        await analytics.setFlagBucket(featureKey: featureKey, bucket: bucket.rawValue)
        return true
    }

    /// The install id flags resolve under — an on-device debug surface reads this back to show
    /// alongside the current bucket, same as ToneAdapt's own gear-icon AB debug button
    /// (`docs/claude/toneadapt.md`).
    public func currentUserID() -> String {
        installFlagStore.installID()
    }
}
