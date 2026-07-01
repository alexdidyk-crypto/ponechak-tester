import SwiftUI

// MARK: - Tile styling

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

struct TileCard<Content: View>: View {
    let title: String
    let icon: String
    let status: TileStatus
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon).font(.system(size: 24)).frame(maxWidth: .infinity)
                if let badge = status.badge {
                    Image(systemName: badge).foregroundColor(status.badgeColor)
                }
            }
            Text(title).font(.caption).fontWeight(.semibold)
                .multilineTextAlignment(.center).lineLimit(2)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(12)
        .background(status.bg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(status.border, lineWidth: 1.5))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Microphone record + playback tile

struct MicRecordTile: View {
    let micName: String
    let display: String
    @StateObject private var rec: MicRecorder

    init(micName: String, display: String) {
        self.micName = micName
        self.display = display
        _rec = StateObject(wrappedValue: MicRecorder(micName: micName))
    }

    private var status: TileStatus {
        switch rec.state {
        case .recording, .playing: return .running
        case .recorded: return .pass
        case .idle: return .idle
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.fill").font(.system(size: 22))
            Text(display).font(.caption).fontWeight(.semibold).lineLimit(1)
            if rec.state == .recording {
                ProgressView(value: rec.level).tint(.green)
                Text("recording…").font(.caption2).foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button("Rec") { rec.record() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Play") { rec.play() }
                        .buttonStyle(.bordered).controlSize(.small).disabled(!rec.hasRecording)
                }
                Text(stateText).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(12)
        .background(status.bg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(status.border, lineWidth: 1.5))
        .cornerRadius(16)
        .onDisappear { rec.stopAll() }
    }

    private var stateText: String {
        switch rec.state {
        case .playing: return "playing…"
        case .recorded: return "recorded ✓"
        default: return "record, then play"
        }
    }
}

// MARK: - Speaker tiles (bottom loudspeaker / top earpiece)

struct SpeakerToneTile: View {
    let title: String
    let icon: String
    let route: AudioRoute
    @State private var playing = false
    private let tone = ToneTester()

    var body: some View {
        TileCard(title: title, icon: icon, status: playing ? .running : .idle, onTap: {
            playing = true
            tone.play(route: route)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { playing = false }
        }) {
            Text(playing ? "playing…" : "tap to test").font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Simple / live tiles

struct TorchTile: View {
    @State private var on = false
    var body: some View {
        TileCard(title: "Flashlight", icon: on ? "flashlight.on.fill" : "flashlight.off.fill",
                 status: on ? .running : .idle, onTap: { on.toggle(); TorchTester.set(on) }) {
            Text(TorchTester.available ? (on ? "on" : "tap to toggle") : "N/A")
                .font(.caption2).foregroundColor(.secondary)
        }
        .onDisappear { if on { TorchTester.set(false) } }
    }
}

struct DisplayTile: View {
    @Binding var show: Bool
    var body: some View {
        TileCard(title: "Display", icon: "square.stack.3d.up.fill", status: .idle, onTap: { show = true }) {
            Text("colors / dead pixels").font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct BiometryTile: View {
    @State private var status: TileStatus = .idle
    @State private var text = BiometryTester.describe()
    var body: some View {
        TileCard(title: "Face ID / Touch ID", icon: "faceid", status: status, onTap: {
            BiometryTester.evaluate { ok, msg in status = ok ? .pass : .fail; text = msg }
        }) {
            Text(text).font(.caption2).foregroundColor(.secondary).lineLimit(2)
        }
    }
}

struct VibrationTile: View {
    var body: some View {
        TileCard(title: "Vibration", icon: "iphone.radiowaves.left.and.right",
                 status: .idle, onTap: { VibrationTester.buzz() }) {
            Text("tap to buzz").font(.caption2).foregroundColor(.secondary)
        }
    }
}

struct SensorsTile: View {
    @StateObject private var s = SensorTester()
    var body: some View {
        TileCard(title: "Motion sensors", icon: "gyroscope", status: s.moved ? .pass : .idle) {
            Text(s.accel).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
            Text(s.moved ? "motion ✓" : "tilt the phone").font(.caption2).foregroundColor(.secondary)
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }
}

struct DeviceTile: View {
    @StateObject private var d = DeviceInfoTester()
    var body: some View {
        TileCard(title: "Proximity & battery", icon: "battery.100", status: d.proximityTriggered ? .pass : .info) {
            Text("Battery: \(d.battery)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
            Text("Proximity: \(d.proximity)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
        .onAppear { d.start() }
        .onDisappear { d.stop() }
    }
}

struct VolumeTile: View {
    @StateObject private var v = VolumeButtonTester()
    var body: some View {
        TileCard(title: "Volume buttons", icon: "speaker.badge.exclamationmark", status: v.pressed ? .pass : .idle) {
            Text(v.pressed ? v.lastChange : "press volume buttons").font(.caption2)
                .foregroundColor(.secondary).lineLimit(2)
        }
        .onAppear { v.start() }
        .onDisappear { v.stop() }
    }
}

// MARK: - Dashboard

struct ContentView: View {
    @State private var micNames: [String] = []
    @State private var showDisplay = false
    @State private var showMicTest = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Button(action: { showMicTest = true }) {
                        HStack {
                            Image(systemName: "waveform.badge.mic")
                            Text("Mic auto-test (quality)").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundColor(.white).cornerRadius(14)
                    }

                    ForEach(micRowStarts, id: \.self) { i in
                        HStack(spacing: 12) {
                            MicRecordTile(micName: micNames[i], display: micLabel(micNames[i]))
                            if i + 1 < micNames.count {
                                MicRecordTile(micName: micNames[i + 1], display: micLabel(micNames[i + 1]))
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        SpeakerToneTile(title: "Bottom speaker", icon: "speaker.wave.3.fill", route: .speaker)
                        SpeakerToneTile(title: "Top speaker (earpiece)", icon: "speaker.wave.1.fill", route: .earpiece)
                    }
                    HStack(spacing: 12) { TorchTile(); DisplayTile(show: $showDisplay) }
                    HStack(spacing: 12) { SensorsTile(); DeviceTile() }
                    HStack(spacing: 12) { BiometryTile(); VibrationTile() }
                    HStack(spacing: 12) { VolumeTile(); Color.clear.frame(maxWidth: .infinity) }
                }
                .padding(12)
            }
            .navigationTitle("PONECHAK")
            .onAppear { if micNames.isEmpty { micNames = MicTester.builtInMicNames() } }
            .fullScreenCover(isPresented: $showDisplay) { DisplayTestView() }
            .fullScreenCover(isPresented: $showMicTest) {
                MicTestView(mics: micNames, label: micLabel, verdict: .constant([:]))
            }
        }
        .navigationViewStyle(.stack)
    }

    private var micRowStarts: [Int] { Array(stride(from: 0, to: micNames.count, by: 2)) }

    private func micLabel(_ name: String) -> String {
        switch name.lowercased() {
        case "bottom": return "Bottom mic"
        case "front": return "Front mic"
        case "back": return "Back mic"
        default: return "Mic \(name)"
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
                Text("Tap the screen to cycle colors. Look for dead pixels / stains.")
                    .padding(10).background(Color.black.opacity(0.55)).foregroundColor(.white)
                    .cornerRadius(8).padding(.top, 40)
                Spacer()
                Button("Close") { dismiss() }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(12).padding()
            }
        }
    }
}
