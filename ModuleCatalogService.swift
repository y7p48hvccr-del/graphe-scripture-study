import Foundation

struct GrapheModuleMetadata {
    let identifier: String
    let displayName: String
    let description: String
    let kind: ModuleType
    let contentFormat: String
    let version: String
    let source: String?
    let capabilities: [String]
    let language: String
    let linkedLanguages: [String]
}

protocol GrapheModuleMetadataReading {
    func readMetadata(
        from moduleURL: URL,
        info: [String: String],
        tables: Set<String>,
        validation: GrapheRuntimeValidationReport
    ) -> GrapheModuleMetadata?
}

struct ModuleCatalogRecord {
    let module: MyBibleModule
    let metadata: GrapheModuleMetadata
    let metadataBlob: String
    let validation: GrapheRuntimeValidationReport

    var hasStrongsCapability: Bool {
        validation.hasStrongsCapability || metadata.capabilities.contains("strongNumbers")
    }
}

struct ModuleCatalogDiagnostic: Hashable {
    let filePath: String
    let validation: GrapheRuntimeValidationReport
    let reason: String
    let attemptedMetadataReaders: [String]
    let tableNames: [String]
}

struct ModuleCatalogScanResult {
    let recordsByPath: [String: ModuleCatalogRecord]
    let modules: [MyBibleModule]
    let hiddenModulePaths: Set<String>
    let diagnostics: [ModuleCatalogDiagnostic]
}

struct ModuleSelectionPaths {
    let biblePath: String
    let strongsPath: String
    let dictionaryPath: String
    let commentaryPath: String
    let encyclopediaPath: String
    let crossRefPath: String
    let devotionalPath: String
}

struct ModuleSelectionResolution {
    let bible: MyBibleModule?
    let strongs: MyBibleModule?
    let dictionary: MyBibleModule?
    let commentary: MyBibleModule?
    let encyclopedia: MyBibleModule?
    let crossRef: MyBibleModule?
    let devotional: MyBibleModule?
}

enum ModuleCatalogScanError: Error {
    case unreadableFolder
}

enum ModuleCatalogService {
    private static let runtimeModuleInspector: GrapheRuntimeModuleInspecting = GrapheRuntimeModuleAccessor()

    private enum InspectionOutcome {
        case record(ModuleCatalogRecord)
        case diagnostic(ModuleCatalogDiagnostic)
    }

    private struct RuntimeInspectionModuleMetadataReader: GrapheModuleMetadataReading {
        func readMetadata(
            from moduleURL: URL,
            info: [String: String],
            tables: Set<String>,
            validation: GrapheRuntimeValidationReport
        ) -> GrapheModuleMetadata? {
            guard !info.isEmpty else { return nil }
            let fileStem = moduleURL.deletingPathExtension().lastPathComponent
            let displayName = ModuleCatalogService.preferredModuleTitle(
                description: info["description"],
                title: info["title"] ?? info["name"],
                fallback: fileStem
            )
            let contentFormat = moduleURL.pathExtension.lowercased() == "graphe" ? "graphe" : "sqlite-legacy"

            return GrapheModuleMetadata(
                identifier: info["identifier"] ?? fileStem,
                displayName: displayName,
                description: displayName,
                kind: validation.moduleType,
                contentFormat: contentFormat,
                version: info["version"] ?? "1",
                source: info["source"],
                capabilities: ModuleCatalogService.capabilities(
                    for: validation.moduleType,
                    hasStrongNumbers: validation.hasStrongsCapability,
                    isInterlinear: ModuleCatalogService.isInterlinearModule(info: info, tables: tables)
                ),
                language: info["language"] ?? "en",
                linkedLanguages: ModuleCatalogService.linkedLanguages(from: info)
            )
        }
    }

    private struct SidecarCompatibilityModuleMetadataReader: GrapheModuleMetadataReading {
        func readMetadata(
            from moduleURL: URL,
            info: [String: String],
            tables: Set<String>,
            validation: GrapheRuntimeValidationReport
        ) -> GrapheModuleMetadata? {
            guard let sidecar = ModuleCatalogService.sidecarMetadata(forModuleAt: moduleURL.path) else {
                return nil
            }
            let fileStem = moduleURL.deletingPathExtension().lastPathComponent
            let contentFormat = moduleURL.pathExtension.lowercased() == "graphe" ? "graphe" : "sqlite-legacy"
            let moduleType = ModuleCatalogService.moduleType(
                fromSidecarType: sidecar.type,
                fallback: validation.moduleType
            )
            let hasStrongs = validation.hasStrongsCapability || sidecar.hasStrongsCapability
            let displayName = ModuleCatalogService.preferredModuleTitle(
                description: info["description"] ?? sidecar.displayName,
                title: info["title"] ?? info["name"],
                fallback: fileStem
            )

            return GrapheModuleMetadata(
                identifier: sidecar.identifier ?? info["identifier"] ?? fileStem,
                displayName: displayName,
                description: displayName,
                kind: moduleType,
                contentFormat: contentFormat,
                version: sidecar.version ?? info["version"] ?? "1",
                source: sidecar.source ?? info["source"],
                capabilities: ModuleCatalogService.capabilities(
                    for: moduleType,
                    hasStrongNumbers: hasStrongs,
                    isInterlinear: ModuleCatalogService.isInterlinearModule(info: info, tables: tables)
                ),
                language: sidecar.language ?? info["language"] ?? "en",
                linkedLanguages: ModuleCatalogService.linkedLanguages(from: info)
            )
        }
    }

    private struct FilenameFallbackModuleMetadataReader: GrapheModuleMetadataReading {
        func readMetadata(
            from moduleURL: URL,
            info: [String: String],
            tables: Set<String>,
            validation: GrapheRuntimeValidationReport
        ) -> GrapheModuleMetadata? {
            guard validation.state == .ready || !tables.isEmpty else { return nil }
            let fileStem = moduleURL.deletingPathExtension().lastPathComponent
            let displayName = ModuleCatalogService.normalizedModuleBaseName(for: moduleURL)
            let contentFormat = moduleURL.pathExtension.lowercased() == "graphe" ? "graphe" : "sqlite-legacy"

            return GrapheModuleMetadata(
                identifier: info["identifier"] ?? fileStem,
                displayName: displayName,
                description: displayName,
                kind: validation.moduleType,
                contentFormat: contentFormat,
                version: info["version"] ?? "1",
                source: info["source"],
                capabilities: ModuleCatalogService.capabilities(
                    for: validation.moduleType,
                    hasStrongNumbers: validation.hasStrongsCapability,
                    isInterlinear: ModuleCatalogService.isInterlinearModule(info: info, tables: tables)
                ),
                language: info["language"] ?? "en",
                linkedLanguages: ModuleCatalogService.linkedLanguages(from: info)
            )
        }
    }

    private struct ModuleInfoSidecarMetadata {
        let displayName: String?
        let identifier: String?
        let language: String?
        let version: String?
        let source: String?
        let type: String?
        let hasStrongsCapability: Bool
    }

    private struct ModuleCache: Codable {
        var entries: [String: CacheEntry]

        struct CacheEntry: Codable {
            let name: String
            let description: String
            let language: String
            let type: String
            let modDate: Double
            var metaBlob: String
            var hasStrongs: Bool
            var isInterlinear: Bool?
            var linkedLanguages: [String]?
            var validationState: String?
            var matchedProfileName: String?
            var rejectionReasons: [String]?
        }
    }

    private static let metadataReaders: [GrapheModuleMetadataReading] = [
        RuntimeInspectionModuleMetadataReader(),
        SidecarCompatibilityModuleMetadataReader(),
        FilenameFallbackModuleMetadataReader(),
    ]

    static func scanModules(
        folderURL: URL,
        bundledCanonicalStrongsPath: String?
    ) async throws -> ModuleCatalogScanResult {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ModuleCatalogScanError.unreadableFolder
        }

        let moduleFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { ["sqlite3", "sqlite", "db", "graphe"].contains($0.pathExtension.lowercased()) }

        var cache = loadCache()
        var recordsByPath: [String: ModuleCatalogRecord] = [:]
        var hiddenModulePaths: Set<String> = []
        var diagnostics: [ModuleCatalogDiagnostic] = []
        var cacheUpdated = false

        let currentPaths = Set(moduleFiles.map(\.path))
        let stalePaths = cache.entries.keys.filter { !currentPaths.contains($0) }
        for path in stalePaths {
            cache.entries.removeValue(forKey: path)
            cacheUpdated = true
        }

        for fileURL in moduleFiles {
            let path = fileURL.path
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?
                .timeIntervalSince1970 ?? 0

            if let entry = cache.entries[path], entry.modDate == modDate {
                let type = moduleType(from: entry.type)
                let module = MyBibleModule(
                    name: entry.name,
                    description: entry.description,
                    language: entry.language,
                    type: type,
                    filePath: path
                )
                let metadata = GrapheModuleMetadata(
                    identifier: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                    displayName: entry.name,
                    description: entry.description,
                    kind: type,
                    contentFormat: URL(fileURLWithPath: path).pathExtension.lowercased() == "graphe" ? "graphe" : "sqlite-legacy",
                    version: "1",
                    source: nil,
                    capabilities: capabilities(for: type, hasStrongNumbers: entry.hasStrongs, isInterlinear: entry.isInterlinear == true),
                    language: entry.language,
                    linkedLanguages: entry.linkedLanguages ?? []
                )
                let validation = GrapheRuntimeValidationReport(
                    state: GrapheRuntimeValidationState(rawValue: entry.validationState ?? "ready") ?? .ready,
                    matchedProfileName: entry.matchedProfileName,
                    rejectionReasons: entry.rejectionReasons ?? [],
                    moduleType: type,
                    hasStrongsCapability: entry.hasStrongs
                )
                recordsByPath[path] = ModuleCatalogRecord(
                    module: module,
                    metadata: metadata,
                    metadataBlob: entry.metaBlob,
                    validation: validation
                )
                continue
            }

            if let outcome = await inspectModule(at: path) {
                switch outcome {
                case .record(let record):
                    recordsByPath[path] = record
                    cache.entries[path] = ModuleCache.CacheEntry(
                        name: record.module.name,
                        description: record.module.description,
                        language: record.module.language,
                        type: moduleTypeString(record.module.type),
                        modDate: modDate,
                        metaBlob: record.metadataBlob,
                        hasStrongs: record.hasStrongsCapability,
                        isInterlinear: record.metadata.capabilities.contains("interlinear"),
                        linkedLanguages: record.metadata.linkedLanguages,
                        validationState: record.validation.state.rawValue,
                        matchedProfileName: record.validation.matchedProfileName,
                        rejectionReasons: record.validation.rejectionReasons
                    )
                    cacheUpdated = true
                case .diagnostic(let diagnostic):
                    diagnostics.append(diagnostic)
                }
            }
        }

        if let bundled = await bundledCanonicalStrongsModule(at: bundledCanonicalStrongsPath) {
            recordsByPath[bundled.module.filePath] = bundled
            hiddenModulePaths.insert(bundled.module.filePath)
        }

        if cacheUpdated {
            saveCache(cache)
        }

        return ModuleCatalogScanResult(
            recordsByPath: recordsByPath,
            modules: sortModules(recordsByPath.values.map(\.module)),
            hiddenModulePaths: hiddenModulePaths,
            diagnostics: diagnostics.sorted { $0.filePath < $1.filePath }
        )
    }

    static func resolveSelections(
        modules: [MyBibleModule],
        savedPaths: ModuleSelectionPaths,
        currentPaths: ModuleSelectionPaths,
        bundledCanonicalStrongsPath: String?
    ) -> ModuleSelectionResolution {
        ModuleSelectionResolution(
            bible: resolveModule(
                in: modules,
                savedPath: savedPaths.biblePath,
                currentPath: currentPaths.biblePath,
                defaultTypes: [.bible]
            ),
            strongs: resolveStrongsModule(
                in: modules,
                savedPath: savedPaths.strongsPath,
                currentPath: currentPaths.strongsPath,
                bundledCanonicalStrongsPath: bundledCanonicalStrongsPath
            ),
            dictionary: resolveModule(
                in: modules,
                savedPath: savedPaths.dictionaryPath,
                currentPath: currentPaths.dictionaryPath,
                defaultTypes: [.dictionary]
            ),
            commentary: resolveModule(
                in: modules,
                savedPath: savedPaths.commentaryPath,
                currentPath: currentPaths.commentaryPath,
                defaultTypes: [.commentary]
            ),
            encyclopedia: resolveModule(
                in: modules,
                savedPath: savedPaths.encyclopediaPath,
                currentPath: currentPaths.encyclopediaPath,
                defaultTypes: [.encyclopedia]
            ),
            crossRef: resolveModule(
                in: modules,
                savedPath: savedPaths.crossRefPath,
                currentPath: currentPaths.crossRefPath,
                defaultTypes: [.crossRefNative, .crossRef]
            ),
            devotional: resolveModule(
                in: modules,
                savedPath: savedPaths.devotionalPath,
                currentPath: currentPaths.devotionalPath,
                defaultTypes: [.devotional]
            )
        )
    }

    private static func cacheURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = appSupport.appendingPathComponent("Graphe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("module_cache_v5.json")
    }

    private static func loadCache() -> ModuleCache {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ModuleCache.self, from: data)
        else {
            return ModuleCache(entries: [:])
        }
        return cache
    }

    private static func saveCache(_ cache: ModuleCache) {
        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(cache)
        else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func resolveStrongsModule(
        in modules: [MyBibleModule],
        savedPath: String,
        currentPath: String,
        bundledCanonicalStrongsPath: String?
    ) -> MyBibleModule? {
        if let bundledCanonicalStrongsPath,
           let bundled = modules.first(where: { $0.filePath == bundledCanonicalStrongsPath }) {
            return bundled
        }
        return resolveModule(
            in: modules,
            savedPath: savedPath,
            currentPath: currentPath,
            defaultTypes: [.strongs]
        )
    }

    private static func resolveModule(
        in modules: [MyBibleModule],
        savedPath: String,
        currentPath: String,
        defaultTypes: [ModuleType]
    ) -> MyBibleModule? {
        if !savedPath.isEmpty,
           let saved = modules.first(where: { $0.filePath == savedPath }) {
            return saved
        }
        if !currentPath.isEmpty,
           let current = modules.first(where: { $0.filePath == currentPath }) {
            return current
        }
        for type in defaultTypes {
            if let fallback = modules.first(where: { $0.type == type }) {
                return fallback
            }
        }
        return nil
    }

    private static func moduleType(from value: String) -> ModuleType {
        switch value {
        case "bible": return .bible
        case "commentary": return .commentary
        case "crossRef": return .crossRef
        case "crossRefNative": return .crossRefNative
        case "devotional": return .devotional
        case "dictionary": return .dictionary
        case "encyclopedia": return .encyclopedia
        case "strongs": return .strongs
        case "readingPlan": return .readingPlan
        case "subheadings": return .subheadings
        case "wordIndex": return .wordIndex
        case "atlas": return .atlas
        default: return .unknown
        }
    }

    private static func moduleTypeString(_ type: ModuleType) -> String {
        switch type {
        case .bible: return "bible"
        case .commentary: return "commentary"
        case .crossRef: return "crossRef"
        case .crossRefNative: return "crossRefNative"
        case .devotional: return "devotional"
        case .dictionary: return "dictionary"
        case .encyclopedia: return "encyclopedia"
        case .strongs: return "strongs"
        case .readingPlan: return "readingPlan"
        case .subheadings: return "subheadings"
        case .wordIndex: return "wordIndex"
        case .atlas: return "atlas"
        case .unknown: return "unknown"
        }
    }

    private static func sortModules(_ modules: [MyBibleModule]) -> [MyBibleModule] {
        let typeOrder: [ModuleType] = [
            .bible, .commentary, .crossRef, .crossRefNative, .atlas,
            .devotional, .dictionary, .encyclopedia, .strongs,
            .readingPlan, .subheadings, .wordIndex, .unknown,
        ]

        return modules.sorted {
            let leftIndex = typeOrder.firstIndex(of: $0.type) ?? 99
            let rightIndex = typeOrder.firstIndex(of: $1.type) ?? 99
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            return $0.name < $1.name
        }
    }

    private static func bundledCanonicalStrongsModule(
        at path: String?
    ) async -> ModuleCatalogRecord? {
        guard let path,
              let outcome = await inspectModule(at: path)
        else {
            return nil
        }
        guard case let .record(record) = outcome else {
            return nil
        }

        return ModuleCatalogRecord(
            module: MyBibleModule(
                name: record.module.name,
                description: record.module.description,
                language: record.module.language,
                type: .strongs,
                filePath: record.module.filePath
            ),
            metadata: GrapheModuleMetadata(
                identifier: record.metadata.identifier,
                displayName: record.metadata.displayName,
                description: record.metadata.description,
                kind: .strongs,
                contentFormat: record.metadata.contentFormat,
                version: record.metadata.version,
                source: record.metadata.source,
                capabilities: record.metadata.capabilities,
                language: record.metadata.language,
                linkedLanguages: record.metadata.linkedLanguages
            ),
            metadataBlob: record.metadataBlob,
            validation: GrapheRuntimeValidationReport(
                state: record.validation.state,
                matchedProfileName: record.validation.matchedProfileName,
                rejectionReasons: record.validation.rejectionReasons,
                moduleType: .strongs,
                hasStrongsCapability: true
            )
        )
    }

    private static func inspectModule(at path: String) async -> InspectionOutcome? {
        let moduleURL = URL(fileURLWithPath: path)
        guard let inspection = runtimeModuleInspector.inspectModule(at: path) else {
            return nil
        }
        guard inspection.validationReport.state != .rejected else {
            return .diagnostic(
                ModuleCatalogDiagnostic(
                    filePath: path,
                    validation: inspection.validationReport,
                    reason: inspection.validationReport.rejectionReasons.first ?? "Runtime validation rejected the module.",
                    attemptedMetadataReaders: [],
                    tableNames: inspection.tables.sorted()
                )
            )
        }
        let metadataReaderNames = metadataReaders.map { String(describing: type(of: $0)) }
        guard let metadata = resolveMetadata(
            for: moduleURL,
            info: inspection.info,
            tables: inspection.tables,
            validation: inspection.validationReport
        ) else {
            return .diagnostic(
                ModuleCatalogDiagnostic(
                    filePath: path,
                    validation: inspection.validationReport,
                    reason: "No embedded or sidecar metadata could be resolved after runtime access.",
                    attemptedMetadataReaders: metadataReaderNames,
                    tableNames: inspection.tables.sorted()
                )
            )
        }

        return .record(
            ModuleCatalogRecord(
            module: MyBibleModule(
                name: metadata.displayName,
                description: metadata.description,
                language: metadata.language,
                type: metadata.kind,
                filePath: path
            ),
            metadata: metadata,
            metadataBlob: inspection.metadataBlob,
            validation: inspection.validationReport
            )
        )
    }

    private static func resolveMetadata(
        for moduleURL: URL,
        info: [String: String],
        tables: Set<String>,
        validation: GrapheRuntimeValidationReport
    ) -> GrapheModuleMetadata? {
        for reader in metadataReaders {
            if let metadata = reader.readMetadata(
                from: moduleURL,
                info: info,
                tables: tables,
                validation: validation
            ) {
                return metadata
            }
        }
        return nil
    }

    private static func capabilities(for type: ModuleType, hasStrongNumbers: Bool, isInterlinear: Bool) -> [String] {
        var values: [String] = []
        switch type {
        case .bible:
            values.append("passageLookup")
        case .commentary:
            values.append("commentaryLookup")
        case .crossRef, .crossRefNative:
            values.append("crossReferenceLookup")
        case .devotional:
            values.append("devotionalLookup")
        case .dictionary, .encyclopedia, .strongs:
            values.append("articleLookup")
        case .readingPlan:
            values.append("readingPlanLookup")
        case .subheadings:
            values.append("subheadingLookup")
        case .wordIndex:
            values.append("wordIndexLookup")
        case .atlas:
            values.append("mapLookup")
        case .unknown:
            break
        }
        if hasStrongNumbers {
            values.append("strongNumbers")
        }
        if isInterlinear {
            values.append("interlinear")
        }
        return values
    }

    private static func isInterlinearModule(info: [String: String], tables: Set<String>) -> Bool {
        guard tables.contains("verses"),
              info["strong_numbers"]?.lowercased() == "true",
              info["is_strong"]?.lowercased() != "true",
              let hyperlinkLanguages = info["hyperlink_languages"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              hyperlinkLanguages.contains("/")
        else {
            return false
        }
        return true
    }

    private static func linkedLanguages(from info: [String: String]) -> [String] {
        info["hyperlink_languages"]?
            .lowercased()
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func sidecarMetadata(forModuleAt path: String) -> ModuleInfoSidecarMetadata? {
        let sidecarURL = sidecarURL(forModuleAt: path)
        guard let contents = try? String(contentsOf: sidecarURL, encoding: .utf8) else {
            return nil
        }

        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty {
                values[key] = value
            }
        }

        guard !values.isEmpty else { return nil }
        return ModuleInfoSidecarMetadata(
            displayName: values["description"] ?? values["title"] ?? values["name"],
            identifier: values["identifier"] ?? values["id"] ?? values["moduleid"],
            language: values["language"] ?? values["lang"],
            version: values["version"],
            source: values["source"] ?? values["publisher"] ?? values["author"],
            type: values["type"] ?? values["kind"] ?? values["module type"] ?? values["category"],
            hasStrongsCapability: (values["strong_numbers"] ?? values["strongnumbers"] ?? values["strongs"])?.lowercased() == "true"
        )
    }

    private static func normalizedModuleBaseName(for moduleURL: URL) -> String {
        var base = moduleURL.deletingPathExtension().lastPathComponent
        let typeExtensions = [
            "bibles", "commentaries", "dictionaries", "crossreferences",
            "cross_references", "devotions", "subheadings", "words",
            "reading_plan", "readingplan",
        ]

        for typeExtension in typeExtensions {
            let suffix = "." + typeExtension
            if base.lowercased().hasSuffix(suffix.lowercased()) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        return base
    }

    private static func preferredModuleTitle(
        description: String?,
        title: String?,
        fallback: String
    ) -> String {
        let primary = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty {
            return primary
        }

        let secondary = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !secondary.isEmpty {
            return secondary
        }

        return fallback
    }

    private static func sidecarURL(forModuleAt path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let base = normalizedModuleBaseName(for: url)
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        return root
            .appendingPathComponent("_ModuleInfo")
            .appendingPathComponent("\(base).txt")
    }

    private static func moduleType(fromSidecarType value: String?, fallback: ModuleType) -> ModuleType {
        guard let value else { return fallback }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bible", "bibles":
            return .bible
        case "commentary", "commentaries":
            return .commentary
        case "cross references", "cross-reference", "cross references (native)", "crossreferences":
            return .crossRef
        case "devotional", "devotions":
            return .devotional
        case "reading plan", "readingplan":
            return .readingPlan
        case "strongs", "strong's":
            return .strongs
        case "dictionary", "dictionaries":
            return .dictionary
        case "encyclopedia":
            return .encyclopedia
        case "subheadings":
            return .subheadings
        case "word index", "words":
            return .wordIndex
        case "atlas", "bible maps":
            return .atlas
        default:
            return fallback
        }
    }
}
