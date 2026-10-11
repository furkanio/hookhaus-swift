# HookhausKit

English: [README.md](README.md)

HookhausKit, [Hookhaus](https://app.hookhaus.studio)'un app içi SDK'sıdır. iOS app'inde kullanıcıların nerede
bıraktığını ölçer: ilk açılıştan başlayıp her onboarding ekranından geçerek paywall'a, denemeye ve satın almaya kadar.
Sonuçlar Hookhaus panelinde **Sonuçlar → Huniler** ve **Sonuçlar → Elde tutma** altında görünür.

- **Gizlilik öncelikli:** Reklam kimliği (IDFA), IDFV ya da parmak izi kullanılmaz. Her kurulum rastgele bir
  kimlik alır; bu yüzden App Tracking Transparency izni gerekmez.
- **Gizlilik manifesti dahil:** Paket kendi `PrivacyInfo.xcprivacy` dosyasını taşır.
- **Güvenilir gönderim:** Olaylar diskte sıraya alınır ve küçük paketlerle gönderilir. İnternet yokken, app yeniden
  açıldığında ve yeniden denemelerde kaybolmaz, iki kez sayılmaz.
- **Hafif:** Bağımlılığı yoktur, ana iş parçacığında iş yapmaz.

| Gereksinim | Sürüm |
|---|---|
| Xcode | 15 ve üstü |
| Swift | 5.9 ve üstü |
| Platformlar | iOS 15+, macOS 12+, tvOS 15+, visionOS 1+ |

## İçindekiler

1. [SDK anahtarını al](#1-sdk-anahtarını-al)
2. [Paketi ekle](#2-paketi-ekle)
3. [SDK'yı başlat](#3-sdkyı-başlat)
4. [Onboarding ekranlarını işaretle](#4-onboarding-ekranlarını-işaretle)
5. [Paywall, deneme ve satın almayı işaretle](#5-paywall-deneme-ve-satın-almayı-işaretle)
6. [Olayların geldiğini kontrol et](#6-olayların-geldiğini-kontrol-et)
7. [App Store gizlilik etiketini doldur](#7-app-store-gizlilik-etiketini-doldur)
8. [Yayınla](#8-yayınla)
- [Ek: kullanıcı, rıza ve vazgeçme](#ek-kullanıcı-rıza-ve-vazgeçme)
- [Ek: özel olaylar ve ekranlar](#ek-özel-olaylar-ve-ekranlar)
- [Veri silme istekleri](#veri-silme-istekleri)
- [Sorun giderme](#sorun-giderme)
- [Başvuru](#başvuru)

---

## 1. SDK anahtarını al

1. Hookhaus paneline gir.
2. Üstteki app seçiciden app'ini seç.
3. **Sonuçlar → Huniler**'i aç. İlk olay gelene kadar sayfada anahtarınla birlikte **App'ine HookhausKit'i ekle**
   bölümü görünür.
4. Anahtarı kopyala; `hh_pk_` ile başlar.

Anahtar yalnız bu app için olay **yazar**, hiçbir veriyi okuyamaz. App'in içinde durması güvenlidir. Yeni anahtar
gerekirse aynı sayfada **Anahtarı yenile**'yi kullan. Eski anahtar hemen geçersiz olur; yeni anahtar yeni bir app
sürümüyle yayına çıkana kadar olay gelmez.

## 2. Paketi ekle

### Xcode ile

1. App projeni Xcode'da aç.
2. **File → Add Package Dependencies…** menüsünü seç.
3. Sağ üstteki arama kutusuna şu adresi yapıştır:
   ```
   https://github.com/furkanio/hookhaus-swift
   ```
4. **Dependency Rule** olarak **Up to Next Major Version** seç, önerilen sürümü (`0.3.0` ya da sonrası) bırak.
5. **Add Package**'a bas.
6. Açılan pencerede **HookhausKit**'in **app hedefine** eklendiğinden emin ol (yalnız test hedefine değil), sonra
   yine **Add Package**'a bas.

Proje gezgininde **Package Dependencies** altında `hookhaus-swift` görünmeli.

### Package.swift ile

Swift paketi geliştiriyorsan ya da SPM'i doğrudan kullanıyorsan:

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

## 3. SDK'yı başlat

`Hookhaus.configure`'u app açılışında **bir kez ve olabildiğince erken** çağır. `configure` bitmeden gönderilen
olaylar saklanır ve sonra gönderilir.

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

### Geliştirirken

SDK'nın ne yaptığını konsolda görmek için:

```swift
#if DEBUG
Hookhaus.configure(apiKey: "hh_pk_…", options: HookhausOptions(debug: true))
#else
Hookhaus.configure(apiKey: "hh_pk_…")
#endif
```

Bundan sonra üç olay kendiliğinden gelir:

| Olay | Ne zaman |
|---|---|
| `$first_open` | App kurulduktan sonraki ilk açılış (kurulum başına bir kez) |
| `$app_open` | App her öne geldiğinde |
| `$app_updated` | App sürümü değiştikten sonraki ilk açılış |

> **Deneme olayları sayılara girmez.** Simülatörden ya da Debug derlemesinden gelen olaylar geliştirme olayı olarak
> işaretlenir. Bunlar **Son olaylar**'da "test" etiketiyle ve ilk gerçek olay gelene kadar hunide görünür; böylece
> kurulumunu kontrol edebilirsin. App Store ya da TestFlight sürümünden olay gelmeye başlayınca huniler, elde tutma ve
> karar defteri yalnız onları sayar. TestFlight derlemeleri Release olduğu için gerçek kullanıcı sayılır.

## 4. Onboarding ekranlarını işaretle

Her onboarding ekranı **göründüğünde** `onboardingStep`'i, kullanıcı onboarding'i bitirince `onboardingCompleted`'ı
çağır.

```swift
Hookhaus.onboardingStep("welcome", index: 1)
Hookhaus.onboardingStep("goal", index: 2)
Hookhaus.onboardingStep("notifications", index: 3)
Hookhaus.onboardingCompleted()
```

### SwiftUI

Değiştiriciyi her ekrana ekle; `onAppear`'da çalışır:

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
        // paywall'u ya da ana ekranı göster
    }
}
```

> Sayfa stilindeki `TabView`, kullanıcı kaydırmadan önce yandaki sayfanın `onAppear`'ını çağırabilir. Akışın böyle
> kuruluysa değiştirici yerine `Hookhaus.onboardingStep`'i `.onChange(of: page)` içinde çağır.

### UIKit

```swift
final class WelcomeViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Hookhaus.onboardingStep("welcome", index: 1)
    }
}
```

### Adlandırma kuralları

- **Kısa ve sabit adlar kullan:** `welcome`, `goal`, `notifications` gibi. Ekranın metnini değiştirsen de adı aynı
  kalırsa geçmişi karşılaştırılabilir kalır.
- **`index`'i her zaman ver:** Hookhaus huniyi `index`'e göre sıralar. Kullanıcı bir ekranı atlasa da sıra doğru
  kalır.
- **Tekrar sorun değil:** Bir ekran iki kez gösterilirse (geri tuşu, yeniden çizim) kurulum başına yine bir kez
  sayılır.
- **İsteğe bağlı ekranlar:** Onlara da kendi index'ini ver; panelde istersen huniden çıkarırsın.
- **İzin verilen karakterler:** harf, rakam, boşluk ve `_ . : -`; en çok 64 karakter.

İlk olaylar gelince Hookhaus **ana onboarding hunisini** kendiliğinden kurar:

> ilk açılış → `index` sırasıyla onboarding adımların → onboarding bitti → paywall → deneme ya da satın alma

Adımları yeniden adlandırabilir, sıralarını değiştirebilir, zaman penceresini ayarlayabilir ve panelde yeni huniler
kurabilirsin.

## 5. Paywall, deneme ve satın almayı işaretle

```swift
Hookhaus.paywallShown("main")                       // paywall görününce; kimlik senin verdiğin ad
Hookhaus.trialStarted(product: "pro.yearly")        // ücretsiz deneme başlayınca
Hookhaus.purchased(product: "pro.yearly")           // ücretli satın alma tamamlanınca
```

Gelirin kendisi App Store Connect'ten okunur; `price` ve `currency` isteğe bağlıdır. İşlemin ya da makbuzun
kendisini gönderme.

### StoreKit 2 ile

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

RevenueCat ya da başka bir satın alma kütüphanesi kullanıyorsan aynı fonksiyonları başarılı satın almadan sonra
çağır. SwiftUI'da paywall'u değiştiriciyle işaretleyebilirsin:

```swift
PaywallView().hookhausPaywall("main")
```

## 6. Olayların geldiğini kontrol et

1. SDK'yı `HookhausOptions(debug: true)` ile başlat ([3. adım](#geliştirirken)).
2. App'i simülatörde ya da cihazda çalıştır. Daha önce kuruluysa `$first_open` gelsin diye önce sil.
3. Xcode konsolunda şuna benzer satırlar görmelisin:
   ```
   [Hookhaus] configured; 0 queued events
   [Hookhaus] queued $first_open (1)
   [Hookhaus] queued $onboarding_step (2)
   [Hookhaus] sent 2 events
   ```
   Olaylar 30 saniyede bir, 20 olay birikince ya da app arka plana geçince gönderilir. Hemen göndermek için Ana
   ekrana dön ya da `Hookhaus.flush()`'ı çağır.
4. Panelde **Sonuçlar → Huniler**'i aç. Kurulum sayfası birkaç saniyede bir yenilenir. İlk olaydan sonra huni
   görünümüne geçer; **Son olaylar** gelenleri listeler.
5. Onboarding'i baştan sona bir kez geç. Ana huni, en az iki farklı adımdan olay gelince görünür.

## 7. App Store gizlilik etiketini doldur

**App Store Connect → app'in → App Privacy** bölümünde:

1. **Get Started**'a (ya da **Edit**'e) bas ve **Yes, we collect data from this app** cevabını ver.
2. Şu veri türlerini seç:
   - **Identifiers → Device ID:** rastgele kurulum kimliği için.
   - **Usage Data → Product Interaction:** onboarding, paywall ve satın alma olayları için.
   - **Identifiers → User ID:** yalnız `Hookhaus.identify` kullanıyorsan.
3. Her veri türü için:
   - **Purpose:** Analytics.
   - **Linked to the user's identity:** No. Yalnız `Hookhaus.identify` kullanıyorsan **Yes**.
   - **Used for tracking:** No.
4. Değişiklikleri yayınla.

Paketin gizlilik manifesti Device ID ve Product Interaction'ı (analitik, kişiye bağlı değil, izleme yok) ve
`UserDefaults` kullanımını (neden `CA92.1`) zaten bildiriyor. Xcode bunu app'inin gizlilik raporuna kendiliğinden
ekler. `Hookhaus.identify` kullanıyorsan User ID'yi app'inin kendi gizlilik manifestine de ekle.

## 8. Yayınla

- HookhausKit'li sürümü her zamanki gibi yayınla.
- Gerçek kullanıcı olayları, insanlar bu sürümü kurdukça ya da güncelledikçe gelmeye başlar. Eski sürümler olay
  göndermez.
- Huniler sayfasındaki **Mağazadan app'e** bölümü App Store gösterimlerini, ürün sayfası görüntülemelerini ve ilk
  indirmeleri ilk açılışlarla yan yana koyar. Apple'ın sayıları 1–3 gün gecikmeli gelir.
- Bir ekranı değiştirdiğinde **Karar defteri**'ne yaz. Hookhaus onboarding tamamlama oranını (ya da 1. gün geri
  dönüş oranını) değişiklikten önce ve sonra ölçer.
- **Sonuçlar → Elde tutma**, kurulumların app'i ilk açtıkları güne göre 1., 7. ve 30. günde kaçının geri geldiğini
  gösterir.

---

## Ek: kullanıcı, rıza ve vazgeçme

```swift
// Kayıt ya da girişten sonra: kendi kullanıcı kimliğin. E-posta, ad ya da telefon numarası asla.
Hookhaus.identify("user-42")

// Çıkışta: kullanıcı kimliğini unut ve yeni bir kurulum kimliği başlat.
Hookhaus.reset()
```

Analitikten önce rıza alman gerekiyorsa (ör. AB'deki kullanıcılar için):

```swift
Hookhaus.configure(apiKey: "hh_pk_…", options: HookhausOptions(requireConsent: true))

// Kullanıcı kabul edince (seçim açılışlar arasında hatırlanır):
Hookhaus.grantConsent()
```

`grantConsent()` çağrılana kadar hiçbir şey toplanmaz ve sıraya alınmaz.

Kullanıcının analitiği kapatabilmesi için (ör. Ayarlar'daki bir anahtarla):

```swift
Hookhaus.optOut()   // toplamayı durdurur, sıradaki olayları siler; açılışlar arasında hatırlanır
Hookhaus.optIn()    // yeniden toplar
```

## Ek: özel olaylar ve ekranlar

```swift
Hookhaus.track("tapped_share", properties: ["source": "result_screen", "count": 3, "pro": true])
Hookhaus.screen("settings")

// SwiftUI
SettingsView().hookhausScreen("settings")
```

Özel olayları panelde huni adımı olarak kullanabilirsin.

- **Olay adları:** harf, rakam, boşluk ve `_ . : -`; en çok 64 karakter. `$` ile başlayan adlar SDK'ya ayrılmıştır.
- **Özellikler:** olay başına en çok 40; değerler metin, sayı ya da doğru/yanlış olabilir. Metin 512 karakterde
  kesilir.
- **Kişisel veri yok:** Özelliklere e-posta, ad, telefon numarası ya da kullanıcının yazdığı serbest metni koyma.

## Veri silme istekleri

Bir kullanıcı verisinin silinmesini isterse, onu bulmak için bir kimlik gerekir:

- **Hesapsız app'lerde:** kurulum kimliğini app'te göster, ör. Ayarlar → Destek altında:
  ```swift
  let id = await Hookhaus.installId()
  ```
- **Hesaplı app'lerde:** `Hookhaus.identify` ile verdiğin kullanıcı kimliğini kullan.

Sonra panelde **Sonuçlar → Huniler → App içi SDK → Gizlilik ve App Store gizlilik etiketi → Kullanıcı verisini sil**
bölümüne kimliği yapıştırıp onayla. O kurulumun ya da kullanıcının tüm olayları kalıcı olarak silinir. Bunu yalnız
çalışma alanı yöneticileri yapabilir.

---

## Sorun giderme

| Ne görüyorsun | Ne yapmalı |
|---|---|
| Konsolda `[Hookhaus]` satırı yok | `debug: true` verilmemiş ya da `configure` hiç çağrılmıyor. `App.init` ya da `didFinishLaunching` içine koy. |
| `API key rejected; check the key…` | Anahtar yanlış ya da yenilenmiş. **Sonuçlar → Huniler**'den yeniden kopyala ve yeniden derle. |
| `send failed (0); retry #1` | İnternet yok. Olaylar sırada kalır ve sonra gönderilir. |
| `dropped invalid event name: …` | Ad, [adlandırma kurallarına](#adlandırma-kuralları) uymuyor. |
| `$first_open` görünmüyor | Kurulum başına bir kez gelir. App'i silip yeniden çalıştır. |
| Hiçbir şey sıraya girmiyor | `requireConsent: true` verip `grantConsent()` çağırmamışsın ya da daha önce `optOut()` çağrılmış. `optIn()` çağır ya da app'i sil. |
| Olaylar geliyor ama huni yok | Otomatik huni için en az iki farklı adımdan olay gerekir. Onboarding'i bir kez geç ya da panelde huni kur. |
| Adımların sırası yanlış | Her `onboardingStep`'e `index` ver ya da paneldeki huni düzenleyiciden sırayı değiştir. |
| Deneme çalıştırmaları sayılara giriyor | Simülatör ve Debug olayları zaten sayılmaz. Cihazda Release derlemesiyle deniyorsan ayrı bir Hookhaus app'i ve anahtarı kullan. |

## Başvuru

### API

| Çağrı | Ne yapar |
|---|---|
| `Hookhaus.configure(apiKey:options:)` | SDK'yı başlatır. Açılışta bir kez çağır; yeniden çağırmak ayarları değiştirir. |
| `Hookhaus.onboardingStep(_:index:properties:)` | Bir onboarding ekranı gösterildi. |
| `Hookhaus.onboardingCompleted(properties:)` | Kullanıcı onboarding'i bitirdi. |
| `Hookhaus.paywallShown(_:properties:)` | Paywall gösterildi. |
| `Hookhaus.trialStarted(product:properties:)` | Ücretsiz deneme başladı. |
| `Hookhaus.purchased(product:price:currency:properties:)` | Ücretli satın alma tamamlandı. |
| `Hookhaus.track(_:properties:)` | Özel olay. |
| `Hookhaus.screen(_:properties:)` | Bir ekran gösterildi. |
| `Hookhaus.identify(_:)` | Kendi kullanıcı kimliğini ekler. |
| `Hookhaus.reset()` | Kullanıcı kimliğini unutur ve yeni kurulum kimliği başlatır. |
| `Hookhaus.grantConsent()` | `requireConsent` açıkken toplamayı başlatır. |
| `Hookhaus.optOut()` / `optIn()` | Toplamayı durdurur ya da yeniden başlatır. |
| `Hookhaus.flush()` | Sıradaki olayları hemen gönderir. |
| `await Hookhaus.installId()` | Bu kurulumun rastgele kimliği; veri silme istekleri için. |
| `.hookhausOnboardingStep(_:index:)`, `.hookhausPaywall(_:)`, `.hookhausScreen(_:)` | `onAppear`'da çalışan SwiftUI değiştiricileri. |

### Seçenekler

```swift
HookhausOptions(
    host: URL(string: "https://app.hookhaus.studio")!, // yalnız kendi sunucundaki panel için değiştir
    flushAt: 20,            // bu kadar olay birikince gönder
    flushInterval: 30,      // …ya da en az bu sıklıkla (saniye)
    maxQueueSize: 1000,     // bunu aşınca en eski olaylar atılır
    requireConsent: false,  // grantConsent() çağrılana kadar hiçbir şey toplama
    captureLifecycle: true, // $first_open, $app_open, $app_updated
    debug: false            // SDK'nın yaptığını konsola yaz
)
```

### Standart olaylar

| Olay | Gönderen | Özellikler |
|---|---|---|
| `$first_open` | kendiliğinden | |
| `$app_open` | kendiliğinden | |
| `$app_updated` | kendiliğinden | `previous_version` |
| `$onboarding_step` | `onboardingStep` | `step`, `index` |
| `$onboarding_complete` | `onboardingCompleted` | |
| `$paywall_view` | `paywallShown` | `paywall` |
| `$trial_start` | `trialStarted` | `product` |
| `$purchase` | `purchased` | `product`, `price`, `currency` |
| `$screen` | `screen` | `name` |
| `$identify` | `identify` | |

Her paket ayrıca app sürümünü ve build numarasını, işletim sistemi sürümünü, cihaz modelini (ör. `iPhone16,2`),
dili ve cihazda ayarlı bölgeyi taşır. IP'den konum bulunmaz.

### Gönderim ve veri

- Olaylar `x-hookhaus-key` başlığıyla `POST {host}/v1/sdk/batch` adresine gönderilir.

  | Yanıt | SDK ne yapar |
  |---|---|
  | 2xx | Paketi sıradan çıkarır. |
  | İnternet yok ya da 5xx | Olayları tutar, aralığı açarak (en çok 60 sn) yeniden dener. |
  | 400 | Paket bozuk olduğu ve yeniden deneme yine başarısız olacağı için paketi atar. |
  | 413 | Paketi ikiye bölüp yeniden dener. |
  | 401 ya da 403 | Anahtar yanlış olduğu için bir sonraki `configure`'a kadar göndermeyi durdurur. |

- Her olayın zamana göre sıralı bir kimliği vardır (UUID v7). İki kez gönderilen paket bir kez kaydedilir.
- Sunucu, cihaz saatindeki kaymayı paketin gönderilme zamanıyla düzeltir.
- Sıra `Application Support/hookhaus/queue.json` dosyasında, ayarlar `UserDefaults`'ta `hookhaus.*` anahtarlarında
  durur.
- Hookhaus ham olayları 180 gün saklar. Huni sonuçları sayılardan hesaplanır; kişi listesi gösterilmez.

### Güncelleme

Xcode'da **File → Packages → Update to Latest Package Versions**'ı seç. Sürüm notları reponun etiketlerindedir.

### Testler

```
swift test
```
