import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("LiteRT production runtime contracts")
struct LiteRTProductionRuntimeTests {
    @Test("Model store rejects a truncated package")
    func modelStoreRejectsTruncatedPackage() throws {
        let manifest = LiteRTModelManifest(
            fileName: "test.litertlm",
            byteCount: 4,
            sha256: "unused"
        )
        let store = LiteRTModelStore(manifest: manifest)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0, 1, 2]).write(to: fileURL)

        #expect(throws: LiteRTModelStoreError.self) {
            try store.validateModel(at: fileURL)
        }
    }

    @Test("Installer hashes model bytes deterministically")
    func installerHashesModel() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("test".utf8).write(to: fileURL)

        #expect(
            try LiteRTModelInstaller.sha256(of: fileURL)
                == "9f86d081884c7d659a2feaa0c55ad015"
                    + "a3bf4f1b2b0b822cd15d6c15b0f00a08"
        )
    }

    @MainActor
    @Test("Natural definition questions trigger the inline Insight contract")
    func detectsDefinitionRequests() {
        #expect(
            definitionTerm(in: "What does prudence mean?") == "prudence"
        )
        #expect(
            definitionTerm(in: "What is the meaning of act and potency?")
                == "act and potency"
        )
        #expect(
            definitionTerm(in: "Please define natural law.") == "natural law"
        )
        #expect(
            definitionTerm(in: "What is prudence?") == "prudence"
        )
    }

    @Test("Insight annotations cannot rewrite existing link markup")
    func insightAnnotationsDoNotNest() {
        let response = ModelResponse(
            text: "The deuterocanonical books form a wider canon.",
            keyTerms: [
                KeyTerm(displayText: "deuterocanonical"),
                KeyTerm(displayText: "canon")
            ]
        )

        #expect(
            response.annotatedText
                == "The [deuterocanonical](aq://deuterocanonical) books form a wider "
                    + "[canon](aq://canon)."
        )
        #expect(!response.annotatedText.contains("](["))
    }

    @MainActor
    @Test("Visible responses omit generated wrapper labels")
    func visibleResponsesOmitWrapperLabels() {
        #expect(
            LiteRTAquinasModel.visibleResponseText(
                from: "Answer: A good act can be corrupted by an evil intention."
            ) == "A good act can be corrupted by an evil intention."
        )
        #expect(
            LiteRTAquinasModel.visibleResponseText(
                from: "## **Response:**\nMercy perfects justice."
            ) == "Mercy perfects justice."
        )
        #expect(
            LiteRTAquinasModel.visibleResponseText(
                from: "The answer: prudence governs practical judgment."
            ) == "The answer: prudence governs practical judgment."
        )
    }

    @Test("Generation guard rejects exact repetitive loops")
    func generationGuardRejectsRepetitiveLoops() {
        let sentence = "Prudence directs practical reason toward the right action in a concrete circumstance"
        #expect(
            LiteRTGenerationGuard.hasDegenerateRepetition(
                in: "\(sentence). \(sentence)."
            )
        )
        #expect(
            !LiteRTGenerationGuard.hasDegenerateRepetition(
                in: "Prudence directs practical reason. Justice gives another person what is due."
            )
        )
    }

    @Test("Conversation decoding stays deterministic for the quantized checkpoint")
    func conversationSamplingStaysDeterministic() {
        let primary = LiteRTSampling.conversation
        let retry = LiteRTSampling.conversation.retryVariant

        #expect(primary.topK == 1)
        #expect(primary.topP == 1)
        #expect(primary.temperature == 0)
        #expect(retry.topK == 1)
        #expect(retry.topP == 1)
        #expect(retry.temperature == 0)
        #expect(retry.seed == 0)
        #expect(LiteRTSampling.structured.retryVariant.seed == 7)
    }

    @Test("Generation guard rejects mixed-script token corruption")
    func generationGuardRejectsMixedScriptCorruption() {
        let corrupted = String(
            repeating: "dynamは scotch 法 chim العربية 한글 磨 random_code ",
            count: 8
        )

        #expect(LiteRTGenerationGuard.hasDegenerateOutput(in: corrupted))
        #expect(
            !LiteRTGenerationGuard.hasDegenerateOutput(
                in: "Aquinas sometimes uses the Greek term phronesis, but the explanation remains coherent English prose."
            )
        )
    }

    @Test("Generation guard catches separated phrase loops")
    func generationGuardRejectsSeparatedPhraseLoops() {
        let phrase = "virtue directs a person toward the good through stable practical habits"
        let response = "\(phrase), especially in difficult choices. A separate thought appears. \(phrase)."

        #expect(LiteRTGenerationGuard.hasDegenerateRepetition(in: response))
        #expect(
            LiteRTGenerationGuard.responseBeforeRepetition(in: response)?
                .contains("A separate thought appears") == true
        )
        #expect(
            LiteRTGenerationGuard.responseBeforeRepetition(in: response)?
                .components(separatedBy: phrase).count == 2
        )
    }

    @MainActor
    @Test("Thinking summary matches a forgiveness question")
    func thinkingSummaryMatchesForgivenessQuestion() {
        let context = ConversationContext(
            transcript: [
                .user(
                    "How do I forgive myself when I keep making moral mistakes?",
                    nil,
                    []
                )
            ]
        )

        #expect(
            LiteRTAquinasModel.approachSummary(for: context) == [
                "Distinguishing forgiveness, repentance, guilt, and growth after repeated failure."
            ]
        )
    }

    @MainActor
    @Test("Thinking summary fallback includes the question's focus")
    func thinkingSummaryFallbackEchoesQuestionFocus() {
        let context = ConversationContext(
            transcript: [
                .user(
                    "How can friendship help a person become more patient?",
                    nil,
                    []
                )
            ]
        )

        let summary = LiteRTAquinasModel.approachSummary(for: context)
        #expect(summary.count == 1)
        #expect(summary[0].contains("friendship"))
        #expect(summary[0].contains("patient"))
    }

    @MainActor
    @Test("Explicit authorship corrections reject contradictory drafts")
    func explicitAuthorshipCorrectionRejectsContradiction() {
        let correction = LiteRTAquinasModel.authorshipCorrectionDetails(
            in: "The Didache was not written by Paul; its author is unknown, right?"
        )
        #expect(correction?.subject == "The Didache")
        #expect(correction?.author == "Paul")

        #expect(
            !LiteRTAquinasModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul is known to have written the Didache."
            )
        )
        #expect(
            LiteRTAquinasModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul wrote the Didache, although its author is unknown."
            )
        )
        #expect(
            !LiteRTAquinasModel.responseContradictsExplicitAuthorshipCorrection(
                question: "The Didache was not written by Paul.",
                response: "Paul is not known to have written the Didache; its author is unknown."
            )
        )
    }

    @Test("Canvas collapses an Insight whose title matches its Node")
    func canvasCollapsesMatchingInsightTitle() {
        let matching = InsightModel(title: "Didache", definition: "An anonymous early Christian text.")
        let related = InsightModel(title: "Two Ways", definition: "A moral teaching within the text.")

        let collapsed = canvasInsightMembers(
            nodeLabel: "The Didache",
            insights: [matching, related],
            preservesMatchingTitle: false
        )
        #expect(collapsed.map(\.id) == [related.id])
        #expect(
            canvasInsightMembers(
                nodeLabel: "The Didache",
                insights: [matching],
                preservesMatchingTitle: true
            ).map(\.id) == [matching.id]
        )
    }

    @Test("Loopback backend addresses are not physical-device recovery targets")
    func loopbackBackendDetection() {
        #expect(
            AquinasBackendConfiguration.isLoopback(
                URL(string: "http://127.0.0.1:8000")!
            )
        )
        #expect(
            !AquinasBackendConfiguration.isLoopback(
                URL(string: "http://192.168.1.50:8000")!
            )
        )
    }

    @MainActor
    private func definitionTerm(in request: String) -> String? {
        LiteRTAquinasModel.definitionRequestTerm(
            in: [.user(request, nil, [])]
        )
    }
}
