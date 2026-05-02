//
//  InterlinearView.swift
//  ScriptureStudy
//
//  Full-chapter interlinear display.
//  NT: English → Greek → morphology → Strong's number
//  OT: Hebrew → English → Strong's number  (right-to-left aware)
//

import SwiftUI

struct InterlinearView: View {
    let bookNumber:  Int
    let chapter:     Int
    let syncedVerse: Int

    @EnvironmentObject var myBible:         MyBibleService
    @EnvironmentObject var interlinearSvc:  InterlinearService

    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var theme:              AppTheme { AppTheme.find(themeID) }
    var accent:             Color    { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }
    var filigreeAccentFill: Color    { resolvedFiligreeAccentFill(colorIndex: filigreeColor, themeID: themeID) }

    @State private var verses:          [InterlinearVerse] = []
    @State private var isLoading:       Bool               = false
    @State private var selectedStrongs: String             = ""
    @State private var strongsEntry:    StrongsEntry?      = nil
    @State private var isLoadingEntry:  Bool               = false

    private var isOT: Bool { bookNumber < 470 }

    private var languageFilteredModules: [InterlinearModule] {
        let scriptMatched = interlinearSvc.modules.filter { $0.isRTL == isOT }
        let filter = myBible.selectedLanguageFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !filter.isEmpty, filter != "all" else { return scriptMatched }
        let languageMatched = scriptMatched.filter { $0.supportsLanguage(filter) }
        return languageMatched.isEmpty ? scriptMatched : languageMatched
    }

    private var activeModule: InterlinearModule? {
        let selected = isOT ? interlinearSvc.selectedOT : interlinearSvc.selectedNT
        if let selected, languageFilteredModules.contains(selected) {
            return selected
        }
        return languageFilteredModules.first
    }

    private var availableVerseNumbers: Set<Int> {
        Set(verses.map(\.verse))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Module picker bar
            moduleBar

            Divider()

            if activeModule == nil {
                emptyState(
                    icon: "character.book.closed",
                    message: isOT
                        ? "No Hebrew interlinear module found in your modules folder.\nAdd IHOT or similar."
                        : "No Greek interlinear module found in your modules folder.\nAdd iESVTH or similar."
                )
            } else if isLoading {
                VStack { Spacer(); ProgressView("Loading…"); Spacer() }
                    .frame(maxWidth: .infinity).background(theme.background)
            } else if verses.isEmpty {
                emptyState(icon: "book", message: "Load a chapter in the Bible panel")
            } else {
                ZStack(alignment: .bottom) {
                    chapterView
                    if !selectedStrongs.isEmpty {
                        InterlinearStrongsCard(
                            strongsNum:  selectedStrongs,
                            entry:       strongsEntry,
                            isLoading:   isLoadingEntry,
                            accent:      accent,
                            theme:       theme,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedStrongs = ""; strongsEntry = nil
                                }
                            },
                            onFullEntry: {
                                // Switch companion panel to Dictionaries tab
                                NotificationCenter.default.post(
                                    name: Notification.Name("strongsTapped"),
                                    object: nil,
                                    userInfo: ["number": selectedStrongs, "bookNumber": bookNumber]
                                )
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(theme.background)
        .onAppear { loadVerses() }
        .onChange(of: bookNumber)  { selectedStrongs = ""; loadVerses() }
        .onChange(of: chapter)     { selectedStrongs = ""; loadVerses() }
        .onChange(of: interlinearSvc.selectedOT) { loadVerses() }
        .onChange(of: interlinearSvc.selectedNT) { loadVerses() }
        .onChange(of: myBible.selectedLanguageFilter) {
            selectedStrongs = ""
            loadVerses()
        }
    }

    // MARK: - Module bar

    private var moduleBar: some View {
        HStack(spacing: 8) {
            Text(isOT ? "Hebrew" : "Greek")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Spacer()

            // Module picker
            let candidates = languageFilteredModules
            if candidates.count > 1 {
                Menu {
                    ForEach(candidates) { mod in
                        Button(moduleMenuLabel(for: mod)) {
                            if isOT { interlinearSvc.selectedOT = mod }
                            else    { interlinearSvc.selectedNT = mod }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeModule.map(moduleButtonLabel(for:)) ?? "None")
                            .font(.caption).foregroundStyle(theme.text).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8)).foregroundStyle(accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)
            } else if let mod = activeModule {
                Text(moduleButtonLabel(for: mod))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(theme.background)
    }

    private func moduleButtonLabel(for module: InterlinearModule) -> String {
        let title = module.name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false ? title! : module.name)
        let linked = module.hyperlinkLanguages.isEmpty ? module.language.uppercased() : module.hyperlinkLanguages
        return "\(resolvedTitle) [\(linked)]"
    }

    private func moduleMenuLabel(for module: InterlinearModule) -> String {
        "\(moduleButtonLabel(for: module)) • \(module.fileStem)"
    }

    // MARK: - Chapter view

    private var chapterView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(verses) { interlinearVerse in
                        let isSynced = syncedVerse > 0 && interlinearVerse.verse == syncedVerse
                        VStack(alignment: .leading, spacing: 8) {
                            if isOT {
                                HStack {
                                    Spacer(minLength: 0)
                                    verseBadge(for: interlinearVerse.verse, isSynced: isSynced)
                                }

                                RTLFlowLayout(hSpacing: 6, vSpacing: 8) {
                                    ForEach(interlinearVerse.tokens) { token in
                                        tokenCell(for: token)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                verseBadge(for: interlinearVerse.verse, isSynced: isSynced)

                                FlowLayout(hSpacing: 6, vSpacing: 8) {
                                    ForEach(interlinearVerse.tokens) { token in
                                        tokenCell(for: token)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(isSynced ? accent.opacity(0.12) : Color.clear)
                        .overlay {
                            if isSynced {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(accent.opacity(0.30), lineWidth: 1)
                            }
                        }
                        .id(interlinearVerse.verse)

                        Divider().padding(isOT ? .trailing : .leading, 12)
                    }

                    Spacer().frame(height: 20)
                }
            }
            .onChange(of: syncedVerse) { _, v in
                if v > 0, availableVerseNumbers.contains(v) {
                    DispatchQueue.main.async {
                        proxy.scrollTo(v, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func verseBadge(for verse: Int, isSynced: Bool) -> some View {
        Text("\(verse)")
            .font(.system(size: isSynced ? 11 : 10, weight: isSynced ? .heavy : .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, isSynced ? 9 : 7).padding(.vertical, isSynced ? 3 : 2)
            .background(isSynced ? filigreeAccentFill : filigreeAccentFill.opacity(0.5), in: Capsule())
            .overlay {
                if isSynced {
                    Capsule()
                        .stroke(accent.opacity(0.35), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func tokenCell(for token: InterlinearToken) -> some View {
        let isSelected = token.strongsNum == selectedStrongs
        InterlinearWordCell(
            token: token,
            isOT: isOT,
            isSelected: isSelected,
            accent: accent,
            theme: theme
        )
        .onTapGesture { tapped(token) }
    }

    private func tapped(_ token: InterlinearToken) {
        guard !token.strongsNum.isEmpty else { return }
        // Deselect if tapping the same word again
        if selectedStrongs == token.strongsNum {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedStrongs = ""; strongsEntry = nil
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedStrongs = token.strongsNum
            strongsEntry    = nil
            isLoadingEntry  = true
        }
        guard let module = myBible.selectedStrongs else {
            isLoadingEntry = false; return
        }
        let num = token.strongsNum
        let ot  = isOT
        Task {
            let entry = await myBible.lookupStrongs(module: module, number: num, isOldTestament: ot)
            await MainActor.run {
                strongsEntry   = entry
                isLoadingEntry = false
            }
        }
    }

    private func loadVerses() {
        guard let module = activeModule else { verses = []; return }
        isLoading = true
        let bn = bookNumber
        let ch = chapter
        Task {
            let result = await interlinearSvc.fetchVerses(module: module, bookNumber: bn, chapter: ch)
            await MainActor.run { verses = result; isLoading = false }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.quaternary)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity).background(theme.background)
    }
}

private struct RTLFlowLayout: Layout {
    var hSpacing: CGFloat = 6
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + vSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.maxX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x - size.width < bounds.minX, x < bounds.maxX {
                y += rowHeight + vSpacing
                x = bounds.maxX
                rowHeight = 0
            }

            x -= size.width
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x -= hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Inline Strong's card

private struct InterlinearStrongsCard: View {
    let strongsNum:  String
    let entry:       StrongsEntry?
    let isLoading:   Bool
    let accent:      Color
    let theme:       AppTheme
    var onClose:     () -> Void
    var onFullEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 32, height: 3)
                .frame(maxWidth: .infinity)
                .padding(.top, 8).padding(.bottom, 6)

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 20)
            } else if let e = entry {
                // Header row
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(strongsNum)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(accent, in: Capsule())
                            if !e.lexeme.isEmpty {
                                Text(e.lexeme)
                                    .font(.system(size: 18))
                                    .foregroundStyle(theme.text)
                            }
                            if !e.transliteration.isEmpty {
                                Text(e.transliteration)
                                    .font(.system(size: 12).italic())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !e.pronunciation.isEmpty {
                            Text(e.pronunciation)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.bottom, 8)

                Divider()

                // Definition
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !e.shortDefinition.isEmpty || !e.strongsDefinition.isEmpty {
                            Text("Strong's")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(e.strongsDefinition.isEmpty ? e.shortDefinition : e.strongsDefinition)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.text)
                        }
                        if !e.derivation.isEmpty {
                            Text("Derivation")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(e.derivation)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.text)
                        }
                        if !e.kjv.isEmpty {
                            Text("KJV Usage")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(e.kjv)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        // Full entry button
                        Button {
                            onFullEntry()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Full entry in Dictionaries")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .frame(maxHeight: 160)

            } else {
                // No module selected
                HStack {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Select a Strong's lexicon in Dictionaries to see definitions")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

struct InterlinearWordCell: View {
    let token:      InterlinearToken
    let isOT:       Bool
    let isSelected: Bool
    let accent:     Color
    let theme:      AppTheme

    var body: some View {
        VStack(spacing: 2) {
            if isOT {
                // OT: Hebrew on top (larger, RTL), English below
                Text(token.original)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? accent : theme.text)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(1)

                Text(token.english.isEmpty ? " " : token.english)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? accent : theme.text.opacity(0.75))
                    .lineLimit(1)
            } else {
                // NT: English on top, Greek below
                Text(token.english.isEmpty ? " " : token.english)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? accent : theme.text)
                    .lineLimit(1)

                Text(token.original)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? accent : theme.text.opacity(0.85))
                    .lineLimit(1)

                // Morphology (NT only)
                if !token.morphology.isEmpty {
                    Text(token.morphology)
                        .font(.system(size: 8).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Strong's number
            Text(token.strongsNum)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent.opacity(isSelected ? 1.0 : 0.65))
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(
            isSelected ? accent.opacity(0.1) : Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accent.opacity(0.4) : Color.clear, lineWidth: 0.5)
        )
        .fixedSize()
    }
}
