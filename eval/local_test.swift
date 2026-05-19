import Foundation

@main
enum LocalTest {
    static func main() {
        let cases: [(String, String)] = [
            ("imgoingtothestoretmr",      "I'm going to the store tomorrow"),
            ("thedogranhome",             "The dog ran home"),
            ("iwanttogotoschool",         "I want to go to school"),
            ("letmeknowwhenyourehome",    "Let me know when you're home"),
            ("dontforgetmymeetingrn",     "Don't forget my meeting right now"),
            ("imrunninglate",             "I'm running late"),
            ("happybday",                 "Happy birthday"),
            ("brbgrabbingcoffee",         "Be right back grabbing coffee"),
            ("idkwhattodo",               "I don't know what to do"),
            // Spelling-correction cases:
            ("ithinkithinktehdog",        "I think i think the dog"),     // teh → the
            ("missspelling",              "Misspelling"),                  // miss → miss
            ("recievedthemessage",        "Received the message"),         // recieve → receive
            ("seperatethewords",          "Separate the words"),           // seperate → separate
            ("hellotehre",                "Hello there"),                  // tehre → there
            ("canyoupickupgrocerieswhenuhome", "Can you pick up groceries when you home"),
            // Cases the local pipeline should NOT handle confidently (expect low conf):
            ("tdrh",                      "—  (single-letter shorthand; needs AI)"),
            ("iwgotosch",                 "—  (mixed partials; needs AI)"),
            ("iwbthrin5min",              "—  (digits + mixed; needs AI)"),
        ]
        var totalMs = 0.0
        var failures = 0
        for (input, expected) in cases {
            let r = LocalPipeline.run(input)
            totalMs += r.latencyMs
            let mark: String
            let note: String
            if r.confidence >= 0.85 {
                if r.expandedSentence == expected {
                    mark = "✓"
                    note = ""
                } else {
                    mark = "✗"
                    note = " got '\(r.expandedSentence)'"
                    failures += 1
                }
            } else {
                // Low confidence — AI fallback expected.
                mark = "↘"
                note = " conf=\(String(format: "%.2f", r.confidence)) → would fall through to AI"
            }
            print("\(mark) [\(input)] → '\(r.expandedSentence)' (\(String(format: "%.1f", r.latencyMs)) ms, conf \(String(format: "%.2f", r.confidence)), segs \(r.segments))\(note)")
        }
        print("")
        print("--- \(cases.count) cases, \(failures) failures, total \(String(format: "%.1f", totalMs)) ms")
        exit(failures == 0 ? 0 : 1)
    }
}
