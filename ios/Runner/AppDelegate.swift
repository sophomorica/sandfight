import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var iosChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.narrowroad.sandfight/ios",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "machine":
        result(Self.machine())
      case "play":
        Self.play(call.arguments)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    iosChannel = channel
  }

  private static func machine() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafePointer(to: &system.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(validatingCString: $0) ?? "unknown"
      }
    }
  }

  private static func play(_ arguments: Any?) {
    let args = arguments as? [String: Any]
    let kind = args?["kind"] as? String ?? ""
    let intensity = (args?["intensity"] as? Double) ?? 0
    let pattern = args?["pattern"] as? [Double] ?? [intensity]
    switch kind {
    case "lightTap":
      pulse(.light, intensity, delay: 0)
    case "sharpBuzz":
      pulse(.rigid, intensity, delay: 0)
    case "rumble":
      pulse(.heavy, intensity, delay: 0)
    case "descend":
      for (index, step) in pattern.enumerated() {
        pulse(.medium, step, delay: Double(index) * 0.12)
      }
    default:
      pulse(.light, intensity, delay: 0)
    }
  }

  private static func pulse(
    _ style: UIImpactFeedbackGenerator.FeedbackStyle,
    _ intensity: Double,
    delay: Double
  ) {
    let clamped = CGFloat(max(0, min(1, intensity)))
    if clamped <= 0 { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      let generator = UIImpactFeedbackGenerator(style: style)
      generator.prepare()
      generator.impactOccurred(intensity: clamped)
    }
  }
}
