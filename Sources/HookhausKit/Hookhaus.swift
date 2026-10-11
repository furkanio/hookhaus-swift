import Foundation

/// Hookhaus app-side SDK: measures your onboarding and paywall funnel and sends the events to your Hookhaus panel.
///
/// ```swift
/// Hookhaus.configure(apiKey: "hh_pk_…")          // in App.init or application(_:didFinishLaunchingWithOptions:)
/// Hookhaus.onboardingStep("welcome", index: 1)    // each onboarding screen
/// Hookhaus.onboardingCompleted()
/// Hookhaus.paywallShown("main")
/// Hookhaus.purchased(product: "pro.yearly")
/// ```
///
/// Privacy: no advertising ID (IDFA), no IDFV, no fingerprinting. Each install gets a random UUID that is reset by
/// `reset()` or by deleting the app. No App Tracking Transparency prompt is needed. See README for the App Store
/// privacy label answers.
public enum Hookhaus {
    /// SDK version sent with every batch.
    public static let version = "0.1.1"

    static let engine = Engine()

    /// Start the SDK. Call once, as early as possible. Calling again replaces the configuration.
    public static func configure(apiKey: String, options: HookhausOptions = HookhausOptions()) {
        let launch = Date()
        Task { await engine.configure(apiKey: apiKey, options: options, launchedAt: launch) }
    }

    /// Track a custom event. Names: letters, digits, space, `_ . : -`, at most 64 characters; names starting with `$`
    /// are reserved for the SDK's standard events.
    public static func track(_ event: String, properties: [String: HookhausValue] = [:]) {
        enqueue(event, properties)
    }

    /// A screen was shown.
    public static func screen(_ name: String, properties: [String: HookhausValue] = [:]) {
        enqueue(StandardEvent.screen, properties.merging(["name": .string(name)]) { a, _ in a })
    }

    /// An onboarding step was shown. Give `index` (1, 2, 3…) so the funnel keeps your order even if a step is skipped.
    public static func onboardingStep(_ step: String, index: Int? = nil, properties: [String: HookhausValue] = [:]) {
        var p = properties
        p["step"] = .string(step)
        if let index { p["index"] = .int(index) }
        enqueue(StandardEvent.onboardingStep, p)
    }

    /// The user finished onboarding.
    public static func onboardingCompleted(properties: [String: HookhausValue] = [:]) {
        enqueue(StandardEvent.onboardingComplete, properties)
    }

    /// A paywall was shown.
    public static func paywallShown(_ id: String? = nil, properties: [String: HookhausValue] = [:]) {
        var p = properties
        if let id { p["paywall"] = .string(id) }
        enqueue(StandardEvent.paywallView, p)
    }

    /// A free trial started.
    public static func trialStarted(product: String? = nil, properties: [String: HookhausValue] = [:]) {
        var p = properties
        if let product { p["product"] = .string(product) }
        enqueue(StandardEvent.trialStart, p)
    }

    /// A purchase completed. Price is optional; revenue itself is read from App Store Connect.
    public static func purchased(product: String, price: Decimal? = nil, currency: String? = nil, properties: [String: HookhausValue] = [:]) {
        var p = properties
        p["product"] = .string(product)
        if let price { p["price"] = .double(NSDecimalNumber(decimal: price).doubleValue) }
        if let currency { p["currency"] = .string(currency) }
        enqueue(StandardEvent.purchase, p)
    }

    /// Attach your own user id (e.g. after sign-up). Do not pass e-mail addresses or names.
    public static func identify(_ userId: String) {
        let at = Date()
        Task { await engine.identify(userId, at: at) }
    }

    /// Forget the user id and start a new install id (e.g. on log-out).
    public static func reset() {
        Task { await engine.reset() }
    }

    /// Stop collecting and drop queued events. Persisted across launches.
    public static func optOut() {
        Task { await engine.setOptOut(true) }
    }

    /// Resume collecting after `optOut()`.
    public static func optIn() {
        Task { await engine.setOptOut(false) }
    }

    /// When `HookhausOptions.requireConsent` is true nothing is collected until this is called (persisted).
    public static func grantConsent() {
        Task { await engine.setConsent(true) }
    }

    /// Send queued events now.
    public static func flush() {
        Task { await engine.flush() }
    }

    static func enqueue(_ event: String, _ properties: [String: HookhausValue]) {
        let at = Date()
        Task { await engine.enqueue(event, properties: properties, at: at) }
    }
}

/// SDK options.
public struct HookhausOptions: Sendable {
    /// Your Hookhaus panel address (self-hosted installs change this).
    public var host: URL
    /// Send when this many events are queued.
    public var flushAt: Int
    /// …or at least this often (seconds) while the app is open.
    public var flushInterval: TimeInterval
    /// Oldest events are dropped beyond this many queued events.
    public var maxQueueSize: Int
    /// Collect nothing until `Hookhaus.grantConsent()` (e.g. for EU users).
    public var requireConsent: Bool
    /// Track first open, app open and app updates automatically.
    public var captureLifecycle: Bool
    /// Print what the SDK does to the console.
    public var debug: Bool

    public init(
        host: URL = URL(string: "https://app.hookhaus.studio")!,
        flushAt: Int = 20,
        flushInterval: TimeInterval = 30,
        maxQueueSize: Int = 1000,
        requireConsent: Bool = false,
        captureLifecycle: Bool = true,
        debug: Bool = false
    ) {
        self.host = host
        self.flushAt = max(1, flushAt)
        self.flushInterval = max(5, flushInterval)
        self.maxQueueSize = max(10, maxQueueSize)
        self.requireConsent = requireConsent
        self.captureLifecycle = captureLifecycle
        self.debug = debug
    }
}

/// A property value: text, number or true/false.
public enum HookhausValue: Codable, Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(v): try c.encode(v)
        case let .int(v): try c.encode(v)
        case let .double(v): try c.encode(v.isFinite ? v : 0)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else { self = .string(try c.decode(String.self)) }
    }
}

enum StandardEvent {
    static let firstOpen = "$first_open"
    static let appOpen = "$app_open"
    static let appUpdated = "$app_updated"
    static let screen = "$screen"
    static let onboardingStep = "$onboarding_step"
    static let onboardingComplete = "$onboarding_complete"
    static let paywallView = "$paywall_view"
    static let trialStart = "$trial_start"
    static let purchase = "$purchase"
    static let identify = "$identify"
}
