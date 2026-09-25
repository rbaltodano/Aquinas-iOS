import Foundation
import Testing
import simd
@testable import Aquinas_iOS

@Suite("Study Tool Prototype Geometry")
struct StudyToolPrototypeTests {
    private let cluster: [SIMD3<Double>] = (0..<5).map { index in
        let azimuth = Double(index) / 5 * 2 * .pi
        return simd_normalize(SIMD3(cos(azimuth), sin(azimuth), index % 2 == 0 ? 0.7 : -0.7))
    }

    @Test func nearbyIdeasFillGapsWithinTheTreeBand() {
        let directions = StudyToolGeometry.gapDirections(occupied: cluster, near: cluster[0], count: 4)
        #expect(directions.count == 4)
        let everything = cluster + directions
        for (index, direction) in directions.enumerated() {
            #expect(abs(direction.z) < 0.72)
            let others = everything.enumerated().filter { $0.offset != cluster.count + index }.map(\.element)
            let clearance = others.map { StudyToolGeometry.angle(direction, $0) }.min() ?? 0
            #expect(clearance > 0.3, "Idea \(index) crowds another chip")
        }
        #expect(directions == StudyToolGeometry.gapDirections(occupied: cluster, near: cluster[0], count: 4))
    }

    @Test func keptResultsLieFlatInTheTree() {
        let node = SIMD3<Double>(100, 50, 0)
        let source = node + SIMD3(190, 0, 40)
        let results = [
            StudyToolResult(kind: .branch, nodeID: UUID(), sourceInsightID: UUID(), index: 0, count: 1,
                            title: "Idea", direction: simd_normalize(SIMD3(0, 1, 0.6))),
            StudyToolResult(kind: .stage, nodeID: UUID(), sourceInsightID: UUID(), index: 2, count: 4,
                            title: "Stage", direction: SIMD3(0, 1, 0)),
        ]
        for result in results {
            let tree = StudyToolGeometry.position(
                of: result, rank: 0, source: source, node: node, radius: 190, progress: 0, time: 0
            )
            let study = StudyToolGeometry.position(
                of: result, rank: 0, source: source, node: node, radius: 190, progress: 1, time: 0
            )
            #expect(result.kind == .stage ? tree.z == source.z : tree.z == 0)
            #expect(simd_distance(tree, study) > 1)
        }
    }
}
