//
//  ScriptureCitation.swift
//  Aquinas-iOS
//

import Foundation

/// A scripture reference named explicitly in a question ("John 14", "Romans 8:28",
/// "1 Corinthians chapter 13").
///
/// MiniLM embeds a bare citation semantically, which is the wrong operation for it: measured
/// against the bundled corpus, "John chapter 14" ranks Augustine's *Confessions* first and reaches
/// the Gospel of John only via a passage about *John Hyrcanus* in Maccabees, while the same
/// question phrased in prose ("what does John 14 say about the way, the truth and the life?")
/// retrieves the correct chapter at 0.69 similarity. A citation is a lookup key, not a topic, so
/// it is resolved lexically against the corpus's own chapter locator tags before semantic search
/// runs — see `OnDeviceGroundingStore.chapter(for:)`.
nonisolated struct ScriptureCitation: Equatable {
    /// USFM book code as it appears in the corpus's `[JHN14]`-style chapter tags.
    let bookCode: String
    let chapter: Int
    /// Display form for prompt/citation text, e.g. "John 14".
    let displayName: String

    /// Book aliases mapped to the USFM codes used by the bundled World English Bible export.
    /// Ordered longest-first at lookup time so "1 john" wins over "john" in "1 John 2".
    private static let bookAliases: [(alias: String, code: String, display: String)] = [
        ("genesis", "GEN", "Genesis"), ("exodus", "EXO", "Exodus"),
        ("leviticus", "LEV", "Leviticus"), ("numbers", "NUM", "Numbers"),
        ("deuteronomy", "DEU", "Deuteronomy"), ("joshua", "JOS", "Joshua"),
        ("judges", "JDG", "Judges"), ("ruth", "RUT", "Ruth"),
        ("1 samuel", "1SA", "1 Samuel"), ("first samuel", "1SA", "1 Samuel"),
        ("2 samuel", "2SA", "2 Samuel"), ("second samuel", "2SA", "2 Samuel"),
        ("1 kings", "1KI", "1 Kings"), ("first kings", "1KI", "1 Kings"),
        ("2 kings", "2KI", "2 Kings"), ("second kings", "2KI", "2 Kings"),
        ("1 chronicles", "1CH", "1 Chronicles"), ("2 chronicles", "2CH", "2 Chronicles"),
        ("ezra", "EZR", "Ezra"), ("nehemiah", "NEH", "Nehemiah"), ("esther", "EST", "Esther"),
        ("job", "JOB", "Job"), ("psalm", "PSA", "Psalm"), ("psalms", "PSA", "Psalm"),
        ("proverbs", "PRO", "Proverbs"), ("ecclesiastes", "ECC", "Ecclesiastes"),
        ("song of solomon", "SNG", "Song of Solomon"), ("song of songs", "SNG", "Song of Songs"),
        ("isaiah", "ISA", "Isaiah"), ("jeremiah", "JER", "Jeremiah"),
        ("lamentations", "LAM", "Lamentations"), ("ezekiel", "EZK", "Ezekiel"),
        ("daniel", "DAN", "Daniel"), ("hosea", "HOS", "Hosea"), ("joel", "JOL", "Joel"),
        ("amos", "AMO", "Amos"), ("obadiah", "OBA", "Obadiah"), ("jonah", "JON", "Jonah"),
        ("micah", "MIC", "Micah"), ("nahum", "NAM", "Nahum"), ("habakkuk", "HAB", "Habakkuk"),
        ("zephaniah", "ZEP", "Zephaniah"), ("haggai", "HAG", "Haggai"),
        ("zechariah", "ZEC", "Zechariah"), ("malachi", "MAL", "Malachi"),
        ("matthew", "MAT", "Matthew"), ("matt", "MAT", "Matthew"),
        ("mark", "MRK", "Mark"), ("luke", "LUK", "Luke"),
        ("john", "JHN", "John"), ("gospel of john", "JHN", "John"),
        ("acts", "ACT", "Acts"), ("romans", "ROM", "Romans"),
        ("1 corinthians", "1CO", "1 Corinthians"), ("first corinthians", "1CO", "1 Corinthians"),
        ("2 corinthians", "2CO", "2 Corinthians"), ("second corinthians", "2CO", "2 Corinthians"),
        ("galatians", "GAL", "Galatians"), ("ephesians", "EPH", "Ephesians"),
        ("philippians", "PHP", "Philippians"), ("colossians", "COL", "Colossians"),
        ("1 thessalonians", "1TH", "1 Thessalonians"),
        ("2 thessalonians", "2TH", "2 Thessalonians"),
        ("1 timothy", "1TI", "1 Timothy"), ("2 timothy", "2TI", "2 Timothy"),
        ("titus", "TIT", "Titus"), ("philemon", "PHM", "Philemon"),
        ("hebrews", "HEB", "Hebrews"), ("james", "JAS", "James"),
        ("1 peter", "1PE", "1 Peter"), ("first peter", "1PE", "1 Peter"),
        ("2 peter", "2PE", "2 Peter"), ("second peter", "2PE", "2 Peter"),
        ("1 john", "1JN", "1 John"), ("first john", "1JN", "1 John"),
        ("2 john", "2JN", "2 John"), ("3 john", "3JN", "3 John"),
        ("jude", "JUD", "Jude"), ("revelation", "REV", "Revelation")
    ]

    private static let sortedAliases: [(alias: String, code: String, display: String)] =
        bookAliases.sorted { $0.alias.count > $1.alias.count }

    /// Every citation named in `question`, most specific book name first. Returns an empty array
    /// for questions that merely mention a book without a chapter ("who wrote John?"), since
    /// those are topical and semantic search handles them correctly.
    static func citations(in question: String) -> [ScriptureCitation] {
        let normalized = question
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        guard !normalized.isEmpty else { return [] }

        var found: [ScriptureCitation] = []
        var claimed: [Range<String.Index>] = []

        for entry in sortedAliases {
            var searchStart = normalized.startIndex
            while let range = normalized.range(
                of: entry.alias,
                range: searchStart..<normalized.endIndex
            ) {
                searchStart = range.upperBound
                guard isWordBoundary(normalized, before: range.lowerBound),
                      isWordBoundary(normalized, after: range.upperBound),
                      !claimed.contains(where: { $0.overlaps(range) }),
                      let chapter = chapterNumber(in: normalized, after: range.upperBound)
                else { continue }
                claimed.append(range.lowerBound..<chapter.end)
                found.append(
                    ScriptureCitation(
                        bookCode: entry.code,
                        chapter: chapter.value,
                        displayName: "\(entry.display) \(chapter.value)"
                    )
                )
            }
        }
        return found
    }

    /// Reads the chapter number following a book name, tolerating an intervening "chapter" or
    /// "ch." A verse suffix ("8:28") is deliberately ignored: the corpus's smallest retrievable
    /// unit is a chapter chunk.
    private static func chapterNumber(
        in text: String,
        after index: String.Index
    ) -> (value: Int, end: String.Index)? {
        var cursor = index
        var sawSeparator = false
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == " " || character == "." || character == "," {
                cursor = text.index(after: cursor)
                sawSeparator = true
                continue
            }
            if text[cursor...].hasPrefix("chapter") {
                cursor = text.index(cursor, offsetBy: "chapter".count)
                sawSeparator = true
                continue
            }
            if text[cursor...].hasPrefix("ch ") {
                cursor = text.index(cursor, offsetBy: 3)
                sawSeparator = true
                continue
            }
            break
        }
        guard sawSeparator || cursor == index else { return nil }

        var digits = ""
        var end = cursor
        while end < text.endIndex, text[end].isNumber {
            digits.append(text[end])
            end = text.index(after: end)
        }
        guard let value = Int(digits), value > 0, value < 200 else { return nil }
        return (value, end)
    }

    private static func isWordBoundary(_ text: String, before index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        return !text[text.index(before: index)].isLetter
    }

    private static func isWordBoundary(_ text: String, after index: String.Index) -> Bool {
        guard index < text.endIndex else { return true }
        return !text[index].isLetter
    }
}
