//
//  OnDeviceGroundingStore.swift
//  Aquinas-iOS
//

import Accelerate
import Foundation

/// A passage retrieved from the local grounding corpus. Mirrors the
/// backend's `GroundingPassage` (see Aquinas_Backend/grounding_retrieval.py)
/// so the local and backend prompt-construction paths can share the same
/// shape and wording.
struct GroundingPassage {
    let text: String
    let title: String
    let sourceID: String
    let distance: Float
}

private struct PassageRecord: Decodable {
    let text: String
    let title: String
    let sourceId: String
    let chunkIndex: Int
}

/// Loads the pre-embedded grounding corpus once (a flat float32 embeddings
/// file plus a parallel-indexed JSON metadata file, exported from the
/// backend's Chroma collection — see Aquinas_Backend/grounding_retrieval.py
/// for the matching embedding space) and serves nearest-passage queries with
/// a vectorized linear scan. At ~41k chunks this is comfortably faster than
/// generation itself, so no on-device approximate-NN index is needed.
final class OnDeviceGroundingStore {
    private let embeddingDimension = 384
    private let passages: [PassageRecord]
    private let embeddings: Data

    /// Cosine distance on MiniLM embeddings is a ranking signal, not a
    /// calibrated probability (see MODEL-INTEGRATION.md). Matches the
    /// backend's DEFAULT_MAX_DISTANCE screen against clearly irrelevant hits.
    private let defaultMaxDistance: Float = 1.0

    init(embeddingsURL: URL, passagesURL: URL) throws {
        let passagesData = try Data(contentsOf: passagesURL)
        self.passages = try JSONDecoder().decode([PassageRecord].self, from: passagesData)
        self.embeddings = try Data(contentsOf: embeddingsURL, options: .alwaysMapped)

        let expectedBytes = passages.count * embeddingDimension * MemoryLayout<Float>.size
        guard embeddings.count == expectedBytes else {
            throw OnDeviceGroundingStoreError.corpusMismatch
        }
    }

    var passageCount: Int { passages.count }

    func retrieve(
        queryEmbedding: [Float],
        k: Int = 4,
        maxDistance: Float? = nil
    ) -> [GroundingPassage] {
        guard queryEmbedding.count == embeddingDimension, !passages.isEmpty else {
            return []
        }
        let threshold = maxDistance ?? defaultMaxDistance

        var similarities = [Float](repeating: 0, count: passages.count)
        embeddings.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let base = rawBuffer.bindMemory(to: Float.self).baseAddress!
            queryEmbedding.withUnsafeBufferPointer { queryBuffer in
                let query = queryBuffer.baseAddress!
                for index in 0..<passages.count {
                    let row = base + index * embeddingDimension
                    var dot: Float = 0
                    vDSP_dotpr(query, 1, row, 1, &dot, vDSP_Length(embeddingDimension))
                    similarities[index] = dot
                }
            }
        }

        let ranked = similarities.enumerated()
            .map { index, similarity in (index: index, distance: 1 - similarity) }
            .filter { $0.distance <= threshold }
            .sorted { $0.distance < $1.distance }
            .prefix(k)

        return ranked.map { entry in
            let record = passages[entry.index]
            return GroundingPassage(
                text: record.text,
                title: record.title,
                sourceID: record.sourceId,
                distance: entry.distance
            )
        }
    }
}

enum OnDeviceGroundingStoreError: LocalizedError {
    case corpusMismatch

    var errorDescription: String? {
        "The bundled grounding corpus's embeddings and passage metadata are out of sync."
    }
}
