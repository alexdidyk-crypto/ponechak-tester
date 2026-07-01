import AVFoundation
import Combine
import Foundation

/// One band of the measured frequency response (level in dBFS).
struct BandLevel: Identifiable {
    let id = UUID()
    let freq: Int
    let db: Double          // dBFS (~ -60...0)
    var height: Double { max(0.02, min(1.0, (db + 60) / 60)) }  // 0...1 for bar display
}

/// Quality summary for one microphone.
struct MicQuality {
    let noiseFloor: Double  // dBFS
    let snr: Double         // dB
    let rolloff: Double     // dB, high band vs 1 kHz (negative = muffled)
    let bands: [BandLevel]
    let verdict: String
    let pass: Bool
}

/// Automatic per-microphone QUALITY test via a speaker→mic loopback sweep.
///
/// For each built-in mic: measure the noise floor, then play tones at several
/// frequencies through the speaker while recording. From the captured levels we
/// derive SNR, a frequency-response curve and a high-frequency rolloff
/// (muffled/clogged detection), then grade the mic and compare the three.
final class MicAutoTester: ObservableObject {
    @Published var samples: [Double] = []        // rolling 0...1 levels for the live graph
    @Published var currentMic: String?
    @Published var currentFreq: Int = 0
    @Published var quality: [String: MicQuality] = [:]
    @Published var results: [String: Bool] = [:] // pass/fail for the dashboard tiles
    @Published var running = false
    @Published var finished = false

    let threshold = 0.40                         // visual line on the live graph

    // Mid/high focus: phone speakers roll off bass, so we compare where it's meaningful.
    private let freqs = [500, 1000, 2000, 4000, 6000, 8000]
    private let refIndex = 1                      // 1 kHz reference band
    private let baselineTicks = 8                 // 0.4 s
    private let bandTicks = 10                    // 0.5 s per band
    private let bandWarmup = 4                    // skip ramp-up ticks when averaging
    private let maxSamples = 90

    private var queue: [String] = []
    private var recorder: AVAudioRecorder?
    private let tone = ToneTester()
    private var timer: Timer?

    private var step = 0                          // 0 = baseline, 1...n = band index
    private var tick = 0
    private var measSum = 0.0
    private var measCount = 0
    private var noiseFloor = -160.0
    private var bandDB: [Double] = []

    func startAll(mics: [String]) {
        guard !mics.isEmpty else { finished = true; return }
        quality = [:]; results = [:]; samples = []
        finished = false; running = true
        queue = mics
        beginNext()
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        tone.stop()
        recorder?.stop(); recorder = nil
        running = false; currentMic = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - per-mic
    private func beginNext() {
        guard !queue.isEmpty else { finish(); return }
        let mic = queue.removeFirst()
        currentMic = mic
        configureSession(mic: mic)
        startRecorder()
        bandDB = []
        startStep(0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.onTick()
        }
    }

    private func startStep(_ s: Int) {
        step = s; tick = 0; measSum = 0; measCount = 0
        if s == 0 {
            currentFreq = 0
            tone.stop()
        } else {
            let freq = freqs[s - 1]
            currentFreq = freq
            tone.play(seconds: Double(bandTicks) * 0.05 + 0.15, frequency: Double(freq), configureSession: false)
        }
    }

    private func onTick() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        let powerDB = Double(recorder.averagePower(forChannel: 0))   // dBFS
        pushSample(max(0.0, min(1.0, (powerDB + 50) / 50)))
        tick += 1

        if step == 0 {
            measSum += powerDB; measCount += 1
            if tick >= baselineTicks {
                noiseFloor = measCount > 0 ? measSum / Double(measCount) : -160
                startStep(1)
            }
        } else {
            if tick > bandWarmup { measSum += powerDB; measCount += 1 }
            if tick >= bandTicks {
                bandDB.append(measCount > 0 ? measSum / Double(measCount) : -160)
                if step < freqs.count { startStep(step + 1) } else { evaluate() }
            }
        }
    }

    private func evaluate() {
        timer?.invalidate(); timer = nil
        tone.stop(); recorder?.stop(); recorder = nil

        let mic = currentMic ?? ""
        let signal = bandDB.max() ?? -160
        let snr = signal - noiseFloor
        let ref = refIndex < bandDB.count ? bandDB[refIndex] : signal
        let high = bandDB.last ?? signal
        let rolloff = high - ref

        let verdict: String
        let pass: Bool
        if snr < 8 {
            verdict = "🔴 No signal"; pass = false
        } else if noiseFloor > -42 {
            verdict = "🟡 Noisy"; pass = false
        } else if rolloff < -12 {
            verdict = "🟡 Muffled (clogged?)"; pass = false
        } else if snr < 18 {
            verdict = "🟡 Weak"; pass = false
        } else {
            verdict = "🟢 Good"; pass = true
        }

        let bands = zip(freqs, bandDB).map { BandLevel(freq: $0, db: $1) }
        quality[mic] = MicQuality(noiseFloor: noiseFloor, snr: snr, rolloff: rolloff,
                                  bands: bands, verdict: verdict, pass: pass)
        results[mic] = pass

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.beginNext() }
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        currentMic = nil; currentFreq = 0
        running = false; finished = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - helpers
    private func pushSample(_ value: Double) {
        samples.append(value)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
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
