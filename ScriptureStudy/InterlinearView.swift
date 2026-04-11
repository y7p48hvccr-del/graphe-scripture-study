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

    private var activeModule: InterlinearModule? {
        isOT ? interlinearSvc.selectedOT : interlinearSvc.selectedNT
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
        .onChange(of: bookNumber)  { _ in selectedStrongs = ""; loadVerses() }
        .onChange(of: chapter)     { _ in selectedStrongs = ""; loadVerses() }
        .onChange(of: interlinearSvc.selectedOT) { _ in loadVerses() }
        .onChange(of: interlinearSvc.selectedNT) { _ in loadVerses() }
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
            let candidates = interlinearSvc.modules.filter { $0.isRTL == isOT }
            if candidates.count > 1 {
                Menu {
                    ForEach(candidates) { mod in
                        Button(mod.name) {
                            if isOT { interlinearSvc.selectedOT = mod }
                            else    { interlinearSvc.selectedNT = mod }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeModule?.name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? "None")
                            .font(.caption).foregroundStyle(theme.text).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8)).foregroundStyle(accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)
            } else if let mod = activeModule {
                Text(mod.name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? mod.name)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(theme.background)
    }

    // MARK: - Chapter view

    private var chapterView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(verses) { interlinearVerse in
                        let isSynced = syncedVerse > 0 && interlinearVerse.verse == syncedVerse
                        VStack(alignment: .leading, spacing: 8) {
                            // Verse number
                            Text("\(interlinearVerse.verse)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(isSynced ? filigreeAccentFill : filigreeAccentFill.opacity(0.5),
                                            in: Capsule())

                            // Token flow
                            FlowLayout(hSpacing: 6, vSpacing: 8) {
                                ForEach(interlinearVerse.tokens) { token in
                                    InterlinearWordCell(
                                        token:      token,
                                        isOT:       isOT,
                                        isSelected: token.strongsNum == selectedStrongs,
                                        accent:     accent,
                                        theme:      theme
                                    )
                                    .onTapGesture { tapped(token) }
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(isSynced ? accent.opacity(0.06) : Color.clear)
                        .id(interlinearVerse.verse)

                        Divider().padding(.leading, 12)
                    }

                    Spacer().frame(height: 20)
                }
            }
            .onChange(of: syncedVerse) { v in
                if v > 0 { withAnimation { proxy.scrollTo(v, anchor: .center) } }
            }
        }
    }

    // MARK: - Actions

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
