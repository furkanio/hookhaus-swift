import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Sent once per batch: app and device facts. No identifiers, no IP-based location (region is the device setting).
struct DeviceContext: Encodable, Sendable {
    var app_version: String?
    var build: String?
    var os_version: String
    var device: String
    var locale: String
    var region: String?
    /// Simulator or Debug build: Hookhaus keeps these events out of funnels and retention (they still show up while
    /// you check your setup).
    var dev: Bool

    static func current() -> DeviceContext {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var region: String?
        if #available(iOS 16, macOS 13, tvOS 16, *) {
            region = Locale.current.region?.identifier
        } else {
            region = Locale.current.regionCode
        }
        return DeviceContext(
            app_version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            os_version: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            device: modelIdentifier(),
            locale: Locale.current.identifier,
            region: region,
            dev: isDevelopment
        )
    }

    static var isDevelopment: Bool {
        #if targetEnvironment(simulator)
        return true
        #elseif DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Hardware model, e.g. "iPhone16,2" (not unique to a person or device).
    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { s, e in
            guard let v = e.value as? Int8, v != 0 else { return }
            s.append(Character(UnicodeScalar(UInt8(bitPattern: v))))
        }
        return id.isEmpty ? "unknown" : String(id.prefix(48))
    }
}

/// App lifecycle on iOS/tvOS/visionOS: "app open" when the app becomes active, flush when it goes to background.
final class LifecycleObserver: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    init(onActive: @escaping @Sendable (Date) -> Void, onBackground: @escaping @Sendable () -> Void) {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in onActive(Date()) })
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in onBackground() })
        #endif
    }

    deinit {
        for t in tokens { NotificationCenter.default.removeObserver(t) }
    }
}
