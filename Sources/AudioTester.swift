import AVFoundation
import Combine

/// Tests each physical microphone individually via AVAudioSession data sources
/// (Bottom / Front / Back) — something a Safari web page cannot do.
final class MicTester: ObservableObject {
    @Published var level: Double = 0          // 0...1 (live meter)
    @Published var peak: Double = 0           // highest level seen this run
    @Published var recordingName: String?     // data source currently recording

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Names of the built-in microphone data sources (e.g. "Bottom", "Front", "Back").
    static func builtInMicNames() -> [String] {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return []
        }
        return (mic.dataSources ?? []).map { $0.dataSourceName }
    }

    func start(micName: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                if let ds = (mic.dataSources ?? []).first(where: { $0.dataSourceName == micName }) {
                    try mic.setPreferredDataSource(ds)
                }
                try session.setPreferredInput(mic)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ponechak-mic.caf")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            recordingName = micName
            peak = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let rec = self.recorder else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)        // dBFS, ~ -160...0
                let norm = max(0.0, min(1.0, Double(power + 50) / 50.0))  // -50dB..0dB -> 0..1
                self.level = norm
                if norm > self.peak { self.peak = norm }
            }
        } catch {
            recordingName = nil
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        recordingName = nil
        level = 0
    }
}
