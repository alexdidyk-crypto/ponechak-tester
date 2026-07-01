import AVFoundation
import Combine

/// Record from one specific microphone, then play the recording back through the
/// speaker so the operator can judge it by ear. One instance per mic.
final class MicRecorder: ObservableObject {
    enum State { case idle, recording, recorded, playing }

    @Published var state: State = .idle
    @Published var level: Double = 0

    private let micName: String
    private let url: URL
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(micName: String) {
        self.micName = micName
        let safe = micName.replacingOccurrences(of: " ", with: "_")
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ponechak-rec-\(safe).caf")
    }

    func record(seconds: Double = 3.0) {
        stopAll()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)
        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            if let ds = (mic.dataSources ?? []).first(where: { $0.dataSourceName == micName }) {
                try? mic.setPreferredDataSource(ds)
            }
            try? session.setPreferredInput(mic)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record(forDuration: seconds)
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let rec = self.recorder else { return }
            rec.updateMeters()
            self.level = max(0.0, min(1.0, Double(rec.averagePower(forChannel: 0) + 50) / 50))
            if !rec.isRecording {
                self.timer?.invalidate(); self.timer = nil
                self.level = 0
                self.state = .recorded
            }
        }
    }

    func play() {
        guard state == .recorded || state == .idle else { return }
        stopPlayer()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [])
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        guard let player = player else { return }
        player.play()
        state = .playing
        let duration = player.duration > 0 ? player.duration : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
            if self?.state == .playing { self?.state = .recorded }
        }
    }

    var hasRecording: Bool { FileManager.default.fileExists(atPath: url.path) }

    private func stopPlayer() {
        player?.stop(); player = nil
    }

    func stopAll() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        stopPlayer()
        level = 0
    }
}
