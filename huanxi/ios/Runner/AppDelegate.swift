import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerScreenshotSecurityChannel(engineBridge)
  }

  private func registerScreenshotSecurityChannel(_ engineBridge: FlutterImplicitEngineBridge) {
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenshotSecurityPlugin")
    let channel = FlutterMethodChannel(
      name: "huanxi/screenshot_security",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "apply":
        let args = call.arguments as? [String: Any]
        _ = args?["iosPreventScreenshotEnabled"] as? Bool
        // iOS screenshot prevention placeholder.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
