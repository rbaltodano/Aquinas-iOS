//
//  MiniLMEmbedder.swift
//  Aquinas-iOS
//

import CoreML
import Foundation

/// On-device sentence embeddings via a Core ML export of
/// `sentence-transformers/all-MiniLM-L6-v2`. Verified against the reference
/// PyTorch model at ~0.9999 cosine similarity (see the export script in
/// Aquinas_Backend); this is the same embedding space the grounding corpus
/// was built with, not the unrelated NLEmbedding space used elsewhere in
/// this app's global Insight Library canvas.
final class MiniLMEmbedder {
    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let sequenceLength: Int

    init(modelURL: URL, vocabURL: URL, sequenceLength: Int = 128) throws {
        self.model = try MLModel(contentsOf: modelURL)
        self.tokenizer = try WordPieceTokenizer(
            vocabURL: vocabURL,
            maxLength: sequenceLength
        )
        self.sequenceLength = sequenceLength
    }

    /// Returns a normalized 384-dimensional embedding for `text`.
    func embed(_ text: String) throws -> [Float] {
        let (ids, mask) = tokenizer.encode(text)

        let idsArray = try MLMultiArray(
            shape: [1, NSNumber(value: sequenceLength)],
            dataType: .int32
        )
        let maskArray = try MLMultiArray(
            shape: [1, NSNumber(value: sequenceLength)],
            dataType: .int32
        )
        for index in 0..<sequenceLength {
            idsArray[index] = NSNumber(value: ids[index])
            maskArray[index] = NSNumber(value: mask[index])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": idsArray,
            "attention_mask": maskArray,
        ])
        let output = try model.prediction(from: input)
        guard let featureName = output.featureNames.first,
              let embeddingArray = output.featureValue(for: featureName)?.multiArrayValue else {
            throw MiniLMEmbedderError.missingOutput
        }

        var embedding = [Float](repeating: 0, count: embeddingArray.count)
        for index in 0..<embeddingArray.count {
            embedding[index] = embeddingArray[index].floatValue
        }
        return embedding
    }
}

enum MiniLMEmbedderError: LocalizedError {
    case missingOutput

    var errorDescription: String? {
        "The on-device embedding model did not return an embedding."
    }
}
