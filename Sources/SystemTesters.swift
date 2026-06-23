import AVFoundation
import CoreHaptics
import LocalAuthentication
import UIKit

/// Face ID / Touch ID checks — also impossible from a web page.
enum BiometryTester {
    static func describe() -> String {
        let ctx = LAContext()
        var error: NSError?
        let canEval = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID:
            return canEval ? "Face ID доступен" : "Face ID есть, но не настроен/недоступен"
        case .touchID:
            return canEval ? "Touch ID доступен" : "Touch ID есть, но недоступен"
        case .opticID:
            return canEval ? "Optic ID доступен" : "Optic ID недоступен"
        default:
            return "Биометрия не обнаружена"
        }
    }

    static func evaluate(_ completion: @escaping (Bool, String) -> Void) {
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Проверка биометрии") { ok, error in
            DispatchQueue.main.async {
                completion(ok, ok ? "Распознано ✓" : (error?.localizedDescription ?? "Не распознано"))
            }
        }
    }
}

/// Vibration / Taptic Engine — web has no access to this on iOS.
enum VibrationTester {
    static func buzz() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        // legacy vibration as a fallback (works on all devices)
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
                self.lastChange = new > old ? "Громкость + нажата" : "Громкость − нажата"
                self.pressed = true
            }
        }
    }

    func stop() {
        observation?.invalidate(); observation = nil
    }
}
