import SwiftUI

// Synthetic, inert views only. Never instantiate Beseda's controller or request permissions.
public enum ConceptDirection: String, CaseIterable { case focus, ledger }
public enum ConceptScene: String, CaseIterable { case idle, recording, archive }

private struct SampleCall: Identifiable {
    let id: Int
    let title: String
    let time: String
    let app: String
    let minutes: Int
}

private let calls: [SampleCall] = [
    .init(id: 1, title: "Team check-in", time: "10:42", app: "Zoom", minutes: 28),
    .init(id: 2, title: "Planning review", time: "09:15", app: "Meet", minutes: 36),
    .init(id: 3, title: "Team check-in", time: "16:20", app: "Zoom", minutes: 42),
    .init(id: 4, title: "Project update", time: "14:05", app: "Teams", minutes: 31),
    .init(id: 5, title: "Planning review", time: "11:00", app: "Meet", minutes: 24),
    .init(id: 6, title: "Team check-in", time: "09:30", app: "Zoom", minutes: 18),
    .init(id: 7, title: "Project update", time: "15:10", app: "Teams", minutes: 55),
    .init(id: 8, title: "Planning review", time: "13:00", app: "Meet", minutes: 27),
    .init(id: 9, title: "Team check-in", time: "10:20", app: "Zoom", minutes: 34),
    .init(id: 10, title: "Project update", time: "09:40", app: "Teams", minutes: 22),
    .init(id: 11, title: "Planning review", time: "16:15", app: "Meet", minutes: 39),
    .init(id: 12, title: "Team check-in", time: "11:30", app: "Zoom", minutes: 26)
]

public struct NativeConcept: View {
    public let direction: ConceptDirection
    public let scene: ConceptScene
    @State private var autoRecord = false
    @State private var section = 1
    @State private var selectedCall: Int? = 1
    @State private var search = ""

    public init(direction: ConceptDirection, scene: ConceptScene) {
        self.direction = direction
        self.scene = scene
    }

    public var body: some View {
        Group {
            if scene == .archive { archive } else { popover }
        }
        .tint(.accentColor)
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: direction == .focus ? 16 : 9) {
            Label(scene == .recording ? "Recording" : "Ready to record", systemImage: scene == .recording ? "record.circle.fill" : "checkmark.circle")
                .font(direction == .focus ? .title2.weight(.semibold) : .headline)
                .foregroundStyle(scene == .recording ? Color.red : Color.primary)
            Text(scene == .recording ? "00:12:48 · Stops after a minute of silence" : "Auto-record is off")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if scene == .recording {
                HStack {
                    Button("Pause", systemImage: "pause.fill") {}
                        .accessibilityIdentifier("concept.pause")
                    Button("Stop", systemImage: "stop.fill") {}
                        .buttonStyle(.borderedProminent).tint(.red)
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityIdentifier("concept.stop")
                }
                level("Microphone", value: 0.72, symbol: "mic")
                level("Other person", value: 0.42, symbol: "speaker.wave.2")
                DisclosureGroup("Live key points and draft") {
                    Text("Draft appears after about 20 seconds.")
                }
            } else {
                HStack {
                    Button("Start recording", systemImage: "record.circle") {}
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityIdentifier("concept.start")
                    Spacer(minLength: 0)
                    Toggle("Auto-record", isOn: $autoRecord).toggleStyle(.switch)
                        .accessibilityIdentifier("concept.autoRecord")
                }
                Divider()
                if direction == .focus {
                    Text("Recent call").font(.caption).foregroundStyle(.secondary)
                    Text("Team check-in").font(.headline)
                    Text("Zoom · 28 min").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Open") {}
                        Button("Copy transcript") {}
                    }
                } else {
                    Text("Recent calls").font(.caption).foregroundStyle(.secondary)
                    ForEach(calls.prefix(3)) { call in
                        Button { } label: {
                            VStack(alignment: .leading) {
                                Text(call.title)
                                Text("\(call.time) · \(call.minutes) min")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Divider()
                Button("Conversations…", systemImage: "rectangle.stack") {}
                Button("Settings…", systemImage: "gearshape") {}
                Button("Quit Beseda", systemImage: "power") {}
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .buttonStyle(.bordered)
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
    }

    private func level(_ title: String, value: Double, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).frame(width: 125, alignment: .leading)
            ProgressView(value: value).accessibilityLabel("Sound level: \(title)")
                .accessibilityValue("\(Int(value * 100)) percent")
        }.font(.caption)
    }

    private var archive: some View {
        NavigationSplitView {
            List(selection: $selectedCall) {
                Section("Today") {
                    ForEach(calls.prefix(2)) { row($0) }
                }
                Section("Yesterday") {
                    ForEach(calls.dropFirst(2).prefix(4)) { row($0) }
                }
                Section("Earlier") {
                    ForEach(calls.dropFirst(6)) { row($0) }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: direction == .focus ? 280 : 350, max: 420)
            .accessibilityIdentifier("concept.archive")
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Team check-in")
                    .font(direction == .focus ? .largeTitle : .title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Today at 10:42 · Zoom · 28 minutes · Microphone and system audio")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Section", selection: $section) {
                    Text("Transcript").tag(0)
                    Text("Results").tag(1)
                    Text("Info").tag(2)
                }.pickerStyle(.segmented).fixedSize().padding(.vertical, 16)
                    .accessibilityIdentifier("concept.section")
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if direction == .focus {
                            Text("Call result").font(.title2.weight(.semibold))
                            Text("Review the revised opening on Friday.")
                                .font(.title3).foregroundStyle(.primary)
                        } else {
                            Text("Summary").font(.headline)
                        }
                        Text("The team reviewed the current draft and agreed to share feedback before Friday. The next discussion will focus on the revised version. The review identified two open questions: whether the introduction explains the audience clearly and which examples should remain in the final draft. The team will collect written comments before the next discussion. Friday’s review will compare the revised opening with the original and decide which examples to keep. No changes to the release date were agreed in this call.")
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Previous related call · Planning review")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: direction == .focus ? 620 : 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                }
                Spacer(minLength: 0)
                HStack {
                    Button("Play", systemImage: "play.fill") {}
                    Text("00:00 / 28:00").monospacedDigit()
                    Spacer()
                    Button("Speed: 1×") {}
                }.padding(12).background(.bar)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Conversations")
        .searchable(text: $search, placement: .sidebar, prompt: "Search conversations")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy transcript", systemImage: "doc.on.doc") {}
                Button("Delete", systemImage: "trash") {}
                Button("Record", systemImage: "record.circle") {}
            }
        }
        .frame(width: 1100, height: 720)
    }

    private func row(_ call: SampleCall) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(call.title).lineLimit(1)
            Text("\(call.time) · \(call.minutes) min · \(call.app)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .tag(call.id)
        .accessibilityLabel("\(call.title), \(call.time), \(call.minutes) minutes, \(call.app)")
    }
}
