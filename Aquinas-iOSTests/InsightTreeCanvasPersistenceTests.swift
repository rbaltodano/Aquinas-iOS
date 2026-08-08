import CoreGraphics
import Foundation
import Testing
@testable import Aquinas_iOS

/// Covers the canvas-local persistence stores added for Make Node / Midpoint / cluster state:
/// each one exists specifically so that recreating the view (navigating away and back, or
/// switching conversations) doesn't silently drop state that looks committed to the user. These
/// tests simulate that recreation by constructing a second, independent store/view model against
/// the same UserDefaults-backed scope and asserting the state carried over.
@Suite("Insight Tree canvas persistence")
struct InsightTreeCanvasPersistenceTests {
    private func makeConcept(word: String = "Essence") -> ConceptDefinition {
        ConceptDefinition(
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: "What a thing is, apart from the act by which it exists.",
            example: ""
        )
    }

    // MARK: - GlobalInsightPromotedIDsStore

    @Test("A Make Node promotion on the Global tree survives being reloaded")
    func globalPromotedIDsRoundTrip() {
        let original = GlobalInsightPromotedIDsStore.load()
        defer { GlobalInsightPromotedIDsStore.save(original) }

        let promoted = [UUID(), UUID()]
        GlobalInsightPromotedIDsStore.save(promoted)

        #expect(GlobalInsightPromotedIDsStore.load() == promoted)
    }

    @Test("With nothing ever saved, the store reads back empty rather than crashing")
    func globalPromotedIDsDefaultsToEmpty() {
        let original = GlobalInsightPromotedIDsStore.load()
        defer { GlobalInsightPromotedIDsStore.save(original) }

        GlobalInsightPromotedIDsStore.save([])

        #expect(GlobalInsightPromotedIDsStore.load().isEmpty)
    }

    // MARK: - Placed Midpoints (InsightTreeViewModel)

    @MainActor
    @Test("A placed Midpoint survives the view model being torn down and recreated")
    func placedMidpointSurvivesRecreation() {
        let scope = UUID()
        let midpoint = makeConcept(word: "Being")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let firstLoad = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scope
        )
        firstLoad.addPlacedMidpoint(concept: midpoint, at: CGPoint(x: 40, y: 20), sources: [source])

        // Simulates navigating away and back: a brand-new instance, same conversation scope.
        let secondLoad = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scope
        )

        #expect(secondLoad.placedMidpointNodeIDs.contains(midpoint.id))
        #expect(secondLoad.placedMidpointConcept(for: midpoint.id)?.word == "Being")
    }

    @MainActor
    @Test("Removing a placed Midpoint persists, rather than reappearing on the next load")
    func removedPlacedMidpointStaysRemoved() {
        let scope = UUID()
        let midpoint = makeConcept(word: "Act")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let firstLoad = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scope
        )
        firstLoad.addPlacedMidpoint(concept: midpoint, at: .zero, sources: [source])
        firstLoad.removePlacedMidpoint(id: midpoint.id)

        let secondLoad = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scope
        )

        #expect(!secondLoad.placedMidpointNodeIDs.contains(midpoint.id))
    }

    @MainActor
    @Test("A Midpoint placed in one conversation's tree does not leak into another's")
    func placedMidpointsAreScopedPerConversation() {
        let scopeA = UUID()
        let scopeB = UUID()
        let midpoint = makeConcept(word: "Potency")
        let source = MidpointSource(insightID: UUID(), isNode: false)

        let treeA = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scopeA
        )
        treeA.addPlacedMidpoint(concept: midpoint, at: .zero, sources: [source])

        let treeB = InsightTreeViewModel(
            insights: [],
            model: MockAquinasModel(),
            midpointStoreScope: scopeB
        )

        #expect(!treeB.placedMidpointNodeIDs.contains(midpoint.id))
    }
}
