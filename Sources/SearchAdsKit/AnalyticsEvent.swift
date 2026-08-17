import Foundation

/// One `/api/event` post, already shaped to the asa-server wire contract (`lib/events.js:record`):
/// `application_token`, `name`, `user_id`, `bundle_id`, `app_version`, `props` — a plain JSON
/// object the server both stores as-is and mines `props.screen` out of for its funnel views.
public struct AnalyticsEvent: Sendable, Equatable {
    public let applicationToken: String
    public let name: String
    public let userID: String
    public let bundleID: String
    public let appVersion: String
    public let props: [String: AnalyticsValue]

    public init(applicationToken: String, name: String, userID: String, bundleID: String,
                appVersion: String, props: [String: AnalyticsValue]) {
        self.applicationToken = applicationToken
        self.name = name
        self.userID = userID
        self.bundleID = bundleID
        self.appVersion = appVersion
        self.props = props
    }

    var jsonObject: [String: Any] {
        [
            "application_token": applicationToken,
            "name": name,
            "user_id": userID,
            "bundle_id": bundleID,
            "app_version": appVersion,
            "props": props.jsonObject,
        ]
    }
}

/// One `/api/attribution` post. `asaAttributionResponse` is Apple's own JSON, forwarded verbatim —
/// the server's `resolveAttribution` reads `campaignId`/`adGroupId`/`keywordId`/`orgId` off it
/// itself, so nothing here re-parses what Apple already returned. `nil` reports "asked, got
/// nothing usable" rather than skipping the post — the server records that as organic.
public struct AttributionReport: Sendable, Equatable {
    public let applicationToken: String
    public let userID: String
    public let asaAttributionResponse: [String: AnalyticsValue]?

    public init(applicationToken: String, userID: String,
                asaAttributionResponse: [String: AnalyticsValue]?) {
        self.applicationToken = applicationToken
        self.userID = userID
        self.asaAttributionResponse = asaAttributionResponse
    }

    var jsonObject: [String: Any] {
        [
            "application_token": applicationToken,
            "user_id": userID,
            "asa_attribution_response": asaAttributionResponse?.jsonObject as Any,
        ]
    }
}
