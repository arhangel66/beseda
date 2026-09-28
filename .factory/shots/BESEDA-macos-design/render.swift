import AppKit
import SwiftUI

// Isolated proposals: no app model, permissions, windows or audio.
struct Concept: View {
    let direction: Int
    let screen: String
    let dark: Bool
    var paper: Color { direction == 1 ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor) }
    var ink: Color { .primary }
    var accent: Color { direction == 1 ? .indigo : .teal }
    var body: some View {
        Group {
            if screen == "archive" { archive } else { popover }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
    var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: screen == "recording" ? "record.circle.fill" : "waveform.path")
                    .foregroundStyle(screen == "recording" ? .red : accent)
                Text("Beseda").font(.headline)
                Spacer()
                Text("PROPOSAL · \(direction == 1 ? "FOCUS" : "LEDGER")").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.bottom, 25)
            if screen == "recording" {
                Text(direction == 1 ? "Recording" : "Call in progress").font(.system(size: direction == 1 ? 30 : 24, weight: .semibold, design: direction == 1 ? .rounded : .default))
                Text("00:12:48  ·  Stops after silence").font(.subheadline).foregroundStyle(.secondary).padding(.top, 5)
                VStack(spacing: 15) {
                    meter("Microphone", 0.72, symbol: "mic.fill")
                    meter("Other person", 0.42, symbol: "speaker.wave.2.fill")
                }.padding(.vertical, 24)
                HStack(spacing: 10) {
                    Button("Pause") {}.keyboardShortcut("p").frame(maxWidth: .infinity)
                    Button("Stop recording") {}.keyboardShortcut("r").frame(maxWidth: .infinity).tint(.red).buttonStyle(.borderedProminent)
                }
                Divider().padding(.vertical, 19)
                Label("Live key points and draft", systemImage: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(direction == 1 ? "Ready when you are." : "Ready to record").font(.system(size: direction == 1 ? 27 : 23, weight: .semibold, design: direction == 1 ? .rounded : .default))
                Text("Start a call or use auto-record").font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
                Button {} label: { Label("Start recording", systemImage: "record.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(accent).padding(.top, 24)
                HStack { Text("Auto-record"); Spacer(); Text("Off").foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 18)
                Divider()
                Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary).padding(.top, 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Team check-in").font(.headline)
                    Text("Today, 10:42  ·  Zoom  ·  28 min").font(.caption).foregroundStyle(.secondary)
                    Text("Open conversation  →").font(.subheadline).foregroundStyle(accent).padding(.top, 5)
                }.padding(.vertical, 13)
                Divider()
                HStack { Label("Conversations", systemImage: "rectangle.stack"); Spacer(); Text("⌘1").foregroundStyle(.tertiary) }.padding(.top, 16)
                Label("Settings", systemImage: "gearshape").padding(.top, 14)
                Label("Quit Beseda", systemImage: "power").padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13)).foregroundStyle(ink)
        .padding(20).frame(width: 340, height: screen == "recording" ? 310 : 450, alignment: .topLeading)
        .background(paper)
    }
    func meter(_ title: String, _ level: CGFloat, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).frame(width: 90, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(accent).frame(width: geometry.size.width * level)
                }
            }.frame(height: 6)
        }.font(.subheadline)
    }
    var archive: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("Conversations").font(.title2.bold()); Spacer(); Image(systemName: "magnifyingglass") }.padding(.bottom, 24)
                Text("TODAY").font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary).padding(.bottom, 10)
                row("Team check-in", "10:42  ·  Zoom  ·  28 min", true)
                row("Planning review", "09:15  ·  Meet  ·  36 min", false)
                Text("YESTERDAY").font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary).padding(.top, 30).padding(.bottom, 10)
                row("Project update", "16:20  ·  Zoom  ·  42 min", false)
                Spacer()
                Divider(); Text("3 conversations").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
            }.padding(22).frame(width: direction == 1 ? 290 : 330).background(Color(nsColor: .windowBackgroundColor))
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    Label("Record", systemImage: "record.circle")
                    Spacer()
                    Image(systemName: "square.on.square")
                    Image(systemName: "trash")
                }.font(.subheadline).foregroundStyle(.secondary).frame(height: 52).padding(.horizontal, 28)
                Divider()
                VStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Team check-in").font(.system(size: direction == 1 ? 34 : 29, weight: .semibold, design: direction == 1 ? .rounded : .default)).padding(.top, 34)
                        Text("Today at 10:42  ·  Zoom  ·  28 minutes  ·  Microphone + system audio")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                        HStack(spacing: 26) {
                            Text("Results").foregroundStyle(accent).fontWeight(.semibold)
                            Text("Transcript"); Text("Info")
                        }.font(.subheadline).padding(.top, 32).padding(.bottom, 12)
                        Rectangle().fill(accent).frame(width: 48, height: 2)
                        Divider().padding(.bottom, 32)
                        if direction == 1 {
                            Text("RESULT").font(.caption2.bold()).tracking(2).foregroundStyle(accent)
                            Text("Review the draft on Friday")
                                .font(.system(size: 25, weight: .medium)).padding(.top, 12).padding(.bottom, 28)
                        } else {
                            Text("Call result").font(.title2.bold()).padding(.bottom, 18)
                        }
                        Text(direction == 1 ? "Conversation summary" : "Summary").font(.headline).padding(.bottom, 12)
                        Text("The team reviewed the current draft and agreed to share feedback before Friday. The next discussion will focus on the revised version.")
                            .font(.body).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                        Divider().padding(.vertical, 30)
                        Text("Previous related call").font(.subheadline.weight(.medium))
                        Text("Planning review  ·  12 Sep  ·  Show context")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.frame(maxWidth: direction == 1 ? 620 : 570, alignment: .leading).frame(maxWidth: .infinity, alignment: .center).padding(.horizontal, 34)
                    Spacer()
                }
                Divider()
                HStack(spacing: 15) {
                    Image(systemName: "play.fill"); Text("00:00"); Capsule().fill(accent.opacity(0.45)).frame(height: 4); Text("28:04"); Text("1×")
                }.font(.caption).padding(.horizontal, 28).frame(height: 64)
            }.background(paper)
        }.frame(width: 1100, height: 720).foregroundStyle(ink)
    }
    func row(_ title: String, _ detail: String, _ selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 12)
            .background(selected ? accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

@MainActor
func render() throws {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    for direction in 1...2 {
        for screen in ["idle", "recording", "archive"] {
            for dark in [false, true] {
                let view = Concept(direction: direction, screen: screen, dark: dark).body
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
                let name = "\(direction == 1 ? "focus" : "ledger")-\(screen)-\(dark ? "dark" : "light")"
                try png.write(to: folder.appendingPathComponent(name + ".png"))
                // A 390-pixel inspection strip from the real pixels, not a reflowed phone UI.
                let source = NSImage(data: png)!
                let scaledHeight = Int(Double(bitmap.pixelsHigh) * 390 / Double(bitmap.pixelsWide))
                let thumbnail = NSImage(size: NSSize(width: 390, height: scaledHeight))
                thumbnail.lockFocus()
                source.draw(in: NSRect(x: 0, y: 0, width: 390, height: scaledHeight), from: .zero, operation: .copy, fraction: 1)
                thumbnail.unlockFocus()
                let reduced = NSBitmapImageRep(data: thumbnail.tiffRepresentation!)!
                try reduced.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + "-390.png"))
                print(name, bitmap.pixelsWide, bitmap.pixelsHigh)
            }
        }
    }
}
try MainActor.assumeIsolated { try render() }
