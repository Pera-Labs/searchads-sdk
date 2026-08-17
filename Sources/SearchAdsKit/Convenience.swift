import Foundation

// One-line setup used by the README and the searchads.tools agent prompt.
// The designated initializers stay dependency-injected for tests; these
// extensions wire the live defaults (URLSession transport + UserDefaults
// install store) so an integrating app needs exactly one call.

public extension AnalyticsTracker {
    init(configuration: AnalyticsConfig) {
        self.init(transport: URLSessionAnalyticsTransport(config: configuration),
                  config: configuration,
                  installFlagStore: UserDefaultsInstallFlagStore())
    }
}

public extension AppleSearchAdsAttributionReporter {
    init(configuration: AnalyticsConfig) {
        #if canImport(AdServices)
        let provider: any AppleAttributionTokenProvider = LiveAppleAttributionTokenProvider()
        #else
        let provider: any AppleAttributionTokenProvider = UnavailableAppleAttributionTokenProvider()
        #endif
        self.init(tokenProvider: provider,
                  transport: URLSessionAnalyticsTransport(config: configuration),
                  config: configuration,
                  installFlagStore: UserDefaultsInstallFlagStore())
    }
}
