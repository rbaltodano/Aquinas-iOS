import Testing
@testable import Aquinas_iOS

@Suite("Conversation response state")
struct ConversationResponseStatePolicyTests {
    @Test("Completed text reveals while its queue task waits for the reveal gate")
    func responseTextBreaksRevealGateCycle() {
        let isAwaiting = ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: true,
            isLocallyPending: false,
            taskPhase: .current
        )

        #expect(!isAwaiting)
    }

    @Test("An empty response remains awaiting for current and queued tasks")
    func emptyResponseTracksQueueState() {
        #expect(ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: .current
        ))
        #expect(ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: .upcoming
        ))
    }

    @Test("An empty response without pending work is ready")
    func emptyResponseWithoutPendingWorkIsReady() {
        #expect(!ConversationResponseStatePolicy.isAwaitingResponse(
            hasResponseText: false,
            isLocallyPending: false,
            taskPhase: nil
        ))
    }
}
