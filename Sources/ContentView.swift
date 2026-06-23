import SwiftUI

struct ContentView: View {
    @StateObject private var mic = MicTester()
    @StateObject private var volume = VolumeButtonTester()
    @StateObject private var sensors = SensorTester()
    @StateObject private var deviceInfo = DeviceInfoTester()
    private let tone = ToneTester()

    @State private var micNames: [String] = []
    @State private var micVerdict: [String: Bool] = [:]
    @State private var biometryInfo = ""
    @State private var faceResult = ""
    @State private var torchOn = false
    @State private var showDisplayTest = false

    var body: some View {
        NavigationView {
            List {
                micSection
                cameraTorchSection
                speakerSection
                displaySection
                sensorsSection
                proximityBatterySection
                biometrySection
                otherSection
            }
            .navigationTitle("PONECHAK Tester")
            .onAppear {
                micNames = MicTester.builtInMicNames()
                biometryInfo = BiometryTester.describe()
                volume.start()
                sensors.start()
                deviceInfo.start()
            }
            .onDisappear {
                mic.stop(); volume.stop(); sensors.stop(); deviceInfo.stop()
                TorchTester.set(false)
            }
            .fullScreenCover(isPresented: $showDisplayTest) {
                DisplayTestView()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Microphones
    private var micSection: some View {
        Section("Микрофоны — каждый отдельно") {
            if micNames.isEmpty {
                Text("Встроенные микрофоны не найдены").foregroundColor(.secondary)
            }
            ForEach(micNames, id: \.self) { name in micRow(name) }
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
                    if isActive { micVerdict[name] = mic.peak > 0.25; mic.stop() }
                    else { mic.start(micName: name) }
                }
                .buttonStyle(.borderedProminent)
            }
            if isActive {
                ProgressView(value: mic.level).tint(mic.level > 0.25 ? .green : .accentColor)
                Text(mic.peak > 0.25 ? "Сигнал есть — нажми «Стоп»" : "Говори в этот микрофон…")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func localizedMic(_ name: String) -> String {
        switch name.lowercased() {
        case "bottom": return "Нижний (разговорный)"
        case "front": return "Фронтальный (верх)"
        case "back": return "Задний"
        default: return name
        }
    }

    // MARK: Flashlight
    private var cameraTorchSection: some View {
        Section("Фонарик (LED)") {
            Toggle(isOn: Binding(get: { torchOn }, set: { v in torchOn = v; TorchTester.set(v) })) {
                Text(TorchTester.available ? "Включить фонарик" : "Фонарик недоступен")
            }
            .disabled(!TorchTester.available)
        }
    }

    // MARK: Speaker
    private var speakerSection: some View {
        Section("Динамик") {
            Button("Проиграть тон (2 сек)") { tone.play() }
            Text("Должен быть слышен звук из динамика").font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: Display
    private var displaySection: some View {
        Section("Дисплей") {
            Button("Тест экрана (цвета / пиксели)") { showDisplayTest = true }
        }
    }

    // MARK: Sensors
    private var sensorsSection: some View {
        Section("Датчики движения") {
            row("Акселерометр", sensors.accel)
            row("Гироскоп", sensors.gyro)
            row("Магнитометр (компас)", sensors.magnet)
            HStack {
                Text("Реакция на движение")
                Spacer()
                Image(systemName: sensors.moved ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(sensors.moved ? .green : .secondary)
            }
            Text("Поверни/покачай телефон — цифры должны меняться").font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: Proximity + battery
    private var proximityBatterySection: some View {
        Section("Датчик приближения и батарея") {
            HStack {
                Text("Датчик приближения")
                Spacer()
                Image(systemName: deviceInfo.proximityTriggered ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(deviceInfo.proximityTriggered ? .green : .secondary)
            }
            Text(deviceInfo.proximity).font(.caption).foregroundColor(.secondary)
            row("Батарея", deviceInfo.battery)
        }
    }

    // MARK: Biometry
    private var biometrySection: some View {
        Section("Face ID / Touch ID") {
            Text(biometryInfo).font(.subheadline)
            Button("Проверить биометрию") {
                BiometryTester.evaluate { _, msg in faceResult = msg }
            }
            if !faceResult.isEmpty { Text(faceResult).font(.caption).foregroundColor(.secondary) }
        }
    }

    // MARK: Other
    private var otherSection: some View {
        Section("Вибрация и кнопки") {
            Button("Проверить вибрацию") { VibrationTester.buzz() }
            HStack {
                Text("Кнопки громкости")
                Spacer()
                Image(systemName: volume.pressed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(volume.pressed ? .green : .secondary)
            }
            Text(volume.pressed ? volume.lastChange : "Нажми кнопки громкости")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.system(.footnote, design: .monospaced)).foregroundColor(.secondary)
        }
    }
}

/// Fullscreen colour cycling for dead-pixel / display defect checks.
struct DisplayTestView: View {
    @Environment(\.dismiss) private var dismiss
    private let colors: [Color] = [.white, .black, .red, .green, .blue, .gray]
    @State private var index = 0

    var body: some View {
        ZStack {
            colors[index].ignoresSafeArea()
                .onTapGesture { index = (index + 1) % colors.count }
            VStack {
                Text("Тапай по экрану — смена цвета. Ищи битые пиксели/пятна.")
                    .padding(10).background(Color.black.opacity(0.55)).foregroundColor(.white)
                    .cornerRadius(8).padding(.top, 40)
                Spacer()
                Button("Закрыть") { dismiss() }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
                    .padding()
            }
        }
    }
}
