//
//  WordPieceTokenizer.swift
//  Aquinas-iOS
//

import Foundation

/// BERT-style WordPiece tokenizer, matching the tokenizer bundled with
/// `sentence-transformers/all-MiniLM-L6-v2` (uncased, basic tokenization then
/// greedy longest-match subword splitting). Only what MiniLMEmbedder needs:
/// single-sequence encoding to fixed-length token/attention-mask arrays.
struct WordPieceTokenizer {
    let maxLength: Int

    private let vocab: [String: Int32]
    private let clsID: Int32
    private let sepID: Int32
    private let padID: Int32
    private let unkID: Int32
    private let unkToken = "[UNK]"
    private static let maxWordPieceChars = 200

    init(vocabURL: URL, maxLength: Int = 128) throws {
        let contents = try String(contentsOf: vocabURL, encoding: .utf8)
        var table: [String: Int32] = [:]
        for (index, line) in contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            table[String(line)] = Int32(index)
        }
        guard let cls = table["[CLS]"],
              let sep = table["[SEP]"],
              let pad = table["[PAD]"],
              let unk = table["[UNK]"] else {
            throw WordPieceTokenizerError.missingSpecialToken
        }
        self.vocab = table
        self.clsID = cls
        self.sepID = sep
        self.padID = pad
        self.unkID = unk
        self.maxLength = maxLength
    }

    /// Returns (inputIDs, attentionMask), each exactly `maxLength` long.
    func encode(_ text: String) -> (inputIDs: [Int32], attentionMask: [Int32]) {
        let wordPieceIDs = tokenize(text)
        let available = max(maxLength - 2, 0)
        let truncated = Array(wordPieceIDs.prefix(available))

        var ids: [Int32] = [clsID] + truncated + [sepID]
        var mask = [Int32](repeating: 1, count: ids.count)

        if ids.count < maxLength {
            ids += [Int32](repeating: padID, count: maxLength - ids.count)
            mask += [Int32](repeating: 0, count: maxLength - mask.count)
        }
        return (ids, mask)
    }

    private func tokenize(_ text: String) -> [Int32] {
        var ids: [Int32] = []
        for word in basicTokenize(text) {
            ids.append(contentsOf: wordPiece(word))
        }
        return ids
    }

    /// Lowercase, strip accents, split off punctuation as its own token,
    /// split on whitespace. Matches BasicTokenizer's default (uncased) behavior.
    private func basicTokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        for scalar in lowered.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flush()
            } else if isPunctuation(scalar) {
                flush()
                tokens.append(String(scalar))
            } else {
                let stripped = stripAccent(scalar)
                if let stripped {
                    current.unicodeScalars.append(stripped)
                }
            }
        }
        flush()
        return tokens
    }

    private func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value)
            || (91...96).contains(value) || (123...126).contains(value) {
            return true
        }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }

    private func stripAccent(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let normalized = String(scalar).decomposedStringWithCanonicalMapping
        for candidate in normalized.unicodeScalars where !isCombiningMark(candidate) {
            return candidate
        }
        return normalized.unicodeScalars.first
    }

    private func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        (0x0300...0x036F).contains(scalar.value)
    }

    /// Greedy longest-match-first subword splitting, the core WordPiece algorithm.
    private func wordPiece(_ word: String) -> [Int32] {
        if word.count > Self.maxWordPieceChars {
            return [unkID]
        }
        let characters = Array(word)
        var result: [Int32] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var matched: Int32?
            while start < end {
                var piece = String(characters[start..<end])
                if start > 0 {
                    piece = "##" + piece
                }
                if let id = vocab[piece] {
                    matched = id
                    break
                }
                end -= 1
            }
            guard let matchedID = matched else {
                return [unkID]
            }
            result.append(matchedID)
            start = end
        }
        return result
    }
}

enum WordPieceTokenizerError: LocalizedError {
    case missingSpecialToken

    var errorDescription: String? {
        "The bundled vocabulary is missing a required special token."
    }
}
