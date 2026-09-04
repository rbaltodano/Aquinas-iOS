import Foundation
import Testing
@testable import Aquinas_iOS

/// End-to-end checks against the real bundled 48k-passage export, covering the three failure modes
/// a measured audit of that corpus turned up. These assert retrieval *correctness*, not merely that
/// retrieval returns rows — the weaker bar that originally let all three ship.
@Suite("MiniLM grounding retrieval")
struct MiniLMGroundingRetrievalTests {
    @Test("Council questions ground in curated facts, not Roman history")
    func councilQuestionAvoidsClassicalHistory() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(
            for: "What did the Council of Nicaea decide about the Son?",
            limit: 3
        )

        // Semantic search alone answers this out of Livy, Herodotus and Plutarch, matching
        // "council" and *Nicaea the Greek city*. The curated layer must anchor it instead.
        #expect(references.contains { $0.id == "nicaea-325" })

        let classicalSources = ["livy", "herodotus", "plutarch", "thucydides", "tacitus"]
        for reference in references {
            let id = reference.id.lowercased()
            #expect(
                !classicalSources.contains { id.contains($0) },
                "classical history reached the prompt as grounding: \(reference.id)"
            )
        }
    }

    @Test("Curated ids survive so verified answers stay reachable")
    func curatedReferencesKeepStableIdentifiers() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(
            for: "What was the second ecumenical council?",
            limit: 3
        )
        // LiteRTAquinasModel.verifiedGroundedResponse gates on this exact id.
        #expect(references.contains { $0.id == "constantinople-381" })
    }

    @Test("An explicit citation resolves to that chapter's real text")
    func citationResolvesToChapterText() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(for: "John chapter 14", limit: 3)

        #expect(!references.isEmpty, "a cited chapter present in the corpus returned nothing")
        let combined = references.map(\.facts).joined(separator: "\n").lowercased()
        #expect(
            combined.contains("don't let your heart be troubled")
                || combined.contains("the way, the truth"),
            "John 14 lookup did not return the chapter's own text"
        )
    }

    @Test("Doctrinal questions still retrieve the corpus itself")
    func doctrinalQuestionRetrievesCorpus() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(for: "Is God altogether simple?", limit: 3)
        #expect(!references.isEmpty)
        #expect(references.contains { $0.facts.count > 40 })
    }

    @Test("Questions the corpus cannot answer ground in nothing")
    func offTopicQuestionReturnsNoGrounding() throws {
        let provider = try MiniLMGroundingProvider()
        // Scores ~0.37 similarity against this corpus, far below the 0.62 floor. Returning
        // nothing is correct: generation proceeds ungrounded rather than grounded in something
        // false.
        #expect(provider.references(for: "How do I bake sourdough bread?", limit: 3).isEmpty)
        #expect(provider.references(for: "What is the capital of Japan?", limit: 3).isEmpty)
    }
}
