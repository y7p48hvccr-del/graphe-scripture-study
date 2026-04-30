import Foundation

struct StrongsEntry {
    let topic:              String
    let lexeme:             String
    let transliteration:    String
    let pronunciation:      String
    let shortDefinition:    String
    let derivation:         String
    let strongsDefinition:  String   // The "Strong's:" section — separate from derivation
    let kjv:                String
    let references:         String   // Cross-refs: ETCBC#, OSHL, TWOT, GK, Greek/Hebrew equivalents
    let cognates:           [String]
    let expandedDefinition: String   // Merged-dictionary rich definition when present
    let sourceFlags:        String   // strong | sece | both
    let rawDefinition:      String   // Raw HTML definition — fallback for VGNT/prose-style modules
}

extension StrongsEntry {
    var hasExpandedDefinition: Bool {
        !expandedDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var preferredDefinitionSectionTitle: String {
        if hasExpandedDefinition {
            return sourceFlags == "both" ? "Merged Entry" : "Entry"
        }
        return "Strong's"
    }

    var preferredDefinitionHTML: String {
        if hasExpandedDefinition {
            return expandedDefinition
        }
        if !strongsDefinition.isEmpty {
            return strongsDefinition
        }
        if !shortDefinition.isEmpty {
            return shortDefinition
        }
        if !derivation.isEmpty {
            return derivation
        }
        if !kjv.isEmpty {
            return kjv
        }
        return rawDefinition
    }
}
