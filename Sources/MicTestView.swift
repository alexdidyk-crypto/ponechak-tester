import SwiftUI

/// Live amplitude line drawn with Path (no Swift Charts, works on iOS 15).
struct WaveformGraph: View {
    let samples: [Double]
    let threshold: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { p in
                    let y = h * (1 - CGFloat(threshold))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                Path { p in
                    guard samples.count > 1 else { return }
                    let step = w / CGFloat(max(1, samples.count - 1))
                    for (i, s) in samples.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h * (1 - CGFloat(min(1, max(0, s))))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke((samples.last ?? 0) > threshold ? Color.green : Color.blue, lineWidth: 2)
            }
        }
    }
}

/// Frequency-response bars (mini EQ) for one mic.
struct ResponseBars: View {
    let bands: [BandLevel]
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bands) { band in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor(band))
                                .frame(height: max(3, geo.size.height * CGFloat(band.height)))
                        }
                    }
                    Text(label(band.freq)).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
        }
        .frame(height: 70)
    }

    private func barColor(_ b: BandLevel) -> Color {
        b.height > 0.55 ? .green : (b.height > 0.3 ? .yellow : .red)
    }
    private func label(_ f: Int) -> String { f >= 1000 ? "\(f/1000)k" : "\(f)" }
}

struct MicTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tester = MicAutoTester()

    let mics: [String]
    let label: (String) -> String
    @Binding var verdict: [String: Bool]

    var body: some View {
        VStack(spacing: 16) {
            Text("🎙 Качество микрофонов").font(.title2).bold()
            Text(headline).foregroundColor(.secondary).font(.subheadline)

            if !tester.finished {
                WaveformGraph(samples: tester.samples, threshold: tester.threshold)
                    .frame(height: 150)
                    .padding(8).background(Color.gray.opacity(0.10)).cornerRadius(14)
                HStack(spacing: 10) { ForEach(mics, id: \.self) { dot($0) } }
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(mics, id: \.self) { mic in
                        if let q = tester.quality[mic] { resultCard(mic, q) }
                    }
                }
            }

            Button(tester.finished ? "Закрыть" : "Отмена") { tester.cancel(); dismiss() }
                .frame(maxWidth: .infinity).padding()
                .background(tester.finished ? Color.green : Color.accentColor)
                .foregroundColor(.white).cornerRadius(12)
        }
        .padding()
        .onAppear { tester.startAll(mics: mics) }
        .onDisappear { tester.cancel() }
        .onChange(of: tester.results) { newResults in
            verdict.merge(newResults) { _, new in new }
        }
    }

    private var headline: String {
        if let cur = tester.currentMic {
            let f = tester.currentFreq
            return f > 0 ? "\(label(cur)) · \(f) Гц" : "\(label(cur)) · фон"
        }
        if tester.finished {
            let ok = tester.results.values.filter { $0 }.count
            return "Готово · хороших: \(ok) из \(mics.count)"
        }
        return "Запуск…"
    }

    private func resultCard(_ mic: String, _ q: MicQuality) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label(mic)).font(.headline)
                Spacer()
                Text(q.verdict).font(.subheadline)
            }
            ResponseBars(bands: q.bands)
            HStack {
                Text(String(format: "SNR %.0f дБ", q.snr))
                Spacer()
                Text(String(format: "верхи %@%.0f дБ", q.rolloff >= 0 ? "+" : "", q.rolloff))
                Spacer()
                Text(String(format: "шум %.0f", q.noiseFloor))
            }
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(12)
        .background(q.pass ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(q.pass ? Color.green : Color.orange, lineWidth: 1.5))
        .cornerRadius(14)
    }

    private func dot(_ mic: String) -> some View {
        let isCurrent = tester.currentMic == mic
        let result = tester.results[mic]
        let color: Color = result == true ? .green : (result == false ? .red : (isCurrent ? .blue : .gray.opacity(0.4)))
        let symbol = result == true ? "checkmark.circle.fill"
                   : (result == false ? "exclamationmark.circle.fill"
                   : (isCurrent ? "waveform.circle.fill" : "circle"))
        return VStack(spacing: 4) {
            Image(systemName: symbol).foregroundColor(color).font(.title3)
            Text(label(mic)).font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
