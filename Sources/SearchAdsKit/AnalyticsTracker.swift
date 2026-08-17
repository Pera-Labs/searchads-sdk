import Foundation

/// The one thing a `ViewModel` calls to report an event. An actor rather than a `@MainActor`
/// class: nothing here needs the main thread, and an actor's own serial queue is what keeps two
/// `track` calls issued back-to-back landing in the order they were issued despite each running on
/// its own detached `Task`.
public actor AnalyticsTracker {
    private let transport: any AnalyticsTransport
    private let config: AnalyticsConfig
    private let installFlagStore: any InstallFlagStore
    private let environment: AnalyticsEnvironmentInfo
    private let sessionID: String
    private var eventSeq: Int = 0
    private var currentScreen: String?
    private var previousScreen: String?
    private var abBuckets: [String: AnalyticsValue] = [:]

    public init(transport: any AnalyticsTransport, config: AnalyticsConfig,
                installFlagStore: any InstallFlagStore,
                environment: AnalyticsEnvironmentInfo = .current(),
                sessionID: String = UUID().uuidString) {
        self.transport = transport
        self.config = config
        self.installFlagStore = installFlagStore
        self.environment = environment
        self.sessionID = sessionID
    }

    /// What every environment gets before a real `AnalyticsConfig` is resolved: previews, unit
    /// tests elsewhere in the app, a build without the secret configured. `track`/`screen` still
    /// work, they just land on `NullAnalyticsTransport` instead of a socket.
    public static func disabled() -> AnalyticsTracker {
        AnalyticsTracker(
            transport: NullAnalyticsTransport(),
            config: AnalyticsConfig(applicationToken: "", bundleID: "", appVersion: "", build: ""),
            installFlagStore: UserDefaultsInstallFlagStore())
    }

    /// Fire-and-forget: every call site is synchronous (a `ViewModel` method, a button action),
    /// and an event is not worth making any of them `await` a network round trip for — the brief's
    /// own framing ("never block launch") applies just as much to every event after launch.
    public nonisolated func track(_ name: String, _ props: [String: AnalyticsValue] = [:]) {
        Task { await self.recordEvent(name: name, props: props) }
    }

    /// `screen_view` plus the bookkeeping (`screen`/`prev_screen`) every later event's superprops
    /// read back out. Its own event, not folded into whatever the caller does next, because a
    /// destination can be selected without any other event following it.
    public nonisolated func screen(_ name: String) {
        Task { await self.recordScreenChange(name: name) }
    }

    /// Awaitable twins of the two calls above, for tests that need the transport to have already
    /// been called when the `await` returns rather than racing a detached `Task`. Production code
    /// never calls these — they exist only so `SearchAdsKitTests` can assert deterministically.
    public func trackAwaiting(_ name: String, _ props: [String: AnalyticsValue] = [:]) async {
        await recordEvent(name: name, props: props)
    }

    public func screenAwaiting(_ name: String) async {
        await recordScreenChange(name: name)
    }

    /// `FeatureFlagService.resolve`/`.override` call this every time a bucket is assigned or
    /// flipped, so every event after that point — not just ones a call site remembers to tag —
    /// carries `ab_<featureKey>`. Awaited rather than fire-and-forget like `track`/`screen` above:
    /// both callers are already `async` actor methods on `FeatureFlagService`, one bucket write is
    /// not a network round trip worth detaching from, and `resolve`/`override` returning must mean
    /// the superprop is visible to whatever the caller `track`s next — the exact race a detached
    /// `Task` here would have reopened (a `track()` issued right after `resolve()` returns racing
    /// this actor's own queue instead of being strictly ordered after it).
    public func setFlagBucket(featureKey: String, bucket: String) async {
        abBuckets["ab_\(featureKey)"] = .string(bucket)
    }

    private func recordScreenChange(name: String) async {
        previousScreen = currentScreen
        currentScreen = name
        await recordEvent(name: "screen_view", props: [:])
    }

    private func recordEvent(name: String, props: [String: AnalyticsValue]) async {
        eventSeq += 1
        let merged = Self.merge(base: superprops(), override: props)
        let event = AnalyticsEvent(
            applicationToken: config.applicationToken, name: name,
            userID: installFlagStore.installID(), bundleID: config.bundleID,
            appVersion: config.appVersion, props: merged)
        _ = await transport.sendEvent(event)
    }

    private func superprops() -> [String: AnalyticsValue] {
        var props: [String: AnalyticsValue] = [
            "platform": .string(environment.platform),
            "platform_version": .string(environment.platformVersion),
            "app_version": .string(config.appVersion),
            "build": .string(config.build),
            "session_id": .string(sessionID),
            "event_seq": .int(eventSeq),
            "locale": .string(environment.locale),
            "timezone": .string(environment.timezone),
        ]
        if let currentScreen { props["screen"] = .string(currentScreen) }
        if let previousScreen { props["prev_screen"] = .string(previousScreen) }
        for (key, value) in abBuckets { props[key] = value }
        return props
    }

    /// Call-site `props` win on key collision. A caller naming its own `"screen"` (a paywall
    /// reporting the surface it was triggered from under a more specific key, say) means more than
    /// the ambient one this actor already tracks — the override is `merging(_:uniquingKeysWith:)`
    /// with the second value kept, not the superprop silently first.
    static func merge(base: [String: AnalyticsValue],
                      override: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        base.merging(override) { _, overrideValue in overrideValue }
    }
}
