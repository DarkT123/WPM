import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // Backend
    @Published var backendURLString: String = "http://localhost:3002"
    @Published var health: HealthResponse?
    @Published var healthError: String?

    // Predict inputs
    @Published var compressed: String = "i wa to ma a pr ma re ap"
    @Published var contextBefore: String = ""
    @Published var contextAfter: String = ""
    @Published var domain: Domain = .general
    @Published var useAI: Bool = false

    // Predict outputs
    @Published var prediction: String = ""
    @Published var alternatives: [String] = []
    @Published var aiSuggestions: [String] = []
    @Published var wordCandidates: [WordCandidate] = []
    @Published var sentenceConfidence: Double = 0
    @Published var latencyMs: Int? = nil
    @Published var source: PredictionSource? = nil
    @Published var predictError: String?

    // Session-local corrections log (the backend persists its own; this list
    // shows what *this session* has taught it).
    struct CorrectionEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let compressed: String
        let corrected: String
        let domain: Domain
    }
    @Published var corrections: [CorrectionEntry] = []
    @Published var learnError: String?

    private var api: EdgeAPI

    init() {
        self.api = EdgeAPI()
    }

    func applyBaseURL() {
        guard let u = URL(string: backendURLString) else { return }
        Task { await api.setBaseURL(u) }
    }

    // MARK: - Health

    func refreshHealth() async {
        do {
            let h = try await api.health()
            self.health = h
            self.healthError = nil
        } catch {
            self.health = nil
            self.healthError = (error as? EdgeAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Predict (debounced)

    private var inflight: Task<Void, Never>?

    func schedulePredict() {
        inflight?.cancel()
        let tokens = compressed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            prediction = ""; alternatives = []; aiSuggestions = []; wordCandidates = []
            sentenceConfidence = 0; latencyMs = nil; source = nil; predictError = nil
            return
        }
        let req = PredictRequest(
            tokens: tokens,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            domain: domain,
            useAI: useAI
        )
        inflight = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
            if Task.isCancelled { return }
            await self?.runPredict(req)
        }
    }

    private func runPredict(_ req: PredictRequest) async {
        do {
            let resp = try await api.predict(req)
            self.prediction = resp.prediction
            self.alternatives = resp.alternatives
            self.aiSuggestions = resp.aiSuggestions ?? []
            self.wordCandidates = resp.wordCandidates
            self.sentenceConfidence = resp.confidence
            self.latencyMs = resp.latencyMs
            self.source = resp.source
            self.predictError = nil
        } catch {
            self.predictError = (error as? EdgeAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Learn

    func teach(corrected: String) async {
        let tokens = compressed.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        let correctedWords = corrected.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty, tokens.count == correctedWords.count else {
            self.learnError = "Correction must have the same word count as tokens (\(tokens.count))."
            return
        }
        let req = LearnRequest(
            compressed: tokens.joined(separator: " "),
            corrected: correctedWords.joined(separator: " "),
            domain: domain
        )
        do {
            _ = try await api.learn(req)
            self.corrections.insert(
                .init(timestamp: Date(), compressed: req.compressed, corrected: req.corrected, domain: domain),
                at: 0
            )
            self.learnError = nil
            schedulePredict() // refetch so the new exact-match shows up
        } catch {
            self.learnError = (error as? EdgeAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
