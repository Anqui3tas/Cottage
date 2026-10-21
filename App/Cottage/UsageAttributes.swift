//
//  UsageAttributes.swift
//  Cottage
//
//  Anonymous usage attributes for RevenueCat (self-test build). The Cottage has no sign-in, so RevenueCat
//  runs with an anonymous customer and does not handle purchases. The app never reads anything back
//  from RevenueCat; it only sets these attributes.
//

import Foundation
import RevenueCat
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum UsageAttributes {
    /// RevenueCat public SDK key for The Cottage (safe to ship; it can only send data).
    static let apiKey = "appl_mUZeVddMFlpEjNZgGQaenBonpAZ"
    /// Flip to false to stop all collection without removing the code.
    static let isEnabled = true

    private static var isConfigured = false

    /// Call once at launch.
    static func start() {
        guard isEnabled, !isConfigured else { return }
        Purchases.logLevel = .error
        let configuration = Configuration
            .builder(withAPIKey: apiKey)
            .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
            .with(entitlementVerificationMode: .informational)
            .build()
        Purchases.configure(with: configuration)
        isConfigured = true
        refresh()
        // Creates the anonymous customer right away so the attributes show up in the dashboard.
        Task { _ = try? await Purchases.shared.customerInfo() }
    }

    /// Re-sends the attributes (cheap; RevenueCat only uploads what changed). Call when the app becomes active.
    static func refresh() {
        guard isEnabled, isConfigured else { return }
        Purchases.shared.attribution.setAttributes(currentAttributes())
    }

    static func currentAttributes() -> [String: String] {
        let locale = Locale.current
        let machine = machineIdentifier
        return [
            "country": locale.region?.identifier ?? "unknown",
            "language": Locale.preferredLanguages.first ?? locale.identifier,
            "device_model": machine,
            "device_name": DeviceModelNames.friendlyName(for: machine),
            "os_version": osVersion,
            "app_version": appVersion,
        ]
    }

    // MARK: - Values

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return "iOS \(text)"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static var machineIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}
