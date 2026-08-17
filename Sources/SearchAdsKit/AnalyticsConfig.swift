import Foundation

/// What the tracker and the attribution reporter need to address `searchads.tools`. Nothing here
/// reads `Bundle` — `BundleSecrets` in `the host app` is the app's one sanctioned bundle reader,
/// and `the host app` is the one that depends on `SearchAdsKit`, not the other way around, so
/// the secret is resolved there (in `AppEnvironment.live()`) and handed in already-resolved. Same
/// shape as `TraktConfiguration`, which takes its client id/secret the same way for the same reason.
public struct AnalyticsConfig: Sendable, Equatable {
    public let baseURL: URL
    public let applicationToken: String
    public let bundleID: String
    public let appVersion: String
    public let build: String

    public init(baseURL: URL = AnalyticsConfig.liveBaseURL, applicationToken: String,
                bundleID: String, appVersion: String, build: String) {
        self.baseURL = baseURL
        self.applicationToken = applicationToken
        self.bundleID = bundleID
        self.appVersion = appVersion
        self.build = build
    }

    /// The one live endpoint every Friday app's asa-server client posts to (see
    /// `docs/claude/infra-map.md`). Not a secret — the token is the credential, the host is not.
    public static let liveBaseURL = URL(string: "https://searchads.tools")!
}
