//
//  SemanticLayout.swift
//  Aquinas-iOS
//

import CoreGraphics
import Foundation

/// World-space layout targets derived from the nodes' semantic embeddings.
struct SemanticLayoutResult {
    /// Target position per node. Only nodes with a non-empty embedding get an entry;
    /// callers place the rest (previous position, neighbor centroid, radial seed).
    var positions: [UUID: CGPoint]
    /// Normalized depth per node in [0, 1] from the third embedding component
    /// (1 = nearest). Nodes without an entry should be treated as depth 1.
    var depth: [UUID: Double]
}

/// Embedding-driven node layout: classical MDS (Torgerson) over the pairwise semantic
/// distance matrix, so on-screen distance between nodes reflects how related their
/// meanings are — globally, not just along drawn edges. The third MDS component feeds
/// the 2.5D depth cue. Deterministic (fixed power-iteration seed + eigenvector sign
/// convention) and stable across incremental solves (Procrustes-aligned to the previous
/// layout so adding a node doesn't reshuffle or rotate the whole map).
enum SemanticLayout {

    /// Maps semantic distance (~0–1 cosine distance) into world px. Chosen so typical
    /// separations (~0.3–0.7 cosine) exceed the sum of two node footprints (orbit ring
    /// ~190px + chip extent ~64px each) — otherwise overlap cleanup, not semantics,
    /// would decide the spacing.
    static let defaultWorldScale: CGFloat = 900

    static func solve(
        nodes: [NodeModel],
        pinnedIDs: Set<UUID>,
        previousPositions: [UUID: CGPoint],
        worldScale: CGFloat = SemanticLayout.defaultWorldScale
    ) -> SemanticLayoutResult {
        let embedded = nodes.filter { !$0.embedding.isEmpty }
        guard embedded.count >= 2 else {
            // Nothing to triangulate — keep whatever positions exist.
            return SemanticLayoutResult(positions: [:], depth: [:])
        }

        let n = embedded.count
        var distances = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = semanticDistance(embedded[i].embedding, embedded[j].embedding)
                distances[i][j] = d
                distances[j][i] = d
            }
        }

        let coords = classicalMDS(distances: distances, dimensions: 3)

        // If the leading axis carries no spread (identical embeddings), MDS collapses to a
        // point — fall back to a deterministic ring so downstream cleanup has room to work.
        let spreadX = coords.map { abs($0[0]) }.max() ?? 0
        var positions: [UUID: CGPoint] = [:]
        if spreadX < 1e-6 {
            for (index, node) in embedded.enumerated() {
                let angle = (CGFloat(index) / CGFloat(n)) * (.pi * 2)
                positions[node.id] = CGPoint(x: cos(angle) * worldScale, y: sin(angle) * worldScale)
            }
        } else {
            for (index, node) in embedded.enumerated() {
                positions[node.id] = CGPoint(
                    x: CGFloat(coords[index][0]) * worldScale,
                    y: CGFloat(coords[index][1]) * worldScale
                )
            }
        }

        // Depth from the third component, normalized to [0, 1] (constant → all 1).
        var depth: [UUID: Double] = [:]
        let zs = coords.map { $0[2] }
        if let minZ = zs.min(), let maxZ = zs.max(), maxZ - minZ > 1e-9 {
            for (index, node) in embedded.enumerated() {
                depth[node.id] = (zs[index] - minZ) / (maxZ - minZ)
            }
        } else {
            for node in embedded { depth[node.id] = 1 }
        }

        // Orient the fresh solve to the previous layout (rotation/reflection + translation
        // only — never scale, screen distance must stay proportional to semantic distance)
        // so incremental additions and re-solves don't spin or mirror the map. Pinned nodes
        // participate as anchors so the map orients around user-placed positions.
        let shared = embedded.compactMap { node -> (CGPoint, CGPoint)? in
            guard let prev = previousPositions[node.id], let new = positions[node.id] else { return nil }
            return (new, prev)
        }
        if shared.count >= 2 {
            let t = procrustesTransform(from: shared)
            for (id, p) in positions {
                let x = t.reflect ? -p.x : p.x
                positions[id] = CGPoint(
                    x: x * t.cosθ - p.y * t.sinθ + t.translation.dx,
                    y: x * t.sinθ + p.y * t.cosθ + t.translation.dy
                )
            }
        }

        return SemanticLayoutResult(positions: positions, depth: depth)
    }

    // MARK: - Classical MDS

    /// Torgerson MDS: double-center the squared distance matrix and extract the top
    /// eigenpairs. Returns per-point coordinates `v_k · √λ_k` for each of `dimensions`
    /// axes (zeros where an eigenvalue is non-positive).
    private static func classicalMDS(distances: [[Double]], dimensions: Int) -> [[Double]] {
        let n = distances.count
        // B = -1/2 · J · D² · J with J = I - (1/n)·11ᵀ, expanded to row/col/grand means.
        var sq = distances.map { $0.map { $0 * $0 } }
        let rowMeans = sq.map { $0.reduce(0, +) / Double(n) }
        let grandMean = rowMeans.reduce(0, +) / Double(n)
        var b = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in 0..<n {
                b[i][j] = -0.5 * (sq[i][j] - rowMeans[i] - rowMeans[j] + grandMean)
            }
        }
        sq = []

        // Power iteration finds the largest-|λ| eigenpair, and cosine distances are
        // non-Euclidean so B has negative eigenvalues mixed in — deflate those and keep
        // going until `dimensions` positive ones are found (or the spectrum is exhausted).
        var coords = Array(repeating: Array(repeating: 0.0, count: dimensions), count: n)
        var dim = 0
        for _ in 0..<(dimensions + 6) where dim < dimensions {
            let (eigenvalue, vector) = powerIteration(b, iterations: 100)
            guard abs(eigenvalue) > 1e-9 else { break }   // spectrum exhausted

            if eigenvalue > 0 {
                // Sign convention: largest-|magnitude| component positive, so the same
                // input always yields the identical layout.
                let flip: Double = {
                    var best = 0.0
                    for v in vector where abs(v) > abs(best) { best = v }
                    return best < 0 ? -1 : 1
                }()
                let scale = sqrt(eigenvalue)
                for i in 0..<n {
                    coords[i][dim] = vector[i] * flip * scale
                }
                dim += 1
            }
            // Deflate: B -= λ·v·vᵀ (valid for negative eigenpairs too).
            for i in 0..<n {
                for j in 0..<n {
                    b[i][j] -= eigenvalue * vector[i] * vector[j]
                }
            }
        }
        return coords
    }

    /// Deterministic power iteration for the dominant eigenpair of a symmetric matrix.
    private static func powerIteration(_ matrix: [[Double]], iterations: Int) -> (eigenvalue: Double, vector: [Double]) {
        let n = matrix.count
        // Fixed, non-degenerate start vector (never accidentally orthogonal to a
        // structured eigenvector the way a constant vector can be).
        var v = (0..<n).map { 1.0 + Double($0) * 0.618 }
        var norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        v = v.map { $0 / norm }

        var eigenvalue = 0.0
        for _ in 0..<iterations {
            var next = Array(repeating: 0.0, count: n)
            for i in 0..<n {
                var sum = 0.0
                for j in 0..<n { sum += matrix[i][j] * v[j] }
                next[i] = sum
            }
            norm = sqrt(next.reduce(0) { $0 + $1 * $1 })
            guard norm > 1e-12 else { return (0, v) }
            v = next.map { $0 / norm }
            eigenvalue = norm
        }
        // Rayleigh quotient for a signed eigenvalue (norm is always positive).
        var bv = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            for j in 0..<n { bv[i] += matrix[i][j] * v[j] }
        }
        eigenvalue = zip(v, bv).reduce(0) { $0 + $1.0 * $1.1 }
        return (eigenvalue, v)
    }

    // MARK: - Procrustes

    /// Closed-form 2D orthogonal Procrustes: the rotation (optionally with reflection)
    /// + translation mapping each pair's first point onto its second, minimizing squared
    /// residual. Tries both the plain and reflected solutions and keeps the better fit.
    private static func procrustesTransform(
        from pairs: [(CGPoint, CGPoint)]
    ) -> (cosθ: CGFloat, sinθ: CGFloat, reflect: Bool, translation: CGVector) {
        let count = CGFloat(pairs.count)
        let srcCentroid = CGPoint(
            x: pairs.reduce(0) { $0 + $1.0.x } / count,
            y: pairs.reduce(0) { $0 + $1.0.y } / count
        )
        let dstCentroid = CGPoint(
            x: pairs.reduce(0) { $0 + $1.1.x } / count,
            y: pairs.reduce(0) { $0 + $1.1.y } / count
        )

        func solve(reflect: Bool) -> (cosθ: CGFloat, sinθ: CGFloat, residual: CGFloat) {
            var a: CGFloat = 0, b: CGFloat = 0
            for (src, dst) in pairs {
                let sx0 = src.x - srcCentroid.x
                let sx = reflect ? -sx0 : sx0
                let sy = src.y - srcCentroid.y
                let dx = dst.x - dstCentroid.x
                let dy = dst.y - dstCentroid.y
                a += sx * dx + sy * dy
                b += sx * dy - sy * dx
            }
            let mag = hypot(a, b)
            let cosθ: CGFloat = mag > 1e-9 ? a / mag : 1
            let sinθ: CGFloat = mag > 1e-9 ? b / mag : 0
            var residual: CGFloat = 0
            for (src, dst) in pairs {
                let sx0 = src.x - srcCentroid.x
                let sx = reflect ? -sx0 : sx0
                let sy = src.y - srcCentroid.y
                let rx = sx * cosθ - sy * sinθ - (dst.x - dstCentroid.x)
                let ry = sx * sinθ + sy * cosθ - (dst.y - dstCentroid.y)
                residual += rx * rx + ry * ry
            }
            return (cosθ, sinθ, residual)
        }

        let plain = solve(reflect: false)
        let mirrored = solve(reflect: true)
        let reflect = mirrored.residual < plain.residual
        let best = reflect ? mirrored : plain

        // Translation maps the (reflected+)rotated source centroid onto the destination's.
        let cx0 = reflect ? -srcCentroid.x : srcCentroid.x
        let rotated = CGPoint(
            x: cx0 * best.cosθ - srcCentroid.y * best.sinθ,
            y: cx0 * best.sinθ + srcCentroid.y * best.cosθ
        )
        return (
            best.cosθ,
            best.sinθ,
            reflect,
            CGVector(dx: dstCentroid.x - rotated.x, dy: dstCentroid.y - rotated.y)
        )
    }
}
