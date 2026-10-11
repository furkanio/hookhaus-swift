# HookhausKit

Türkçe: [README.tr.md](README.tr.md)

HookhausKit is the in-app SDK for [Hookhaus](https://app.hookhaus.studio). It measures where people drop off in your
iOS app: from first open, through each onboarding screen, to the paywall, trial and purchase. The results appear in
your Hookhaus panel under **Results → Funnels** and **Results → Retention**.

- **Private by design:** no advertising ID (IDFA), no IDFV and no fingerprinting. Each install gets a random ID, so
  no App Tracking Transparency prompt is needed.
- **Privacy manifest included:** the package ships its own `PrivacyInfo.xcprivacy`.
- **Reliable delivery:** events are queued on disk and sent in small batches. They survive offline periods, app
  restarts and retries without being counted twice.
- **Lightweight:** no dependencies, and no work on the main thread.

| Requirement | Version |
|---|---|
| Xcode | 15 or later |
| Swift | 5.9 or later |
| Platforms | iOS 15+, macOS 12+, tvOS 15+, visionOS 1+ |

## Contents

1. [Get your SDK key](#1-get-your-sdk-key)
2. [Add the package](#2-add-the-package)
3. [Start the SDK](#3-start-the-sdk)
4. [Mark your onboarding screens](#4-mark-your-onboarding-screens)
5. [Mark the paywall, trial and purchase](#5-mark-the-paywall-trial-and-purchase)
6. [Check that events arrive](#6-check-that-events-arrive)
7. [Fill in the App Store privacy label](#7-fill-in-the-app-store-privacy-label)
8. [Release](#8-release)
- [Optional: users, consent and opt-out](#optional-users-consent-and-opt-out)
- [Optional: custom events and screens](#optional-custom-events-and-screens)
- [Data deletion requests](#data-deletion-requests)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

---

## 1. Get your SDK key

1. Sign in to your Hookhaus panel.
2. Pick your app in the app switcher at the top.
3. Open **Results → Funnels**. Until the first event arrives, the page shows **Add HookhausKit to your app** with
   your key.
4. Copy the key. It starts with `hh_pk_`.

The key can only **write** events for this one app; it cannot read any data. It is safe to ship inside your app
binary. If you ever need a new one, use **Rotate key** on the same page. The old key stops working immediately, so
the new key has to ship in a new app version before events arrive again.

## 2. Add the package

### Xcode

1. Open your app project in Xcode.
2. Choose **File → Add Package Dependencies…**
3. Paste this URL into the search field at the top right:
   ```
   https://github.com/furkanio/hookhaus-swift
   ```
4. Set **Dependency Rule** to **Up to Next Major Version** and keep the suggested version (`0.3.0` or later).
5. Click **Add Package**.
6. In the next window, make sure **HookhausKit** is added to your **app target**, not only to a test target. Then
   click **Add Package**.

You should now see `hookhaus-swift` under **Package Dependencies** in the project navigator.

### Package.swift

If you build a Swift package or use SPM directly:

```swift
dependencies: [
    .package(url: "https://github.com/furkanio/hookhaus-swift", from: "0.3.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "HookhausKit", package: "hookhaus-swift"),
    ]),
]
```

## 3. Start the SDK

Call `Hookhaus.configure` **once, as early as possible** in your app's launch. Events tracked before `configure`
finishes are kept and sent afterwards.

### SwiftUI

```swift
import SwiftUI
import HookhausKit

@main
struct MyApp: App {
    init() {
        Hookhaus.configure(apiKey: "hh_pk_…")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### UIKit

```swift
import UIKit
import HookhausKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Hookhaus.configure(apiKey: "hh_pk_…")
        return true
    }
}
```

### While developing

Turn on console output to see what the SDK does:

```swift
#if DEBUG
Hookhaus.configure(apiKey: "hh_pk_…", options: HookhausOptions(debug: true))
#else
Hookhaus.configure(apiKey: "hh_pk_…")
#endif
```

From now on, three events are tracked automatically:

| Event | When |
|---|---|
| `$first_open` | The first launch after the app is installed (once per install) |
| `$app_open` | Every time the app comes to the foreground |
| `$app_updated` | The first launch after the app version changed |

> **Test events stay out of your numbers.** Events from the simulator or a Debug build are marked as development
> events. They show up in **Recent events** (tagged "test") and, until the first real event arrives, in the funnel,
> so you can check your setup. Once your App Store or TestFlight build sends events, funnels, retention and the
> decision log count only those. TestFlight builds are Release builds, so they count as real users.

## 4. Mark your onboarding screens

Call `onboardingStep` when each onboarding screen is **shown**, and `onboardingCompleted` when the user finishes.

```swift
Hookhaus.onboardingStep("welcome", index: 1)
Hookhaus.onboardingStep("goal", index: 2)
Hookhaus.onboardingStep("notifications", index: 3)
Hookhaus.onboardingCompleted()
```

### SwiftUI

Attach the modifier to each screen. It fires in `onAppear`:

```swift
struct OnboardingFlow: View {
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WelcomeView().tag(0)
                .hookhausOnboardingStep("welcome", index: 1)
            GoalView().tag(1)
                .hookhausOnboardingStep("goal", index: 2)
            NotificationsView(onDone: finish).tag(2)
                .hookhausOnboardingStep("notifications", index: 3)
        }
        .tabViewStyle(.page)
    }

    private func finish() {
        Hookhaus.onboardingCompleted()
        // show the paywall or the main screen
    }
}
```

> `TabView` with the page style can call `onAppear` for the neighbouring page before the user swipes to it. If your
> flow is built that way, call `Hookhaus.onboardingStep` in `.onChange(of: page)` instead of using the modifier.

### UIKit

```swift
final class WelcomeViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Hookhaus.onboardingStep("welcome", index: 1)
    }
}
```

### Naming rules

- **Use short, stable names** such as `welcome`, `goal`, `notifications`. If you rewrite a screen's copy but keep its
  name, its history stays comparable.
- **Always pass `index`.** Hookhaus orders the funnel by `index`. If a user skips a screen, the order stays correct.
- **Repeats are fine.** If a screen is shown twice (back button, re-render), it still counts once per install.
- **Optional screens:** give them their own index anyway. You can leave them out of a funnel later in the panel.
- **Allowed characters:** letters, digits, space and `_ . : -`, at most 64 characters.

When the first events arrive, Hookhaus builds your **primary onboarding funnel** automatically:

> first open → your onboarding steps in `index` order → onboarding completed → paywall → trial or purchase

You can rename steps, reorder them, change the time window and create more funnels in the panel.

## 5. Mark the paywall, trial and purchase

```swift
Hookhaus.paywallShown("main")                       // when the paywall is shown; the id is your own name for it
Hookhaus.trialStarted(product: "pro.yearly")        // when a free trial starts
Hookhaus.purchased(product: "pro.yearly")           // when a paid purchase completes
```

Revenue itself is read from App Store Connect, so `price` and `currency` are optional. Do not send the transaction
or receipt itself.

### With StoreKit 2

```swift
import StoreKit
import HookhausKit

func buy(_ product: Product) async throws {
    let result = try await product.purchase()
    guard case .success(let verification) = result,
          case .verified(let transaction) = verification else { return }

    let isFreeTrial = transaction.offerType == .introductory
        && product.subscription?.introductoryOffer?.paymentMode == .freeTrial

    if isFreeTrial {
        Hookhaus.trialStarted(product: product.id)
    } else {
        Hookhaus.purchased(product: product.id,
                           price: product.price,
                           currency: product.priceFormatStyle.currencyCode)
    }
    await transaction.finish()
}
```

With RevenueCat or another purchase library, call the same functions after a successful purchase. In SwiftUI you
can mark the paywall with a modifier:

```swift
PaywallView().hookhausPaywall("main")
```

## 6. Check that events arrive

1. Start the SDK with `HookhausOptions(debug: true)` (see [step 3](#while-developing)).
2. Run the app in the simulator or on a device. If it was installed before, delete it first so `$first_open` fires.
3. In the Xcode console you should see lines like these:
   ```
   [Hookhaus] configured; 0 queued events
   [Hookhaus] queued $first_open (1)
   [Hookhaus] queued $onboarding_step (2)
   [Hookhaus] sent 2 events
   ```
   Events are sent every 30 seconds, when 20 are waiting, or when the app goes to the background. Press the Home
   button, or call `Hookhaus.flush()`, to send at once.
4. Open **Results → Funnels** in the panel. The setup page refreshes every few seconds. After the first event it
   switches to the funnel view, and **Recent events** lists what arrived.
5. Go through your onboarding once from start to finish. The primary funnel appears once events from at least two
   different steps have arrived.

## 7. Fill in the App Store privacy label

In **App Store Connect → your app → App Privacy**:

1. Click **Get Started** (or **Edit**) and answer **Yes, we collect data from this app**.
2. Select these data types:
   - **Identifiers → Device ID**: this covers the random install ID.
   - **Usage Data → Product Interaction**: this covers the onboarding, paywall and purchase events.
   - **Identifiers → User ID**: only if you call `Hookhaus.identify`.
3. For each data type, answer:
   - **Purpose:** Analytics.
   - **Linked to the user's identity:** No. Choose **Yes** only if you call `Hookhaus.identify`.
   - **Used for tracking:** No.
4. Publish the changes.

The package's privacy manifest already declares Device ID and Product Interaction (analytics, not linked, no
tracking) and its use of `UserDefaults` (reason `CA92.1`). Xcode merges it into your app's privacy report
automatically. If you call `Hookhaus.identify`, also declare User ID in your app's own privacy manifest.

## 8. Release

- Ship the version that includes HookhausKit as usual.
- Events from real users start arriving as soon as people install or update to that version. Older versions send
  nothing.
- The **From store to app** panel on the Funnels page puts App Store impressions, product page views and first
  downloads next to first opens. Apple's numbers arrive 1–3 days late.
- When you change a screen, log it in the **Decision log**. Hookhaus then measures the onboarding completion rate
  (or the day-1 return rate) before and after the change.
- **Results → Retention** shows how many installs come back on day 1, 7 and 30, by the day they first opened the app.

---

## Optional: users, consent and opt-out

```swift
// After sign-up or sign-in: your own user ID. Never an e-mail address, name or phone number.
Hookhaus.identify("user-42")

// On log-out: forget the user ID and start a new install ID.
Hookhaus.reset()
```

If you need consent before collecting analytics, for example for EU users:

```swift
Hookhaus.configure(apiKey: "hh_pk_…", options: HookhausOptions(requireConsent: true))

// When the user agrees (the choice is remembered across launches):
Hookhaus.grantConsent()
```

Nothing is collected or queued until `grantConsent()` is called.

To let users turn analytics off, for example from a switch in Settings:

```swift
Hookhaus.optOut()   // stops collecting and deletes queued events; remembered across launches
Hookhaus.optIn()    // starts collecting again
```

## Optional: custom events and screens

```swift
Hookhaus.track("tapped_share", properties: ["source": "result_screen", "count": 3, "pro": true])
Hookhaus.screen("settings")

// SwiftUI
SettingsView().hookhausScreen("settings")
```

You can use custom events as funnel steps in the panel.

- **Event names:** letters, digits, space and `_ . : -`, at most 64 characters. Names starting with `$` are
  reserved.
- **Properties:** at most 40 per event; values are text, numbers or true/false. Text is cut at 512 characters.
- **No personal data:** do not put e-mail addresses, names, phone numbers or free text the user typed into
  properties.

## Data deletion requests

If a user asks you to delete their data, you need an ID to find it:

- **Without accounts:** show the install ID in your app, for example under Settings → Support:
  ```swift
  let id = await Hookhaus.installId()
  ```
- **With accounts:** use the user ID you passed to `Hookhaus.identify`.

Then, in the panel, open **Results → Funnels → In-app SDK → Privacy and the App Store privacy label → Delete user
data**, paste the ID and confirm. All events of that install or user are deleted permanently. Only workspace admins
can do this.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| No `[Hookhaus]` lines in the console | `debug: true` is not set, or `configure` is never called. Put it in `App.init` or `didFinishLaunching`. |
| `API key rejected; check the key…` | The key is wrong or was rotated. Copy it again from **Results → Funnels** and rebuild. |
| `send failed (0); retry #1` | No network connection. Events stay queued and are sent later. |
| `dropped invalid event name: …` | The name breaks the [naming rules](#naming-rules). |
| `$first_open` does not appear | It fires once per install. Delete the app and run it again. |
| Nothing is queued at all | You set `requireConsent: true` without calling `grantConsent()`, or `optOut()` was called earlier. Call `optIn()`, or delete the app. |
| Events arrive but no funnel | The automatic funnel needs events from at least two different steps. Go through onboarding once, or create a funnel in the panel. |
| Steps are in the wrong order | Pass `index` to every `onboardingStep`, or reorder the steps in the panel's funnel editor. |
| Test runs show up in the numbers | Simulator and Debug events are already left out. If you test with a Release build on a device, use a separate Hookhaus app and key. |

## Reference

### API

| Call | What it does |
|---|---|
| `Hookhaus.configure(apiKey:options:)` | Starts the SDK. Call once at launch; calling it again replaces the settings. |
| `Hookhaus.onboardingStep(_:index:properties:)` | An onboarding screen was shown. |
| `Hookhaus.onboardingCompleted(properties:)` | The user finished onboarding. |
| `Hookhaus.paywallShown(_:properties:)` | A paywall was shown. |
| `Hookhaus.trialStarted(product:properties:)` | A free trial started. |
| `Hookhaus.purchased(product:price:currency:properties:)` | A paid purchase completed. |
| `Hookhaus.track(_:properties:)` | A custom event. |
| `Hookhaus.screen(_:properties:)` | A screen was shown. |
| `Hookhaus.identify(_:)` | Attach your own user ID. |
| `Hookhaus.reset()` | Forget the user ID and start a new install ID. |
| `Hookhaus.grantConsent()` | Start collecting when `requireConsent` is on. |
| `Hookhaus.optOut()` / `optIn()` | Stop or resume collecting. |
| `Hookhaus.flush()` | Send queued events now. |
| `await Hookhaus.installId()` | This install's random ID, for data deletion requests. |
| `.hookhausOnboardingStep(_:index:)`, `.hookhausPaywall(_:)`, `.hookhausScreen(_:)` | SwiftUI modifiers that fire in `onAppear`. |

### Options

```swift
HookhausOptions(
    host: URL(string: "https://app.hookhaus.studio")!, // change only for a self-hosted panel
    flushAt: 20,            // send when this many events are waiting
    flushInterval: 30,      // …or at least this often, in seconds
    maxQueueSize: 1000,     // the oldest events are dropped beyond this
    requireConsent: false,  // collect nothing until grantConsent()
    captureLifecycle: true, // $first_open, $app_open, $app_updated
    debug: false            // print what the SDK does
)
```

### Standard events

| Event | Sent by | Properties |
|---|---|---|
| `$first_open` | automatic | |
| `$app_open` | automatic | |
| `$app_updated` | automatic | `previous_version` |
| `$onboarding_step` | `onboardingStep` | `step`, `index` |
| `$onboarding_complete` | `onboardingCompleted` | |
| `$paywall_view` | `paywallShown` | `paywall` |
| `$trial_start` | `trialStarted` | `product` |
| `$purchase` | `purchased` | `product`, `price`, `currency` |
| `$screen` | `screen` | `name` |
| `$identify` | `identify` | |

Each batch also carries the app version and build, OS version, device model (for example `iPhone16,2`), language
and the region set on the device. IP-based location is not used.

### Delivery and data

- Events are sent to `POST {host}/v1/sdk/batch` with the `x-hookhaus-key` header.

  | Response | What the SDK does |
  |---|---|
  | 2xx | Removes the batch from the queue. |
  | No network or 5xx | Keeps the events and retries with backoff, up to 60 seconds apart. |
  | 400 | Drops the batch, because it is malformed and a retry would fail again. |
  | 413 | Halves the batch and retries. |
  | 401 or 403 | Stops sending until the next `configure`, because the key is wrong. |

- Every event has a time-ordered ID (UUID v7). A batch sent twice is stored once.
- The server corrects device clock errors using the time the batch was sent.
- The queue lives in `Application Support/hookhaus/queue.json`; settings live in `UserDefaults` under `hookhaus.*`.
- Hookhaus keeps raw events for 180 days. Funnel results are computed from counts; no list of people is shown.

### Updating

In Xcode, choose **File → Packages → Update to Latest Package Versions**. Release notes are on the repository's
tags.

### Tests

```
swift test
```
