import SwiftUI
import WebKit

// MARK: - Source definitions

struct DiscoverSource: Identifiable {
    let id:      String
    let name:    String
    let url:     String
    let icon:    String
    let blurb:   String
}

let discoverSources: [DiscoverSource] = [
    DiscoverSource(id: "monergism",
                   name: "Monergism",
                   url:  "https://www.monergism.com/1100-free-ebooks-listed-alphabetically-author",
                   icon: "books.vertical.fill",
                   blurb: "1,300+ Reformed theology classics — EPUB & PDF"),
    DiscoverSource(id: "ccel",
                   name: "CCEL",
                   url:  "https://ccel.org/index/format/epub",
                   icon: "building.columns.fill",
                   blurb: "Christian Classics Ethereal Library — patristics to Puritans"),
    DiscoverSource(id: "inspiredwalk",
                   name: "Inspired Walk",
                   url:  "https://www.inspiredwalk.com/free-christian-ebooks",
                   icon: "figure.walk",
                   blurb: "400+ free devotional & teaching ebooks"),
    DiscoverSource(id: "biblesnet",
                   name: "BiblesNet",
                   url:  "https://www.biblesnet.com/ebooks.html",
                   icon: "book.fill",
                   blurb: "Free classic Christian ebooks — Spurgeon, Ryle & more"),
    DiscoverSource(id: "spiritualibrary",
                   name: "Spiritual Library",
                   url:  "https://www.spiritualibrary.com/",
                   icon: "leaf.fill",
                   blurb: "Christian living, devotionals & magazines — many languages"),
    DiscoverSource(id: "standardebooks",
                   name: "Standard Ebooks",
                   url:  "https://standardebooks.org/ebooks?query=&subject=Religion",
                   icon: "star.fill",
                   blurb: "Beautifully formatted public domain classics"),
    DiscoverSource(id: "openlibrary",
                   name: "Open Library",
                   url:  "https://openlibrary.org/subjects/christian_literature",
                   icon: "globe",
                   blurb: "Internet Archive — borrow or download free Christian texts"),
]

// MARK: - Main Discover View

struct DiscoverView: View {
    @AppStorage("epubFolder")    private var epubFolder:    String = ""
    @AppStorage("filigreeColor") private var filigreeColor: Int    = 0
    @AppStorage("themeID")       private var themeID:       String = "light"
    var filigreeAccent: Color { resolvedFiligreeAccent(colorIndex: filigreeColor, themeID: themeID) }

    @State private var selectedSource: DiscoverSource = discoverSources[0]
    @State private var downloadStatus: String?        = nil
    @State private var downloadIsError: Bool          = false
    @State private var isDownloading:   Bool          = false

    var body: some View {
        VStack(spacing: 0) {
            // Source picker
            sourcePicker

            Divider()

            if epubFolder.isEmpty {
                noFolderPrompt
            } else {
                // Browser
                ZStack(alignment: .bottom) {
                    DiscoverBrowserView(
                        source:         selectedSource,
                        booksFolder:    epubFolder,
                        filigreeAccent: filigreeAccent,
                        onDownloadStart: { filename in
                            isDownloading  = true
                            downloadStatus = "Downloading \(filename)…"
                            downloadIsError = false
                        },
                        onDownloadComplete: { filename in
                            isDownloading  = false
                            downloadStatus = "\(filename) saved to Books"
                            downloadIsError = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                downloadStatus = nil
                            }
                        },
                        onDownloadError: { message in
                            isDownloading  = false
                            downloadStatus = message
                            downloadIsError = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                downloadStatus = nil
                            }
                        }
                    )

                    // Download toast
                    if let status = downloadStatus {
                        HStack(spacing: 8) {
                            if isDownloading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: downloadIsError
                                      ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(downloadIsError ? .red : .green)
                            }
                            Text(status).font(.caption.weight(.medium))
                            Spacer()
                            if !isDownloading {
                                Button { downloadStatus = nil } label: {
                                    Image(systemName: "xmark").font(.system(size: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: downloadStatus)
            }
        }
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(discoverSources) { source in
                    Button {
                        selectedSource = source
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: source.icon)
                                .font(.system(size: 11))
                            Text(source.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selectedSource.id == source.id
                                    ? filigreeAccent
                                    : filigreeAccent.opacity(0.1))
                        .foregroundStyle(selectedSource.id == source.id ? .white : filigreeAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(source.blurb)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - No folder prompt

    private var noFolderPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("No books folder set")
                .font(.title2.weight(.semibold))
            Text("Go to the My Books tab and choose a folder\nbefore browsing for downloads.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

// MARK: - WKWebView wrapper

struct DiscoverBrowserView: NSViewRepresentable {
    let source:             DiscoverSource
    let booksFolder:        String
    let filigreeAccent:     Color
    let onDownloadStart:    (String) -> Void
    let onDownloadComplete: (String) -> Void
    let onDownloadError:    (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(booksFolder:        booksFolder,
                    onDownloadStart:    onDownloadStart,
                    onDownloadComplete: onDownloadComplete,
                    onDownloadError:    onDownloadError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let url = URL(string: source.url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Navigate when source changes
        if context.coordinator.currentSourceID != source.id {
            context.coordinator.currentSourceID = source.id
            if let url = URL(string: source.url) {
                webView.load(URLRequest(url: url))
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let booksFolder:        String
        let onDownloadStart:    (String) -> Void
        let onDownloadComplete: (String) -> Void
        let onDownloadError:    (String) -> Void
        var currentSourceID:    String = ""
        weak var webView:       WKWebView?

        private let downloadableExtensions: Set<String> = ["epub", "pdf", "mobi", "azw3"]

        init(booksFolder:        String,
             onDownloadStart:    @escaping (String) -> Void,
             onDownloadComplete: @escaping (String) -> Void,
             onDownloadError:    @escaping (String) -> Void)
        {
            self.booksFolder        = booksFolder
            self.onDownloadStart    = onDownloadStart
            self.onDownloadComplete = onDownloadComplete
            self.onDownloadError    = onDownloadError
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
        {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let ext = url.pathExtension.lowercased()
            if downloadableExtensions.contains(ext) {
                decisionHandler(.cancel)
                downloadFile(from: url)
            } else {
                decisionHandler(.allow)
            }
        }

        private func downloadFile(from url: URL) {
            let filename = url.lastPathComponent
            DispatchQueue.main.async { self.onDownloadStart(filename) }

            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.onDownloadError("Download failed: \(error.localizedDescription)")
                    }
                    return
                }
                guard let tempURL = tempURL else {
                    DispatchQueue.main.async { self.onDownloadError("Download failed — no data") }
                    return
                }

                // Use server-suggested filename if available
                let finalName: String
                if let suggested = (response as? HTTPURLResponse)?
                    .suggestedFilename ?? response?.suggestedFilename {
                    finalName = suggested
                } else {
                    finalName = filename
                }

                let destFolder = URL(fileURLWithPath: self.booksFolder)
                let dest = destFolder.appendingPathComponent(finalName)

                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    DispatchQueue.main.async { self.onDownloadComplete(finalName) }
                } catch {
                    DispatchQueue.main.async {
                        self.onDownloadError("Could not save \(finalName): \(error.localizedDescription)")
                    }
                }
            }
            task.resume()
        }
    }
}
