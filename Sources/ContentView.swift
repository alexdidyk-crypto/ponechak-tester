import SwiftUI

// MARK: - Tile status / styling

enum TileStatus: Equatable {
    case idle, running, pass, fail, info

    var bg: Color {
        switch self {
        case .pass: return Color.green.opacity(0.18)
        case .fail: return Color.red.opacity(0.18)
        case .running: return Color.blue.opacity(0.18)
        case .info: return Color.orange.opacity(0.14)
        case .idle: return Color.gray.opacity(0.12)
        }
    }
    var border: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .running: return .blue
        case .info: return .orange
        case .idle: return Color.gray.opacity(0.35)
        }
    }
    var badge: String? {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        default: return nil
        }
    }
    var badgeColor: Color { self == .pass ? .green : .red }
}

// MARK: - Generic tile container

struct TileCard<Content: View>: View {
    let title: String
    let icon: String
    let status: TileStatus
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon).font(.system(size: 26)).frame(maxWidth: .infinity)
                    if let badge = status.badge {
                        Image(systemName: badge).foregroundColor(status.badgeColor)
                    }
                }
                Text(title).font(.caption).fontWeight(.semibold)
                    .multilineTextAlignment(.center).lineLimit(2)
                content
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(12)
            .background(status.bg)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(status.border, lineWidth: 2))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Microphone tile (live level on the tile)

struct MicTile: View {
    let micName: String
    let display: String
    @ObservedObject var mic: MicTester
    @Binding var verdict: [String: Bool]

    private var isActive: Bool { mic.recordingName == micName }
    private var status: TileStatus {
        if isActive { return .running }
        if let v = verdict[micName] { return v ? .pass : .fail }
        return .idle
    }

    var body: some View {
        TileCard(title: display, icon: "mic.fill", status: status, action: tap) {
            if isActive {
                ProgressView(value: mic.level).tint(mic.level > 0.25 ? .green : .blue)
                Text(mic.peak > 0.25 ? "сигнал есть · стоп" : "говори…")
                    .font(.caption2).foregroundColor(.secondary)
            } else if let v = verdict[micName] {
                Text(v ? "OK" : "нет сигнала").font(.caption2).foregroundColor(.secondary)
            } else {
                Text("нажми для теста").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func tap() {
        if isActive { verdict[micName] = mic.peak > 0.25; mic.stop() }
        else { mic.start(micName: micName) }
    }
}

// MARK: - Record & playback tile (per microphone)

struct MicRecPlayTile: View {
    let micName: String
    let display: String
    @ObservedObject var rp: MicRecordPlayer

    private var isActive: Bool { rp.activeMic == micName }
    private var status: TileStatus { isActive ? .running : .idle }

    var body: some View {
        TileCard(title: display, icon: "record.circle.fill", status: status,
                 action: { if !isActive { rp.recordThenPlay(micName: micName) } }) {
            if isActive {
                if rp.phase == .recording {
                    ProgressView(value: rp.level).tint(.red)
                    Text("recording 3s…").font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("playing…").font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Text("record + play").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Main dashboard

struct ContentView: View {
    @StateObject private var mic = MicTester()
    @StateObject private var volume = VolumeButtonTester()
    @StateObject private var sensors = SensorTester()
    @StateObject private var deviceInfo = DeviceInfoTester()
    @StateObject private var recPlayer = MicRecordPlayer()
    private let tone = ToneTester()

    @State private var micNames: [String] = []
    @State private var micVerdict: [String: Bool] = [:]
    @State private var biometryStatus: TileStatus = .idle
    @State private var biometryText = ""
    @State private var torchOn = false
    @State private var spkTop = false
    @State private var spkBottom = false
    @State private var showDisplayTest = false
    @State private var showMicTest = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationView {
            ScrollView {
                Button(action: { showMicTest = true }) {
                    HStack {
                        Image(systemName: "waveform.badge.mic")
                        Text("Авто-тест микрофонов").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(14)
                }
                .padding(.horizontal, 12).padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(micNames, id: \.self) { name in
                        MicTile(micName: name, display: micLabel(name), mic: mic, verdict: $micVerdict)
                    }
                    ForEach(micNames, id: \.self) { name in
                        MicRecPlayTile(micName: name, display: "Rec+Play " + micLabel(name), rp: recPlayer)
                    }
                    speakerTopTile
                    speakerBottomTile
                    torchTile
                    displayTile
                    sensorsTile
                    proximityTile
                    batteryTile
                    biometryTile
                    vibrationTile
                    volumeTile
                }
                .padding(12)
            }
            .navigationTitle("PONECHAK")
            .onAppear {
                micNames = MicTester.builtInMicNames()
                biometryText = BiometryTester.describe()
                volume.start(); sensors.start(); deviceInfo.start()
            }
            .onDisappear {
                mic.stop(); volume.stop(); sensors.stop(); deviceInfo.stop()
                recPlayer.stopAll(); TorchTester.set(false)
            }
            .fullScreenCover(isPresented: $showDisplayTest) { DisplayTestView() }
            .fullScreenCover(isPresented: $showMicTest) {
                MicTestView(mics: micNames, label: micLabel, verdict: $micVerdict)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func micLabel(_ name: String) -> String {
        switch name.lowercased() {
        case "bottom": return "Mic bottom"
        case "front": return "Mic front"
        case "back": return "Mic back"
        default: return "Mic \(name)"
        }
    }

    private var speakerTopTile: some View {
        TileCard(title: "Speaker · top", icon: "speaker.wave.2",
                 status: spkTop ? .running : .idle,
                 action: { spkTop = true; tone.play(seconds: 2, earpiece: true)
                           DispatchQueue.main.asyncAfter(deadline: .now() + 2) { spkTop = false } }) {
            Text(spkTop ? "playing (earpiece)…" : "earpiece").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var speakerBottomTile: some View {
        TileCard(title: "Speaker · bottom", icon: "speaker.wave.3.fill",
                 status: spkBottom ? .running : .idle,
                 action: { spkBottom = true; tone.play(seconds: 2, earpiece: false)
                           DispatchQueue.main.asyncAfter(deadline: .now() + 2) { spkBottom = false } }) {
            Text(spkBottom ? "playing (loud)…" : "loudspeaker").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var torchTile: some View {
        TileCard(title: "Фонарик", icon: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                 status: torchOn ? .running : .idle,
                 action: { torchOn.toggle(); TorchTester.set(torchOn) }) {
            Text(TorchTester.available ? (torchOn ? "включён" : "нажми") : "нет").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var displayTile: some View {
        TileCard(title: "Дисплей", icon: "square.stack.3d.up.fill", status: .idle,
                 action: { showDisplayTest = true }) {
            Text("цвета / пиксели").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var sensorsTile: some View {
        TileCard(title: "Датчики", icon: "gyroscope",
                 status: sensors.moved ? .pass : .idle, action: {}) {
            Text(sensors.accel).font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary).lineLimit(1)
            Text(sensors.moved ? "движение ✓" : "покачай телефон").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var proximityTile: some View {
        TileCard(title: "Приближение", icon: "sensor.tag.radiowaves.forward.fill",
                 status: deviceInfo.proximityTriggered ? .pass : .idle, action: {}) {
            Text(deviceInfo.proximity).font(.caption2).foregroundColor(.secondary).lineLimit(2)
        }
    }

    private var batteryTile: some View {
        TileCard(title: "Батарея", icon: "battery.100", status: .info, action: {}) {
            Text(deviceInfo.battery).font(.caption2).foregroundColor(.secondary).lineLimit(2)
        }
    }

    private var biometryTile: some View {
        TileCard(title: "Face ID", icon: "faceid", status: biometryStatus, action: {
            BiometryTester.evaluate { ok, msg in
                biometryStatus = ok ? .pass : .fail; biometryText = msg
            }
        }) {
            Text(biometryText).font(.caption2).foregroundColor(.secondary).lineLimit(2)
        }
    }

    private var vibrationTile: some View {
        TileCard(title: "Вибрация", icon: "iphone.radiowaves.left.and.right",
                 status: .idle, action: { VibrationTester.buzz() }) {
            Text("нажми — вибро").font(.caption2).foregroundColor(.secondary)
        }
    }

    private var volumeTile: some View {
        TileCard(title: "Кнопки громк.", icon: "button.programmable",
                 status: volume.pressed ? .pass : .idle, action: {}) {
            Text(volume.pressed ? volume.lastChange : "нажми кнопки").font(.caption2)
                .foregroundColor(.secondary).lineLimit(2)
        }
    }
}

// MARK: - Fullscreen display test

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
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(12).padding()
            }
        }
    }
}
