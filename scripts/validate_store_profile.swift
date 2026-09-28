import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    fputs("invalid macOS provisioning profile: \(message)\n", stderr)
    exit(1)
}

guard CommandLine.arguments.count == 3,
      let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let profile = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let teams = profile["TeamIdentifier"] as? [String], teams.count == 1,
      let platform = profile["Platform"] as? [String], platform == ["OSX"],
      let expiration = profile["ExpirationDate"] as? Date, expiration > Date(),
      let entitlements = profile["Entitlements"] as? [String: Any],
      let appID = entitlements["com.apple.application-identifier"] as? String ?? entitlements["application-identifier"] as? String,
      appID == "\(teams[0]).app.beseda.Beseda",
      entitlements["application-identifier"] == nil || (entitlements["application-identifier"] as? String) == appID,
      let certificates = profile["DeveloperCertificates"] as? [Data],
      certificates.contains(where: { Insecure.SHA1.hash(data: $0).map { String(format: "%02X", $0) }.joined() == CommandLine.arguments[2].uppercased() })
else { fail("team, explicit app ID, macOS platform, expiry or signing certificate mismatch") }
