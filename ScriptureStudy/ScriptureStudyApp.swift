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
    @StateObject private var notesManager      = NotesManager(
        storageDirectoryOverride: AppRuntimeContext.isRunningTests ? AppRuntimeContext.testNotesDirectory : nil,
        remoteSyncEnabled: !AppRuntimeContext.isRunningTests
    )
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
    #if os(macOS)
    @StateObject private var mainWindowState = MainWindowStateController()
    #endif
    @State private var launchDone:    Bool = false
    @AppStorage("hasSeenOnboarding")  private var hasSeenOnboarding:  Bool = false
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool = true

    @AppStorage("themeID") private var themeID = "light"

    @ViewBuilder
    private var mainRootView: some View {
        Group {
            if AppRuntimeContext.isRunningTests {
                Color.clear
            } else {
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
                        }
                        .zIndex(99)
                        .transition(.opacity)
                    }
                }
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
        .background(WindowAccessor { window in
            window.styleMask.remove(.fullSizeContentView)
            mainWindowState.configure(window: window)
        })
        #endif
        .preferredColorScheme(
            themeID == "charcoal" ? .dark : .light
        )
    }

    var body: some Scene {
        #if os(macOS)
        Window("ScriptureStudy", id: "main") {
            mainRootView
        }
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands {
            NoteCommands()
        }
        #else
        WindowGroup(id: "main") {
            mainRootView
        }
        .commands {
            NoteCommands()
        }
        #endif

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
final class MainWindowStateController: ObservableObject {
    private let defaults = UserDefaults.standard
    private let fullscreenKey = "mainWindowShouldRestoreFullscreen"
    private var observedWindow: NSWindow?
    private var notificationTokens: [NSObjectProtocol] = []
    private var didApplyInitialFullscreen = false

    func configure(window: NSWindow) {
        guard observedWindow !== window else {
            applyInitialFullscreenIfNeeded(to: window)
            return
        }

        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        observedWindow = window
        didApplyInitialFullscreen = false

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.defaults.set(true, forKey: self?.fullscreenKey ?? "")
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.defaults.set(false, forKey: self?.fullscreenKey ?? "")
            }
        )

        applyInitialFullscreenIfNeeded(to: window)
    }

    private func applyInitialFullscreenIfNeeded(to window: NSWindow) {
        guard !didApplyInitialFullscreen else { return }
        didApplyInitialFullscreen = true
        guard defaults.bool(forKey: fullscreenKey) else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        DispatchQueue.main.async {
            guard self.observedWindow === window else { return }
            guard !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }
}

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
