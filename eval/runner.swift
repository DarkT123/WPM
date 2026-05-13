import Foundation
import AppKit

// MARK: - Test case schema

struct ExpectBlock: Decodable {
    let gate: String                    // "proceed" or "skip"
    let should_expand: Bool?
    let acceptable_outputs: [String]?
    let reason_contains: String?
}

struct TestCase: Decodable {
    let id: String
    let compressed_input: String
    let context_before: String
    let context_after: String
    let focused_bundle_id: String?
    let aggressive: Bool?
    let expect: ExpectBlock
}

struct TestFile: Decodable {
    let version: Int
    let cases: [TestCase]
}

@main
enum Runner {
    static func main() async {
        var path = "eval/test_cases.json"
        for arg in CommandLine.arguments.dropFirst() {
            if !arg.hasPrefix("--") {
                path = arg
                break
            }
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("could not read \(path)\n".utf8))
            exit(2)
        }
        let file: TestFile
        do {
            file = try JSONDecoder().decode(TestFile.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("could not parse \(path): \(error)\n".utf8))
            exit(2)
        }

        var onlyID: String?
        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasPrefix("--only=") { onlyID = String(arg.dropFirst("--only=".count)) }
        }
        var runAI = !CommandLine.arguments.contains("--no-ai")

        let cases = onlyID.map { id in file.cases.filter { $0.id == id } } ?? file.cases
        FileHandle.standardError.write(Data("running \(cases.count) cases (AI=\(runAI ? "on" : "off"))\n".utf8))

        var total = 0
        var gateCorrect = 0
        var aiCalls = 0
        var aiValidJSON = 0
        var aiMatched = 0
        var aiShouldExpandMatch = 0
        var latencies: [Double] = []

        let ai: MiniMaxClient? = MiniMaxClient.makeDefault()
        if runAI && ai == nil {
            FileHandle.standardError.write(Data("no MINIMAX_API_KEY in .env — disabling AI tests\n".utf8))
            runAI = false
        }

        for c in cases {
            total += 1
            let decision = ExpansionGate.check(
                compressed: c.compressed_input,
                contextBefore: c.context_before,
                contextAfter: c.context_after,
                focusedAppBundleID: c.focused_bundle_id,
                aggressiveMode: c.aggressive ?? false
            )
            let gateExpected = c.expect.gate
            let gateActual: String
            let reason: String?
            switch decision {
            case .proceed: gateActual = "proceed"; reason = nil
            case .skip(let r): gateActual = "skip"; reason = r
            }

            var gateOk = (gateActual == gateExpected)
            if gateOk, let needle = c.expect.reason_contains, let r = reason {
                if !r.lowercased().contains(needle.lowercased()) {
                    gateOk = false
                }
            }
            if gateOk { gateCorrect += 1 }

            var note = ""
            if !gateOk {
                note = " gate=\(gateActual) (expected \(gateExpected))" + (reason.map { " reason=\($0)" } ?? "")
            }

            var aiNote = ""
            if runAI, gateActual == "proceed", c.expect.should_expand == true, let ai {
                aiCalls += 1
                let req = ExpansionRequest(
                    compressedInput: c.compressed_input,
                    contextBefore: c.context_before,
                    contextAfter: c.context_after,
                    recentCorrections: [],
                    styleNotes: ""
                )
                let t0 = Date()
                let result = await ai.expand(req)
                let dt = Date().timeIntervalSince(t0) * 1000
                latencies.append(dt)
                switch result {
                case .success(let resp):
                    aiValidJSON += 1
                    if resp.shouldExpand {
                        aiShouldExpandMatch += 1
                        let nout = normalize(resp.expanded)
                        let matched: Bool = {
                            if let accept = c.expect.acceptable_outputs {
                                if accept.contains(where: { normalize($0) == nout }) { return true }
                            }
                            return lettersInOrder(c.compressed_input, nout)
                        }()
                        if matched {
                            aiMatched += 1
                        } else {
                            aiNote = " ai='\(resp.expanded)'"
                        }
                    } else {
                        aiNote = " ai shouldExpand=false (expected true)"
                    }
                case .failure(let err):
                    aiNote = " AI error: \(err.displayMessage)"
                }
            }

            let mark = gateOk && aiNote.isEmpty ? "✓" : "✗"
            print("\(mark) [\(c.id)] \(c.compressed_input)\(note)\(aiNote)")
        }

        let sorted = latencies.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        print("")
        print("---")
        print("gate correct:        \(gateCorrect) / \(total) (\(String(format: "%.1f", Double(gateCorrect) / Double(total) * 100))%)")
        print("ai calls:            \(aiCalls)")
        print("ai valid JSON:       \(aiValidJSON) / \(aiCalls)")
        print("ai should-expand ok: \(aiShouldExpandMatch) / \(aiCalls)")
        print("ai answer correct:   \(aiMatched) / \(aiCalls)")
        print("median latency:      \(String(format: "%.0f", median)) ms")
        print("p95 latency:         \(String(format: "%.0f", p95)) ms")

        let allOk = gateCorrect == total && (!runAI || aiMatched == aiCalls)
        exit(allOk ? 0 : 1)
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        let stripped = t.unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }
        t = String(String.UnicodeScalarView(stripped))
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func lettersInOrder(_ compressed: String, _ candidate: String) -> Bool {
        let needle = Array(compressed.lowercased())
        var i = 0
        for ch in candidate.lowercased() where i < needle.count && ch == needle[i] {
            i += 1
        }
        return i == needle.count
    }
}
