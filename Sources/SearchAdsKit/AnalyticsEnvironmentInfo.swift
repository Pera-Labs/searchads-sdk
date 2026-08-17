import Foundation

/// The superprops every event carries, gathered once per process rather than per event — the
/// platform, OS version, locale and timezone do not change inside a launch, so nothing here is
/// worth re-reading on every `track` call.
public struct AnalyticsEnvironmentInfo: Sendable, Equatable {
    public let platform: String
    public let platformVersion: String
    public let locale: String
    public let timezone: String

    public init(platform: String, platformVersion: String, locale: String, timezone: String) {
        self.platform = platform
        self.platformVersion = platformVersion
        self.locale = locale
        self.timezone = timezone
    }

    public static func current() -> AnalyticsEnvironmentInfo {
        AnalyticsEnvironmentInfo(
            platform: platformName,
            platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier)
    }

    private static var platformName: String {
        #if os(tvOS)
        "tvOS"
        #elseif os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #else
        "unknown"
        #endif
    }
}
