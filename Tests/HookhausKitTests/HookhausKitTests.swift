import Foundation
import XCTest
@testable import HookhausKit

/// Records requests and answers with scripted status codes.
actor FakeServer {
    private var statuses: [Int]
    private(set) var batches: [[String: Any]] = []
    private(set) var headers: [[String: String]] = []

    init(statuses: [Int] = []) { self.statuses = statuses }

    func handle(_ request: URLRequest) -> Int {
        if let body = request.httpBody, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { batches.append(json) }
        headers.append(request.allHTTPHeaderFields ?? [:])
        return statuses.isEmpty ? 200 : statuses.removeFirst()
    }

    nonisolated var transport: Transport {
        { request in await self.handle(request) }
    }

    var events: [[String: Any]] { batches.flatMap { ($0["events"] as? [[String: Any]]) ?? [] } }
    var sizes: [Int] { batches.map { ($0["events"] as? [Any])?.count ?? 0 } }
}

final class HookhausKitTests: XCTestCase {
    var dir: URL!
    var defaults: UserDefaults!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hookhaus.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func engine(_ server: FakeServer, options: HookhausOptions = HookhausOptions(flushAt: 100, captureLifecycle: false)) async -> Engine {
        let e = Engine(store: Store(directory: dir), transport: server.transport, defaults: defaults)
        await e.configure(apiKey: "hh_pk_test_key_123456789", options: options, launchedAt: Date())
        return e
    }

    func testBatchFormatAndHeaders() async throws {
        let server = FakeServer()
        let e = await engine(server)
        await e.enqueue("$onboarding_step", properties: ["step": "welcome", "index": 1], at: Date(timeIntervalSince1970: 1_700_000_000))
        // Same session: second event 1 minute later (a gap over 30 minutes would start a new session)
        await e.enqueue("signup", properties: ["plan": "pro", "ok": true, "n": 2.5], at: Date(timeIntervalSince1970: 1_700_000_060))
        await e.flush()
        let batches = await server.batches
        XCTAssertEqual(batches.count, 1)
        let batch = batches[0]
        XCTAssertEqual(batch["sdk"] as? String, "hookhaus-swift/\(Hookhaus.version)")
        XCTAssertNotNil(batch["sent_at"] as? String)
        XCTAssertNotNil((batch["context"] as? [String: Any])?["os_version"])
        let events = await server.events
        XCTAssertEqual(events.map { $0["event"] as? String }, ["$onboarding_step", "signup"])
        XCTAssertEqual((events[0]["props"] as? [String: Any])?["step"] as? String, "welcome")
        XCTAssertEqual((events[0]["props"] as? [String: Any])?["index"] as? Int, 1)
        XCTAssertEqual(events[0]["timestamp"] as? String, "2023-11-14T22:13:20.000Z")
        // Same install and session for both events; v7 ids are unique
        XCTAssertEqual(events[0]["distinct_id"] as? String, events[1]["distinct_id"] as? String)
        XCTAssertEqual(events[0]["session_id"] as? String, events[1]["session_id"] as? String)
        XCTAssertNotEqual(events[0]["id"] as? String, events[1]["id"] as? String)
        let headers = await server.headers
        XCTAssertEqual(headers[0]["x-hookhaus-key"], "hh_pk_test_key_123456789")
        let left = await e.queued
        XCTAssertTrue(left.isEmpty)
    }

    func testRetryKeepsQueueAndBackoff() async {
        let server = FakeServer(statuses: [500])
        let e = await engine(server)
        await e.enqueue("a", properties: [:], at: Date())
        await e.flush()
        let left = await e.queued
        XCTAssertEqual(left.count, 1, "failed send keeps events")
        // Backoff: an immediate second flush does not send
        await e.flush()
        let n = await server.batches.count
        XCTAssertEqual(n, 1)
    }

    func test413SplitsBatch() async {
        let server = FakeServer(statuses: [413])
        let e = await engine(server)
        for i in 0 ..< 4 { await e.enqueue("e\(i)", properties: [:], at: Date()) }
        await e.flush()
        // First attempt: 4 events (413), then halves and sends 2 + 2
        let sizes = await server.sizes
        XCTAssertEqual(sizes, [4, 2, 2])
        let left = await e.queued
        XCTAssertTrue(left.isEmpty)
    }

    func testWrongKeyPausesSending() async {
        let server = FakeServer(statuses: [401])
        let e = await engine(server)
        await e.enqueue("a", properties: [:], at: Date())
        await e.flush()
        await e.flush()
        let n = await server.batches.count
        XCTAssertEqual(n, 1)
        let left = await e.queued
        XCTAssertEqual(left.count, 1)
    }

    func testQueuePersistsAcrossLaunches() async {
        let server = FakeServer(statuses: [0])
        let e = await engine(server)
        await e.enqueue("offline", properties: [:], at: Date())
        await e.flush()
        let e2 = await engine(FakeServer())
        let left = await e2.queued
        XCTAssertEqual(left.map(\.event), ["offline"])
    }

    func testConsentAndOptOut() async {
        let server = FakeServer()
        let e = await engine(server, options: HookhausOptions(flushAt: 100, requireConsent: true, captureLifecycle: false))
        await e.enqueue("before", properties: [:], at: Date())
        var left = await e.queued
        XCTAssertTrue(left.isEmpty, "nothing collected before consent")
        await e.setConsent(true)
        await e.enqueue("after", properties: [:], at: Date())
        left = await e.queued
        XCTAssertEqual(left.map(\.event), ["after"])
        await e.setOptOut(true)
        left = await e.queued
        XCTAssertTrue(left.isEmpty, "opt-out drops the queue")
        await e.enqueue("ignored", properties: [:], at: Date())
        left = await e.queued
        XCTAssertTrue(left.isEmpty)
    }

    func testFirstOpenOnceAndIdentity() async {
        let server = FakeServer()
        let options = HookhausOptions(flushAt: 100, captureLifecycle: true)
        let e = await engine(server, options: options)
        var left = await e.queued
        XCTAssertEqual(left.map(\.event), ["$first_open"])
        await e.configure(apiKey: "hh_pk_test_key_123456789", options: options, launchedAt: Date())
        left = await e.queued
        XCTAssertEqual(left.map(\.event), ["$first_open"], "second launch has no first open")
        let install = await e.installId
        XCTAssertEqual(install.count, 36)
        await e.identify("user-42", at: Date())
        left = await e.queued
        XCTAssertEqual(left.last?.user_id, "user-42")
        await e.reset()
        let fresh = await e.installId
        XCTAssertNotEqual(install, fresh)
    }

    func testInvalidNamesAndPropertyLimits() async {
        let server = FakeServer()
        let e = await engine(server)
        await e.enqueue("", properties: [:], at: Date())
        await e.enqueue("bad$name", properties: [:], at: Date())
        await e.enqueue(String(repeating: "x", count: 65), properties: [:], at: Date())
        var many: [String: HookhausValue] = [:]
        for i in 0 ..< 60 { many["k\(i)"] = .string(String(repeating: "y", count: 600)) }
        await e.enqueue("ok", properties: many, at: Date())
        let left = await e.queued
        XCTAssertEqual(left.map(\.event), ["ok"])
        XCTAssertEqual(left[0].props.count, 40)
        if case let .string(s)? = left[0].props.values.first { XCTAssertEqual(s.count, 512) } else { XCTFail("string prop") }
    }

    func testEventsBeforeConfigureAreKept() async {
        let server = FakeServer()
        let e = Engine(store: Store(directory: dir), transport: server.transport, defaults: defaults)
        await e.enqueue("early", properties: [:], at: Date())
        await e.configure(apiKey: "hh_pk_test_key_123456789", options: HookhausOptions(flushAt: 100, captureLifecycle: false), launchedAt: Date())
        let left = await e.queued
        XCTAssertEqual(left.map(\.event), ["early"])
    }

    func testUUIDv7() {
        let a = UUIDv7.make(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(a.count, 36)
        XCTAssertEqual(Array(a)[14], "7")
        XCTAssertTrue("89ab".contains(Array(a)[19]))
        XCTAssertTrue(a.hasPrefix("018bcfe5-6800"))
    }
}
