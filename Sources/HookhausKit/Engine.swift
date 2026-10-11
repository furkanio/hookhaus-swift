import Foundation

/// One queued event (wire format of `POST /v1/sdk/batch`).
struct QueuedEvent: Codable, Equatable, Sendable {
    var id: String
    var event: String
    var distinct_id: String
    var user_id: String?
    var session_id: String?
    var timestamp: String
    var props: [String: HookhausValue]
}

struct Batch: Encodable {
    var sent_at: String
    var sdk: String
    var context: DeviceContext
    var events: [QueuedEvent]
}

/// Sends a request and returns the HTTP status (0 when the network failed). Replaced in tests.
typealias Transport = @Sendable (URLRequest) async -> Int

let defaultTransport: Transport = { request in
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
        return 0
    }
}

/// All SDK state lives in this actor: identity, session, queue and sending.
actor Engine {
    private var apiKey: String?
    private var options = HookhausOptions()
    private var store: Store
    private var transport: Transport
    private var defaults: UserDefaults
    private var queue: [QueuedEvent] = []
    private var sessionId: String?
    private var lastActive: Date?
    private var sending = false
    private var batchLimit = 50
    private var retries = 0
    private var nextAttempt = Date.distantPast
    private var paused = false // wrong key: stop until next configure
    private var timer: Task<Void, Never>?
    private var lifecycle: LifecycleObserver?
    /// Events tracked before `configure` finished (calls are asynchronous): replayed once configured
    private var early: [(String, [String: HookhausValue], Date)] = []

    static let sessionTimeout: TimeInterval = 30 * 60

    init(store: Store = Store(), transport: @escaping Transport = defaultTransport, defaults: UserDefaults = .standard) {
        self.store = store
        self.transport = transport
        self.defaults = defaults
    }

    // MARK: Configuration

    func configure(apiKey: String, options: HookhausOptions, launchedAt: Date) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.options = options
        paused = false
        queue = store.load()
        log("configured; \(queue.count) queued events")
        startTimer()
        if options.captureLifecycle {
            captureLaunch(at: launchedAt)
            if lifecycle == nil {
                lifecycle = LifecycleObserver(
                    onActive: { at in Task { await Hookhaus.engine.didBecomeActive(at: at) } },
                    onBackground: { Task { await Hookhaus.engine.didEnterBackground() } }
                )
            }
        }
        let pending = early
        early = []
        for (event, props, at) in pending { enqueue(event, properties: props, at: at) }
    }

    private var canCollect: Bool {
        apiKey != nil && !defaults.bool(forKey: Keys.optOut) && (!options.requireConsent || defaults.bool(forKey: Keys.consent))
    }

    // MARK: Identity and session

    var installId: String {
        if let id = defaults.string(forKey: Keys.installId) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Keys.installId)
        return id
    }

    private func session(at date: Date) -> String {
        if let s = sessionId, let last = lastActive, date.timeIntervalSince(last) < Self.sessionTimeout {
            lastActive = date
            return s
        }
        let s = UUIDv7.make(at: date)
        sessionId = s
        lastActive = date
        return s
    }

    func identify(_ userId: String, at date: Date) {
        let id = String(userId.prefix(128))
        defaults.set(id, forKey: Keys.userId)
        enqueue(StandardEvent.identify, properties: [:], at: date)
    }

    func reset() {
        defaults.removeObject(forKey: Keys.userId)
        defaults.removeObject(forKey: Keys.installId)
        sessionId = nil
    }

    func setOptOut(_ value: Bool) {
        defaults.set(value, forKey: Keys.optOut)
        if value {
            queue = []
            store.save(queue)
        }
    }

    func setConsent(_ value: Bool) {
        defaults.set(value, forKey: Keys.consent)
    }

    // MARK: Lifecycle

    private func captureLaunch(at date: Date) {
        let version = DeviceContext.current().app_version ?? ""
        if !defaults.bool(forKey: Keys.firstOpenSent) {
            enqueue(StandardEvent.firstOpen, properties: [:], at: date)
            if canCollect { defaults.set(true, forKey: Keys.firstOpenSent) }
        } else if let last = defaults.string(forKey: Keys.appVersion), last != version {
            enqueue(StandardEvent.appUpdated, properties: ["previous_version": .string(last)], at: date)
        }
        defaults.set(version, forKey: Keys.appVersion)
    }

    func didBecomeActive(at date: Date) {
        enqueue(StandardEvent.appOpen, properties: [:], at: date)
    }

    func didEnterBackground() async {
        lastActive = Date()
        await flush()
    }

    // MARK: Queue

    func enqueue(_ event: String, properties: [String: HookhausValue], at date: Date) {
        if apiKey == nil {
            if early.count < 100 { early.append((event, properties, date)) }
            return
        }
        guard canCollect else { return }
        let name = event.trimmingCharacters(in: .whitespaces)
        guard Self.validName(name) else {
            log("dropped invalid event name: \(event)")
            return
        }
        let e = QueuedEvent(
            id: UUIDv7.make(at: date),
            event: name,
            distinct_id: installId,
            user_id: defaults.string(forKey: Keys.userId),
            session_id: session(at: date),
            timestamp: ISO.string(date),
            props: Self.clean(properties)
        )
        queue.append(e)
        if queue.count > options.maxQueueSize { queue.removeFirst(queue.count - options.maxQueueSize) }
        store.save(queue)
        log("queued \(name) (\(queue.count))")
        if queue.count >= options.flushAt { Task { await self.flush() } }
    }

    var queued: [QueuedEvent] { queue }

    static func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.:- $"))
        if name.dropFirst().contains("$") { return false }
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func clean(_ p: [String: HookhausValue]) -> [String: HookhausValue] {
        var out: [String: HookhausValue] = [:]
        for (k, v) in p.prefix(40) {
            let key = String(k.prefix(64))
            if case let .string(s) = v { out[key] = .string(String(s.prefix(512))) } else { out[key] = v }
        }
        return out
    }

    // MARK: Sending

    private func startTimer() {
        timer?.cancel()
        let interval = options.flushInterval
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.flush()
            }
        }
    }

    func flush() async {
        guard !sending, !paused, let key = apiKey, !queue.isEmpty, Date() >= nextAttempt else { return }
        sending = true
        defer { sending = false }
        while !queue.isEmpty {
            let batch = Array(queue.prefix(batchLimit))
            let status = await send(batch, key: key)
            switch status {
            case 200 ..< 300, 400:
                // Delivered (or malformed beyond repair): drop these events
                queue.removeFirst(min(batch.count, queue.count))
                store.save(queue)
                retries = 0
                if status == 400 { log("server rejected a batch (400); dropped \(batch.count) events") } else { log("sent \(batch.count) events") }
            case 413:
                if batch.count == 1 {
                    queue.removeFirst()
                    store.save(queue)
                } else {
                    batchLimit = max(1, batch.count / 2)
                }
            case 401, 403:
                log("API key rejected; check the key in Hookhaus → Funnels → SDK")
                paused = true
                return
            default:
                retries += 1
                nextAttempt = Date().addingTimeInterval(min(Double(retries) * 2, 60))
                log("send failed (\(status)); retry #\(retries)")
                return
            }
        }
        batchLimit = 50
    }

    private func send(_ events: [QueuedEvent], key: String) async -> Int {
        var request = URLRequest(url: options.host.appendingPathComponent("v1/sdk/batch"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-hookhaus-key")
        let body = Batch(sent_at: ISO.string(Date()), sdk: "hookhaus-swift/\(Hookhaus.version)", context: DeviceContext.current(), events: events)
        guard let data = try? JSONEncoder().encode(body) else { return 400 }
        request.httpBody = data
        return await transport(request)
    }

    private func log(_ message: String) {
        if options.debug { print("[Hookhaus] \(message)") }
    }
}


enum Keys {
    static let installId = "hookhaus.install_id"
    static let userId = "hookhaus.user_id"
    static let optOut = "hookhaus.opt_out"
    static let consent = "hookhaus.consent"
    static let firstOpenSent = "hookhaus.first_open_sent"
    static let appVersion = "hookhaus.app_version"
}

enum ISO {
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

/// Queue persisted as one small JSON file in Application Support (survives app restarts and offline periods).
struct Store: Sendable {
    let url: URL?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        url = base?.appendingPathComponent("hookhaus", isDirectory: true).appendingPathComponent("queue.json")
    }

    func load() -> [QueuedEvent] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([QueuedEvent].self, from: data)) ?? []
    }

    func save(_ events: [QueuedEvent]) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: url, options: .atomic)
        } catch {}
    }
}

/// Time-ordered UUID (RFC 9562 v7): unique event id, also lets the server deduplicate retries.
enum UUIDv7 {
    static func make(at date: Date = Date()) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        for i in 0 ..< 6 { bytes[i] = UInt8((ms >> (8 * (5 - i))) & 0xFF) }
        var random = SystemRandomNumberGenerator()
        for i in 6 ..< 16 { bytes[i] = UInt8.random(in: 0 ... 255, using: &random) }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let i = hex.startIndex
        func s(_ a: Int, _ b: Int) -> Substring { hex[hex.index(i, offsetBy: a) ..< hex.index(i, offsetBy: b)] }
        return "\(s(0, 8))-\(s(8, 12))-\(s(12, 16))-\(s(16, 20))-\(s(20, 32))"
    }
}
