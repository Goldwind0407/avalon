import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let soundEffects = AvalonSoundEffects()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AvalonSoundEffects") {
      let channel = FlutterMethodChannel(name: "avalon/sound_effects", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let effects = self?.soundEffects else { result(nil); return }
        if call.method == "stop" { effects.stop(); result(nil); return }
        guard call.method == "play", let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              name.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil else {
          result(FlutterMethodNotImplemented); return
        }
        let key = registrar.lookupKey(forAsset: "assets/audio/\(name).wav")
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
          result(FlutterError(code: "missing_sound", message: name, details: nil)); return
        }
        do {
          try effects.play(path, volume: (args["volume"] as? NSNumber)?.floatValue ?? 0.6,
                           important: args["important"] as? Bool ?? false)
          result(nil)
        } catch { result(FlutterError(code: "sound_error", message: error.localizedDescription, details: nil)) }
      }
    }
  }
}

/// Shares the existing session with WebRTC. Never changes category, route,
/// microphone permissions or activation state when starting/stopping an effect.
private class AvalonSoundEffects: NSObject, AVAudioPlayerDelegate {
  private var playing: [AVAudioPlayer] = []
  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(stop),
      name: UIApplication.willResignActiveNotification, object: nil)
  }
  func play(_ path: String, volume: Float, important: Bool) throws {
    if important { stop() }
    while playing.count >= 3 { playing.removeFirst().stop() }
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player.volume = min(1, max(0, volume))
    player.numberOfLoops = 0
    player.delegate = self
    playing.append(player)
    if !player.play() { playing.removeAll { $0 === player } }
  }
  @objc func stop() {
    for player in playing { player.stop() }
    playing.removeAll()
  }
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    playing.removeAll { $0 === player }
  }
  deinit { NotificationCenter.default.removeObserver(self) }
}
