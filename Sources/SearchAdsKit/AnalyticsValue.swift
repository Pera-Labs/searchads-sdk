import Foundation

/// A property value an event can carry. A closed set rather than `Any`, so a value built on one
/// actor and read on another is provably `Sendable` and provably one of the four JSON scalars the
/// server already accepts — nothing here can smuggle a reference type across the boundary.
public enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// What `JSONSerialization` wants for this case. Foundation bridges `Int`/`Double`/`Bool` to
    /// `NSNumber` on its own; this only has to hand back something `JSONSerialization` accepts.
    var jsonObject: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        }
    }
}

extension AnalyticsValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension AnalyticsValue {
    /// Lifts one value out of a `JSONSerialization` result (`String`/`NSNumber`/`Bool`/…) into the
    /// closed set this type models. `nil` for anything JSON's own decoder wouldn't hand back as a
    /// scalar (nested objects/arrays, `NSNull`) — Apple's attribution response is flat, so this is
    /// only ever asked to lift what is already one of these four.
    init?(jsonScalar value: Any) {
        switch value {
        case let value as String: self = .string(value)
        case let value as Bool: self = .bool(value)
        case let value as Int: self = .int(value)
        case let value as Double: self = .double(value)
        default: return nil
        }
    }
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    /// The wire shape the server's `/api/event` and `/api/attribution` routes both read `props`
    /// as: a plain JSON object, values already unwrapped from their `AnalyticsValue` case.
    var jsonObject: [String: Any] {
        mapValues { $0.jsonObject }
    }
}
