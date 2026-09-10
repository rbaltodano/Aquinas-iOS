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

    @Test("Named passages begin at their own source text, not at a chapter's opening")
    func namedPassagesUseSourceTextAnchors() throws {
        let provider = try MiniLMGroundingProvider()
        let checks = [
            (
                question: "What is the parable of the Good Samaritan about?",
                sourceText: "a certain samaritan"
            ),
            (
                question: "How did Jesus teach us to pray?",
                sourceText: "lord, teach us to pray"
            ),
            (
                question: "What does the Our Father say?",
                sourceText: "our father in heaven"
            ),
            (
                question: "What do the Gospels say about the resurrection of Jesus?",
                sourceText: "he isn't here, but is risen"
            )
        ]

        for check in checks {
            let references = provider.references(for: check.question, limit: 3)
            #expect(
                references.contains {
                    $0.id.hasPrefix("citation-")
                        && $0.facts.localizedCaseInsensitiveContains(check.sourceText)
                },
                "named-passage pointer did not begin at its source text for: \(check.question)"
            )
        }
    }

    @Test("Doctrinal questions still retrieve the corpus itself")
    func doctrinalQuestionRetrievesCorpus() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(for: "Is God altogether simple?", limit: 3)
        #expect(!references.isEmpty)
        #expect(references.contains { $0.facts.count > 40 })
    }

    @Test("A named council title finds its relevant decree, not its front matter")
    func trentJustificationFindsDecree() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(
            for: "What did the Council of Trent teach about justification?",
            limit: 3
        )

        let combined = references.map(\.facts).joined(separator: "\n").lowercased()
        #expect(
            combined.contains("not remission of sins merely"),
            "Trent source routing did not reach Chapter VII's definition of justification"
        )
    }

    @Test("Authority-section pointers select the primary-source formulation")
    func authoritySectionPointersSelectPrimaryText() throws {
        let provider = try MiniLMGroundingProvider()
        let checks = [
            (
                question: "How did Nicaea describe Christ's relationship to the Father?",
                sourceText: "very god of very god"
            ),
            (
                question: "How did Chalcedon describe Christ?",
                sourceText: "in two natures"
            ),
            (
                question: "What did the Council of Trent teach about the real presence?",
                sourceText: "on the real presence of our lord"
            ),
            (
                question: "How does the Roman Catechism define Baptism?",
                sourceText: "consists of ablution"
            )
        ]

        for check in checks {
            let references = provider.references(for: check.question, limit: 3)
            #expect(
                references.contains {
                    $0.id.hasPrefix("authority-section-")
                        && $0.facts.localizedCaseInsensitiveContains(check.sourceText)
                },
                "authority pointer did not select the source's own formulation for: \(check.question)"
            )
        }
    }

    @Test("An authority pointer includes the section's explanatory context")
    func authoritySectionIncludesFollowingContext() throws {
        let provider = try MiniLMGroundingProvider()
        let references = provider.references(
            for: "What did the Council of Trent teach about the real presence?",
            limit: 3
        )
        let combined = references.map(\.facts).joined(separator: "\n").lowercased()
        #expect(
            combined.contains("truly, real") && combined.contains("substantially contained"),
            "authority lookup stopped at Trent's heading instead of including Chapter I's explanation"
        )
    }

    @Test("Authority sections enable evidence-first generation")
    func authoritySectionEnablesEvidenceFirstInstruction() {
        let reference = AquinasGroundingReference(
            id: "authority-section-council-of-trent-0",
            title: "Canons and Decrees of the Council of Trent",
            sourceName: "Canons and Decrees of the Council of Trent",
            facts: "CHAPTER VII. What the Justification of the impious is.",
            retrievalAliases: []
        )
        let context = ConversationContext(
            transcript: [.user("What did Trent teach about justification?", nil, [])]
        )

        let instruction = LiteRTAquinasModel.evidenceExperimentInstruction(
            context: context, references: [reference]
        )
        #expect(instruction.contains("exact primary-source section"))
        #expect(instruction.contains("Do not use general background knowledge to fill a gap"))
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
