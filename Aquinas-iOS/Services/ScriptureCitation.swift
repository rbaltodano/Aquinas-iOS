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
    /// A phrase in the source text at which this named passage begins. A chapter citation has no
    /// anchor and therefore begins at the chapter opening.
    let anchorText: String?

    init(bookCode: String, chapter: Int, displayName: String, anchorText: String? = nil) {
        self.bookCode = bookCode
        self.chapter = chapter
        self.displayName = displayName
        self.anchorText = anchorText
    }

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

    /// Passages people name rather than cite. "The Beatitudes", "the prodigal son" and "the Our
    /// Father" are lookup keys exactly like "John 14" is, and for the same reason they must be
    /// resolved lexically: MiniLM is a topical matcher, not a lexical one. Measured against the
    /// bundled corpus, a descriptor card containing the literal words "the Our Father" scores 0.345
    /// against the question "What is the Our Father?", and Matthew 5 itself scores 0.213 against
    /// "What are the Beatitudes?" — the word "Beatitudes" never appears in the chapter, which says
    /// "Blessed are...". Re-chunking, cleaning boilerplate and prepending descriptive headers were
    /// all measured and none closed that gap; naming is simply not what the embedder does.
    ///
    /// This maps a name to a *location in the real corpus*. It does not hardcode an answer — the
    /// text still comes from Scripture — so it generalises to any question about the passage
    /// rather than only the one someone anticipated.
    private static let namedPassages: [(name: String, code: String, chapter: Int, display: String)] = [
        ("beatitudes", "MAT", 5, "Matthew 5"),
        ("sermon on the mount", "MAT", 5, "Matthew 5"),
        ("salt of the earth", "MAT", 5, "Matthew 5"),
        ("light of the world", "MAT", 5, "Matthew 5"),
        ("lord's prayer", "MAT", 6, "Matthew 6"),
        ("lords prayer", "MAT", 6, "Matthew 6"),
        ("our father", "MAT", 6, "Matthew 6"),
        ("teach us to pray", "LUK", 11, "Luke 11"),
        ("treasure in heaven", "MAT", 6, "Matthew 6"),
        ("golden rule", "MAT", 7, "Matthew 7"),
        ("great commission", "MAT", 28, "Matthew 28"),
        ("sheep and the goats", "MAT", 25, "Matthew 25"),
        ("parable of the talents", "MAT", 25, "Matthew 25"),
        ("parable of the sower", "MAT", 13, "Matthew 13"),
        ("good samaritan", "LUK", 10, "Luke 10"),
        ("mary and martha", "LUK", 10, "Luke 10"),
        ("prodigal son", "LUK", 15, "Luke 15"),
        ("lost sheep", "LUK", 15, "Luke 15"),
        ("lost coin", "LUK", 15, "Luke 15"),
        ("magnificat", "LUK", 1, "Luke 1"),
        ("annunciation", "LUK", 1, "Luke 1"),
        ("nativity", "LUK", 2, "Luke 2"),
        ("christmas story", "LUK", 2, "Luke 2"),
        ("road to emmaus", "LUK", 24, "Luke 24"),
        ("prologue of john", "JHN", 1, "John 1"),
        ("word became flesh", "JHN", 1, "John 1"),
        ("born again", "JHN", 3, "John 3"),
        ("woman at the well", "JHN", 4, "John 4"),
        ("samaritan woman", "JHN", 4, "John 4"),
        ("bread of life", "JHN", 6, "John 6"),
        ("good shepherd", "JHN", 10, "John 10"),
        ("raising of lazarus", "JHN", 11, "John 11"),
        ("washing of the feet", "JHN", 13, "John 13"),
        ("farewell discourse", "JHN", 14, "John 14"),
        ("way the truth and the life", "JHN", 14, "John 14"),
        ("the vine and the branches", "JHN", 15, "John 15"),
        ("doubting thomas", "JHN", 20, "John 20"),
        ("ten commandments", "EXO", 20, "Exodus 20"),
        ("burning bush", "EXO", 3, "Exodus 3"),
        ("passover", "EXO", 12, "Exodus 12"),
        ("parting of the red sea", "EXO", 14, "Exodus 14"),
        ("creation account", "GEN", 1, "Genesis 1"),
        ("garden of eden", "GEN", 2, "Genesis 2"),
        ("the fall", "GEN", 3, "Genesis 3"),
        ("cain and abel", "GEN", 4, "Genesis 4"),
        ("noah", "GEN", 6, "Genesis 6"),
        ("tower of babel", "GEN", 11, "Genesis 11"),
        ("binding of isaac", "GEN", 22, "Genesis 22"),
        ("joseph and his brothers", "GEN", 37, "Genesis 37"),
        ("david and goliath", "1SA", 17, "1 Samuel 17"),
        ("the shepherd psalm", "PSA", 23, "Psalm 23"),
        ("valley of the shadow of death", "PSA", 23, "Psalm 23"),
        ("hymn to love", "1CO", 13, "1 Corinthians 13"),
        ("love is patient", "1CO", 13, "1 Corinthians 13"),
        ("fruit of the spirit", "GAL", 5, "Galatians 5"),
        ("armor of god", "EPH", 6, "Ephesians 6"),
        ("faith without works", "JAS", 2, "James 2"),
        ("suffering servant", "ISA", 53, "Isaiah 53"),
        ("fiery furnace", "DAN", 3, "Daniel 3"),
        ("den of lions", "DAN", 6, "Daniel 6"),
        ("pentecost", "ACT", 2, "Acts 2"),
        ("road to damascus", "ACT", 9, "Acts 9"),
        ("faith chapter", "HEB", 11, "Hebrews 11")
    ]

    /// Some familiar passages begin after the opening chunk of their chapter. These anchors are
    /// literal phrases from the bundled World English Bible and select that source text in reading
    /// order; they are locations, never summaries or answers. The natural wording "teach us to
    /// pray" likewise identifies the question-and-answer at the start of Luke 11.
    private static let namedPassageAnchors: [String: String] = [
        "lord's prayer": "our father in heaven",
        "lords prayer": "our father in heaven",
        "our father": "our father in heaven",
        "teach us to pray": "lord, teach us to pray",
        "good samaritan": "a certain man was going down from jerusalem to jericho"
    ]

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

        for entry in namedPassages.sorted(by: { $0.name.count > $1.name.count })
        where normalized.contains(entry.name) {
            let citation = ScriptureCitation(
                bookCode: entry.code,
                chapter: entry.chapter,
                displayName: entry.display,
                anchorText: namedPassageAnchors[entry.name]
            )
            if !found.contains(citation) { found.append(citation) }
        }

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
