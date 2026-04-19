import SwiftUI

@main
struct ScriptureStudyApp: App {
    init() {
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    @StateObject private var bibleService  = BibleAPIService()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var myBible       = MyBibleService()
    @StateObject private var notesManager      = NotesManager()
    @StateObject private var bookmarksManager  = BookmarksManager()
    @StateObject private var calendarStore     = CalendarEventStore()
    @State private var launchDone:    Bool = false
    @State private var readyToShow:   Bool = false
    @AppStorage("hasSeenOnboarding")  private var hasSeenOnboarding:  Bool = false
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool = true

    @AppStorage("themeID") private var themeID = "light"

    var body: some Scene {
        WindowGroup(id: "main") {
            ZStack {
                // Only render ContentView once launch splash is fully done
                if readyToShow {
                    ContentView()
                }
                // Launch splash — shows first, then optionally onboarding
                if !launchDone {
                    LaunchScreenView {
                        withAnimation { launchDone = true }
                        // Show onboarding after splash if needed
                        // ContentView handles onboarding internally
                        readyToShow = true
                    }
                    .zIndex(99)
                }
            }
                .environmentObject(bibleService)
                .environmentObject(ollamaService)
                .environmentObject(myBible)
                .environmentObject(notesManager)
                .environmentObject(bookmarksManager)
                .environmentObject(calendarStore)
                #if os(macOS)
                .frame(minWidth: 1100, minHeight: 650)
                #endif
                .preferredColorScheme(
                    themeID == "charcoal" ? .dark : .light
                )
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            NoteCommands()
        }

        #if os(macOS)
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(ollamaService)
                .background(WindowAccessor { window in
                    window.backgroundColor = NSColor.windowBackgroundColor
                    window.isOpaque = true
                    // Remove the sidebar tint that macOS applies to the leftmost pane
                    window.styleMask.remove(.fullSizeContentView)
                    for view in window.contentView?.subviews ?? [] {
                        view.wantsLayer = true
                        if let splitView = view as? NSSplitView {
                            for item in splitView.subviews {
                                item.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                            }
                        }
                    }
                })
        }
        #endif
    }
}

#if os(macOS)
/// Provides access to the NSWindow hosting this SwiftUI view.
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                self.callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.callback(window)
            }
        }
    }
}
#endif
