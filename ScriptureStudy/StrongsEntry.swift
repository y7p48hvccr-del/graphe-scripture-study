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
}
