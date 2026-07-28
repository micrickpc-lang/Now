import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var snapshotShield: UIVisualEffectView?
  private var channels: [FlutterMethodChannel] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(obscureSnapshot),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(revealSnapshot),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SeychasPrivacy")
    let privacyChannel = FlutterMethodChannel(
      name: "ru.seychas/privacy",
      binaryMessenger: registrar.messenger()
    )
    privacyChannel.setMethodCallHandler { call, result in
      if call.method == "secureScreen" {
        // iOS does not expose an equivalent of Android FLAG_SECURE. Sensitive
        // screens are protected from app-switcher snapshots by the lifecycle shield.
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let storageChannel = FlutterMethodChannel(
      name: "ru.seychas/storage",
      binaryMessenger: registrar.messenger()
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackups" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
        return
      }
      do {
        var url = URL(fileURLWithPath: path)
        try url.setResourceValue(true, forKey: .isExcludedFromBackupKey)
        result(nil)
      } catch {
        result(FlutterError(code: "backup_exclusion_failed", message: nil, details: nil))
      }
    }
    channels = [privacyChannel, storageChannel]
  }

  @objc private func obscureSnapshot() {
    guard snapshotShield == nil, let window = activeWindow else { return }
    let shield = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    shield.frame = window.bounds
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(shield)
    snapshotShield = shield
  }

  @objc private func revealSnapshot() {
    snapshotShield?.removeFromSuperview()
    snapshotShield = nil
  }

  private var activeWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
      .first
  }
}
