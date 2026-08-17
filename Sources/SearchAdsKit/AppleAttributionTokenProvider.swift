import Foundation
#if canImport(AdServices)
import AdServices
#endif

/// The seam between `AppleSearchAdsAttributionReporter` and Apple's own attribution exchange, so a
/// unit test can supply a canned response (or a failure) instead of the reporter ever reaching
/// `AdServices` or the network — the once-per-install and retry/backoff behaviour is the
/// reporter's own logic and does not need a real device token to be exercised.
public protocol AppleAttributionTokenProvider: Sendable {
    /// `nil` means "asked Apple, got nothing usable" (no token, exchange failed, bad response) —
    /// the reporter treats that the same as "nothing to report", not as an error to retry, because
    /// a retry would just ask `AdServices` for the same token again.
    func fetchAttributionResponse() async -> [String: AnalyticsValue]?
}

#if canImport(AdServices)
/// Exchanges the device's install token for Apple's own attribution JSON, straight to Apple's
/// `api-adservices.apple.com` endpoint. No server credentials involved in this step at all —
/// `asa-server` never sees the token, only whatever JSON Apple hands back, forwarded verbatim.
public struct LiveAppleAttributionTokenProvider: AppleAttributionTokenProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchAttributionResponse() async -> [String: AnalyticsValue]? {
        guard let token = try? AAAttribution.attributionToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api-adservices.apple.com/api/v1/")!)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json.compactMapValues { AnalyticsValue(jsonScalar: $0) }
    }
}
#endif

/// What tvOS gets: `AdServices` does not exist there, so there is no token to ever exchange.
/// Compiles and behaves identically to a real provider that always came back empty — the reporter
/// needs no tvOS-specific branch of its own because of this.
public struct UnavailableAppleAttributionTokenProvider: AppleAttributionTokenProvider {
    public init() {}
    public func fetchAttributionResponse() async -> [String: AnalyticsValue]? { nil }
}
