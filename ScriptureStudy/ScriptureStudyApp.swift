import SwiftUI

@main
struct ScriptureStudyApp: App {
    init() {
        // Seed Advanced → Book Reader toggles based on CPU (arm64 on,
        // Intel off). Idempotent — only runs once per install.
        ArchitectureDefaults.applyIfNeeded()
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    @StateObject private var bibleService  = BibleAPIService()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var myBible       = MyBibleService()
    @StateObject private var notesManager      = NotesManager()
    @StateObject private var bookmarksManager  = BookmarksManager()
    @StateObject private var favouritesStore   = FavouritesStore()
    @StateObject private var calendarStore     = CalendarEventStore()
    @StateObject private var chatHistory       = ChatHistoryManager()
    // 2026-04-21: moved up from ContentView. When declared on ContentView
    // these were reinitialised 7× during cold start because SwiftUI was
    // reconstructing ContentView (via `if readyToShow { ContentView() }`
    // in the WindowGroup body) and each new @StateObject allocated a
    // fresh service instance. Owning them at App level guarantees one
    // shared instance for the app lifetime — matches the other services.
    @StateObject private var bmapsService       = BMapsService()
    @StateObject private var interlinearService = InterlinearService()
    @State private var launchDone:    Bool = false
    @AppStorage("hasSeenOnboarding")  private var hasSeenOnboarding:  Bool = false
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool = true

    @AppStorage("themeID") private var themeID = "light"

    var body: some Scene {
        WindowGroup(id: "main") {
            ZStack {
                // 2026-04-21: ContentView lives in the tree from app launch
                // regardless of splash state. The previous
                // `if readyToShow { ContentView() }` pattern was losing
                // SwiftUI view identity across body re-evaluations (each
                // @Published change on any App-level service caused the
                // WindowGroup body to re-evaluate, and the `if` wrapper
                // wasn't consistently preserving ContentView's identity
                // across those re-evals). Result was ContentView being
                // reconstructed 7× on cold start — which spun up 7
                // LocalBibleViews, 7 CompanionPanels, 7 WKWebViews, and
                // 7 concurrent loadChapter() races. Keeping ContentView
                // unconditionally in the tree with splash overlaid on
                // top gives SwiftUI one stable identity to preserve.
                ContentView()
                // Launch splash — shows first, then optionally onboarding
                if !launchDone {
                    LaunchScreenView {
                        withAnimation { launchDone = true }
                        // Show onboarding after splash if needed
                        // ContentView handles onboarding internally
                    }
                    .zIndex(99)
                    .transition(.opacity)
                }
            }
                .environmentObject(bibleService)
                .environmentObject(ollamaService)
                .environmentObject(myBible)
                .environmentObject(favouritesStore)
                .environmentObject(notesManager)
                .environmentObject(bookmarksManager)
                .environmentObject(calendarStore)
                .environmentObject(chatHistory)
                .environmentObject(bmapsService)
                .environmentObject(interlinearService)
                #if os(macOS)
                .frame(minWidth: 1100, minHeight: 650)
                // Force the main window out of fullSizeContentView style.
                // Without this the reader content (WKWebView in particular)
                // extends up behind the window toolbar, causing the
                // scrollbar to disappear under it and any top-right
                // button (e.g. EPUB bookmark) to render in the invisible
                // region. Matches the treatment already applied to the
                // Settings window below.
                .background(WindowAccessor { window in
                    window.styleMask.remove(.fullSizeContentView)
                })
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
