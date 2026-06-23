import SwiftUI

struct ContentView: View {
    @StateObject private var mic = MicTester()
    @StateObject private var volume = VolumeButtonTester()

    @State private var micNames: [String] = []
    @State private var micVerdict: [String: Bool] = [:]      // name -> passed
    @State private var biometryInfo = ""
    @State private var faceResult = ""

    var body: some View {
        NavigationView {
            List {
                micSection
                biometrySection
                otherSection
            }
            .navigationTitle("PONECHAK Tester")
            .onAppear {
                micNames = MicTester.builtInMicNames()
                biometryInfo = BiometryTester.describe()
                volume.start()
            }
            .onDisappear {
                mic.stop()
                volume.stop()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Microphones (each one separately)
    private var micSection: some View {
        Section("Микрофоны — каждый отдельно") {
            if micNames.isEmpty {
                Text("Встроенные микрофоны не найдены").foregroundColor(.secondary)
            }
            ForEach(micNames, id: \.self) { name in
                micRow(name)
            }
        }
    }

    private func micRow(_ name: String) -> some View {
        let isActive = mic.recordingName == name
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localizedMic(name)).font(.headline)
                if let passed = micVerdict[name] {
                    Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(passed ? .green : .red)
                }
                Spacer()
                Button(isActive ? "Стоп" : "Тест") {
                    if isActive {
                        micVerdict[name] = mic.peak > 0.25
                        mic.stop()
                    } else {
                        mic.start(micName: name)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            if isActive {
                ProgressView(value: mic.level)
                    .tint(mic.level > 0.25 ? .green : .accentColor)
                Text(mic.peak > 0.25 ? "Сигнал есть — скажи что-нибудь, потом «Стоп»"
                                     : "Говори в этот микрофон…")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func localizedMic(_ name: String) -> String {
        switch name.lowercased() {
        case "bottom": return "Нижний (разговорный)"
        case "front": return "Фронтальный (верх)"
        case "back": return "Задний"
        default: return name
        }
    }

    // MARK: - Biometry
    private var biometrySection: some View {
        Section("Face ID / Touch ID") {
            Text(biometryInfo).font(.subheadline)
            Button("Проверить биометрию") {
                BiometryTester.evaluate { _, msg in faceResult = msg }
            }
            if !faceResult.isEmpty {
                Text(faceResult).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Other
    private var otherSection: some View {
        Section("Прочее") {
            Button("Проверить вибрацию") { VibrationTester.buzz() }
            HStack {
                Text("Кнопки громкости")
                Spacer()
                Image(systemName: volume.pressed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(volume.pressed ? .green : .secondary)
            }
            Text(volume.pressed ? volume.lastChange : "Нажми кнопки громкости на телефоне")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
