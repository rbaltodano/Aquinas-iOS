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

    @Test("Model store accepts an exact development probe package")
    func modelStoreAcceptsDevelopmentProbePackage() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data([0, 1, 2, 3]).write(to: fileURL)
        let manifest = LiteRTModelManifest(
            fileName: fileURL.lastPathComponent,
            byteCount: 4,
            sha256: "development-probe"
        )
        let store = LiteRTModelStore(
            manifest: manifest,
            developmentModelURL: fileURL
        )

        #expect(try store.installedModelURL() == fileURL)
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

    @MainActor
    @Test("Broad what-is questions do not become definition cards")
    func broadQuestionsDoNotTriggerDefinitionCards() {
        #expect(definitionTerm(in: "What is the second ecumenical council?") == nil)
        #expect(definitionTerm(in: "What is the Peloponnesian War about?") == nil)
        #expect(definitionTerm(in: "What is the best way to learn JavaScript?") == nil)
        #expect(definitionTerm(in: "What is happening with this code?") == nil)
        #expect(definitionTerm(in: "What is natural law?") == "natural law")
    }

    @Test("Validated direct definitions render an inline Insight card")
    func validatedDefinitionRendersInlineCard() {
        let insight = ConceptDefinition(
            word: "Prudence",
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "Right reason applied to action.",
            example: "",
            context: "Virtue"
        )
        let response = ModelResponse(
            text: "Prudence guides practical judgment.",
            keyTerms: [KeyTerm(displayText: "Prudence")],
            insight: insight
        )

        #expect(InlineInsightMarkup.insights(in: response.annotatedText) == [insight])
        #expect(response.annotatedText.contains("[Prudence](aq://prudence)"))
    }

    @Test("Ordinary responses never render an inline Insight card")
    func ordinaryResponseDoesNotRenderInlineCard() {
        let response = ModelResponse(
            text: "The council met in 381.",
            keyTerms: [KeyTerm(displayText: "council")]
        )

        #expect(InlineInsightMarkup.insights(in: response.annotatedText).isEmpty)
    }

    @MainActor
    @Test("Unrelated substantial questions start with fresh context")
    func topicShiftStartsFreshContext() {
        #expect(
            LiteRTAquinasModel.startsFreshTopic(
                latestQuestion: "What was the Peloponnesian War about?",
                previousQuestion: "Was the Didache written by the Apostle Paul?"
            )
        )
        #expect(
            LiteRTAquinasModel.startsFreshTopic(
                latestQuestion: "Can you write some JavaScript cursor tracker code?",
                previousQuestion: "What was the Peloponnesian War about?"
            )
        )
        #expect(
            !LiteRTAquinasModel.startsFreshTopic(
                latestQuestion: "Why was that council important?",
                previousQuestion: "What was the second ecumenical council?"
            )
        )
    }

    @MainActor
    @Test("Previous answers cannot be returned verbatim for a new turn")
    func repeatedPriorAnswerIsDetected() {
        let answer = "The Apostle Paul's letter to the elders is presented as a model of Christian teaching and living."
        let transcript: [ChatBlock] = [
            .user("Tell me about an early church letter.", nil, []),
            .text(answer),
            .user("Write some JavaScript cursor tracker code.", nil, [])
        ]

        #expect(
            LiteRTAquinasModel.repeatsEarlierAnswer(
                answer,
                transcript: transcript
            )
        )
        #expect(
            !LiteRTAquinasModel.repeatsEarlierAnswer(
                "A cursor tracker listens for pointer movement and updates coordinates.",
                transcript: transcript
            )
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
        #expect(
            LiteRTAquinasModel.visibleResponseText(
                from: "<TASK:ANSWER_USER>Mercy perfects justice.</TASK:ANSWER_USER>"
            ) == "Mercy perfects justice."
        )
    }

    @MainActor
    @Test("Plain conversation output never exposes a legacy JSON wrapper")
    func plainConversationOutputRecoversLegacyJSON() {
        let raw = #"{"thinking_summary":["Hidden metadata"],"response":"Constantinople was the second ecumenical council.","key_terms":[]}"#

        #expect(
            LiteRTAquinasModel.plainConversationText(from: raw)
                == "Constantinople was the second ecumenical council."
        )
        #expect(!LiteRTAquinasModel.plainConversationText(from: raw).contains("key_terms"))
    }

    @MainActor
    @Test("Single-pass key-term metadata accepts only exact answer text")
    func singlePassKeyTermMetadataIsValidated() {
        let raw = #"{"response":"The First Council of Constantinople met in 381.","key_terms":[{"display_text":"First Council of Constantinople","canonical_term":"First Council of Constantinople","context_excerpt":"The First Council of Constantinople met in 381."},{"display_text":"Council of Adhesion","canonical_term":"Council of Adhesion","context_excerpt":"Council of Adhesion"}]}"#
        let response = LiteRTAquinasModel.conversationResponse(from: raw)

        #expect(response.text == "The First Council of Constantinople met in 381.")
        #expect(response.keyTerms.map(\.displayText) == ["First Council of Constantinople"])
    }

    @MainActor
    @Test("Inline markers become key terms with no separate recall step")
    func inlineMarkersBecomeKeyTerms() {
        let raw = "Aquinas distinguishes {{essence}} from {{existence}} to explain change."
        let (text, keyTerms) = LiteRTAquinasModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Aquinas distinguishes essence from existence to explain change.")
        #expect(keyTerms.map(\.displayText) == ["essence", "existence"])
        #expect(keyTerms.allSatisfy { text.contains($0.displayText) })
    }

    @MainActor
    @Test("An unterminated inline marker becomes plain prose without truncation")
    func unterminatedInlineMarkerPreservesProse() {
        let raw = "Aquinas distinguishes {{essence}} from exis{{tence"
        let (text, keyTerms) = LiteRTAquinasModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Aquinas distinguishes essence from existence")
        #expect(!text.contains("{{"))
        #expect(keyTerms.map(\.displayText) == ["essence"])
    }

    @MainActor
    @Test("Invalid inline metadata preserves its exact inner prose")
    func invalidInlineMarkerPreservesInnerProse() {
        let oversizedTerm = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces)
        let raw = "Before {{\(oversizedTerm)}} after."
        let (text, keyTerms) = LiteRTAquinasModel.inlineAnnotatedResponse(from: raw)

        #expect(text == "Before \(oversizedTerm) after.")
        #expect(keyTerms.isEmpty)
    }

    @MainActor
    @Test("Conversation card previews hide markers and retain highlighted terms")
    func conversationCardPreviewFormatsInsightMarkup() {
        let segments = ConversationCardAnswerFormatting.segments(
            from: "Aquinas joins {{prudence}} to *[right reason](aq://right-reason)*."
        )

        #expect(
            segments == [
                .plain("Aquinas joins "),
                .insight("prudence"),
                .plain(" to "),
                .insight("right reason"),
                .plain(".")
            ]
        )
    }

    @MainActor
    @Test("Conversation card previews preserve prose after a dangling marker")
    func conversationCardPreviewPreservesDanglingMarkerText() {
        let segments = ConversationCardAnswerFormatting.segments(
            from: "Aquinas distinguishes {{essence}} from exis{{tence"
        )

        #expect(
            segments == [
                .plain("Aquinas distinguishes "),
                .insight("essence"),
                .plain(" from existence")
            ]
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

    @MainActor
    @Test("Quoted Insights precede the user question in model markup")
    func quotedInsightPromptMarkup() {
        let insight = ConceptDefinition(
            word: "Act & Potency",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "A capacity < ordered toward > actuality.",
            example: ""
        )

        let prompt = ConversationPromptMarkup.userPrompt(
            question: "How does this apply to change?",
            quotedInsight: insight
        )

        #expect(prompt.hasPrefix("<insight_quote>"))
        #expect(prompt.contains("<title>Act &amp; Potency</title>"))
        #expect(
            prompt.contains(
                "<definition>A capacity &lt; ordered toward &gt; actuality.</definition>"
            )
        )
        #expect(
            prompt.contains(
                "</insight_quote>\n\nUser question:\nHow does this apply to change?"
            )
        )
        #expect(!prompt.contains("<quoted_insight"))
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
    @Test("Thinking summary fallback avoids echoing the user's question")
    func thinkingSummaryFallbackAvoidsQuestionEcho() {
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
        #expect(
            summary == [
                "Identifying the central claim and checking the relevant distinctions and evidence."
            ]
        )
        #expect(!summary[0].contains("Focusing on"))
    }

    @Test("Local grounding distinguishes the first councils and icon council")
    func localGroundingRetrievesCouncilReferences() {
        let references = LocalAquinasGroundingProvider().references(
            for: "What were the first and second ecumenical councils?",
            limit: 3
        )
        let ids = Set(references.map(\.id))

        #expect(ids.contains("nicaea-325"))
        #expect(ids.contains("constantinople-381"))
        #expect(
            references.first { $0.id == "constantinople-381" }?.facts
                .contains("not called the Council of Adhesion") == true
        )
    }

    @Test("Local grounding corrects Didache authorship")
    func localGroundingRetrievesDidacheAuthorship() {
        let references = LocalAquinasGroundingProvider().references(
            for: "Was the Didache written by Paul?",
            limit: 2
        )

        #expect(references.first?.id == "didache-authorship")
        #expect(references.first?.facts.contains("author is unknown") == true)
    }

    @MainActor
    @Test("Direct grounded council questions bypass contradictory generation")
    func directCouncilQuestionUsesVerifiedAnswer() throws {
        let question = "What was the second ecumenical council?"
        let references = LocalAquinasGroundingProvider().references(
            for: question,
            limit: 3
        )
        let response = try #require(
            LiteRTAquinasModel.groundedResponse(
                for: question,
                references: references
            )
        )

        #expect(response.text.contains("First Council of Constantinople"))
        #expect(response.text.contains("381"))
        #expect(!response.text.contains("Nicaea (325) is called the second"))
        #expect(
            response.keyTerms.map(\.displayText) == [
                "First Council of Constantinople",
                "Nicene-Constantinopolitan Creed"
            ]
        )
        #expect(response.thinkingSummary.first?.contains("Constantinople in 381 was second") == true)
    }

    @MainActor
    @Test("Direct grounded Didache questions bypass false attribution")
    func directDidacheQuestionUsesVerifiedAnswer() throws {
        let question = "Was the Didache written by Paul?"
        let references = LocalAquinasGroundingProvider().references(
            for: question,
            limit: 3
        )
        let response = try #require(
            LiteRTAquinasModel.groundedResponse(
                for: question,
                references: references
            )
        )

        #expect(response.text.contains("author is unknown"))
        #expect(response.text.contains("not known to have been written by the Apostle Paul"))
    }

    @MainActor
    @Test("Structured local responses preserve exact key terms and public summaries")
    func structuredConversationResponseIsValidated() {
        let raw = #"""
        {
          "thinking_summary": ["Distinguishing Nicaea in 325 from Constantinople in 381."],
          "response": "The first council met at Nicaea in 325. The second met at Constantinople in 381.",
          "key_terms": [
            {
              "display_text": "The first council met at Nicaea",
              "canonical_term": "First Council of Nicaea",
              "context_excerpt": "The first council met at Nicaea in 325."
            },
            {
              "display_text": "Council of Adhesion",
              "canonical_term": "Council of Adhesion",
              "context_excerpt": "This excerpt does not occur in the response."
            }
          ]
        }
        """#

        let response = LiteRTAquinasModel.conversationResponse(from: raw)

        #expect(response.thinkingSummary.count == 1)
        #expect(response.keyTerms.count == 1)
        #expect(response.keyTerms.first?.displayText == "The first council met at Nicaea")
        #expect(
            response.annotatedText.contains(
                "[The first council met at Nicaea](aq://first-council-of-nicaea)"
            )
        )
        #expect(!response.annotatedText.contains("Council of Adhesion"))
    }

    @MainActor
    @Test("Truncated local JSON recovers the answer without exposing its wrapper")
    func truncatedConversationJSONRecoversAnswer() {
        let raw = #"""
        { "thinking_summary": ["A noisy plan."], "response": "The First Council of Constantinople (381) is called the second ecumenical council.
        """#
        let fallback = [
            "Comparing the established sequence: Nicaea in 325 was first, Constantinople in 381 was second, and Nicaea II in 787 was seventh."
        ]

        let response = LiteRTAquinasModel.conversationResponse(
            from: raw,
            fallbackThinkingSummary: fallback
        )

        #expect(
            response.text
                == "The First Council of Constantinople (381) is called the second ecumenical council."
        )
        #expect(response.thinkingSummary == fallback)
        #expect(!response.text.contains("thinking_summary"))
        // No heuristic fallback fills in key terms anymore — only the model's own inline
        // {{markers}} do, and truncated/malformed JSON never went through that path.
        #expect(response.keyTerms.isEmpty)
    }

    @MainActor
    @Test("Generic one-word annotation fragments are rejected")
    func genericKeyTermFragmentsAreRejected() {
        let raw = #"""
        {
          "thinking_summary": ["Checking the established historical sequence."],
          "response": "The First Council of Constantinople was the second ecumenical council.",
          "key_terms": [
            {
              "display_text": "second",
              "canonical_term": "second",
              "context_excerpt": "The First Council of Constantinople was the second ecumenical council."
            },
            {
              "display_text": "First Council of Constantinople",
              "canonical_term": "First Council of Constantinople",
              "context_excerpt": "The First Council of Constantinople was the second ecumenical council."
            }
          ]
        }
        """#

        let response = LiteRTAquinasModel.conversationResponse(from: raw)
        #expect(response.keyTerms.map(\.displayText) == ["First Council of Constantinople"])
    }

    @MainActor
    @Test("Generic model summaries are replaced by an inquiry-specific fallback")
    func genericStructuredThinkingSummaryUsesFallback() {
        let raw = #"""
        {
          "thinking_summary": ["Focusing on the user's question and the distinctions needed for a direct answer."],
          "response": "Prudence governs practical judgment.",
          "key_terms": []
        }
        """#
        let fallback = ["Distinguishing practical judgment from theoretical knowledge."]

        let response = LiteRTAquinasModel.conversationResponse(
            from: raw,
            fallbackThinkingSummary: fallback
        )

        #expect(response.thinkingSummary == fallback)
    }

    @MainActor
    @Test("Thinking summaries persist and older branches still decode")
    func responsePresentationMetadataPersistsCompatibly() throws {
        var branch = ChatBranch(startingConcept: nil)
        branch.setResponsePresentation(
            ResponsePresentationMetadata(
                responseIndex: 1,
                showsThinking: true,
                thinkingSummary: ["Comparing the two councils by date and doctrine."]
            )
        )

        let encoded = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(ChatBranch.self, from: encoded)
        #expect(
            decoded.responsePresentation(at: 1)?.thinkingSummary
                == ["Comparing the two councils by date and doctrine."]
        )

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "responsePresentations")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyBranch = try JSONDecoder().decode(ChatBranch.self, from: legacyData)
        #expect(legacyBranch.responsePresentations == nil)
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
