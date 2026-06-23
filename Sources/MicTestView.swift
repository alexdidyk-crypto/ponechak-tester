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
                // threshold line
                Path { p in
                    let y = h * (1 - CGFloat(threshold))
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                // waveform
                Path { p in
                    guard samples.count > 1 else { return }
                    let step = w / CGFloat(max(1, samples.count - 1))
                    for (i, s) in samples.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h * (1 - CGFloat(min(1, max(0, s))))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke((samples.last ?? 0) > threshold ? Color.green : Color.blue, lineWidth: 2)
            }
        }
    }
}

struct MicTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tester = MicAutoTester()

    let mics: [String]
    let label: (String) -> String
    @Binding var verdict: [String: Bool]

    var body: some View {
        VStack(spacing: 18) {
            Text("🎙 Тест микрофонов").font(.title2).bold()

            Text(headline).foregroundColor(.secondary).font(.subheadline)

            WaveformGraph(samples: tester.samples, threshold: tester.threshold)
                .frame(height: 190)
                .padding(8)
                .background(Color.gray.opacity(0.10))
                .cornerRadius(14)

            HStack(spacing: 10) {
                ForEach(mics, id: \.self) { mic in dot(mic) }
            }

            Spacer()

            Button(tester.finished ? "Закрыть" : "Отмена") {
                tester.cancel(); dismiss()
            }
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
        if let cur = tester.currentMic { return "Проверяю: \(label(cur))" }
        if tester.finished {
            let ok = tester.results.values.filter { $0 }.count
            return "Готово · рабочих микрофонов: \(ok) из \(mics.count)"
        }
        return "Запуск…"
    }

    private func dot(_ mic: String) -> some View {
        let isCurrent = tester.currentMic == mic
        let result = tester.results[mic]
        let color: Color = result == true ? .green : (result == false ? .red : (isCurrent ? .blue : .gray.opacity(0.4)))
        let symbol = result == true ? "checkmark.circle.fill"
                   : (result == false ? "xmark.circle.fill"
                   : (isCurrent ? "waveform.circle.fill" : "circle"))
        return VStack(spacing: 4) {
            Image(systemName: symbol).foregroundColor(color).font(.title3)
            Text(label(mic)).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
