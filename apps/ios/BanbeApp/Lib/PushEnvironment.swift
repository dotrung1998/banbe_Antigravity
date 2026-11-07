import Foundation

/// Which APNs gateway a device token belongs to (migration 194's `device_push_tokens.environment`): a token minted
/// by a development-signed build only works against the sandbox gateway, an App Store / TestFlight one only against
/// production, so the server has to know which one to send through.
enum PushEnvironment {
    /// "sandbox" | "production" for this running build.
    static var current: String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        return environment(fromProvisionData: url.flatMap { try? Data(contentsOf: $0) })
        #endif
    }

    /// Pure: the provisioning profile is a CMS-signed blob with its plist embedded in clear text between "<?xml"
    /// and "</plist>". `Entitlements["aps-environment"] == "development"` → "sandbox"; any other value, no
    /// profile at all (an App Store install has none) or an unreadable one → "production".
    static func environment(fromProvisionData data: Data?) -> String {
        guard let data,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return "production" }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let aps = entitlements["aps-environment"] as? String
        else { return "production" }
        return aps == "development" ? "sandbox" : "production"
    }
}
