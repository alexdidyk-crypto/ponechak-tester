import AVFoundation
import Combine
import Foundation

/// Records a few seconds from ONE selected microphone, then plays it back so the
/// technician can hear that mic individually.
final class MicRecordPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum Phase { case idle, recording, playing }

    @Published var phase: Phase = .idle
    @Published var activeMic: String?
    @Published var level: Double = 0

    let recordSeconds = 3.0
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("ponechak-recplay.m4a")

    func recordThenPlay(micName: String) {
        stopAll()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)
        if let input = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            if let ds = (input.dataSources ?? []).first(where: { $0.dataSourceName == micName }) {
                try? input.setPreferredDataSource(ds)
            }
            try? session.setPreferredInput(input)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record(forDuration: recordSeconds)

        activeMic = micName
        phase = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let rec = self.recorder else { return }
            rec.updateMeters()
            let power = rec.averagePower(forChannel: 0)
            self.level = max(0.0, min(1.0, Double(power + 50) / 50.0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + recordSeconds + 0.2) { [weak self] in
            self?.playback()
        }
    }

    private func playback() {
        timer?.invalidate(); timer = nil
        level = 0
        recorder?.stop(); recorder = nil
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.volume = 1.0
            player?.play()
            phase = .playing
        } catch {
            phase = .idle; activeMic = nil
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        phase = .idle
        activeMic = nil
    }

    func stopAll() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        player?.stop(); player = nil
        phase = .idle
        activeMic = nil
        level = 0
    }
}
