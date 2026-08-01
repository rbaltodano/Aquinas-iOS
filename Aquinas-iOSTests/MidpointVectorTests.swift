import Foundation
import Testing
@testable import Aquinas_iOS

struct MidpointVectorTests {
    @Test
    func equalWeightsProduceNormalizedDiagonalCentroid() {
        let centroid = normalizedWeightedCentroid(
            [[2, 0], [0, 4]],
            weights: [0.5, 0.5]
        )

        #expect(centroid != nil)
        #expect(abs((centroid?[0] ?? 0) - sqrt(0.5)) < 0.000_001)
        #expect(abs((centroid?[1] ?? 0) - sqrt(0.5)) < 0.000_001)
    }

    @Test
    func weightsControlLiteralVectorDirection() {
        let centroid = normalizedWeightedCentroid(
            [[1, 0], [0, 1]],
            weights: [3, 1]
        )

        #expect(centroid != nil)
        #expect((centroid?[0] ?? 0) > (centroid?[1] ?? 0) * 2.9)
    }

    @Test
    func incompatibleVectorsAreRejected() {
        #expect(
            normalizedWeightedCentroid(
                [[1, 0], [0, 1, 0]],
                weights: [0.5, 0.5]
            ) == nil
        )
    }
}
