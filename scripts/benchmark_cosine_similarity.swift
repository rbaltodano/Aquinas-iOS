import Foundation

/// Repeatable microbenchmark for the inner loop used by Insight Tree clustering and MDS.
/// Run from `Aquinas-iOS/` with:
/// `swift scripts/benchmark_cosine_similarity.swift`
///
/// The 384 dimensions match all-MiniLM-L6-v2 embeddings. Both variants are run against
/// identical deterministic inputs and must agree before their timings are reported.
let dimensions = 384
let iterations = 200_000

func fixture(_ seed: Int) -> [Double] {
    (0..<dimensions).map { index in
        Double((seed &* 1_103_515_245 &+ index &* 12_345) % 10_000) / 10_000
    }
}

func allocatingCosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0 }
    let dot = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}

func singlePassCosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0 }
    var dot = 0.0
    var squaredMagnitudeA = 0.0
    var squaredMagnitudeB = 0.0
    for index in a.indices {
        let valueA = a[index]
        let valueB = b[index]
        dot += valueA * valueB
        squaredMagnitudeA += valueA * valueA
        squaredMagnitudeB += valueB * valueB
    }
    let magA = sqrt(squaredMagnitudeA)
    let magB = sqrt(squaredMagnitudeB)
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}

@inline(never)
func measure(_ implementation: ([Double], [Double]) -> Double, a: [Double], b: [Double]) -> (seconds: Double, checksum: Double) {
    var checksum = 0.0
    let startedAt = Date().timeIntervalSinceReferenceDate
    for _ in 0..<iterations {
        checksum += implementation(a, b)
    }
    return (Date().timeIntervalSinceReferenceDate - startedAt, checksum)
}

let a = fixture(17)
let b = fixture(29)
let baselineValue = allocatingCosineSimilarity(a, b)
let optimizedValue = singlePassCosineSimilarity(a, b)
precondition(abs(baselineValue - optimizedValue) < 1e-12, "Implementations diverged")

// Warm each implementation before timing to reduce one-time runtime effects.
_ = measure(allocatingCosineSimilarity, a: a, b: b)
_ = measure(singlePassCosineSimilarity, a: a, b: b)
let baseline = measure(allocatingCosineSimilarity, a: a, b: b)
let optimized = measure(singlePassCosineSimilarity, a: a, b: b)
let improvement = (1 - optimized.seconds / baseline.seconds) * 100

print("dimensions=\(dimensions) iterations=\(iterations)")
print(String(format: "baseline_seconds=%.6f", baseline.seconds))
print(String(format: "optimized_seconds=%.6f", optimized.seconds))
print(String(format: "speedup=%.2fx improvement=%.1f%%", baseline.seconds / optimized.seconds, improvement))
precondition(baseline.checksum == optimized.checksum, "Benchmark checksums diverged")
