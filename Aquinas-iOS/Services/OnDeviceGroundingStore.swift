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
    private let sourceIndices: [String: [Int]]
    /// "JHN14" -> the passage range covering that chapter, built once from the
    /// corpus's own leading `[JHN14]` locator tags. Lets an explicit citation
    /// be resolved as a lookup key instead of a semantic query.
    private let chapterRanges: [String: Range<Int>]

    /// Cosine distance on MiniLM embeddings is a ranking signal, not a
    /// calibrated probability (see MODEL-INTEGRATION.md), so this is a
    /// measured separation point rather than a confidence level.
    ///
    /// The former value of 1.0 admitted any non-negative similarity, which in
    /// practice screened nothing: "what did the Council of Nicaea decide about
    /// the Son?" passed five straight Livy/Herodotus/Plutarch passages (0.55,
    /// matching "council" and *Nicaea the Greek city*) into the prompt as
    /// grounding. Scored against the bundled corpus, clearly relevant
    /// questions land at 0.64-0.83 similarity while clearly irrelevant ones
    /// top out at 0.60, so 0.38 distance (0.62 similarity) separates them.
    /// Retrieving nothing is the safe outcome here: generation then proceeds
    /// ungrounded, which is strictly better than grounding it in Roman
    /// history.
    ///
    /// The value is 0.45, chosen by sweeping it against the 56-case set in
    /// `Aquinas_Backend/evaluation/evaluate_retrieval.py` rather than by
    /// eyeballing a handful of queries. An earlier 0.38 was calibrated only on
    /// doctrinal questions, where the Summa's "Whether X..." phrasing closely
    /// mirrors the question, and it silently discarded ordinary narrative
    /// scripture -- the Lord's Prayer, the Good Samaritan and the prodigal son
    /// all returned nothing despite being in the corpus (61% overall, 17
    /// no-coverage failures). Loosening to 0.45 distance recovers them (75%,
    /// 7 no-coverage) while still screening every out-of-scope question in the
    /// set. Going further to 0.50 scores higher overall but begins grounding
    /// "how do I bake sourdough bread", which is the failure this floor
    /// exists to prevent, so it is not the maximum of the score curve.
    private let defaultMaxDistance: Float = 0.45

    init(embeddingsURL: URL, passagesURL: URL) throws {
        let passagesData = try Data(contentsOf: passagesURL)
        let decodedPassages = try JSONDecoder().decode([PassageRecord].self, from: passagesData)
        self.passages = decodedPassages
        self.embeddings = try Data(contentsOf: embeddingsURL, options: .alwaysMapped)

        let expectedBytes = passages.count * embeddingDimension * MemoryLayout<Float>.size
        guard embeddings.count == expectedBytes else {
            throw OnDeviceGroundingStoreError.corpusMismatch
        }
        self.chapterRanges = Self.indexChapters(in: passages)
        self.sourceIndices = Dictionary(grouping: decodedPassages.indices, by: { decodedPassages[$0].sourceId })
    }

    /// Chapters are chunked across several passages, but only the first chunk
    /// of each carries the `[JHN14]` tag, so a chapter runs from its tagged
    /// chunk up to the next tagged chunk in the same source.
    private static func indexChapters(in passages: [PassageRecord]) -> [String: Range<Int>] {
        var starts: [(key: String, index: Int)] = []
        for (index, passage) in passages.enumerated() {
            guard let key = chapterKey(inLeadingTagOf: passage.text) else { continue }
            starts.append((key, index))
        }
        var ranges: [String: Range<Int>] = [:]
        for (offset, entry) in starts.enumerated() {
            let sourceID = passages[entry.index].sourceId
            var end = entry.index + 1
            while end < passages.count, passages[end].sourceId == sourceID {
                if offset + 1 < starts.count, starts[offset + 1].index == end { break }
                // Book-level tags like `[ROM]` and trailing front/back matter are not chapter
                // starts, so they would otherwise be swallowed into the preceding chapter.
                if hasLeadingTag(passages[end].text) { break }
                end += 1
            }
            // Later duplicates of a tag (the corpus carries a handful) keep the
            // first occurrence, which is the canonical chapter opening.
            if ranges[entry.key] == nil {
                ranges[entry.key] = entry.index..<end
            }
        }
        return ranges
    }

    /// Whether a passage opens with any bracketed corpus tag, chapter-level
    /// (`[JHN14]`) or book-level (`[ROM]`).
    private static func hasLeadingTag(_ text: String) -> Bool {
        let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.first == "[",
              let close = trimmed.firstIndex(of: "]")
        else { return false }
        let body = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        return !body.isEmpty
            && body.count <= 8
            && body.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    /// Reads a leading `[JHN14]` tag: a three-character USFM book code followed
    /// by the chapter number.
    private static func chapterKey(inLeadingTagOf text: String) -> String? {
        let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.first == "[",
              let close = trimmed.firstIndex(of: "]")
        else { return nil }
        let body = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        guard body.count > 3 else { return nil }
        let code = body.prefix(3)
        let chapter = body.dropFirst(3)
        guard code.allSatisfy({ $0.isUppercase || $0.isNumber }),
              chapter.allSatisfy(\.isNumber),
              let number = Int(chapter)
        else { return nil }
        return "\(code)\(number)"
    }

    /// The passages making up an explicitly cited chapter, in reading order. A named passage may
    /// supply a literal source-text anchor, in which case reading begins at that chunk instead of
    /// at the chapter opening. Returns an empty array when the corpus does not carry the chapter
    /// or a claimed anchor is absent, so a stale pointer cannot silently supply the wrong text.
    func chapter(for citation: ScriptureCitation, limit: Int) -> [GroundingPassage] {
        guard limit > 0,
              let range = chapterRanges["\(citation.bookCode)\(citation.chapter)"]
        else { return [] }
        let start: Int
        if let anchorText = citation.anchorText {
            guard let anchor = range.first(where: {
                passages[$0].text.localizedCaseInsensitiveContains(anchorText)
            }) else { return [] }
            start = anchor
        } else {
            start = range.lowerBound
        }
        return passages.indices[start..<range.upperBound].prefix(limit).map { index in
            let record = passages[index]
            return GroundingPassage(
                text: record.text,
                title: "\(citation.displayName) — \(record.title)",
                sourceID: record.sourceId,
                // An exact citation match is a lookup hit, not a ranked one.
                distance: 0
            )
        }
    }

    var passageCount: Int { passages.count }

    /// Returns a source-local run beginning at a known section heading or formula. Authority
    /// pointers identify the first passage exactly; the following chunks supply the explanation
    /// that a short heading alone cannot carry. This never crosses into another source.
    func section(
        sourceIDs: Set<String>,
        requiredTerms: Set<String>,
        limit: Int
    ) -> [GroundingPassage] {
        guard limit > 0, !requiredTerms.isEmpty else { return [] }
        let indices = sourceIDs.sorted().flatMap { sourceIndices[$0] ?? [] }
        guard let anchorOffset = indices.firstIndex(where: { index in
            requiredTerms.allSatisfy { passages[index].text.localizedCaseInsensitiveContains($0) }
        }) else { return [] }

        let anchorSourceID = passages[indices[anchorOffset]].sourceId
        return indices[anchorOffset...]
            .prefix { passages[$0].sourceId == anchorSourceID }
            .prefix(limit)
            .map { index in
                let record = passages[index]
                return GroundingPassage(
                    text: record.text,
                    title: record.title,
                    sourceID: record.sourceId,
                    distance: 0
                )
            }
    }

    func retrieve(
        queryEmbedding: [Float],
        k: Int = 4,
        maxDistance: Float? = nil,
        sourceIDs: Set<String>? = nil,
        prioritizingTerms: Set<String> = [],
        requiredTerms: Set<String> = []
    ) -> [GroundingPassage] {
        guard queryEmbedding.count == embeddingDimension, !passages.isEmpty else {
            return []
        }
        let threshold = maxDistance ?? defaultMaxDistance
        let candidateIndices = sourceIDs.map { ids in
            ids.flatMap { sourceIndices[$0] ?? [] }
        } ?? Array(passages.indices)

        var similarities = [Float](repeating: 0, count: passages.count)
        embeddings.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let base = rawBuffer.bindMemory(to: Float.self).baseAddress!
            queryEmbedding.withUnsafeBufferPointer { queryBuffer in
                let query = queryBuffer.baseAddress!
                for index in candidateIndices {
                    let row = base + index * embeddingDimension
                    var dot: Float = 0
                    vDSP_dotpr(query, 1, row, 1, &dot, vDSP_Length(embeddingDimension))
                    similarities[index] = dot
                }
            }
        }

        let permitsSourceTermMatch = sourceIDs != nil && !prioritizingTerms.isEmpty
        let ranked = candidateIndices.lazy
            .map { index in
                let record = self.passages[index]
                let matchedTerms = prioritizingTerms.reduce(into: 0) { count, term in
                    if record.text.localizedCaseInsensitiveContains(term) { count += 1 }
                }
                let satisfiesRequiredTerms = requiredTerms.allSatisfy {
                    record.text.localizedCaseInsensitiveContains($0)
                }
                return (
                    index: index,
                    distance: 1 - similarities[index],
                    matchedTerms: matchedTerms,
                    satisfiesRequiredTerms: satisfiesRequiredTerms
                )
            }
            // An explicit document title plus a real term in that document is a lookup hit, like
            // a Bible citation. It may legitimately sit below the corpus-wide semantic floor,
            // which exists to reject unrelated *global* matches such as Livy on "council".
            .filter {
                $0.satisfiesRequiredTerms
                    && ($0.distance <= threshold || (permitsSourceTermMatch && $0.matchedTerms > 0))
            }
            .sorted {
                if $0.matchedTerms != $1.matchedTerms {
                    return $0.matchedTerms > $1.matchedTerms
                }
                return $0.distance < $1.distance
            }
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
