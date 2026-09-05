import AppKit
import SwiftUI

/// A speaker's colours. One triple paints the transcript line, its avatar and the speaker's
/// lane in the player, so a glance tells who is talking.
struct SpeakerStyle {
    let bar: Color
    let soft: Color
    let ink: Color

    static let mine = SpeakerStyle(
        bar: Color(hex: 0x4B57D8),
        soft: Color(light: 0x4B57D8, dark: 0x7884FF, lightAlpha: 0.14, darkAlpha: 0.22),
        ink: Color(light: 0x3A44B8, dark: 0xAAB2FF)
    )

    /// remote colours in the order people first speak; the first is the orange the app always had
    private static let remote: [SpeakerStyle] = [
        SpeakerStyle(
            bar: Color(hex: 0xE0654A),
            soft: Color(light: 0xE0654A, dark: 0xFF8264, lightAlpha: 0.15, darkAlpha: 0.22),
            ink: Color(light: 0xB64A32, dark: 0xFF9D84)
        ),
        SpeakerStyle(
            bar: Color(hex: 0x1F8A70),
            soft: Color(light: 0x1F8A70, dark: 0x3FC9A5, lightAlpha: 0.15, darkAlpha: 0.22),
            ink: Color(light: 0x156B56, dark: 0x66DCBB)
        ),
        SpeakerStyle(
            bar: Color(hex: 0x9A5CD0),
            soft: Color(light: 0x9A5CD0, dark: 0xBE8CF0, lightAlpha: 0.15, darkAlpha: 0.22),
            ink: Color(light: 0x7A3FB0, dark: 0xCDA6F5)
        ),
        SpeakerStyle(
            bar: Color(hex: 0xB8862B),
            soft: Color(light: 0xB8862B, dark: 0xE0AC4E, lightAlpha: 0.15, darkAlpha: 0.22),
            ink: Color(light: 0x8F6718, dark: 0xEFC470)
        ),
        SpeakerStyle(
            bar: Color(hex: 0xC2417A),
            soft: Color(light: 0xC2417A, dark: 0xEE7CAC, lightAlpha: 0.15, darkAlpha: 0.22),
            ink: Color(light: 0x9C2F5F, dark: 0xF79BC2)
        )
    ]

    /// "me" is the microphone; everyone else is a remote speaker, numbered by the store key
    static func of(speaker: String) -> SpeakerStyle {
        guard speaker != TranscriptChannel.microphone.speakerID else {
            return .mine
        }
        let index = SpeakerNaming.remoteIndex(of: speaker) ?? 1
        return remote[(max(index, 1) - 1) % remote.count]
    }
}

enum Metrics {
    static let windowCorner: CGFloat = 12
    static let cardCorner: CGFloat = 10
    static let rowCorner: CGFloat = 8
}

extension Color {
    /// an opaque colour pair, e.g. `#ffffff` in light and `#1e1e1e` in dark
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(
            light: NSColor(hex: light, alpha: lightAlpha),
            dark: NSColor(hex: dark, alpha: darkAlpha)
        )
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// SwiftUI resolves an unnamed dynamic NSColor once, in light; a named one stays dynamic
    private init(light: NSColor, dark: NSColor) {
        let name = NSColor.Name("beseda-\(light.description)-\(dark.description)")
        self.init(nsColor: NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
