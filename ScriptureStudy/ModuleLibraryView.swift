import SwiftUI
import SQLite3

struct ModuleLibraryView: View {
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    @EnvironmentObject var myBible: MyBibleService
    @State private var showingESwordPicker = false
    @State private var showingImportPicker = false
    @State private var importStatus:   String? = nil
    @State private var importIsError:  Bool    = false
    @State private var searchText:     String  = ""
    @State private var moduleMetadata: [String: String] = [:]
    @State private var selectedTab:    String  = "All"

    // MARK: - Computed module lists

    var bibles:       [MyBibleModule] { myBible.modules.filter { $0.type == .bible } }
    var commentaries: [MyBibleModule] { myBible.modules.filter { $0.type == .commentary } }
    var crossRefMods: [MyBibleModule] { myBible.modules.filter { $0.type == .crossRef || $0.type == .crossRefNative } }
    var devotionals:  [MyBibleModule] { myBible.modules.filter { $0.type == .devotional } }
    var dictMods:     [MyBibleModule] { myBible.modules.filter { $0.type == .dictionary } }
    var encyclopediaMods: [MyBibleModule] { myBible.modules.filter { $0.type == .encyclopedia } }
    var strongsMods:  [MyBibleModule] { myBible.modules.filter { $0.type == .strongs } }
    var readingPlans: [MyBibleModule] { myBible.modules.filter { $0.type == .readingPlan } }
    var others:       [MyBibleModule] { myBible.modules.filter { $0.type == .unknown || $0.type == .subheadings || $0.type == .wordIndex } }
    var favourites:   [MyBibleModule] { myBible.modules.filter { !myBible.hiddenModules.contains($0.filePath) } }

    // Common abbreviation expansions for search
    private let searchAliases: [String: [String]] = [
        "kjv":  ["king james"],
        "niv":  ["new international"],
        "esv":  ["english standard"],
        "nasb": ["new american standard"],
        "nlt":  ["new living"],
        "nkjv": ["new king james"],
        "asv":  ["american standard"],
        "rsv":  ["revised standard"],
        "csb":  ["christian standard"],
        "nt":   ["new testament"],
        "ot":   ["old testament"],
        "lxx":  ["septuagint"],
        "tsk":  ["treasury of scripture", "treasury scripture"],
        "bbe":  ["bible in basic english"],
        "web":  ["world english"],
        "ylt":  ["youngs literal"],
    ]

    func filtered(_ modules: [MyBibleModule]) -> [MyBibleModule] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return modules }
        // Expand abbreviations
        var terms = [q]
        if let expansions = searchAliases[q] { terms += expansions }
        return modules.filter { m in
            let name = m.name.lowercased()
            let lang = m.language.lowercased()
            let meta = (moduleMetadata[m.filePath] ?? "").lowercased()
            return terms.contains { t in
                name.contains(t) || lang.contains(t) || meta.contains(t)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if myBible.modulesFolder.isEmpty {
                    emptyState
                } else if myBible.isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView("Scanning modules…")
                        Spacer()
                    }
                } else if myBible.modules.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "tray.fill")
                            .font(.largeTitle).foregroundStyle(.quaternary)
                        Text("No MyBible modules found in that folder.")
                            .foregroundStyle(.secondary)
                        Button("Choose Different Folder") { pickFolder() }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(filigreeAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                } else {
                    moduleList
                }
            }
            .navigationTitle("Module Archives")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    #if os(macOS)
                    HelpButton(page: "library")
                    #endif
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { pickFolder() } label: {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }
                }
                ToolbarItem {
                    Button { showingImportPicker = true } label: {
                        Label("Import Files", systemImage: "plus.circle")
                    }
                    .help("Copy .sqlite3 module files into your modules folder")
                    .disabled(myBible.modulesFolder.isEmpty)
                }
                ToolbarItem {
                    Button { showingESwordPicker = true } label: {
                        Label("Import e-Sword", systemImage: "square.and.arrow.down")
                    }
                    .help("Import e-Sword/MySword module")
                    .disabled(myBible.modulesFolder.isEmpty)
                }
                ToolbarItem {
                    Button { Task { await myBible.scanModules() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let status = importStatus {
                    HStack(spacing: 8) {
                        Image(systemName: importIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(importIsError ? .red : .green)
                        Text(status).font(.caption.weight(.medium))
                        Spacer()
                        Button { importStatus = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: importStatus)
            .fileImporter(
                isPresented: $showingESwordPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importESword(url: url)
                case .failure(let error):
                    importStatus  = "Failed to open file: \(error.localizedDescription)"
                    importIsError = true
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): importModuleFiles(urls)
                case .failure(let error):
                    importStatus  = "Failed: \(error.localizedDescription)"
                    importIsError = true
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 56)).foregroundStyle(.quaternary)
            Text("No modules folder selected")
                .font(.title2.weight(.semibold))
            Text("Point the app to the folder containing\nyour MyBible .sqlite3 module files.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choose Modules Folder") { pickFolder() }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(filigreeAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .padding()
    }

    // MARK: - Tab definitions (alphabetical)

    private struct ModuleTab {
        let id: String; let label: String
    }

    private var allTabs: [ModuleTab] {
        var tabs = [ModuleTab(id: "All", label: "All")]
        let pairs: [(String, [MyBibleModule])] = [
            ("Bibles",           bibles),
            ("Commentaries",     commentaries),
            ("Cross-References", crossRefMods),
            ("Devotionals",      devotionals),
            ("Dictionaries",     dictMods),
            ("Encyclopedias",    encyclopediaMods),
            ("Lexicons",         strongsMods),
            ("Other",            others),
            ("Reading Plans",    readingPlans),
        ]
        for (label, modules) in pairs where !modules.isEmpty {
            tabs.append(ModuleTab(id: label, label: "\(label) (\(modules.count))"))
        }
        return tabs
    }

    private func modulesForTab() -> [MyBibleModule] {
        switch selectedTab {
        case "Bibles":           return filtered(bibles)
        case "Commentaries":     return filtered(commentaries)
        case "Cross-References": return filtered(crossRefMods)
        case "Devotionals":      return filtered(devotionals)
        case "Dictionaries":     return filtered(dictMods)
        case "Encyclopedias":    return filtered(encyclopediaMods)
        case "Lexicons":         return filtered(strongsMods)
        case "Other":            return filtered(others)
        case "Reading Plans":    return filtered(readingPlans)
        default:                 return filtered(myBible.modules)
        }
    }

    // MARK: - Module list

    private var moduleList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search modules, authors, languages…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.platformWindowBg)

            Divider()

            // Tab bar
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTabs, id: \.id) { tab in
                            Button { selectedTab = tab.id } label: {
                                Text(tab.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(selectedTab == tab.id
                                                ? filigreeAccent
                                                : filigreeAccent.opacity(0.1))
                                    .foregroundStyle(selectedTab == tab.id ? .white : filigreeAccent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
                HStack {
                    LinearGradient(colors: [Color.platformWindowBg, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 20)
                    Spacer()
                }
                .allowsHitTesting(false)
                HStack {
                    Spacer()
                    LinearGradient(colors: [.clear, Color.platformWindowBg],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 20)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 36)

            Divider()

            let modules = modulesForTab()
            if modules.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty
                         ? "No modules in this category"
                         : "No results for \u{201C}\(searchText)\u{201D}")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(modules) { module in moduleRow(for: module) }
                    if selectedTab == "All" {
                        Section {
                            HStack {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text(myBible.modulesFolder)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button("Change") { pickFolder() }.controlSize(.small)
                            }
                        } header: { Text("Modules Folder") }
                    }
                }
            }
        }
        .onAppear { loadMetadata() }
        .onChange(of: myBible.modules) { _ in loadMetadata() }
    }

    @ViewBuilder
    private func moduleRow(for module: MyBibleModule) -> some View {
        switch module.type {
        case .crossRef, .crossRefNative:
            DictionaryModuleRow(
                module: module,
                isCrossRef: myBible.selectedCrossRef?.filePath == module.filePath,
                isStrongs: false, isDict: false,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSetCrossRef: { myBible.selectedCrossRef = module },
                onSetStrongs: {}, onSetDictionary: {},
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        case .dictionary:
            DictionaryModuleRow(
                module: module,
                isCrossRef: false, isStrongs: false,
                isDict: myBible.selectedDictionary?.filePath == module.filePath,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSetCrossRef: {}, onSetStrongs: {},
                onSetDictionary: { myBible.selectedDictionary = module },
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        case .encyclopedia:
            DictionaryModuleRow(
                module: module,
                isCrossRef: false, isStrongs: false,
                isDict: myBible.selectedEncyclopedia?.filePath == module.filePath,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSetCrossRef: {}, onSetStrongs: {},
                onSetDictionary: { myBible.selectedEncyclopedia = module },
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        case .strongs:
            DictionaryModuleRow(
                module: module,
                isCrossRef: false,
                isStrongs: myBible.selectedStrongs?.filePath == module.filePath,
                isDict: false,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSetCrossRef: {},
                onSetStrongs: { myBible.selectedStrongs = module },
                onSetDictionary: {},
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        case .bible:
            ModuleRow(
                module: module,
                isSelected: myBible.selectedBible == module,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSelect: { myBible.selectedBible = module },
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        case .devotional:
            ModuleRow(
                module: module,
                isSelected: myBible.selectedDevotional?.filePath == module.filePath,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSelect: { myBible.selectedDevotional = module },
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        default:
            ModuleRow(
                module: module,
                isSelected: false,
                isHidden: myBible.hiddenModules.contains(module.filePath),
                onSelect: {},
                onToggleVisibility: { myBible.toggleHidden(module) },
                onDelete: { deleteModule(module) }
            )
        }
    }


    // MARK: - Section header with bulk toggle

    private func allHidden(_ modules: [MyBibleModule]) -> Bool {
        modules.allSatisfy { myBible.hiddenModules.contains($0.filePath) }
    }

    private func toggleAll(_ modules: [MyBibleModule]) {
        if allHidden(modules) {
            modules.forEach { myBible.hiddenModules.remove($0.filePath) }
        } else {
            modules.forEach { myBible.hiddenModules.insert($0.filePath) }
        }
        myBible.saveHiddenModules()
    }

    private func sectionHeader(_ title: String, modules: [MyBibleModule]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                toggleAll(modules)
            } label: {
                Text(allHidden(modules) ? "Show All" : "Hide All")
                    .font(.caption)
                    .foregroundStyle(filigreeAccent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Metadata search loader

    private func loadMetadata() {
        let modules = myBible.modules
        let paths   = modules.map { $0.filePath }
        Task.detached(priority: .background) {
            var result: [String: String] = [:]
            for (i, path) in paths.enumerated() {
                var db: OpaquePointer?
                guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
                else { continue }
                defer { sqlite3_close(db) }
                var blob = ""
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT value FROM info", -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let v = sqlite3_column_text(stmt, 0) {
                            blob += " " + String(cString: v)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                result[path] = blob
                _ = i // suppress warning
            }
            let final = result
            await MainActor.run { moduleMetadata = final }
        }
    }

    // MARK: - e-Sword import

    private func importESword(url: URL) {
        let ext = url.pathExtension.lowercased()
        let supported = ["bblx","cmtx","dctx","lexdbtx","topx","resx","devotx","mybible"]
        guard supported.contains(ext) else {
            importStatus  = "Unsupported: .\(ext)"
            importIsError = true
            return
        }
        importStatus  = "Converting \(url.lastPathComponent)…"
        importIsError = false
        #if os(macOS)
        let folder  = myBible.modulesFolder
        let srcPath = url.path
        DispatchQueue.global(qos: .userInitiated).async {
            let script = Bundle.main.path(forResource: "esword_converter", ofType: "py") ?? ""
            let task   = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments     = [script, srcPath, folder]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = pipe
            do {
                try task.run(); task.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let ok     = task.terminationStatus == 0
                DispatchQueue.main.async {
                    if ok {
                        importStatus  = "\(url.lastPathComponent) imported"
                        importIsError = false
                        Task { await myBible.scanModules() }
                    } else {
                        let last = output.components(separatedBy: "\n").filter { !$0.isEmpty }.last ?? "Unknown error"
                        importStatus  = "Import failed: \(last)"
                        importIsError = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    importStatus  = "Could not run converter: \(error.localizedDescription)"
                    importIsError = true
                }
            }
        }
        #endif
    }

    // MARK: - Folder picker

    private func importModuleFiles(_ urls: [URL]) {
        let destFolder = URL(fileURLWithPath: myBible.modulesFolder)
        var copied = 0
        var skipped = 0
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let ext = url.pathExtension.lowercased()
            guard ext == "sqlite3" || ext == "sqlite" || ext == "db" else {
                skipped += 1
                continue
            }
            let dest = destFolder.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                copied += 1
            } catch {
                importStatus  = "Error copying \(url.lastPathComponent): \(error.localizedDescription)"
                importIsError = true
                return
            }
        }
        if copied > 0 {
            importStatus  = "\(copied) module\(copied == 1 ? "" : "s") imported"
            importIsError = false
            Task { await myBible.scanModules() }
        } else {
            importStatus  = skipped > 0 ? "No .sqlite3 files selected" : "Nothing imported"
            importIsError = true
        }
    }

    private func deleteModule(_ module: MyBibleModule) {
        let url = URL(fileURLWithPath: module.filePath)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        Task { await myBible.scanModules() }
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            myBible.modulesFolder = url.path
        }
        #endif
    }
}

// MARK: - Favourite Row

struct FavouriteRow: View {
    let module:         MyBibleModule
    @ObservedObject var myBible: MyBibleService
    let filigreeAccent: Color
    var onDelete:       (() -> Void)? = nil

    @State private var showDeleteAlert = false

    var typeLabel: String {
        switch module.type {
        case .bible:                   return "Bible"
        case .commentary:              return "Commentary"
        case .crossRef, .crossRefNative: return "Cross-Ref"
        case .devotional:              return "Devotional"
        case .dictionary:              return "Dictionary"
        case .encyclopedia:            return "Encyclopedia"
        case .strongs:                 return "Lexicon"
        case .readingPlan:             return "Plan"
        case .subheadings:             return "Subheadings"
        case .wordIndex:               return "Word Index"
        case .unknown:                 return "Other"
        }
    }

    var typeColor: Color {
        switch module.type {
        case .bible:                   return .blue
        case .commentary:              return .orange
        case .crossRef, .crossRefNative: return .teal
        case .devotional:              return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .dictionary:              return .green
        case .encyclopedia:            return .orange
        case .strongs:                 return .purple
        case .readingPlan:             return Color(red: 0.3, green: 0.6, blue: 0.4)
        case .subheadings:             return .secondary
        case .wordIndex:               return .secondary
        case .unknown:                 return .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(module.name)
                .font(.body)
                .lineLimit(1)
            Spacer()
            Text(typeLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(typeColor.opacity(0.8))
                .clipShape(Capsule())
            // Eye toggle
            Button {
                myBible.toggleHidden(module)
            } label: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(filigreeAccent)
            }
            .buttonStyle(.plain)
            .help("Hide this module from all pickers and dropdowns")
            if onDelete != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this module")
                .alert("Delete Module", isPresented: $showDeleteAlert) {
                    Button("Delete", role: .destructive) { onDelete?() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete this resource! Do you want to continue?")
                }
            }
        }
    }
}

// MARK: - Module Row

struct ModuleRow: View {
    let module:             MyBibleModule
    let isSelected:         Bool
    let isHidden:           Bool
    let onSelect:           () -> Void
    let onToggleVisibility: () -> Void
    var onDelete:           (() -> Void)? = nil

    @State private var showDeleteAlert = false
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    var icon: String {
        switch module.type {
        case .bible:          return "book.fill"
        case .commentary:     return "text.quote"
        case .crossRef, .crossRefNative: return "arrow.triangle.branch"
        case .devotional:     return "book.closed.fill"
        case .readingPlan:    return "calendar"
        case .strongs:        return "h.square.fill"
        case .dictionary:     return "character.book.closed.fill"
        case .encyclopedia:   return "books.vertical.fill"
        case .subheadings:    return "list.bullet.indent"
        case .wordIndex:      return "magnifyingglass"
        case .unknown:        return "doc.fill"
        }
    }

    var iconColor: Color {
        switch module.type {
        case .bible:          return .blue
        case .commentary:     return .orange
        case .crossRef, .crossRefNative: return .teal
        case .devotional:     return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .readingPlan:    return Color(red: 0.3, green: 0.6, blue: 0.4)
        case .strongs:        return .purple
        case .dictionary:     return .green
        case .encyclopedia:   return .orange
        case .subheadings:    return .secondary
        case .wordIndex:      return .secondary
        case .unknown:        return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isHidden ? Color.secondary.opacity(0.4) : iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isHidden ? .secondary : .primary)
                Text(module.language.uppercased())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // Type badge
            Text(module.type.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(iconColor.opacity(isHidden ? 0.3 : 0.8))
                .clipShape(Capsule())
            Button { onToggleVisibility() } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? Color.secondary.opacity(0.5) : filigreeAccent)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            if module.type == .bible {
                Button(isSelected ? "Active" : "Use") { onSelect() }
                    .controlSize(.small).buttonStyle(.bordered).disabled(isSelected)
            }
            if onDelete != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this module")
                .alert("Delete Module", isPresented: $showDeleteAlert) {
                    Button("Delete", role: .destructive) { onDelete?() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete this resource! Do you want to continue?")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if module.type == .bible { onSelect() } }
    }
}

// MARK: - Dictionary Module Row

struct DictionaryModuleRow: View {
    let module:             MyBibleModule
    let isCrossRef:         Bool
    let isStrongs:          Bool
    let isDict:             Bool
    let isHidden:           Bool
    let onSetCrossRef:      () -> Void
    let onSetStrongs:       () -> Void
    let onSetDictionary:    () -> Void
    let onToggleVisibility: () -> Void
    var onDelete:           (() -> Void)? = nil

    @State private var showDeleteAlert = false
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: (module.type == .crossRef || module.type == .crossRefNative) ? "arrow.triangle.branch" :
                              module.type == .strongs ? "h.square.fill" : "character.book.closed.fill")
                .foregroundStyle(isHidden ? Color.secondary.opacity(0.4) :
                                 (module.type == .crossRef || module.type == .crossRefNative) ? Color.teal :
                                 module.type == .strongs ? Color.purple : Color.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name).font(.body).foregroundStyle(isHidden ? .secondary : .primary)
                Text(module.language.uppercased()).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // Always show type badge
            let badgeLabel = (module.type == .crossRef || module.type == .crossRefNative) ? "Cross-Ref" :
                              module.type == .strongs ? "Lexicon" :
                              module.type == .encyclopedia ? "Encyclopedia" : "Dictionary"
            let badgeColor: Color = (module.type == .crossRef || module.type == .crossRefNative) ? .teal :
                                     module.type == .strongs ? .purple :
                                     module.type == .encyclopedia ? .orange : .green
            Text(badgeLabel)
                .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(badgeColor.opacity(isHidden ? 0.3 : 0.8))
                .clipShape(Capsule())
            // Active indicator (checkmark when selected)
            if isCrossRef || isStrongs || isDict {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
            }
            Button { onToggleVisibility() } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? Color.secondary.opacity(0.5) : filigreeAccent)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            Menu("Set as…") {
                if module.type == .crossRef || module.type == .crossRefNative {
                    Button("Default Cross-References module") { onSetCrossRef() }
                }
                if module.type == .strongs {
                    Button("Default Strong's module") { onSetStrongs() }
                }
                if module.type == .dictionary {
                    Button("Default Dictionary module") { onSetDictionary() }
                }
            }
            .font(.caption).controlSize(.small).buttonStyle(.bordered)
            if onDelete != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this module")
                .alert("Delete Module", isPresented: $showDeleteAlert) {
                    Button("Delete", role: .destructive) { onDelete?() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete this resource! Do you want to continue?")
                }
            }
        }
    }
}
