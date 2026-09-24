import CoreGraphics
import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Insight Cluster Spatial Layout")
struct InsightClusterSpatialLayoutTests {
    private typealias Layout = InsightClusterSpatialLayout
    private let maximum = InsightClusterSpatialLayout.maximumElevationRadians

    @Test("Height never exceeds 45 degrees off the plane, even for a chip dragged in to its node")
    func heightStaysInsideGuardrail() {
        for distance in [CGFloat(0), 12, 60, 190, 400] {
            for angle in [-2.0, -maximum, -0.3, 0, 0.3, maximum, 2.0] as [CGFloat] {
                let z = Layout.elevation(angle: angle, horizontalDistance: distance)
                #expect(abs(z) <= distance * tan(maximum) + 1e-9)
                #expect(z == 0 || (z > 0) == (angle > 0))
            }
        }
    }

    private func members(_ azimuths: [Double]) -> [Layout.Member] {
        azimuths.map { Layout.Member(id: UUID(), azimuth: $0) }
    }

    /// Smallest 3D distance between two Insights at `radius`, for the given elevation angles.
    private func minimumSeparation(_ members: [Layout.Member], angles: [UUID: CGFloat], radius: CGFloat = 190) -> CGFloat {
        var result = CGFloat.infinity
        for i in members.indices {
            for j in members.indices where j > i {
                let a = members[i], b = members[j]
                let dx = radius * (cos(a.azimuth) - cos(b.azimuth))
                let dy = radius * (sin(a.azimuth) - sin(b.azimuth))
                let dz = Layout.elevation(angle: angles[a.id, default: 0], horizontalDistance: radius)
                    - Layout.elevation(angle: angles[b.id, default: 0], horizontalDistance: radius)
                result = min(result, (dx * dx + dy * dy + dz * dz).squareRoot())
            }
        }
        return result
    }

    @Test("Neighbors around a node alternate between the top and bottom of the ±45 degree band")
    func evenClusterAlternatesAtFullBand() {
        for count in [2, 4, 6, 8, 10] {
            let ring = members((0..<count).map { Double($0) / Double(count) * 2 * .pi + 0.3 })
            let targets = Layout.elevationTargets(ring)
            for (index, member) in ring.enumerated() {
                #expect(abs(targets[member.id]!) == maximum)
                let next = ring[(index + 1) % count]
                #expect((targets[member.id]! > 0) != (targets[next.id]! > 0))
            }
        }
    }

    @Test("An odd cluster levels one Insight and alternates the rest around the node")
    func oddClusterLevelsOne() {
        for count in [3, 5, 7] {
            let ring = members((0..<count).map { Double($0) / Double(count) * 2 * .pi })
            let targets = Layout.elevationTargets(ring)
            let level = try! #require(ring.firstIndex { targets[$0.id] == 0 })
            #expect(targets.values.filter { $0 == 0 }.count == 1)
            let rest = (1..<count).map { ring[(level + $0) % count] }
            for (a, b) in zip(rest, rest.dropFirst()) {
                #expect(abs(targets[a.id]!) == maximum)
                #expect((targets[a.id]! > 0) != (targets[b.id]! > 0))
            }
        }
    }

    @Test("The same Insights in the same order get the same heights on every open")
    func targetsAreStableAcrossOpens() {
        for count in [4, 5, 6, 7] {
            let ring = members((0..<count).map { Double($0) / Double(count) * 2 * .pi })
            let first = Layout.elevationTargets(ring)
            // A later open: the settled bond directions differ slightly and arrive in another order.
            let reopened = ring.reversed().map { member in
                Layout.Member(id: member.id, azimuth: member.azimuth + Double.random(in: -0.08...0.08))
            }
            #expect(Layout.elevationTargets(reopened) == first)
        }
    }

    @Test("Spreading increases the closest pair's 3D distance over a level cluster")
    func spreadIncreasesSeparation() {
        for count in 2...12 {
            let ring = members((0..<count).map { Double($0) / Double(count) * 2 * .pi })
            let targets = Layout.elevationTargets(ring)
            #expect(minimumSeparation(ring, angles: targets) > minimumSeparation(ring, angles: [:]))
            #expect(targets.values.allSatisfy { abs($0) <= maximum })
        }
    }

    @Test("Rotating a whole cluster past zero degrees does not flip which side each Insight is on")
    func targetsSurviveAngleWrap() {
        for count in [4, 5] {
            let ring = members((0..<count).map { Double($0) / Double(count) * 2 * .pi })
            let before = Layout.elevationTargets(ring)
            let rotated = ring.map { Layout.Member(id: $0.id, azimuth: $0.azimuth - 0.2) }
            #expect(Layout.elevationTargets(rotated) == before)
        }
    }

    @Test("A lone Insight stays level")
    func loneInsightIsLevel() {
        let lone = members([1])
        #expect(Layout.elevationTargets(lone) == [lone[0].id: 0])
    }

    private let camera = PerspectivePlaneProjection(
        pitch: .pi * 34 / 180,
        focalLength: 1300,
        principalPoint: CGPoint(x: 201, y: 437)
    )

    @Test("Unprojecting at the same elevation recovers the flat point, so drags track the finger")
    func projectionRoundTrips() {
        for elevation in [-120.0, 0.0, 95.0] as [CGFloat] {
            for flat in [CGPoint(x: 30, y: 60), CGPoint(x: 350, y: 800), CGPoint(x: 201, y: 437)] {
                let screen = camera.project(flat: flat, elevation: elevation).position
                let recovered = camera.unproject(screen, elevation: elevation)
                #expect(abs(recovered.x - flat.x) < 1e-6)
                #expect(abs(recovered.y - flat.y) < 1e-6)
            }
        }
    }

    @Test("Raised points draw higher and larger than their footprint; lowered points the reverse")
    func elevationIsVisible() {
        let flat = CGPoint(x: 260, y: 300)
        let footprint = camera.project(flat: flat)
        let raised = camera.project(flat: flat, elevation: 80)
        let lowered = camera.project(flat: flat, elevation: -80)

        #expect(raised.position.y < footprint.position.y - 30)
        #expect(raised.scale > footprint.scale)
        #expect(lowered.position.y > footprint.position.y + 30)
        #expect(lowered.scale < footprint.scale)
    }

    @Test("The plane is foreshortened: farther rows shrink toward the principal point")
    func planeIsForeshortened() {
        let near = camera.project(flat: CGPoint(x: 301, y: 637))
        let far = camera.project(flat: CGPoint(x: 301, y: 237))
        #expect(far.scale < 1 && near.scale > 1)
        #expect(abs(far.position.y - camera.principalPoint.y) < 200)
    }

    @Test("Focus places an elevated chip exactly on the principal point")
    func focusCentersElevatedChip() {
        for elevation in [-110.0, 0.0, 70.0] as [CGFloat] {
            let flat = camera.flatPointCentering(elevation: elevation)
            let screen = camera.project(flat: flat, elevation: elevation).position
            #expect(abs(screen.x - camera.principalPoint.x) < 1e-6)
            #expect(abs(screen.y - camera.principalPoint.y) < 1e-6)
        }
    }

    @Test("Zero pitch is the identity, so the shared dot grid is unchanged elsewhere")
    func zeroPitchIsIdentity() {
        let flat = PerspectivePlaneProjection(pitch: 0, focalLength: 1300, principalPoint: .zero)
        let point = flat.project(flat: CGPoint(x: 12, y: -40))
        #expect(point.position == CGPoint(x: 12, y: -40))
        #expect(point.scale == 1)
    }

    @Test("Overhead, raised points magnify and move faster than the plane; lowered ones slower")
    func overheadCameraParallax() {
        let camera = PerspectivePlaneProjection(
            pitch: 0, focalLength: 600, principalPoint: CGPoint(x: 200, y: 400)
        )
        let flat = CGPoint(x: 300, y: 250)
        let raised = camera.project(flat: flat, elevation: 90)
        let lowered = camera.project(flat: flat, elevation: -90)
        #expect(raised.scale > 1)
        #expect(lowered.scale < 1)

        // Panning the plane by 40 pt moves a raised chip farther and a lowered chip less.
        let panned = CGPoint(x: flat.x + 40, y: flat.y)
        let raisedMove = camera.project(flat: panned, elevation: 90).position.x - raised.position.x
        let loweredMove = camera.project(flat: panned, elevation: -90).position.x - lowered.position.x
        #expect(raisedMove > 40)
        #expect(loweredMove < 40)

        // Focus still lands an elevated chip exactly on screen center.
        let centered = camera.project(flat: camera.flatPointCentering(elevation: 90), elevation: 90)
        #expect(centered.position == camera.principalPoint)

        // Unprojection round-trips for pan and chip-drag math.
        let back = camera.unproject(raised.position, elevation: 90)
        #expect(abs(back.x - flat.x) < 1e-6 && abs(back.y - flat.y) < 1e-6)
    }
}
