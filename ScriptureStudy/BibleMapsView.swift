//
//  BibleMapsView.swift
//  ScriptureStudy
//
//  Maps tab inside the Companion Panel.
//  Uses the same AppTheme / filigreeAccent pattern as CompanionPanel.
//

import SwiftUI

// MARK: - Verse ref navigation helper

/// Parses "Exod 14", "Matt 27:33-37", "Acts 9:1-7" etc. and posts
/// the navigateToPassage notification that LocalBibleView expects.
private func navigateToVerseRef(_ ref: String) {
    guard let (bn, ch, vs) = parseVerseRef(ref) else {
        print("[BMaps] Could not parse verse ref: \(ref)")
        return
    }
    var info: [String: Any] = ["bookNumber": bn, "chapter": ch]
    if vs > 0 { info["verse"] = vs }
    NotificationCenter.default.post(name: .navigateToPassage, object: nil, userInfo: info)
}

private func parseVerseRef(_ ref: String) -> (bookNumber: Int, chapter: Int, verse: Int)? {
    // Split "Exod 14" or "Matt 27:33-37" into abbr + reference
    let parts = ref.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
    guard parts.count >= 2 else { return nil }
    let abbr    = parts[0]
    let chapVerse = parts[1...].joined(separator: " ")  // handle "1 Kgs 2:3" style

    guard let bookNum = bmapsAbbrToBookNumber[abbr.lowercased()] else { return nil }

    // Parse chapter and optional verse from "14", "27:33-37", "3:1-5:1"
    let cv = chapVerse.components(separatedBy: ":")
    guard let chapter = Int(cv[0].trimmingCharacters(in: .whitespaces)) else { return nil }

    var verse = 0
    if cv.count >= 2 {
        // Take only the first number before any dash
        let verseStr = cv[1].components(separatedBy: CharacterSet(charactersIn: "-–")).first ?? ""
        verse = Int(verseStr.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    return (bookNum, chapter, verse)
}

/// Abbreviation → MyBible book number (same numbering as osisBookName in CompanionPanel)
private let bmapsAbbrToBookNumber: [String: Int] = [
    "gen":10, "exod":20, "lev":30, "num":40, "deut":50,
    "josh":60, "judg":70, "ruth":80, "1sam":90, "2sam":100,
    "1kgs":110, "2kgs":120, "1chr":130, "2chr":140, "ezra":150,
    "neh":160, "esth":170, "job":180, "ps":230, "pss":230,
    "prov":240, "eccl":250, "song":260, "isa":290, "jer":300,
    "lam":310, "ezek":330, "dan":340, "hos":350, "joel":360,
    "amos":370, "obad":380, "jonah":390, "mic":400, "nah":410,
    "hab":420, "zeph":430, "hag":440, "zech":450, "mal":460,
    "matt":470, "mark":480, "luke":490, "john":500, "acts":510,
    "rom":520, "1cor":530, "2cor":540, "gal":550, "eph":560,
    "phil":570, "col":580, "1thess":590, "2thess":600,
    "1tim":610, "2tim":620, "titus":630, "phlm":640,
    "heb":650, "jas":660, "1pet":670, "2pet":680,
    "1john":690, "2john":700, "3john":710, "jude":720, "rev":730
]

struct BibleMapsView: View {

    @EnvironmentObject var bmapsService: BMapsService

    var currentVerseRef:    String?
    var theme:              AppTheme
    var filigreeAccent:     Color
    var filigreeAccentFill: Color
    var resolvedFont:       Font

    @State private var selectedMap:   BibleMap? = nil
    @State private var searchText:    String    = ""
    @State private var showingSearch: Bool      = false

    private var nearbyPlaces: [BiblePlaceEntry] {
        guard let ref = currentVerseRef else { return [] }
        return bmapsService.placesNear(verseRef: ref)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar ───────────────────────────────────────────────
            HStack(spacing: 8) {
                if selectedMap != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedMap = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("All Maps")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(filigreeAccent)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !showingSearch, selectedMap == nil, !nearbyPlaces.isEmpty,
                   let ref = currentVerseRef {
                    Button { searchText = "" } label: {
                        Label("\(nearbyPlaces.count) near \(ref)", systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(filigreeAccent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(filigreeAccent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Show map places mentioned near \(ref)")
                }

                if selectedMap == nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingSearch.toggle()
                            if !showingSearch { searchText = "" }
                        }
                    } label: {
                        Image(systemName: showingSearch ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(showingSearch ? filigreeAccent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showingSearch ? "Close search" : "Search places")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.background)

            if showingSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Search places…", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(theme.background)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // ── Content ───────────────────────────────────────────────
            if !bmapsService.isLoaded {
                notLoadedView
            } else if let map = selectedMap {
                MapDetailView(map: map, theme: theme, filigreeAccent: filigreeAccent,
                              filigreeAccentFill: filigreeAccentFill, resolvedFont: resolvedFont)
            } else if !searchText.isEmpty {
                PlaceSearchResultsView(searchText: searchText, currentVerseRef: nil,
                    theme: theme, filigreeAccent: filigreeAccent, filigreeAccentFill: filigreeAccentFill,
                    resolvedFont: resolvedFont, onSelectMap: { selectedMap = $0 })
                    .environmentObject(bmapsService)
            } else if !nearbyPlaces.isEmpty && currentVerseRef != nil {
                PlaceSearchResultsView(searchText: "", currentVerseRef: currentVerseRef,
                    theme: theme, filigreeAccent: filigreeAccent, filigreeAccentFill: filigreeAccentFill,
                    resolvedFont: resolvedFont, onSelectMap: { selectedMap = $0 })
                    .environmentObject(bmapsService)
            } else {
                MapListView(theme: theme, filigreeAccent: filigreeAccent,
                            filigreeAccentFill: filigreeAccentFill, onSelect: { selectedMap = $0 })
                    .environmentObject(bmapsService)
            }
        }
        .background(theme.background)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("mapsSearchPlace"))) { note in
            guard let name = note.userInfo?["placeName"] as? String else { return }
            // Clear any open map, open search bar, and pre-fill with the place name
            selectedMap = nil
            searchText  = name
            withAnimation(.easeInOut(duration: 0.18)) { showingSearch = true }
        }
    }

    private var notLoadedView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "map").font(.system(size: 36)).foregroundStyle(.quaternary)
            Text("Bible Maps module not loaded").font(.callout).foregroundStyle(.secondary)
            Text("Add BMaps.dictionary.SQLite3 to your modules folder.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity).background(theme.background)
    }
}

// MARK: - Map List

struct MapListView: View {
    @EnvironmentObject var bmapsService: BMapsService
    let theme:              AppTheme
    let filigreeAccent:     Color
    let filigreeAccentFill: Color
    var onSelect: (BibleMap) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(bmapsService.maps) { map in
                    Button { onSelect(map) } label: {
                        HStack(spacing: 10) {
                            Text(map.number)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(filigreeAccent)
                                .frame(width: 24, height: 24)
                                .background(filigreeAccent.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(map.title)
                                    .font(.system(size: 12)).foregroundStyle(theme.text).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if !map.places.isEmpty {
                                    Text("\(map.places.count) named location\(map.places.count == 1 ? "" : "s")")
                                        .font(.system(size: 10)).foregroundStyle(theme.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10)).foregroundStyle(Color.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if map.id != bmapsService.maps.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .background(theme.background)
    }
}

// MARK: - Map Detail

struct MapDetailView: View {
    @EnvironmentObject var bmapsService: BMapsService
    let map:                BibleMap
    let theme:              AppTheme
    let filigreeAccent:     Color
    let filigreeAccentFill: Color
    let resolvedFont:       Font

    @State private var mapHTML:          String?  = nil
    @State private var isLoading:        Bool     = true
    @State private var navigatedMap:     BibleMap? = nil
    @State private var mapContentHeight: CGFloat  = 400
    @StateObject private var mapController = MapWebController()

    private var displayMap: BibleMap { navigatedMap ?? map }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Title header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Map \(displayMap.number)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(filigreeAccentFill, in: Capsule())
                    Text(displayMap.title)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)

                Divider()

                // ── Map image via WKWebView ───────────────────────────
                Group {
                    if isLoading {
                        VStack {
                            Spacer()
                            ProgressView("Loading map…").foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: mapContentHeight)
                        .frame(maxWidth: .infinity)
                        .background(theme.background)
                    } else if let html = mapHTML {
                        ZStack(alignment: .bottomTrailing) {
                            MapHTMLView(
                                html: html,
                                controller: mapController,
                                contentHeight: $mapContentHeight
                            ) { mapID in
                                if let target = bmapsService.maps.first(where: { $0.id == mapID }) {
                                    navigatedMap = target
                                }
                            }
                            .frame(height: mapContentHeight)
                            .frame(maxWidth: .infinity)

                            // Zoom controls
                            #if os(macOS)
                            HStack(spacing: 2) {
                                Button { mapController.zoomOut() } label: {
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .help("Zoom out")
                                Button { mapController.resetZoom() } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .help("Reset zoom")
                                Button { mapController.zoomIn() } label: {
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .help("Zoom in")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(filigreeAccent)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(10)
                            #endif
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "map").font(.system(size: 28)).foregroundStyle(.quaternary)
                            Text("Map image unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(height: 120).frame(maxWidth: .infinity)
                    }
                }
                .task(id: displayMap.id) {
                    mapContentHeight = 400   // reset while loading
                    isLoading        = true
                    mapHTML          = await bmapsService.renderedHTML(for: displayMap.id)
                    isLoading        = false
                }

                Spacer().frame(height: 20)
            }
        }
        .background(theme.background)
    }
}

// MARK: - WKWebView wrapper for map HTML

import WebKit

#if !os(macOS)
extension View {
    func help(_ text: String) -> some View { self }
}
#endif

/// Controller object — lives in MapDetailView, holds a weak ref to the web view
/// so zoom buttons can drive it without a @Binding roundtrip.
class MapWebController: ObservableObject {
    #if os(macOS)
    weak var webView: PassthroughWKWebView?

    func zoomIn() {
        guard let wv = webView else { return }
        wv.magnification = min(4.0, wv.magnification + 0.4)
    }
    func zoomOut() {
        guard let wv = webView else { return }
        wv.magnification = max(0.5, wv.magnification - 0.4)
    }
    func resetZoom() { webView?.magnification = 1.0 }
    #endif
}

#if os(macOS)
/// WKWebView subclass with smart scroll handling and click-drag panning:
/// • At normal zoom (≈1×): passes wheel events to the SwiftUI ScrollView.
/// • When zoomed in: handles scroll events internally and enables drag-to-pan.
class PassthroughWKWebView: WKWebView {

    private var lastDragPoint: CGPoint = .zero

    override func scrollWheel(with event: NSEvent) {
        if magnification > 1.05 {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    // Pan when zoomed — suppress the default selection drag
    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
        if magnification > 1.05 {
            NSCursor.openHand.set()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard magnification > 1.05 else { super.mouseDragged(with: event); return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - lastDragPoint.x
        let dy = current.y - lastDragPoint.y
        lastDragPoint = current
        NSCursor.closedHand.set()
        // Scroll the web page content by the drag delta
        evaluateJavaScript("window.scrollBy(\(-dx), \(dy))", completionHandler: nil)
    }

    override func mouseUp(with event: NSEvent) {
        if magnification > 1.05 {
            NSCursor.openHand.set()
        } else {
            super.mouseUp(with: event)
        }
    }

    override func resetCursorRects() {
        if magnification > 1.05 {
            addCursorRect(bounds, cursor: .openHand)
        } else {
            super.resetCursorRects()
        }
    }
}
#else
typealias PassthroughWKWebView = WKWebView
#endif

struct MapHTMLView: WKViewRepresentable {
    let html:       String
    let controller: MapWebController
    @Binding var contentHeight: CGFloat
    var onMapLink: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onMapLink: onMapLink)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ wv: WKWebView, context: Context) { updateWebView(wv, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ wv: WKWebView, context: Context) { updateWebView(wv, context: context) }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let wv = PassthroughWKWebView(frame: .zero)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        #if os(macOS)
        controller.webView = wv
        #endif
        return wv
    }

    private func updateWebView(_ wv: WKWebView, context: Context) {
        context.coordinator.onMapLink     = onMapLink
        context.coordinator.contentHeight = $contentHeight
        wv.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var contentHeight: Binding<CGFloat>
        var onMapLink: ((String) -> Void)?

        init(contentHeight: Binding<CGFloat>, onMapLink: ((String) -> Void)?) {
            self.contentHeight = contentHeight
            self.onMapLink     = onMapLink
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let markerJS = """
            (function() {
                // Disable text/element selection so drag always pans, never selects
                document.documentElement.style.webkitUserSelect = 'none';
                document.documentElement.style.userSelect       = 'none';

                function styleMarkers() {
                    document.querySelectorAll('.marker').forEach(function(m) {
                        m.style.background   = 'rgba(255,255,255,0.90)';
                        m.style.border       = '1px solid rgba(0,0,0,0.28)';
                        m.style.borderRadius = '3px';
                        m.style.padding      = '1px 5px';
                        m.style.fontWeight   = '700';
                        m.style.color        = '#1a1a2e';
                        m.style.boxShadow    = '0 1px 4px rgba(0,0,0,0.22)';
                        m.style.whiteSpace   = 'nowrap';
                        m.style.fontSize     = '11px';
                        m.style.lineHeight   = '1.4';
                        m.style.textShadow   = 'none';
                    });
                }
                styleMarkers();
                setTimeout(styleMarkers, 500);
                setTimeout(styleMarkers, 1500);
            })();
            """
            webView.evaluateJavaScript(markerJS, completionHandler: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                    if let h = result as? CGFloat, h > 50 {
                        DispatchQueue.main.async { self.contentHeight.wrappedValue = h }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow); return
            }
            let rawURL = url.absoluteString
            print("[BMaps] link tapped: \(rawURL) type=\(action.navigationType.rawValue)")
            let decoded = rawURL.removingPercentEncoding ?? rawURL
            let upper = decoded.uppercased().hasPrefix("B:") ? "B:" + decoded.dropFirst(2) :
                        decoded.uppercased().hasPrefix("S:") ? "S:" + decoded.dropFirst(2) : decoded
            if upper.hasPrefix("B:") {
                handleBibleRef(String(upper.dropFirst(2)))
                decisionHandler(.cancel); return
            }
            if upper.hasPrefix("S:") {
                onMapLink?(String(upper.dropFirst(2)))
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        private func handleBibleRef(_ ref: String) {
            let parts = ref.components(separatedBy: " ")
            guard parts.count >= 2, let bookNum = Int(parts[0]) else { return }
            let cv = parts[1...].joined().components(separatedBy: ":")
            guard let chapter = Int(cv[0].trimmingCharacters(in: .whitespaces)) else { return }
            var verse = 0
            if cv.count >= 2 {
                verse = Int(cv[1].components(separatedBy: CharacterSet(charactersIn: "-–")).first?
                    .trimmingCharacters(in: .whitespaces) ?? "") ?? 0
            }
            var info: [String: Any] = ["bookNumber": bookNum, "chapter": chapter]
            if verse > 0 { info["verse"] = verse }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .navigateToPassage, object: nil, userInfo: info)
            }
        }
    }
}

// MARK: - Place Row

struct MapPlaceRow: View {
    let place:          MapPlace
    let theme:          AppTheme
    let filigreeAccent: Color
    let resolvedFont:   Font
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(filigreeAccent.opacity(0.75))
                    Text(place.name).font(.system(size: 12)).foregroundStyle(theme.text)
                    Spacer()
                    if !place.verseRefs.isEmpty {
                        Text("\(place.verseRefs.count)")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(filigreeAccent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(filigreeAccent.opacity(0.1), in: Capsule())
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !place.verseRefs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(place.verseRefs, id: \.self) { ref in
                        Button {
                            navigateToVerseRef(ref)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 9)).foregroundStyle(filigreeAccent.opacity(0.6))
                                Text(ref).font(.system(size: 11)).foregroundStyle(filigreeAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9)).foregroundStyle(filigreeAccent.opacity(0.4))
                            }
                            .padding(.horizontal, 28).padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Open \(ref) in Bible panel")
                    }
                }
                .padding(.bottom, 4)
                .background(filigreeAccent.opacity(0.05))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Place Search / Verse-context Results

struct PlaceSearchResultsView: View {
    @EnvironmentObject var bmapsService: BMapsService
    let searchText:        String
    let currentVerseRef:   String?
    let theme:             AppTheme
    let filigreeAccent:    Color
    let filigreeAccentFill: Color
    let resolvedFont:      Font
    var onSelectMap:       (BibleMap) -> Void

    private var results: [BiblePlaceEntry] {
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            return bmapsService.places.filter { $0.name.lowercased().contains(q) }
        }
        if let ref = currentVerseRef { return bmapsService.placesNear(verseRef: ref) }
        return []
    }

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "mappin.slash").font(.system(size: 28)).foregroundStyle(.quaternary)
                Text(searchText.isEmpty ? "No places found near this verse."
                                        : "No places matching \"\(searchText)\".")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Spacer()
            }
            .frame(maxWidth: .infinity).background(theme.background)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if !searchText.isEmpty {
                            Text("\(results.count) place\(results.count == 1 ? "" : "s") found")
                        } else if let ref = currentVerseRef {
                            Text("Map places near \(ref)").font(.caption.weight(.semibold))
                        }
                        Spacer()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)

                    ForEach(results) { place in
                        PlaceEntryRow(place: place, theme: theme, filigreeAccent: filigreeAccent,
                                      filigreeAccentFill: filigreeAccentFill, resolvedFont: resolvedFont,
                                      onSelectMap: onSelectMap)
                            .environmentObject(bmapsService)
                        Divider().padding(.leading, 12)
                    }
                    Spacer().frame(height: 20)
                }
            }
            .background(theme.background)
        }
    }
}

// MARK: - Place Entry Row (search result)

struct PlaceEntryRow: View {
    @EnvironmentObject var bmapsService: BMapsService
    let place:             BiblePlaceEntry
    let theme:             AppTheme
    let filigreeAccent:    Color
    let filigreeAccentFill: Color
    let resolvedFont:      Font
    var onSelectMap:       (BibleMap) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12)).foregroundStyle(filigreeAccent.opacity(0.75))
                    Text(place.name).font(.system(size: 12)).foregroundStyle(theme.text)
                    Spacer()
                    Text("\(place.mapRefs.count) map\(place.mapRefs.count == 1 ? "" : "s")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                }
                .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(place.mapRefs, id: \.mapID) { ref in
                        let matchingMap = bmapsService.maps.first { $0.id == ref.mapID }
                        Button {
                            if let map = matchingMap { onSelectMap(map) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                    .font(.system(size: 9)).foregroundStyle(filigreeAccent.opacity(0.6))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ref.mapTitle).font(.system(size: 11))
                                        .foregroundStyle(filigreeAccent).lineLimit(1)
                                    Text("Grid \(ref.gridRef)").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9)).foregroundStyle(filigreeAccent.opacity(0.4))
                            }
                            .padding(.horizontal, 24).padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help("Open \(ref.mapTitle)")
                    }

                    let verses = bmapsService.versesForPlace(place.name)
                    if !verses.isEmpty {
                        Divider().padding(.horizontal, 24).padding(.vertical, 2)
                        ForEach(verses, id: \.self) { ref in
                            Button {
                                navigateToVerseRef(ref)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "book.closed")
                                        .font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.5))
                                    Text(ref).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9)).foregroundStyle(Color.secondary.opacity(0.4))
                                }
                                .padding(.horizontal, 24).padding(.vertical, 4).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help("Open \(ref) in Bible panel")
                        }
                    }
                }
                .padding(.bottom, 6)
                .background(filigreeAccent.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

