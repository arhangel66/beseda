import AppKit
import SwiftUI

// Synthetic-only experiment. The window is never ordered; no app or capture APIs are used.
struct Idle: View {
    @State private var automatic = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Beseda").font(.headline)
            Text("Ready to record").font(.title2)
            Button("Start recording") {}
            Toggle("Auto-record", isOn: $automatic)
            Spacer()
        }.padding(20).frame(width: 340, height: 450)
    }
}

struct Archive: View {
    @State private var selection: Int? = 1
    @State private var query = ""
    @State private var tab = 0
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Team check-in").tag(1)
                Text("Planning review").tag(2)
            }.searchable(text: $query)
                .navigationTitle("Conversations")
        } detail: {
            VStack(alignment: .leading) {
                Picker("Section", selection: $tab) {
                    Text("Results").tag(0)
                    Text("Transcript").tag(1)
                }.pickerStyle(.segmented)
                Text("Team check-in").font(.largeTitle)
                Text("The team reviewed the current draft.")
                Spacer()
            }.padding(24).navigationTitle("Team check-in")
                .toolbar { Button("Export", systemImage: "square.and.arrow.up") {} }
        }.frame(width: 1100, height: 720)
    }
}

@MainActor
func run() throws {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    for dark in [false, true] {
        for archive in [false, true] {
            let size = archive ? NSSize(width: 1100, height: 720) : NSSize(width: 340, height: 450)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: archive ? [.titled, .closable, .resizable] : [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: AnyView(archive ? AnyView(Archive()) : AnyView(Idle())))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bounds = host.bounds
            guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("No bitmap") }
            rep.size = bounds.size
            host.cacheDisplay(in: bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            let name = "native-\(archive ? "archive" : "idle")-\(dark ? "dark" : "light").png"
            try png.write(to: directory.appendingPathComponent(name))
            print(name, rep.pixelsWide, rep.pixelsHigh, "window visible:", window.isVisible)
        }
    }
}
try MainActor.assumeIsolated { try run() }
