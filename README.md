# HookhausKit

The Hookhaus app-side SDK for iOS. It measures your onboarding and paywall funnel and sends the events to your
Hookhaus panel (**Results → Funnels**).

- No advertising ID (IDFA), no IDFV, no fingerprinting. Each install gets a random UUID.
- No App Tracking Transparency prompt needed.
- Ships its own privacy manifest (`PrivacyInfo.xcprivacy`).
- Queues events on disk and sends them in batches. They survive offline periods and app restarts.
- No dependencies. iOS 15+, macOS 12+, tvOS 15+, visionOS 1+. Swift 5.9+.

## Install

In Xcode, open **File → Add Package Dependencies** and enter:

```
https://github.com/furkanio/hookhaus-swift
```

Add `HookhausKit` to your app target.

## Start

Copy the key from **Hookhaus → Funnels → Add HookhausKit to your app**. The key starts with `hh_pk_`. It can only
write events, not read data, so it is safe inside your app.

```swift
import HookhausKit

@main
struct MyApp: App {
    init() {
        Hookhaus.configure(apiKey: "hh_pk_…")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

With UIKit, call `Hookhaus.configure` in `application(_:didFinishLaunchingWithOptions:)`.

These events are tracked automatically (turn them off with `HookhausOptions(captureLifecycle: false)`):

| Event | When |
|---|---|
| `$first_open` | First launch after install |
| `$app_open` | Each time the app becomes active |
| `$app_updated` | First launch after a version change |

## Mark your onboarding and paywall

```swift
// Each onboarding screen; index keeps the order even if a step is skipped
Hookhaus.onboardingStep("welcome", index: 1)
Hookhaus.onboardingStep("notifications", index: 2)
Hookhaus.onboardingCompleted()

// Paywall and purchase
Hookhaus.paywallShown("main")
Hookhaus.trialStarted(product: "pro.yearly")
Hookhaus.purchased(product: "pro.yearly")
```

SwiftUI modifiers fire once when the view appears:

```swift
WelcomeView().hookhausOnboardingStep("welcome", index: 1)
PaywallView().hookhausPaywall("main")
SettingsView().hookhausScreen("settings")
```

Keep step names short and stable. If you change the copy on a screen but keep its step name, the history stays
comparable.

When the first events arrive, Hookhaus sets up the primary onboarding funnel for you. The steps follow your
`index` order:

> first open → onboarding steps → onboarding completed → paywall → trial or purchase

You can edit that funnel and add new ones in the panel.

## Custom events

```swift
Hookhaus.track("tapped_share", properties: ["source": "result_screen", "count": 3])
```

Rules for custom events:

- **Names:** letters, digits, space and `_ . : -`, at most 64 characters. Names starting with `$` are reserved.
- **Properties:** at most 40 per event. Values are text, numbers or true/false; text is cut at 512 characters.

## Users, consent and opt-out

```swift
Hookhaus.identify("user-42")   // your own user id after sign-up; never an email address or name
Hookhaus.reset()               // on log-out: forget the user id and start a new install id

// EU consent: collect nothing until the user agrees
Hookhaus.configure(apiKey: "hh_pk_…", options: HookhausOptions(requireConsent: true))
Hookhaus.grantConsent()

Hookhaus.optOut()              // stop and drop queued events (persisted)
Hookhaus.optIn()
```

## App Store privacy label

In **App Store Connect → App Privacy**, declare these data types:

- **Product Interaction:** purpose Analytics, Used for Tracking: No.
- **Device ID:** purpose Analytics, Used for Tracking: No. This covers the random install id.
- **Linked to You:** No. Choose Yes only if you call `identify` with your own user id.

## Options

```swift
HookhausOptions(
    host: URL(string: "https://app.hookhaus.studio")!, // self-hosted panels change this
    flushAt: 20,           // send when this many events are queued
    flushInterval: 30,     // …or at least this often (seconds)
    maxQueueSize: 1000,    // oldest events are dropped beyond this
    requireConsent: false,
    captureLifecycle: true,
    debug: false           // print what the SDK does
)
```

## Delivery

Events go to `POST {host}/v1/sdk/batch` in batches with the `x-hookhaus-key` header.

| Response | What the SDK does |
|---|---|
| 200 | Removes the batch from the queue. |
| Network error or 5xx | Keeps the events and retries with backoff, up to 60 seconds. |
| 413 | Halves the batch and retries. |
| 401 | Pauses sending until the next `configure`; the key is wrong. |

Each event has a time-ordered UUID (v7), so a retried batch is never counted twice. The server corrects device clock
skew using the batch's `sent_at`. Raw events are kept for 180 days.

## Tests

```
swift test
```
