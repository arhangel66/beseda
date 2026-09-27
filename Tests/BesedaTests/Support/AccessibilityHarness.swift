import AppKit
import SwiftUI

@MainActor
public final class AccessibilityHarness<Content: View> {
    public let window: NSWindow

    public init(@ViewBuilder content: () -> Content) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if !NSApp.isRunning { NSApp.finishLaunching() }
        let hostingController = NSHostingController(rootView: content())
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.alphaValue = 0
        window.orderBack(nil)
        hostingController.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    public var elements: [NSObject] {
        var visited = Set<ObjectIdentifier>()
        return Self.walk(NSAccessibility.unignoredDescendant(of: window.contentView) as? NSObject, visited: &visited)
    }

    public func element(identifier: String) -> NSObject? {
        elements.first {
            ($0 as? NSView)?.accessibilityIdentifier() == identifier
                || $0.accessibilityAttributeValue(.identifier) as? String == identifier
        }
    }

    public func element(label: String) -> NSObject? {
        elements.first {
            ($0 as? NSView)?.accessibilityLabel() == label
                || $0.accessibilityAttributeValue(.title) as? String == label
        }
    }

    @discardableResult
    public func performPress(identifier: String) -> Bool {
        guard let button = element(identifier: identifier) as? NSAccessibilityButton else { return false }
        button.accessibilityPerformPress()
        return true
    }

    private static func walk(_ element: NSObject?, visited: inout Set<ObjectIdentifier>) -> [NSObject] {
        guard let element, visited.insert(ObjectIdentifier(element)).inserted else { return [] }
        let accessibilityChildren = (element as? NSView)?.accessibilityChildren()
            ?? element.accessibilityAttributeValue(.children) as? [Any]
            ?? []
        let viewChildren = (element as? NSView)?.subviews ?? []
        let children = accessibilityChildren.compactMap { $0 as? NSObject } + viewChildren
        return [element] + children.flatMap { walk($0, visited: &visited) }
    }
}
