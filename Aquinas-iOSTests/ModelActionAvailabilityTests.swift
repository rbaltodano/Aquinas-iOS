import Foundation
import Testing
@testable import Aquinas_iOS

private final class FailingModelActionURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.cannotConnectToHost)
        )
    }

    override func stopLoading() {}
}

@Suite("Live model action availability")
struct ModelActionAvailabilityTests {
    private func model() -> BackendAquinasModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingModelActionURLProtocol.self]
        return BackendAquinasModel(
            baseURL: URL(string: "http://127.0.0.1:9")!,
            session: URLSession(configuration: configuration)
        )
    }

    private var context: ConversationContext {
        ConversationContext(
            transcript: [.user("What is prudence?", nil, [])]
        )
    }

    private var concept: ConceptDefinition {
        ConceptDefinition(
            word: "Prudence",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "Practical wisdom applied to action.",
            example: ""
        )
    }

    @Test("Definitions fail instead of returning a mock Insight")
    func definitionFailsExplicitly() async {
        do {
            _ = try await model().defineTerm("prudence", in: context)
            Issue.record("Expected the unavailable backend to throw.")
        } catch {
            #expect(error is AquinasModelActionError)
        }
    }

    @Test("Tree-generating actions fail instead of returning template content")
    func treeActionsFailExplicitly() async {
        do {
            _ = try await model().labelSubject(
                forTitles: ["Prudence: Practical wisdom applied to action."]
            )
            Issue.record("Expected Node labeling to throw.")
        } catch {
            #expect(error is AquinasModelActionError)
        }

        do {
            _ = try await model().blendConceptCandidates(
                [concept, concept],
                weights: [0.5, 0.5]
            )
            Issue.record("Expected Midpoint generation to throw.")
        } catch {
            #expect(error is AquinasModelActionError)
        }

        do {
            _ = try await model().generateChildren(for: concept)
            Issue.record("Expected Make Node generation to throw.")
        } catch {
            #expect(error is AquinasModelActionError)
        }
    }

    @Test("Question of the Day fails instead of returning a mock question")
    func dailyQuestionFailsExplicitly() async {
        do {
            _ = try await model().generateQuestionOfTheDay(
                from: context,
                conversationTitle: "Practical Wisdom",
                insights: [concept]
            )
            Issue.record("Expected Question of the Day generation to throw.")
        } catch {
            #expect(error is AquinasModelActionError)
        }
    }
}
