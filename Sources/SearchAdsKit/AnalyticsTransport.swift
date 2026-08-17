import Foundation

/// The seam between the tracker/reporter and the network, so a unit test can assert what was
/// about to be sent without a socket ever opening — same shape as `CredentialStore`/
/// `EntitlementService` elsewhere in this codebase.
public protocol AnalyticsTransport: Sendable {
    func sendEvent(_ event: AnalyticsEvent) async -> Bool
    func sendAttribution(_ report: AttributionReport) async -> Bool
}

/// What every environment gets until a real `AnalyticsConfig` is resolved: previews, unit tests,
/// and any build a secret was never configured for. Every call reports success so a caller cannot
/// tell the difference between "sent" and "there was nowhere to send it" from the return value
/// alone — this transport exists precisely so nothing downstream needs to branch on that.
public struct NullAnalyticsTransport: AnalyticsTransport {
    public init() {}
    public func sendEvent(_ event: AnalyticsEvent) async -> Bool { true }
    public func sendAttribution(_ report: AttributionReport) async -> Bool { true }
}

/// The live transport: posts JSON to `searchads.tools`. Fire-and-forget from the tracker's side —
/// this only reports back whether the HTTP round trip itself succeeded, which the attribution
/// reporter uses to decide whether to mark the install as reported; the tracker discards it
/// (an event that failed to land is not worth retrying at the cost of blocking the next one).
public struct URLSessionAnalyticsTransport: AnalyticsTransport {
    private let config: AnalyticsConfig
    private let session: URLSession

    public init(config: AnalyticsConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func sendEvent(_ event: AnalyticsEvent) async -> Bool {
        await post(path: "/api/event", body: event.jsonObject)
    }

    public func sendAttribution(_ report: AttributionReport) async -> Bool {
        await post(path: "/api/attribution", body: report.jsonObject)
    }

    /// Every route on this server answers 200 even for an application-level rejection (an
    /// unrecognised `application_token`, a missing field) — the failure is in the body, not the
    /// status line. So a post only counts as landed once both the transport succeeded and the
    /// body isn't `{"status":"error",...}`.
    private func post(path: String, body: [String: Any]) async -> Bool {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return false }
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            else { return true }
            return (json["status"] as? String) != "error"
        } catch {
            return false
        }
    }
}
