import SwiftUI

// MARK: - Font Preset

struct FontPreset {
    let name:  String
    let value: String   // empty = system default
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

    // Curated font presets — all available on macOS
    static let curatedFonts: [FontPreset] = [
        FontPreset(name: "System",             value: ""),
        FontPreset(name: "New York",           value: "NewYorkMedium-Regular"),
        FontPreset(name: "Georgia",            value: "Georgia"),
        FontPreset(name: "Palatino",           value: "Palatino-Roman"),
        FontPreset(name: "Baskerville",        value: "Baskerville"),
        FontPreset(name: "Times New Roman",    value: "TimesNewRomanPSMT"),
        FontPreset(name: "Garamond",           value: "Garamond"),
        FontPreset(name: "Avenir",             value: "Avenir-Book"),
    ]

    @EnvironmentObject var ollama: OllamaService
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey: String = ""
    @AppStorage("showGestureHints")    private var showGestureHints:    Bool = true
    @AppStorage("showStatusHints")     private var showStatusHints:     Bool = true
    @AppStorage("showOnboardingAgain") private var showOnboardingAgain: Bool = true
    @AppStorage("autoSummaryEnabled")    private var autoSummaryEnabled:   Bool = true
    @AppStorage("showLaunchAnimation")    private var showLaunchAnimation:  Bool = true
    @AppStorage("detectScriptureRefs")   private var detectScriptureRefs:  Bool = false
    @AppStorage("preCacheEpubPages")     private var preCacheEpubPages:    Bool = false
    @State private var showAPIKey = false
    @AppStorage("themeID")   private var themeID:   String = "light"
    @AppStorage("fontSize")  private var fontSize:  Double = 16
    @AppStorage("fontName")          private var fontName:          String = ""
    @AppStorage("textureOn")        private var textureOn:        Bool   = true
    @AppStorage("textureIntensity")  private var textureIntensity:  Double = 0.6
    @AppStorage("filigreeOn")       private var filigreeOn:       Bool   = true
    @AppStorage("filigreeColor")    private var filigreeColor:    Int    = 0
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    @AppStorage("filigreeIntensity") private var filigreeIntensity: Double = 0.25
    @State private var customFont: String = ""

    @State private var showingKey = false

    var body: some View {
        Form {


            // MARK: - Appearance
            Section("Appearance") {

                // Theme picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 10) {
                        ForEach(AppTheme.all) { theme in
                            ThemeSwatch(theme: theme, isSelected: themeID == theme.id) {
                                themeID = theme.id
                            }
                        }
                    }
                }

                // Text size
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Reading text size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Text("A").font(.system(size: 12)).foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: 12...28, step: 1)
                            .tint(filigreeAccent)
                        Text("A").font(.system(size: 22)).foregroundStyle(.secondary)
                    }

                    // Live preview with current font + theme
                    let theme    = AppTheme.find(themeID)
                    let previewF: Font = fontName.isEmpty ? .system(size: fontSize)
                        : (!fontName.isEmpty
                            ? .custom(fontName, size: fontSize)
                            : .system(size: fontSize))
                    Text("In the beginning God created the heaven and the earth.")
                        .font(previewF)
                        .lineSpacing(4)
                        .foregroundStyle(theme.text)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                }

                // Font picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Font")
                        .font(.subheadline.weight(.medium))

                    // Curated presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SettingsView.curatedFonts, id: \.name) { preset in
                                FontChip(
                                    preset:     preset,
                                    isSelected: fontName == preset.value
                                ) {
                                    fontName     = preset.value
                                    customFont   = preset.value
                                }
                            }
                        }
                    }

                    // Free-type field
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                        TextField("Or type any font name…", text: $customFont)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { fontName = customFont }
                        Button("Apply") { fontName = customFont }
                            .controlSize(.small)
                        if !fontName.isEmpty {
                            Button("Reset") { fontName = ""; customFont = "" }
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !fontName.isEmpty && fontName.isEmpty {
                        Text("Font \u{201C}\(fontName)\u{201D} not found — showing system font.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Any font installed on your Mac can be used.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Texture
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Paper texture", isOn: $textureOn)
                        .font(.subheadline.weight(.medium))

                    if textureOn {
                        HStack(spacing: 10) {
                            Text("Subtle")
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: $textureIntensity, in: 0.2...1.0, step: 0.1)
                            .tint(filigreeAccent)
                            Text("Strong")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Filigree decoration
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Filigree decoration", isOn: $filigreeOn)
                        .font(.subheadline.weight(.medium))

                    if filigreeOn {
                        Text("Colour")
                            .font(.caption).foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(filigreePresets) { preset in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(preset.color.opacity(0.5))
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle().stroke(
                                                filigreeColor == preset.id
                                                    ? Color.primary : Color.secondary.opacity(0.3),
                                                lineWidth: filigreeColor == preset.id ? 2 : 0.5)
                                        )
                                        .onTapGesture { filigreeColor = preset.id }
                                    Text(preset.name.components(separatedBy: " ").last ?? "")
                                        .font(.system(size: 9))
                                        .foregroundStyle(filigreeColor == preset.id ? .primary : .secondary)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Subtle").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $filigreeIntensity, in: 0.1...1.0, step: 0.05)
                        .tint(filigreeAccent)
                            Text("Strong").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - Ollama
            // Claude API section

            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.primary)
                    .frame(height: 1.25)
                Spacer()
            }
            .padding(.vertical, 6)

            Section {
                Toggle("Auto-generate chapter summaries", isOn: $autoSummaryEnabled)
                Text("When enabled, a summary is automatically generated each time you load a chapter in the Bible tab. Turn off to generate summaries manually.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show logo animation on launch", isOn: $showLaunchAnimation)
                Text("Displays the Graphē logo with a pulse animation each time the app opens.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Briefly highlights words linked to Strong's numbers on first load.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Behaviour")
            }

            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.primary)
                    .frame(height: 1.25)
                Spacer()
            }
            .padding(.vertical, 6)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Anthropic API Key")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if !anthropicAPIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
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
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !anthropicAPIKey.isEmpty {
                        Text("Claude Haiku will be used for summaries — faster and more capable than local models.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Optional. When set, Claude AI generates summaries instead of Ollama.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("Get API Key") {
                            #if os(macOS)
                            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
                            #else
                            UIApplication.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
                            #endif
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(filigreeAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)

                        Button("Buy Credits") {
                            #if os(macOS)
                            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/billing")!)
                            #else
                            UIApplication.shared.open(URL(string: "https://console.anthropic.com/settings/billing")!)
                            #endif
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filigreeAccent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(filigreeAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(filigreeAccent.opacity(0.4), lineWidth: 0.5))
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("AI Engine — Claude")
            }


            Section {
                HStack(spacing: 8) {
                    Image(systemName: ollama.ollamaReady
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ollama.ollamaReady ? .green : .red)
                    Text(ollama.ollamaReady
                         ? "Ollama running · \(ollama.availableModels.count) model(s)"
                         : "Ollama not detected")
                    Spacer()
                    Button("Refresh") { Task { await ollama.checkOllama() } }
                        .controlSize(.small)
                }

                if ollama.ollamaReady && !ollama.availableModels.isEmpty {
                    Picker("Model", selection: $ollama.selectedModel) {
                        ForEach(ollama.availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .tint(filigreeAccent)
                }
            } header: {
                Text("AI Engine — Ollama")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ollama runs AI locally on your Mac — free, no account needed.")
                    Link("Download at ollama.com",
                         destination: URL(string: "https://ollama.com")!)
                        .font(.caption)
                }
            }

            // MARK: - Ollama Setup
            Section("Ollama Setup Instructions") {
                VStack(alignment: .leading, spacing: 10) {
                    SetupStep(n: "1", title: "Install Ollama",      detail: "Download from ollama.com")
                    SetupStep(n: "2", title: "Download a model",    code: "ollama pull llama3.2")
                    SetupStep(n: "3", title: "Start Ollama",        code: "ollama serve")
                    SetupStep(n: "4", title: "Tap Refresh above",   detail: "Your model will appear")
                }
                .padding(.vertical, 4)
            }

            // MARK: - Advanced Reading

            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.primary)
                    .frame(height: 1.25)
                Spacer()
            }
            .padding(.vertical, 6)

            Section {
                // Warning banner
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                    Text("These options add extra processing when opening books. They can make pages take noticeably longer to load, especially on large books. Leave them off unless you specifically need them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                Toggle(isOn: $detectScriptureRefs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enrich book text with interactive links")
                            .font(.body)
                        Text("Detects Bible references (e.g. John 3:16) and proper nouns (people, places, events) and makes them tappable. Tap a scripture reference to open it in the Bible tab. Tap a name or place to search Maps or Wikipedia. May slow loading on long chapters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $preCacheEpubPages) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-process books for faster re-reading")
                            .font(.body)
                        Text("Processes each book page the first time you open it and saves the result. Revisiting pages becomes instant, but the first visit takes slightly longer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Advanced — Book Reader")
            }

            // MARK: - About
            Section("About") {
                LabeledContent("Version",   value: "1.0")
                LabeledContent("Scripture", value: "MyBible modules (.sqlite3)")
                LabeledContent("AI",        value: "Ollama (local)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear { customFont = fontName }
        .padding()
    }
}

// MARK: - Font Chip

struct FontChip: View {
    let preset:     FontPreset
    let isSelected: Bool
    let onTap:      () -> Void
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    var displayFont: Font {
        preset.value.isEmpty
            ? .system(size: 13)
            : .custom(preset.value, size: 13)
    }

    var body: some View {
        Text(preset.name)
            .font(displayFont)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected
                ? filigreeAccent.opacity(0.15)
                : Color.platformWindowBg)
            .foregroundStyle(isSelected ? filigreeAccent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected
                    ? filigreeAccent
                    : Color.secondary.opacity(0.3),
                    lineWidth: isSelected ? 1.5 : 0.5))
            .onTapGesture { onTap() }
    }
}

// MARK: - Theme Swatch

struct ThemeSwatch: View {
    let theme:      AppTheme
    let isSelected: Bool
    let onTap:      () -> Void
    @AppStorage("filigreeColor") private var filigreeColor: Int = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.background)
                    .frame(width: 52, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected
                                ? filigreeAccent
                                : Color.secondary.opacity(0.3),
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
                        .font(.system(size: 12))
                        .foregroundStyle(filigreeAccent)
                        .offset(x: 18, y: -14)
                }
            }
            Text(theme.name)
                .font(.system(size: 10))
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
