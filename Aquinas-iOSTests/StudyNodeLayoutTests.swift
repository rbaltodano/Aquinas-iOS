import CoreGraphics
import Foundation
import Testing
import simd
@testable import Aquinas_iOS

@Suite("Study Node Layout")
struct StudyNodeLayoutTests {
    /// A tree cluster: alternating ±45° around the ring, one level Insight when the count is odd.
    private func treeCluster(_ count: Int) -> [SIMD3<Double>] {
        (0..<count).map { index in
            let azimuth = Double(index) / Double(count) * 2 * .pi
            let z: Double = count % 2 == 1 && index == 0 ? 0 : (index % 2 == 0 ? 1 : -1)
            return SIMD3(cos(azimuth), sin(azimuth), z) * 190
        }
    }

    private func minimumAngleDegrees(_ points: [SIMD3<Double>]) -> Double {
        var result = Double.pi
        for i in points.indices {
            for j in points.indices where j > i {
                result = min(result, acos(min(max(simd_dot(points[i], points[j]), -1), 1)))
            }
        }
        return result * 180 / .pi
    }

    @Test("Insights spread past the tree's 45 degree band to the best-known sphere arrangements")
    func reachesKnownArrangements() {
        // Minimum angle between neighbors for the optimal (Thomson) arrangements.
        let expected: [Int: Double] = [2: 180, 3: 120, 4: 109.47, 5: 90, 6: 90, 12: 63.43]
        for (count, angle) in expected {
            let spread = StudyNodeLayout.sphereSpread(from: treeCluster(count))
            #expect(abs(minimumAngleDegrees(spread) - angle) < 0.5, "count \(count)")
            #expect(spread.allSatisfy { abs(simd_length($0) - 1) < 1e-9 })
        }
    }

    @Test("Spreading always separates a tree cluster further than the tree did")
    func improvesOnTheTree() {
        for count in 3...16 {
            let tree = treeCluster(count).map(simd_normalize)
            #expect(minimumAngleDegrees(StudyNodeLayout.sphereSpread(from: tree)) > minimumAngleDegrees(tree))
        }
    }

    @Test("The same tree arrangement always opens to the same Study arrangement")
    func isDeterministic() {
        let tree = treeCluster(7)
        #expect(StudyNodeLayout.sphereSpread(from: tree) == StudyNodeLayout.sphereSpread(from: tree))
    }

    @Test("A single Insight keeps its direction")
    func singleInsightUnchanged() {
        let direction = simd_normalize(SIMD3<Double>(1, 2, 0.5))
        let result = StudyNodeLayout.sphereSpread(from: [direction * 190])
        #expect(result.count == 1)
        #expect(simd_distance(result[0], direction) < 1e-12)
    }

    @Test("Slerp stays on the sphere and hits both ends, including opposite directions")
    func slerpStaysOnSphere() {
        let pairs: [(SIMD3<Double>, SIMD3<Double>)] = [
            ([1, 0, 0], [0, 1, 0]),
            ([0, 0, 1], [0, 0, -1]),
            ([1, 0, 0], [1, 0, 0]),
        ]
        for (from, to) in pairs {
            #expect(simd_distance(StudyNodeLayout.slerp(from, to, 0), from) < 1e-9)
            #expect(simd_distance(StudyNodeLayout.slerp(from, to, 1), to) < 1e-9)
            for t in stride(from: 0.0, through: 1, by: 0.1) {
                #expect(abs(simd_length(StudyNodeLayout.slerp(from, to, t)) - 1) < 1e-9)
            }
        }
    }

    @Test("A focused Insight lands just below where the node sat, zoomed in, whatever the pan")
    func focusedInsightIsCentered() throws {
        let framing = StudyFraming(
            nodeCenter: [40, -20, 0],
            radius: 190,
            slot: CGRect(x: 51, y: 160, width: 300, height: 300),
            ringCenterY: 620
        )
        let tree = OrbitCamera(target: [0, 0, 0], distance: 3990, zoom: 1.15, principalPoint: CGPoint(x: 201, y: 380))
        let insight = SIMD3<Double>(40 + 120, -20 - 60, 110)
        let camera = framing.camera(
            from: tree, progress: 1, yaw: 0.7, pan: CGSize(width: 35, height: -20),
            pivot: insight, pivotBlend: 1
        )
        let projected = try #require(camera.project(insight))
        #expect(abs(projected.position.x - framing.slot.midX) < 1e-9)
        #expect(abs(projected.position.y - (framing.nodeY + StudyFraming.pivotDrop)) < 1e-9)
        let unfocused = framing.camera(from: tree, progress: 1)
        #expect(abs(camera.zoom / unfocused.zoom - Double(StudyFraming.hoverZoom)) < 1e-9)
    }

    @Test("Unhovering hands the axis back to the node without moving anything on screen")
    func unhoverKeepsTheView() throws {
        let framing = StudyFraming(
            nodeCenter: [40, -20, 0],
            radius: 190,
            slot: CGRect(x: 51, y: 160, width: 300, height: 300),
            ringCenterY: 620
        )
        let tree = OrbitCamera(target: [0, 0, 0], distance: 3990, zoom: 1.15, principalPoint: CGPoint(x: 201, y: 380))
        let insight = SIMD3<Double>(160, -80, 110)
        let yaw = 1.1, blend = 0.7, pan = CGSize(width: 30, height: -12), zoom: CGFloat = 1.4
        let hovered = framing.camera(
            from: tree, progress: 1, yaw: yaw, pan: pan, zoom: zoom, pivot: insight, pivotBlend: blend
        )
        // What `releaseStudyPivot` does.
        let newTarget = hovered.target(
            keepingViewWhenCenterMovesFrom: try #require(hovered.rotationCenter), to: framing.nodeCenter
        )
        let released = framing.camera(
            from: tree, progress: 1, yaw: yaw,
            pan: CGSize(
                width: pan.width * (1 - blend),
                height: pan.height * (1 - blend) + StudyFraming.pivotDrop * blend
            ),
            zoom: zoom * (1 + (StudyFraming.hoverZoomFactor(zoom: zoom) - 1) * CGFloat(blend)),
            targetShift: newTarget - framing.nodeCenter
        )
        #expect(released.rotationCenter == framing.nodeCenter)
        for point: SIMD3<Double> in [[40, -20, 0], [160, -80, 110], [-120, 90, -140], [300, 10, 60]] {
            let before = try #require(hovered.project(point)), after = try #require(released.project(point))
            #expect(abs(before.position.x - after.position.x) < 1e-6)
            #expect(abs(before.position.y - after.position.y) < 1e-6)
        }
    }

    @Test("The floor draws exactly the visible dots at any rotation, pan, zoom, or focus shift")
    func floorDotsMatchBruteForce() {
        let framing = StudyFraming(
            nodeCenter: [40, -20, 0],
            radius: 190,
            slot: CGRect(x: 51, y: 160, width: 300, height: 300),
            ringCenterY: 600
        )
        let size = CGSize(width: 402, height: 700)
        let tree = OrbitCamera(target: [0, 0, 0], distance: 3990, zoom: 1.15, principalPoint: CGPoint(x: 201, y: 380))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<12 {
            let camera = framing.camera(
                from: tree,
                progress: 1,
                yaw: .random(in: -7...7, using: &generator),
                pan: CGSize(width: .random(in: -80...80), height: .random(in: -80...80)),
                zoom: .random(in: 0.6...2.5),
                targetShift: [.random(in: -200...200), .random(in: -200...200), .random(in: -150...150)]
            )
            let found = Set(framing.visibleFloorDots(camera: camera, size: size).map { [$0.column, $0.row] })

            // Brute force: every dot in a square larger than the floor's reach.
            let spacing = framing.floorSpacing
            let limit = Int((camera.distance * (1 + StudyFraming.floorReach) + 400) / spacing)
            var expected = Set<[Int]>()
            for row in -limit...limit {
                for column in -limit...limit {
                    let point = framing.nodeCenter + SIMD3(Double(column) * spacing, Double(row) * spacing, -framing.floorDepth)
                    guard let projected = camera.project(point),
                          projected.depth >= camera.distance * 0.15 - 1e-6,
                          projected.depth <= camera.distance * (1 + StudyFraming.floorReach) + 1e-6,
                          projected.position.x > -7.9, projected.position.x < size.width + 7.9,
                          projected.position.y > -4, projected.position.y < size.height + 4
                    else { continue }
                    expected.insert([column, row])
                }
            }
            #expect(expected.isSubset(of: found))
        }
    }

    @Test("Opening Study already hovered on an Insight still starts exactly from the tree's view")
    func hoveredEntryStartsFromTree() throws {
        let framing = StudyFraming(
            nodeCenter: [40, -20, 0],
            radius: 190,
            slot: CGRect(x: 51, y: 160, width: 300, height: 300),
            ringCenterY: 600
        )
        let tree = OrbitCamera(target: [10, 5, 0], distance: 3990, zoom: 1.15, principalPoint: CGPoint(x: 201, y: 380))
        let start = framing.camera(
            from: tree, progress: 0, zoom: StudyFraming.hoverZoom,
            pivot: [160, -80, 110], pivotBlend: 1
        )
        for point: SIMD3<Double> in [[40, -20, 0], [160, -80, 110], [-300, 200, 0]] {
            let expected = try #require(tree.project(point)), actual = try #require(start.project(point))
            #expect(abs(expected.position.x - actual.position.x) < 1e-6)
            #expect(abs(expected.position.y - actual.position.y) < 1e-6)
        }
    }
}
