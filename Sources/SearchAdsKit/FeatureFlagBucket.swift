import Foundation

/// The two buckets `appstudio.tools` hands back for `GET /api/flags/assign` — see
/// `docs/claude/toneadapt.md` "A/B Altyapısı" for the ToneAdapt (Expo/JS) side of this same
/// contract. A closed set rather than a raw `String` so an unrecognised third value from the
/// server surfaces as `nil` at the JSON boundary instead of silently becoming a third live bucket
/// no call site was ever tested against.
public enum FeatureFlagBucket: String, Sendable, Equatable, CaseIterable {
    case a
    case b
}
