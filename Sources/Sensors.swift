import Combine
import CoreMotion
import UIKit

/// Accelerometer / gyroscope / magnetometer live readouts.
final class SensorTester: ObservableObject {
    private let motion = CMMotionManager()

    @Published var accel = "—"
    @Published var gyro = "—"
    @Published var magnet = "—"
    @Published var moved = false

    func start() {
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.1
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let d = data else { return }
                self?.accel = String(format: "x %.2f  y %.2f  z %.2f",
                                     d.acceleration.x, d.acceleration.y, d.acceleration.z)
                if abs(d.acceleration.x) + abs(d.acceleration.y) > 0.35 { self?.moved = true }
            }
        } else { accel = "N/A" }

        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = 0.1
            motion.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let d = data else { return }
                self?.gyro = String(format: "x %.2f  y %.2f  z %.2f",
                                    d.rotationRate.x, d.rotationRate.y, d.rotationRate.z)
            }
        } else { gyro = "N/A" }

        if motion.isMagnetometerAvailable {
            motion.magnetometerUpdateInterval = 0.2
            motion.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let d = data else { return }
                self?.magnet = String(format: "x %.0f  y %.0f  z %.0f",
                                      d.magneticField.x, d.magneticField.y, d.magneticField.z)
            }
        } else { magnet = "N/A" }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopMagnetometerUpdates()
    }
}

/// Proximity sensor + battery state.
final class DeviceInfoTester: ObservableObject {
    @Published var proximity = "—"
    @Published var proximityTriggered = false
    @Published var battery = "—"

    private var observers: [NSObjectProtocol] = []

    func start() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        updateBattery()
        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBattery()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBattery()
        })

        device.isProximityMonitoringEnabled = true
        proximity = device.isProximityMonitoringEnabled ? "cover the top of the screen" : "N/A"
        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let near = UIDevice.current.proximityState
            self?.proximity = near ? "triggered ✓" : "clear"
            if near { self?.proximityTriggered = true }
        })
    }

    private func updateBattery() {
        let device = UIDevice.current
        let level = device.batteryLevel >= 0 ? "\(Int(device.batteryLevel * 100))%" : "—"
        let state: String
        switch device.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "on battery"
        default: state = "unknown"
        }
        battery = "\(level) · \(state)"
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        UIDevice.current.isProximityMonitoringEnabled = false
    }
}
