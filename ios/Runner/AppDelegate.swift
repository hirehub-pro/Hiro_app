import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
      !mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      assertionFailure("Missing GMSApiKey in Info.plist.")
      NSLog("Google Maps setup failed: missing GMSApiKey in Info.plist.")
      GeneratedPluginRegistrant.register(with: self)
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let didProvideKey = GMSServices.provideAPIKey(mapsApiKey)
    let prefix = String(mapsApiKey.prefix(8))
    NSLog(
      "Google Maps setup bundle=%@ keyPrefix=%@ didProvideKey=%@",
      Bundle.main.bundleIdentifier ?? "unknown",
      prefix,
      didProvideKey ? "true" : "false"
    )

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
