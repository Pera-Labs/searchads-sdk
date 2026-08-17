import Foundation

/// The seam between `FeatureFlagService` and the network — same role as `AnalyticsTransport`
/// beside it, so a unit test can assert what was about to be requested without a socket ever
/// opening.
public protocol FeatureFlagTransport: Sendable {
    /// `GET /api/flags/assign`. `nil` covers every way this can fail to hand back a usable
    /// bucket: no network, non-2xx, a body that isn't the expected JSON, or a `bucket` value
    /// outside the closed set `FeatureFlagBucket` models — the caller treats all of those the
    /// same way (fall back to the cached/control bucket), so this does not distinguish them.
    func assign(appId: String, featureKey: String, userID: String) async -> FeatureFlagBucket?

    /// `POST /api/flags/self-override` — the on-device debug flip. Returns whether the server
    /// accepted it; the caller only applies the bucket locally once this is `true`, so an
    /// override that failed to persist server-side never disagrees with appstudio's own record
    /// on the next cold start.
    func selfOverride(appId: String, featureKey: String, userID: String,
                      bucket: FeatureFlagBucket) async -> Bool
}

/// What every environment gets until a real `FeatureFlagConfig` is resolved: previews, unit
/// tests, and any build the flag layer was never wired into. Both calls report "nothing to work
/// with" so `FeatureFlagService` always lands on its fallback bucket rather than branching on
/// whether a transport exists.
public struct NullFeatureFlagTransport: FeatureFlagTransport {
    public init() {}
    public func assign(appId: String, featureKey: String,
                       userID: String) async -> FeatureFlagBucket? { nil }
    public func selfOverride(appId: String, featureKey: String, userID: String,
                             bucket: FeatureFlagBucket) async -> Bool { false }
}

/// The live transport: talks to `appstudio.tools`.
public struct URLSessionFeatureFlagTransport: FeatureFlagTransport {
    private let config: FeatureFlagConfig
    private let session: URLSession

    public init(config: FeatureFlagConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func assign(appId: String, featureKey: String,
                       userID: String) async -> FeatureFlagBucket? {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent("/api/flags/assign"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "appId", value: appId),
            URLQueryItem(name: "featureKey", value: featureKey),
            URLQueryItem(name: "userId", value: userID),
        ]
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bucketRaw = json["bucket"] as? String
        else { return nil }
        return FeatureFlagBucket(rawValue: bucketRaw)
    }

    public func selfOverride(appId: String, featureKey: String, userID: String,
                             bucket: FeatureFlagBucket) async -> Bool {
        var request = URLRequest(
            url: config.baseURL.appendingPathComponent("/api/flags/self-override"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "appId": appId, "featureKey": featureKey, "userId": userID, "bucket": bucket.rawValue,
        ]
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return false }
        request.httpBody = data
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
