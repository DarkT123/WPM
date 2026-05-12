import Foundation

// Mirrors edge/shared/types.ts. Keep field names exact — Codable decodes from
// the wire format with no remapping.

enum Domain: String, Codable, CaseIterable, Identifiable {
    case general, school, business, coding, texting, research
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct WordCandidate: Codable, Hashable, Identifiable {
    let token: String
    let selected: String
    let candidates: [String]
    let confidence: Double
    var id: String { "\(token)-\(selected)" }
}

enum PredictionSource: String, Codable {
    case local, ai, phrase, exact
}

struct PredictRequest: Codable {
    let tokens: [String]
    let contextBefore: String
    let contextAfter: String
    let domain: Domain
    let useAI: Bool
}

struct PredictResponse: Codable {
    let prediction: String
    let alternatives: [String]
    let wordCandidates: [WordCandidate]
    let confidence: Double
    let latencyMs: Int
    let source: PredictionSource
    let aiAvailable: Bool
    let aiSuggestions: [String]?
}

struct LearnRequest: Codable {
    let compressed: String
    let corrected: String
    let domain: Domain?
}

struct LearnResponse: Codable { let ok: Bool }

struct HealthResponse: Codable {
    let ok: Bool
    let aiAvailable: Bool
    let aiModel: String
    let aiTimeoutMs: Int
}
