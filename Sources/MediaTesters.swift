import AVFoundation

enum AudioRoute { case speaker, earpiece }

/// Flashlight / torch (LED).
enum TorchTester {
    static var available: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {}
    }
}

/// Plays a tone through a chosen speaker: bottom loudspeaker or top earpiece.
final class ToneTester {
    private var engine: AVAudioEngine?

    func stop() {
        engine?.stop()
        engine = nil
    }

    func play(seconds: Double = 2.0, frequency: Double = 880,
              route: AudioRoute = .speaker, configureSession: Bool = true) {
        stop()
        if configureSession {
            let session = AVAudioSession.sharedInstance()
            if route == .earpiece {
                // Receiver (top earpiece): play&record without speaker override.
                try? session.setCategory(.playAndRecord, options: [])
                try? session.setActive(true)
                try? session.overrideOutputAudioPort(.none)
            } else {
                // Bottom loudspeaker.
                try? session.setCategory(.playback, options: [])
                try? session.setActive(true)
            }
        }

        let sampleRate = 44100.0
        var theta = 0.0
        let thetaIncrement = 2.0 * Double.pi * frequency / sampleRate

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = Float(sin(theta) * 0.5)
                theta += thetaIncrement
                if theta > 2.0 * Double.pi { theta -= 2.0 * Double.pi }
                for buffer in buffers {
                    let ptr = UnsafeMutableBufferPointer<Float>(buffer)
                    ptr[frame] = value
                }
            }
            return noErr
        }

        let engine = AVAudioEngine()
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return }
        self.engine = engine

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.engine?.stop()
            self?.engine = nil
        }
    }
}
