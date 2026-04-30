import SwiftUI

// MARK: - Font Preset

struct FontPreset {
    let name:  String
    let value: String
}

// MARK: - Theme Definition

struct AppTheme: Identifiable, Equatable {
    let id:         String
    let name:       String
    let background: Color
    let text:       Color
    let secondary:  Color

    static let all: [AppTheme] = [
        AppTheme(id: "light",
                 name: "Light",
                 background: Color(red: 1.0,  green: 1.0,  blue: 1.0),
                 text:       Color(red: 0.05, green: 0.05, blue: 0.05),
                 secondary:  Color(red: 0.4,  green: 0.4,  blue: 0.4)),
        AppTheme(id: "sepia",
                 name: "Sepia",
                 background: Color(red: 0.95, green: 0.91, blue: 0.86),
                 text:       Color(red: 0.22, green: 0.17, blue: 0.12),
                 secondary:  Color(red: 0.48, green: 0.40, blue: 0.32)),
        AppTheme(id: "blush",
                 name: "Blush",
                 background: Color(red: 0.98, green: 0.92, blue: 0.93),
                 text:       Color(red: 0.22, green: 0.12, blue: 0.15),
                 secondary:  Color(red: 0.52, green: 0.36, blue: 0.40)),
        AppTheme(id: "lightgrey",
                 name: "Light Grey",
                 background: Color(red: 0.91, green: 0.91, blue: 0.93),
                 text:       Color(red: 0.1,  green: 0.1,  blue: 0.12),
                 secondary:  Color(red: 0.4,  green: 0.4,  blue: 0.45)),
        AppTheme(id: "charcoal",
                 name: "Charcoal",
                 background: Color(red: 0.2,  green: 0.21, blue: 0.23),
                 text:       Color(red: 0.88, green: 0.88, blue: 0.90),
                 secondary:  Color(red: 0.60, green: 0.60, blue: 0.63)),
    ]

    static func find(_ id: String) -> AppTheme {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

// MARK: - Settings View

struct SettingsView: View {

    static let curatedFonts: [FontPreset] = [
        FontPreset(name: "System",          value: ""),
        FontPreset(name: "New York",        value: "NewYorkMedium-Regular"),
        FontPreset(name: "Georgia",         value: "Georgia"),
        FontPreset(name: "Palatino",        value: "Palatino-Roman"),
        FontPreset(name: "Baskerville",     value: "Baskerville"),
        FontPreset(name: "Times New Roman", value: "TimesNewRomanPSMT"),
        FontPreset(name: "Garamond",        value: "Garamond"),
        FontPreset(name: "Avenir",          value: "Avenir-Book"),
    ]

    @EnvironmentObject var ollama: OllamaService
    @AppStorage("anthropicAPIKey")     private var anthropicAPIKey:     String = ""
    @AppStorage("showGestureHints")    private var showGestureHints:    Bool   = true
    @AppStorage("showStatusHints")     private var showStatusHints:     Bool   = true
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool   = true
    @AppStorage("autoSummaryEnabled")  private var autoSummaryEnabled:  Bool   = false
    @AppStorage("showGlossNotes")      private var showGlossNotes:      Bool   = true
    @AppStorage("strongsOnlyFilter")   private var strongsOnly:          Bool   = false
    @AppStorage("showLaunchAnimation") private var showLaunchAnimation: Bool   = true
    @AppStorage("detectScriptureRefs") private var detectScriptureRefs: Bool   = false
    @AppStorage("preCacheEpubPages")   private var preCacheEpubPages:   Bool   = false
    @AppStorage("themeID")             private var themeID:             String = "light"
    @AppStorage("fontSize")            private var fontSize:            Double = 16
    @AppStorage("fontName")            private var fontName:            String = ""
    @AppStorage("filigreeOn")          private var filigreeOn:          Bool   = true
    @AppStorage("filigreeColor")       private var filigreeColor:       Int    = 0
    @AppStorage("filigreeIntensity")   private var filigreeIntensity:   Double = 0.25
    @AppStorage("epubFolder")          private var epubFolder:          String = ""

    @State private var showAPIKey  = false
    @State private var customFont: String = ""

    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.scripturetstudy.app"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftPanel
                .frame(width: 240)
                .background(Color(NSColor.controlBackgroundColor))
            Divider()
            ScrollView {
                mainSettings
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .frame(minWidth: 480, maxWidth: 560)
            .background(Color.platformWindowBg)
            .tint(filigreeAccentFill)
            Divider()
            rightPanel
                .frame(width: 240)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minHeight: 600)
        .onAppear { customFont = fontName }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Version header — small, lowercase
            Text("version \(appVersion) · build \(buildNumber)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    metaSection("Runtime") {
                        metaRow("macOS", value: {
                            let v = ProcessInfo.processInfo.operatingSystemVersion
                            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
                        }())
                        metaRow("CPU Cores", value: "\(ProcessInfo.processInfo.processorCount)")
                        metaRow("Memory", value: {
                            let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
                            return String(format: "%.0f GB", gb)
                        }())
                        metaRow("Bundle ID", value: bundleID, small: true)
                    }

                    metaSection("Storage") {
                        metaRow("Books Folder", value: epubFolder.isEmpty
                            ? "Not set"
                            : (epubFolder as NSString).lastPathComponent, small: true)
                        metaRow("Theme", value: AppTheme.find(themeID).name)
                        metaRow("Font Size", value: "\(Int(fontSize)) pt")
                    }

                    metaSection("AI") {
                        metaRow("Claude Key", value: anthropicAPIKey.isEmpty ? "Not set" : "Configured")
                        metaRow("Ollama", value: ollama.ollamaReady ? "Running" : "Not running")
                        if ollama.ollamaReady && !ollama.selectedModel.isEmpty {
                            metaRow("Model", value: ollama.selectedModel, small: true)
                        }
                    }

                    metaSection("Module Formats") {
                        metaRow("MyBible", value: ".sqlite3", small: true)
                        metaRow("Books", value: ".epub")
                        metaRow("Documents", value: ".pdf")
                    }

                    Spacer(minLength: 20)

                    Button { resetToDefaults() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                            Text("Reset to Defaults").font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.65, green: 0.15, blue: 0.15).opacity(0.12))
                        .foregroundStyle(Color(red: 0.65, green: 0.15, blue: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(red: 0.65, green: 0.15, blue: 0.15).opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func metaSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            content()
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value)
                .font(small
                      ? .system(size: 10, design: .monospaced)
                      : .system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func resetToDefaults() {
        themeID             = "light"
        fontSize            = 16
        fontName            = ""
        filigreeOn          = true
        filigreeColor       = 0
        filigreeIntensity   = 0.25
        autoSummaryEnabled  = true
        showLaunchAnimation = true
        // Advanced toggles reset to architecture-appropriate defaults:
        // on for Apple Silicon, off for Intel. Keeps behaviour consistent
        // with the one-time bootstrap that runs on first launch.
        #if arch(arm64)
        detectScriptureRefs = true
        preCacheEpubPages   = true
        #else
        detectScriptureRefs = false
        preCacheEpubPages   = false
        #endif
        customFont          = ""
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Logo snug top-left, name to its right
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 44, height: 44)
                    if let path = Bundle.main.path(forResource: "AppIcon_1024", ofType: "png"),
                       let img = NSImage(contentsOfFile: path) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                    } else {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Graphē One")
                        .font(.custom("Baskerville", size: 24))
                        .fontWeight(.semibold)
                        .foregroundStyle(themeID == "charcoal"
                            ? Color(red: 0.45, green: 0.58, blue: 0.45)
                            : Color(red: 0.18, green: 0.32, blue: 0.18))
                        .fixedSize()
                    Text("Graphē One ScriptureStudy Pro™")
                        .font(.custom("Baskerville", size: 16))
                        .foregroundStyle(themeID == "charcoal"
                            ? Color(red: 0.45, green: 0.58, blue: 0.45).opacity(0.70)
                            : Color(red: 0.18, green: 0.32, blue: 0.18).opacity(0.8))
                        .fixedSize()
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(minHeight: 68)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Text("SUPPORT & LINKS")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 6) {

                    supportLinkButton(
                        icon: "cup.and.saucer.fill",
                        title: "Buy Me a Coffee",
                        subtitle: "Support development",
                        color: Color(red: 1.0, green: 0.76, blue: 0.29),
                        url: "https://buymeacoffee.com/richardbillings"
                    )

                    supportLinkButton(
                        icon: "globe",
                        title: "Website",
                        subtitle: "richardbillings.github.io",
                        color: Color(red: 0.659, green: 0.784, blue: 0.878),
                        url: "https://richardbillings.github.io"
                    )

                    supportLinkButton(
                        icon: "envelope.fill",
                        title: "Get in Touch",
                        subtitle: "Send feedback",
                        color: Color(red: 0.20, green: 0.47, blue: 0.95),
                        url: "mailto:support@graphescripture.app"
                    )

                    supportLinkButton(
                        icon: "ant.fill",
                        title: "Report a Bug",
                        subtitle: "GitHub Issues",
                        color: Color(red: 0.8, green: 0.3, blue: 0.3),
                        url: "https://github.com/richardbillings/graphe-scripture/issues"
                    )

                    Divider().padding(.vertical, 4)

                    supportLinkButton(
                        icon: "key.fill",
                        title: "Anthropic Console",
                        subtitle: "Manage API keys",
                        color: Color(red: 0.9, green: 0.5, blue: 0.3),
                        url: "https://console.anthropic.com/settings/keys"
                    )

                    supportLinkButton(
                        icon: "cpu.fill",
                        title: "Ollama",
                        subtitle: "Download local AI",
                        color: Color(red: 0.3, green: 0.6, blue: 0.9),
                        url: "https://ollama.com"
                    )

                    Divider().padding(.vertical, 4)

                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private func supportLinkButton(icon: String, title: String, subtitle: String,
                                   color: Color, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func infoChip(_ label: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary)
            Spacer()
            Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Main Settings (Centre)

    private var sectionDivider: some View {
        HStack {
            Spacer()
            Rectangle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 160, height: 1.5)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var mainSettings: some View {
        Form {
            // MARK: Appearance
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme").font(.subheadline.weight(.medium))
                    HStack(spacing: 10) {
                        ForEach(AppTheme.all) { theme in
                            ThemeSwatch(theme: theme, isSelected: themeID == theme.id) {
                                themeID = theme.id
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Reading text size")
                        Spacer()
                        Text("\(Int(fontSize)) pt").foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Text("A").font(.system(size: 12)).foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: 12...28, step: 1).tint(filigreeAccentFill)
                        Text("A").font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                    let theme = AppTheme.find(themeID)
                    let previewF: Font = fontName.isEmpty ? .system(size: fontSize) : .custom(fontName, size: fontSize)
                    Text("In the beginning God created the heaven and the earth.")
                        .font(previewF).lineSpacing(4).foregroundStyle(theme.text)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Font").font(.subheadline.weight(.medium))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SettingsView.curatedFonts, id: \.name) { preset in
                                FontChip(preset: preset, isSelected: fontName == preset.value) {
                                    fontName = preset.value; customFont = preset.value
                                }
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "textformat").foregroundStyle(.secondary)
                        TextField("Or type any font name…", text: $customFont)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { fontName = customFont }
                        Button("Apply") { fontName = customFont }.controlSize(.small)
                        if !fontName.isEmpty {
                            Button("Reset") { fontName = ""; customFont = "" }
                                .controlSize(.small).foregroundStyle(.secondary)
                        }
                    }
                    Text("Any font installed on your Mac can be used.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Filigree decoration", isOn: $filigreeOn)
                        .font(.subheadline.weight(.medium))
                    if filigreeOn {
                        Text("Colour").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(filigreePresets) { preset in
                                VStack(spacing: 4) {
                                    Circle().fill(preset.color.opacity(0.5))
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(
                                            filigreeColor == preset.id ? Color.primary : Color.secondary.opacity(0.3),
                                            lineWidth: filigreeColor == preset.id ? 2 : 0.5))
                                        .onTapGesture { filigreeColor = preset.id }
                                    Text(preset.name.components(separatedBy: " ").last ?? "")
                                        .font(.system(size: 9))
                                        .foregroundStyle(filigreeColor == preset.id ? .primary : .secondary)
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            Text("Subtle").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $filigreeIntensity, in: 0.1...1.0, step: 0.05).tint(filigreeAccentFill)
                            Text("Strong").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            sectionDivider

            // MARK: Behaviour
            Section("Behaviour") {
                Toggle("Auto-generate chapter summaries", isOn: $autoSummaryEnabled)
                Text("When enabled, a summary is automatically generated each time you load a chapter in the Bible tab.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show logo animation on launch", isOn: $showLaunchAnimation)
                Text("Displays the Graphē One logo with a pulse animation each time the app opens.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show translation gloss notes", isOn: $showGlossNotes)
                Text("Shows a small indicator on verses that contain translator's notes. Tap it to see the original language gloss.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            sectionDivider

            // MARK: Claude API
            Section("AI Engine — Claude") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Anthropic API Key").font(.subheadline.weight(.medium))
                        Spacer()
                        if !anthropicAPIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.system(size: 14))
                        }
                    }
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-...", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Button { showAPIKey.toggle() } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    Text(anthropicAPIKey.isEmpty
                         ? "Optional. When set, Claude AI generates summaries instead of Ollama."
                         : "Claude Haiku will be used for summaries — faster and more capable than local models.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Get API Key") {
                            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(filigreeAccentFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).buttonStyle(.plain)

                        Button("Buy Credits") {
                            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/billing")!)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.95))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(red: 0.20, green: 0.47, blue: 0.95).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(red: 0.20, green: 0.47, blue: 0.95).opacity(0.4), lineWidth: 0.5))
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: Ollama
            Section {
                HStack(spacing: 8) {
                    Image(systemName: ollama.ollamaReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ollama.ollamaReady ? .green : .red)
                    Text(ollama.ollamaReady
                         ? "Ollama running · \(ollama.availableModels.count) model(s)"
                         : "Ollama not detected")
                    Spacer()
                    Button("Refresh") { Task { await ollama.checkOllama() } }.controlSize(.small)
                }
                if ollama.ollamaReady && !ollama.availableModels.isEmpty {
                    Picker("Model", selection: $ollama.selectedModel) {
                        ForEach(ollama.availableModels, id: \.self) { m in Text(m).tag(m) }
                    }.tint(filigreeAccentFill)
                }
            } header: {
                Text("AI Engine — Ollama")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ollama runs AI locally on your Mac — free, no account needed.")
                    Link("Download at ollama.com", destination: URL(string: "https://ollama.com")!).font(.caption)
                }
            }

            Section("Ollama Setup Instructions") {
                VStack(alignment: .leading, spacing: 10) {
                    SetupStep(n: "1", title: "Install Ollama",    detail: "Download from ollama.com")
                    SetupStep(n: "2", title: "Download a model",  code:   "ollama pull llama3.2")
                    SetupStep(n: "3", title: "Start Ollama",      code:   "ollama serve")
                    SetupStep(n: "4", title: "Tap Refresh above", detail: "Your model will appear")
                }.padding(.vertical, 4)
            }

            sectionDivider

            // MARK: Advanced — Book Reader
            Section {
                // Warning shown only on Intel Macs — Apple Silicon users
                // don't see it because the features are effectively free
                // on their machines.
                #if !arch(arm64)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.system(size: 14))
                    Text("Turning these on may make book pages load more slowly on Intel Macs.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
                #endif

                Toggle(isOn: $detectScriptureRefs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enrich book text with interactive links").font(.body)
                        Text("Detects Bible references like \"Rom. 8:28\" or \"John 3:16\" inside your books and turns them into tappable links that open the Bible tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $preCacheEpubPages) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-process books for faster re-reading").font(.body)
                        Text("Processes each page on first open and keeps the result in memory. Later visits to the same chapter load instantly.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Advanced — Book Reader")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Logo Mark (fallback)

struct AppLogoMark: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let s  = size / 60.0
            ctx.withCGContext { cg in
                cg.setFillColor(NSColor(red: 0.62, green: 0.49, blue: 0.24, alpha: 1).cgColor)
                cg.fill(CGRect(x: cx - 4*s, y: cy - 22*s, width: 8*s, height: 44*s))
                cg.fill(CGRect(x: cx - 16*s, y: cy - 14*s, width: 32*s, height: 8*s))
                cg.setFillColor(NSColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 0.9).cgColor)
                let vane = CGMutablePath()
                vane.move(to: CGPoint(x: cx, y: cy - 10*s))
                vane.addCurve(to: CGPoint(x: cx - 5*s, y: cy + 8*s),
                              control1: CGPoint(x: cx - 6*s, y: cy),
                              control2: CGPoint(x: cx - 5*s, y: cy + 4*s))
                vane.addCurve(to: CGPoint(x: cx + 5*s, y: cy + 8*s),
                              control1: CGPoint(x: cx + 5*s, y: cy + 4*s),
                              control2: CGPoint(x: cx + 6*s, y: cy))
                vane.closeSubpath()
                cg.addPath(vane); cg.fillPath()
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Font Chip

struct FontChip: View {
    let preset:     FontPreset
    let isSelected: Bool
    let onTap:      () -> Void
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    var displayFont: Font {
        preset.value.isEmpty ? .system(size: 13) : .custom(preset.value, size: 13)
    }

    var body: some View {
        Text(preset.name)
            .font(displayFont)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? filigreeAccent.opacity(0.15) : Color.platformWindowBg)
            .foregroundStyle(isSelected ? filigreeAccent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? filigreeAccent : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 0.5))
            .onTapGesture { onTap() }
    }
}

// MARK: - Theme Swatch

struct ThemeSwatch: View {
    let theme:      AppTheme
    let isSelected: Bool
    let onTap:      () -> Void
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.background).frame(width: 52, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? filigreeAccent : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 2 : 0.5))
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i == 0 ? theme.text : theme.secondary)
                            .frame(width: i == 0 ? 30 : 22, height: 2)
                    }
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(filigreeAccent)
                        .offset(x: 18, y: -14)
                }
            }
            Text(theme.name).font(.system(size: 10))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .onTapGesture { onTap() }
    }
}

// MARK: - Setup Step

struct SetupStep: View {
    let n:      String
    let title:  String
    var detail: String = ""
    var code:   String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "\(n).circle.fill").font(.headline)
            if !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            if !code.isEmpty {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.platformWindowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
            }
        }
    }
}
