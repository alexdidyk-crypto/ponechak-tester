import AVFoundation
import Combine
import Foundation

/// Automatic loopback test of each built-in microphone.
///
/// For every mic (Bottom / Front / Back): measure a baseline level, then play a
/// tone through the speaker while recording with that mic. If the recorded level
/// jumps clearly above the baseline, the mic works. Fully automatic — the
/// operator doesn't need to speak. Publishes a rolling level buffer for the graph.
final class MicAutoTester: ObservableObject {
    @Published var samples: [Double] = []      // rolling normalized levels (0...1) for the graph
    @Published var currentMic: String?
    @Published var results: [String: Bool] = [:]
    @Published var running = false
    @Published var finished = false

    let threshold = 0.40                        // visual line on the graph

    private var queue: [String] = []
    private var recorder: AVAudioRecorder?
    private let tone = ToneTester()
    private var timer: Timer?

    private var phase = 0                        // 0 = baseline, 1 = tone
    private var tick = 0
    private var baselineSum = 0.0
    private var baselineCount = 0
    private var tonePeak = 0.0

    private let baselineTicks = 10               // 0.5 s
    private let toneTicks = 28                   // 1.4 s
    private let maxSamples = 90

    func startAll(mics: [String]) {
        guard !mics.isEmpty else { finished = true; return }
        results = [:]
        finished = false
        running = true
        samples = []
        queue = mics
        beginNext()
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        tone.stop()
        recorder?.stop(); recorder = nil
        running = false
        currentMic = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - per-mic flow
    private func beginNext() {
        guard !queue.isEmpty else { finish(); return }
        let mic = queue.removeFirst()
        currentMic = mic
        configureSession(mic: mic)
        startRecorder()
        phase = 0; tick = 0
        baselineSum = 0; baselineCount = 0; tonePeak = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.onTick()
        }
    }

    private func onTick() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)        // dBFS ~ -160...0
        let level = max(0.0, min(1.0, Double(power + 50) / 50.0))
        pushSample(level)
        tick += 1

        if phase == 0 {
            baselineSum += level; baselineCount += 1
            if tick >= baselineTicks {
                phase = 1; tick = 0
                tone.play(seconds: Double(toneTicks) * 0.05 + 0.1, frequency: 1000, configureSession: false)
            }
        } else {
            if level > tonePeak { tonePeak = level }
            if tick >= toneTicks { evaluate() }
        }
    }

    private func evaluate() {
        timer?.invalidate(); timer = nil
        tone.stop()
        recorder?.stop(); recorder = nil

        let baseline = baselineCount > 0 ? baselineSum / Double(baselineCount) : 0
        let mic = currentMic ?? ""
        let pass = (tonePeak - baseline) > 0.12 && tonePeak > 0.30
        results[mic] = pass

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.beginNext()
        }
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        currentMic = nil
        running = false
        finished = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - helpers
    private func pushSample(_ value: Double) {
        samples.append(value)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func configureSession(mic: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)
        if let input = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            if let ds = (input.dataSources ?? []).first(where: { $0.dataSourceName == mic }) {
                try? input.setPreferredDataSource(ds)
            }
            try? session.setPreferredInput(input)
        }
    }

    private func startRecorder() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ponechak-auto.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()
    }
}
