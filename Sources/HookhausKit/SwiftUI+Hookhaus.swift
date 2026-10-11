#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Track a screen view when this view appears.
    func hookhausScreen(_ name: String, properties: [String: HookhausValue] = [:]) -> some View {
        onAppear { Hookhaus.screen(name, properties: properties) }
    }

    /// Track an onboarding step when this view appears.
    func hookhausOnboardingStep(_ step: String, index: Int? = nil, properties: [String: HookhausValue] = [:]) -> some View {
        onAppear { Hookhaus.onboardingStep(step, index: index, properties: properties) }
    }

    /// Track a paywall view when this view appears.
    func hookhausPaywall(_ id: String? = nil, properties: [String: HookhausValue] = [:]) -> some View {
        onAppear { Hookhaus.paywallShown(id, properties: properties) }
    }
}
#endif
