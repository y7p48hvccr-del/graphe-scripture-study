import SwiftUI

// MARK: - Cross-platform Color helpers

extension Color {
    /// The platform's standard window/view background colour.
    /// Maps to NSColor.windowBackgroundColor on macOS, UIColor.systemBackground on iOS.
    static var platformWindowBg: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
}

// MARK: - Cross-platform WKWebView wrapper typealias

#if os(macOS)
typealias WKViewRepresentable = NSViewRepresentable
#else
typealias WKViewRepresentable = UIViewRepresentable
#endif

// MARK: - Cross-platform Image typealias

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif
