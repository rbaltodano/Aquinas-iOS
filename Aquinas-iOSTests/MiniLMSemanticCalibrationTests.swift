import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("MiniLM semantic calibration")
struct MiniLMSemanticCalibrationTests {
    private enum Judgment: String, CaseIterable {
        case sameNode
        case relatedSeparate
        case unrelated
    }

    private struct LabeledPair {
        let judgment: Judgment
        let left: String
        let right: String
    }

    private struct ScoredPair {
        let pair: LabeledPair
        let similarity: Double

        var distance: Double { 1 - similarity }
    }

    /// Initial hand-labeled set for repeatable threshold work. These are deliberately phrased
    /// like the title + definition text sent through the real Insight clustering path, rather
    /// than as isolated keywords that give the embedder too little context.
    private let pairs: [LabeledPair] = [
        .init(judgment: .sameNode, left: "Grace: God's free gift of divine life", right: "Sanctifying grace: a stable participation in God's life"),
        .init(judgment: .sameNode, left: "Eucharist: Christ is truly present under bread and wine", right: "Real Presence: Christ's body and blood are present in the Eucharist"),
        .init(judgment: .sameNode, left: "Natural law: moral order known through human reason", right: "Moral law grounded in rational human nature"),
        .init(judgment: .sameNode, left: "Trinity: one God in three divine persons", right: "Father, Son, and Holy Spirit share one divine nature"),
        .init(judgment: .sameNode, left: "Beatific vision: direct knowledge of God in heaven", right: "Seeing God face to face as the fulfillment of human life"),
        .init(judgment: .sameNode, left: "Transubstantiation: the substance of bread and wine becomes Christ", right: "Eucharistic change of substance while appearances remain"),
        .init(judgment: .sameNode, left: "Original sin: humanity's inherited fallen condition", right: "The Fall and the deprivation passed from the first sin"),
        .init(judgment: .sameNode, left: "Virtue: a stable habit directed toward the good", right: "Habitual disposition that perfects human action"),

        .init(judgment: .relatedSeparate, left: "Grace: God's free gift of divine life", right: "Free will: the human power to choose and act"),
        .init(judgment: .relatedSeparate, left: "Eucharist: Christ is truly present under bread and wine", right: "Sacrifice of the Mass: the sacramental making-present of Calvary"),
        .init(judgment: .relatedSeparate, left: "Trinity: one God in three divine persons", right: "Incarnation: the Son of God assumes human nature"),
        .init(judgment: .relatedSeparate, left: "Natural law: moral order known through human reason", right: "Conscience: practical judgment about a particular moral act"),
        .init(judgment: .relatedSeparate, left: "Virtue: a stable habit directed toward the good", right: "Beatitude: the happiness that fulfills human desire"),
        .init(judgment: .relatedSeparate, left: "Faith: assent to God and what God reveals", right: "Hope: confident desire for eternal life with God"),
        .init(judgment: .relatedSeparate, left: "Thomas Aquinas: medieval theologian and philosopher", right: "Aristotle: ancient philosopher whose metaphysics shaped scholasticism"),
        .init(judgment: .relatedSeparate, left: "Creation: God's bringing all things into being", right: "Divine providence: God's ordering and care for creation"),

        .init(judgment: .unrelated, left: "Eucharist: Christ is truly present under bread and wine", right: "French Revolution: political upheaval beginning in France in 1789"),
        .init(judgment: .unrelated, left: "Trinity: one God in three divine persons", right: "Salt March: Gandhi's campaign against the British salt tax"),
        .init(judgment: .unrelated, left: "Natural law: moral order known through human reason", right: "DNA double helix: the molecular structure carrying genetic information"),
        .init(judgment: .unrelated, left: "Grace: God's free gift of divine life", right: "Transcontinental railroad: rail line joining the eastern and western United States"),
        .init(judgment: .unrelated, left: "Beatific vision: direct knowledge of God in heaven", right: "Eiffel Tower: iron landmark built in Paris for the 1889 exposition"),
        .init(judgment: .unrelated, left: "Council of Nicaea: council defining the Son's divinity", right: "Haitian Revolution: successful revolt against French colonial rule"),
        .init(judgment: .unrelated, left: "Virtue ethics: moral formation through good habits", right: "Photosynthesis: conversion of light energy into chemical energy in plants"),
        .init(judgment: .unrelated, left: "Incarnation: the Son of God assumes human nature", right: "Quantum mechanics: mathematical theory of matter at microscopic scales")
    ]

    @Test("Bundled MiniLM separates labeled semantic judgments")
    func bundledModelProducesOrderedScoreBands() async throws {
        // The embedder resolves to CPU-only on the simulator because the exported package's
        // MPSGraph path is device-only; physical devices still use all available compute units.
        let provider = try MiniLMEmbeddingProvider()
        let uniqueTexts = Set(pairs.flatMap { [$0.left, $0.right] })
        var embeddings: [String: [Double]] = [:]

        for value in uniqueTexts.sorted() {
            guard let embedding = await provider.embed(value) else {
                Issue.record("MiniLM could not embed: \(value)")
                return
            }
            guard embedding.count == 384, embedding.allSatisfy(\.isFinite) else {
                Issue.record("MiniLM returned an invalid embedding for: \(value)")
                return
            }
            embeddings[value] = embedding
        }

        let scored = pairs.compactMap { pair -> ScoredPair? in
            guard let left = embeddings[pair.left], let right = embeddings[pair.right] else {
                return nil
            }
            return ScoredPair(pair: pair, similarity: cosineSimilarity(left, right))
        }
        #expect(scored.count == pairs.count)

        var medians: [Judgment: Double] = [:]
        for judgment in Judgment.allCases {
            let values = scored
                .filter { $0.pair.judgment == judgment }
                .map(\.similarity)
                .sorted()
            guard let minimum = values.first, let maximum = values.last else {
                Issue.record("No calibration values for \(judgment.rawValue)")
                return
            }
            let median = values[values.count / 2]
            let mean = values.reduce(0, +) / Double(values.count)
            medians[judgment] = median
            print(
                "MINILM_CALIBRATION \(judgment.rawValue) "
                    + "count=\(values.count) similarity[min=\(format(minimum)) "
                    + "median=\(format(median)) mean=\(format(mean)) max=\(format(maximum))] "
                    + "distance[min=\(format(1 - maximum)) max=\(format(1 - minimum))]"
            )
        }

        let ranked = scored.sorted { $0.similarity > $1.similarity }
        for result in ranked {
            print(
                "MINILM_PAIR \(result.pair.judgment.rawValue) "
                    + "similarity=\(format(result.similarity)) distance=\(format(result.distance)) "
                    + "left=\(result.pair.left) | right=\(result.pair.right)"
            )
        }

        let sameMedian = try #require(medians[.sameNode])
        let relatedMedian = try #require(medians[.relatedSeparate])
        let unrelatedMedian = try #require(medians[.unrelated])
        #expect(sameMedian > relatedMedian)
        #expect(relatedMedian > unrelatedMedian)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }
}
