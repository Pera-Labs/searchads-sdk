import Foundation

/// What `FeatureFlagService` needs to address `appstudio.tools`. `appId` is not a secret — it is
/// the same identifier the appstudio dashboard and every other Friday app already register under
/// (`docs/claude/infra-map.md`) — so unlike `AnalyticsConfig.applicationToken` it does not have to
/// round-trip through `BundleSecrets`; `AppEnvironment.live()` passes the literal.
public struct FeatureFlagConfig: Sendable, Equatable {
    public let baseURL: URL
    public let appId: String

    public init(baseURL: URL = FeatureFlagConfig.liveBaseURL, appId: String) {
        self.baseURL = baseURL
        self.appId = appId
    }

    /// The one live endpoint every Friday app's appstudio client posts to (see
    /// `docs/claude/infra-map.md`).
    public static let liveBaseURL = URL(string: "https://appstudio.tools")!

    /// an example registration on `appstudio.tools` — confirmed live 2026-07-22
    /// (`GET .../api/flags/assign?appId=lumen&...` → 200, `{"bucket":"a",...}`).
    public static let lumenAppId = "lumen"
}
