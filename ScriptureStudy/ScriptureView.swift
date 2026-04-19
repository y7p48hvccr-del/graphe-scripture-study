import SwiftUI

struct ScriptureView: View {

    @EnvironmentObject var bibleService: BibleAPIService
    @State private var selectedBook    = bibleBooks[43] // John
    @State private var selectedChapter = 3

    var body: some View {
        #if os(macOS)
        HSplitView {
            // Sidebar: pickers
            VStack(alignment: .leading, spacing: 16) {
                DailyVerseCard()

                Divider()

                Text("BOOK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Book", selection: $selectedBook) {
                    ForEach(bibleBooks) { book in
                        Text(book.name).tag(book)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedBook) { selectedChapter = 1 }

                Text("CHAPTER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Chapter", selection: $selectedChapter) {
                    ForEach(1...selectedBook.chapters, id: \.self) { ch in
                        Text("Chapter \(ch)").tag(ch)
                    }
                }
                .labelsHidden()

                Button("Load Chapter") {
                    Task {
                        await bibleService.loadChapter(
                            book: selectedBook,
                            chapter: selectedChapter
                        )
                    }
                }
                .controlSize(.large)
                .disabled(bibleService.isLoading)

                Spacer()
            }
            .padding()
            .frame(minWidth: 180, maxWidth: 220)

            // Main reading area
            Group {
                if bibleService.isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView("Loading scripture…")
                        Spacer()
                    }
                } else if let error = bibleService.errorMessage {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(error).multilineTextAlignment(.center)
                            .foregroundStyle(.secondary).padding(.horizontal)
                        Button("Try Again") {
                            Task {
                                await bibleService.loadChapter(
                                    book: selectedBook, chapter: selectedChapter)
                            }
                        }
                        Spacer()
                    }
                } else if let chapter = bibleService.chapter {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(chapter.book) \(chapter.chapter)")
                                .font(.title.weight(.bold))
                                .padding(.bottom, 4)
                            Text("King James Version")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.bottom, 20)

                            ForEach(chapter.verses) { verse in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(verse.number)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.orange)
                                        .frame(minWidth: 24, alignment: .trailing)
                                        .padding(.top, 3)
                                    Text(verse.text)
                                        .font(.body)
                                        .lineSpacing(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.bottom, 14)
                            }
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "book.closed")
                            .font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("Select a book and chapter,\nthen tap **Load Chapter**.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        NavigationSplitView {
            Text("Sidebar")
        } detail: {
            Text("Select a chapter")
        }
        #endif
    }
}
