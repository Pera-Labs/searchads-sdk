# searchads-sdk

Analytics + Apple Search Ads attribution SDK for [searchads.tools](https://searchads.tools).
One package, two clients:

- **Swift** (`SearchAdsKit`) — iOS 18+, tvOS 18+, macOS 15+, Swift 6, zero dependencies.
- **JS / React Native** (`js/index.js`) — plain `fetch`, works in React Native, Expo, Node 18+.

## Credentials

Sign up at [searchads.tools](https://searchads.tools/app/) and create an app.
You get two credentials with very different trust levels:

| Credential | Where it lives | What it can do |
|---|---|---|
| **Application token** (UUID) | Inside your app binary — safe to commit | Write-only: ingest events, purchases, attribution |
| **API key** (`sa_...`) | Server / agent side only — **secret** | Read & manage all of your account's data via `/api/agent/*` |

The web console's account tab has an **AI integration** button that copies a
ready-made prompt for Claude Code / Codex / Cursor including both credentials and
everything an AI agent needs to integrate this SDK and query your data.

## Swift (SPM)

Add the package `https://github.com/Pera-Labs/searchads-sdk` (from: `0.1.0`),
product **SearchAdsKit**.

```swift
import SearchAdsKit

let analytics = AnalyticsTracker(
    configuration: AnalyticsConfig(
        applicationToken: "<your-application-token>",
        bundleID: Bundle.main.bundleIdentifier ?? "",
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    )
)
analytics.track("app_open")

// Report Apple Search Ads attribution once per install (iOS only):
AppleSearchAdsAttributionReporter(configuration: analytics.configuration).reportIfNeeded()
```

## JS / React Native

```
npm install github:Pera-Labs/searchads-sdk
```

```js
import { createAnalytics } from 'searchads-sdk';

const analytics = createAnalytics({ applicationToken: '<your-application-token>' });
analytics.identify({ user_id: myStableUserId, is_pro: false });
analytics.track('app_open');
analytics.track('screen_view', { screen: 'home' });
analytics.trackPurchase({ amount: 4.99, currency: 'USD', product_id: 'pro_monthly' });
```

## Event taxonomy

The dashboard understands any event name, but these light up the built-in funnel:
`app_open`, `onboarding_complete`, `paywall_view`, `subscribe_tap`,
`subscribe_success`, `subscribe_fail`, `screen_view` (with a `screen` prop).
Always send a stable `user_id` so retention and user-level views work.

## Reading your data (agent API)

All read endpoints live under `GET https://searchads.tools/api/agent/<endpoint>`
with header `x-api-key: sa_...` — `me`, `events`, `users`, `user/<id>`,
`retention`, `funnel-by-keyword`, `geo`, `hourly`, `revenue-by-keyword`,
`roas`, `asa`. See the AI agent prompt in the web console for the full table.

## License

MIT
