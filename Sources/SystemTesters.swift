import AVFoundation
import CoreHaptics
import LocalAuthentication
import UIKit

/// Face ID / Touch ID checks.
enum BiometryTester {
    static func describe() -> String {
        let ctx = LAContext()
        var error: NSError?
        let canEval = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID:
            return canEval ? "Face ID available" : "Face ID present, not enrolled"
        case .touchID:
            return canEval ? "Touch ID available" : "Touch ID present, not enrolled"
        case .opticID:
            return canEval ? "Optic ID available" : "Optic ID unavailable"
        default:
            return "No biometrics detected"
        }
    }

    static func evaluate(_ completion: @escaping (Bool, String) -> Void) {
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Biometry test") { ok, error in
            DispatchQueue.main.async {
                completion(ok, ok ? "Recognized ✓" : (error?.localizedDescription ?? "Not recognized"))
            }
        }
    }
}

/// Vibration / Taptic Engine.
enum VibrationTester {
    static func buzz() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

/// Detects volume button presses by observing the system output volume.
final class VolumeButtonTester: ObservableObject {
    @Published var lastChange: String = "—"
    @Published var pressed: Bool = false
    private var observation: NSKeyValueObservation?
    private let session = AVAudioSession.sharedInstance()

    func start() {
        try? session.setActive(true)
        observation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            guard let self = self, let new = change.newValue, let old = change.oldValue else { return }
            DispatchQueue.main.async {
                self.lastChange = new > old ? "Volume + pressed" : "Volume − pressed"
                self.pressed = true
            }
        }
    }

    func stop() {
        observation?.invalidate(); observation = nil
    }
}
