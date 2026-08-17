import Foundation

/// Reports Apple Search Ads attribution exactly once per install. The Apple-side token exchange
/// itself lives behind `AppleAttributionTokenProvider` (see that file) — this type only owns the
/// once-per-install gate and the retry/backoff around `transport.sendAttribution`, both of which a
/// test exercises with a fake provider and a fake transport, never real `AdServices` or network.
///
/// `reportIfNeeded()` is safe to call unconditionally from `AppEnvironment.live()` on every
/// platform. On tvOS the default provider (`UnavailableAppleAttributionTokenProvider`, wired at the
/// `AppEnvironment` composition point since `AdServices` isn't `canImport` there) always returns
/// `nil`, so `report()` returns immediately after the first guard — no platform branch needed here.
public actor AppleSearchAdsAttributionReporter {
    private let tokenProvider: any AppleAttributionTokenProvider
    private let transport: any AnalyticsTransport
    private let config: AnalyticsConfig
    private let installFlagStore: any InstallFlagStore
    private let retryDelays: [Duration]

    public init(tokenProvider: any AppleAttributionTokenProvider, transport: any AnalyticsTransport,
                config: AnalyticsConfig, installFlagStore: any InstallFlagStore,
                retryDelays: [Duration] = [.seconds(2), .seconds(8)]) {
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.config = config
        self.installFlagStore = installFlagStore
        self.retryDelays = retryDelays
    }

    /// Fire-and-forget from the caller's side — `AppEnvironment.live()` calls this without
    /// awaiting it, the same posture as `entitlements.beginObserving()` beside it. Never blocks
    /// launch, never throws out of it.
    public nonisolated func reportIfNeeded() {
        Task { await self.report() }
    }

    /// Awaitable for tests; production only ever calls `reportIfNeeded()`.
    public func report() async {
        guard !installFlagStore.attributionReported else { return }
        guard let apple = await tokenProvider.fetchAttributionResponse() else { return }
        var attempt = 0
        while true {
            let sent = await transport.sendAttribution(AttributionReport(
                applicationToken: config.applicationToken,
                userID: installFlagStore.installID(),
                asaAttributionResponse: apple))
            if sent {
                installFlagStore.markAttributionReported()
                return
            }
            guard attempt < retryDelays.count else { return }
            try? await Task.sleep(for: retryDelays[attempt])
            attempt += 1
        }
    }
}
