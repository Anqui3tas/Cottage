//
//  PantheonAnalytics.swift
//  The Cottage
//
//  Opt-in, anonymous usage analytics (PostHog Cloud EU).
//  Nothing is sent unless the user turns on "Share Anonymous Stats".
//  No identify calls, no person profiles, no screen or element autocapture,
//  no session replay, no surveys, no push-token capture.
//
//  Only device type, OS version, app version and country are meant to be kept;
//  everything else is stripped on the PostHog side.
//

import Foundation
import PostHog
import SwiftUI

enum PantheonAnalytics {
    /// PostHog project token for The Cottage (public `phc_` key from Project settings).
    /// Public by design. Leave empty to keep analytics fully disabled and the toggle hidden.
    static let projectToken = "phc_CvD3zUikxbwzoxQvpbHQ3o6DdzcB74xEUGWwNZqc8aQD"
    static let host = "https://eu.i.posthog.com"
    static let appName = "cottage"
    static let enabledKey = "pantheon.analytics.enabled"
    static let promptedKey = "pantheon.analytics.prompted"
    static let launchCountKey = "pantheon.analytics.launchCount"
    /// The opt-in prompt can appear from this launch on (1 = the first open).
    static let promptLaunch = 1

    /// Set by screens that are showing their own alert, so the prompt waits its turn.
    @MainActor static var isSuppressed = false

    /// True when a project token is configured.
    static var isAvailable: Bool { !projectToken.isEmpty }

    /// The user's opt-in choice. Defaults to off.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Call once at launch. Does nothing unless the user has opted in.
    static func start() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: launchCountKey) + 1, forKey: launchCountKey)
        guard isAvailable, isEnabled else { return }
        setUp()
    }

    /// Stores the user's choice and starts or stops collection immediately.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            start()
            // One event at the moment of opting in, so it shows up right away.
            capture("analytics_opt_in")
        } else {
            // Drop the anonymous install ID, stop sending, and shut the SDK down.
            PostHogSDK.shared.reset()
            PostHogSDK.shared.optOut()
            PostHogSDK.shared.close()
        }
    }

    /// Records a named usage event. Keep properties free of anything identifying.
    static func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isAvailable, isEnabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    private static func setUp() {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        #if os(iOS) || os(macOS)
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        #endif
        #if os(iOS)
        config.sessionReplay = false
        if #available(iOS 15.0, *) {
            config.surveys = false
        }
        #endif
        PostHogSDK.shared.setup(config)
        if PostHogSDK.shared.isOptOut() {
            PostHogSDK.shared.optIn()
        }
        PostHogSDK.shared.register(["app": appName])
    }
}

// MARK: - One-time opt-in prompt

extension PantheonAnalytics {
    /// True until the user has answered the prompt once (or already opted in from Settings).
    static var shouldPrompt: Bool {
        let defaults = UserDefaults.standard
        return isAvailable
            && !isEnabled
            && !defaults.bool(forKey: promptedKey)
            && defaults.integer(forKey: launchCountKey) >= promptLaunch
    }

    /// Records the answer so the prompt is never shown again.
    static func answerPrompt(share: Bool) {
        UserDefaults.standard.set(true, forKey: promptedKey)
        setEnabled(share)
    }

    static var systemName: String {
        #if os(macOS)
        "macOS"
        #elseif os(tvOS)
        "tvOS"
        #else
        "iOS"
        #endif
    }

    static var promptTitle: String {
        String(localized: "Help shape The Cottage", comment: "Title of the one-time anonymous stats prompt")
    }

    static var settingsPath: String {
        "About The Cottage"
    }

    static var promptMessage: String {
        String(
            localized: "The Cottage is free, so we can't see which devices or \(systemName) versions people use it on. Sharing anonymous stats (device type, \(systemName) version, app version, and country for localization) helps us decide what to support.",
            comment: "Body of the one-time anonymous stats prompt; the placeholder is iOS, tvOS, or macOS"
        )
    }

    static var promptPrivacy: String {
        String(
            localized: "You can change this anytime in \(settingsPath).",
            comment: "Note in the one-time anonymous stats prompt; the placeholder is the settings location"
        )
    }

    static var shareButtonTitle: String {
        String(localized: "Share Anonymous Stats", comment: "Button that opts in to anonymous stats")
    }

    static var declineButtonTitle: String {
        String(localized: "No Thanks", comment: "Button that declines anonymous stats")
    }
}

/// Shows the opt-in prompt once. It waits while `isBlocked` is true (for example while release notes
/// are showing), while `isBlockedNow` reports another presentation, and while a screen has set
/// `PantheonAnalytics.isSuppressed`. It is only answered by its buttons; a system-forced dismissal re-shows it.
struct PantheonAnalyticsPromptModifier: ViewModifier {
    var isBlocked: Bool
    var delay: Double
    var isBlockedNow: @MainActor () -> Bool
    @State private var isPresented = false
    /// Bumped when the system closes the prompt without an answer, so it comes back.
    @State private var attempt = 0

    func body(content: Content) -> some View {
        content
            .task(id: "\(isBlocked)-\(attempt)") {
                guard !isBlocked else { return }
                while PantheonAnalytics.shouldPrompt {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    let busy = await MainActor.run { PantheonAnalytics.isSuppressed || isBlockedNow() }
                    if busy { continue }
                    isPresented = true
                    return
                }
            }
            // Only a button tap answers. If something else closes the prompt (a system password-save
            // sheet, say), it is shown again instead of counting as "No Thanks".
            .onChange(of: isPresented) { _, presented in
                if !presented, PantheonAnalytics.shouldPrompt { attempt += 1 }
            }
            #if os(tvOS)
            .alert(PantheonAnalytics.promptTitle, isPresented: $isPresented) {
                Button(PantheonAnalytics.shareButtonTitle) { PantheonAnalytics.answerPrompt(share: true) }
                Button(PantheonAnalytics.declineButtonTitle, role: .cancel) { PantheonAnalytics.answerPrompt(share: false) }
            } message: {
                Text(PantheonAnalytics.promptMessage + "\n\n" + PantheonAnalytics.promptPrivacy)
            }
            #else
            .sheet(isPresented: $isPresented) {
                PantheonAnalyticsPromptSheet { share in
                    PantheonAnalytics.answerPrompt(share: share)
                    isPresented = false
                }
            }
            #endif
    }
}

#if !os(tvOS)
private struct PantheonAnalyticsPromptSheet: View {
    let answer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(PantheonAnalytics.promptTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(PantheonAnalytics.promptMessage)
                .multilineTextAlignment(.center)
            Text(PantheonAnalytics.promptPrivacy)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { answer(true) } label: {
                    Text(PantheonAnalytics.shareButtonTitle).frame(maxWidth: .infinity)
                }
                Button { answer(false) } label: {
                    Text(PantheonAnalytics.declineButtonTitle).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        #if os(macOS)
        .frame(width: 420)
        #else
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
        #endif
    }
}
#endif

extension View {
    /// Asks once whether to share anonymous stats.
    func pantheonAnalyticsPrompt(
        isBlocked: Bool = false,
        delay: Double = 1.5,
        isBlockedNow: @escaping @MainActor () -> Bool = { false }
    ) -> some View {
        modifier(PantheonAnalyticsPromptModifier(isBlocked: isBlocked, delay: delay, isBlockedNow: isBlockedNow))
    }
}

/// Opt-in toggle bound to `PantheonAnalytics`. Hidden when no project token is configured.
struct PantheonAnalyticsToggle: View {
    @AppStorage(PantheonAnalytics.enabledKey) private var isEnabled = false

    var body: some View {
        if PantheonAnalytics.isAvailable {
            Toggle(
                String(localized: "Share Anonymous Stats", comment: "Opt-in toggle for anonymous stats"),
                isOn: Binding(
                    get: { isEnabled },
                    set: { PantheonAnalytics.setEnabled($0) }
                )
            )
        }
    }
}

/// Settings section with the opt-in toggle and a plain explanation.
struct PantheonAnalyticsSection: View {
    var body: some View {
        if PantheonAnalytics.isAvailable {
            Section {
                PantheonAnalyticsToggle()
            } header: {
                Text(String(localized: "Anonymous Stats", comment: "Settings section header for anonymous stats"))
            } footer: {
                Text(PantheonAnalytics.explanation)
            }
        }
    }
}

extension PantheonAnalytics {
    static var explanation: String {
        String(
            localized: "Off by default. When on, The Cottage shares your device type, \(systemName) version, app version, and country (for localization) anonymously.",
            comment: "Explanation shown under the anonymous stats toggle"
        )
    }
}
