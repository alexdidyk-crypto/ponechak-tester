import AVFoundation

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

/// Plays a sustained tone through the speaker to verify it works.
final class ToneTester {
    private var engine: AVAudioEngine?

    func stop() {
        engine?.stop()
        engine = nil
    }

    /// - Parameter configureSession: when false, keeps the current audio session
    ///   (used during the mic loopback test where recording is already active).
    /// - Parameter earpiece: route to the top receiver (earpiece) instead of the
    ///   bottom loudspeaker, so each speaker can be tested separately.
    func play(seconds: Double = 2.0, frequency: Double = 880,
              configureSession: Bool = true, earpiece: Bool = false) {
        stop()  // stop any previous tone first (sweep changes frequency)
        if configureSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, options: earpiece ? [] : [.defaultToSpeaker])
            try? session.setActive(true)
            try? session.overrideOutputAudioPort(earpiece ? .none : .speaker)
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
