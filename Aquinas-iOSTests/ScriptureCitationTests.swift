import Testing
@testable import Aquinas_iOS

@Suite("Scripture citation parsing")
struct ScriptureCitationTests {
    @Test("Plain and spelled-out chapter references resolve to the corpus book code")
    func parsesCommonCitationForms() {
        for question in [
            "John 14",
            "John chapter 14",
            "What does John 14 say about the way, the truth and the life?",
            "john 14:6",
            "Explain John chapter 14, please"
        ] {
            let citations = ScriptureCitation.citations(in: question)
            #expect(citations.first?.bookCode == "JHN", "failed for: \(question)")
            #expect(citations.first?.chapter == 14, "failed for: \(question)")
        }
    }

    @Test("A numbered book wins over the bare book name it contains")
    func prefersLongestBookAlias() {
        let citations = ScriptureCitation.citations(in: "What is 1 John 2 about?")
        #expect(citations.count == 1)
        #expect(citations.first?.bookCode == "1JN")
        #expect(citations.first?.chapter == 2)
    }

    @Test("A book named without a chapter is topical, not a lookup")
    func ignoresBookWithoutChapter() {
        #expect(ScriptureCitation.citations(in: "Who wrote the Gospel of John?").isEmpty)
        #expect(ScriptureCitation.citations(in: "What does Romans teach about grace?").isEmpty)
    }

    @Test("Book names embedded in longer words are not citations")
    func requiresWordBoundaries() {
        #expect(ScriptureCitation.citations(in: "Johnson 3 wrote this").isEmpty)
        #expect(ScriptureCitation.citations(in: "Marketing 3 principles").isEmpty)
    }

    @Test("A verse suffix still resolves to its chapter")
    func ignoresVerseSuffix() {
        let citations = ScriptureCitation.citations(in: "Explain Romans 8:28")
        #expect(citations.first?.bookCode == "ROM")
        #expect(citations.first?.chapter == 8)
    }

    @Test("Multiple citations in one question are all returned")
    func parsesMultipleCitations() {
        let citations = ScriptureCitation.citations(in: "Compare Psalm 23 with Matthew 5")
        let pairs = Set(citations.map { "\($0.bookCode)\($0.chapter)" })
        #expect(pairs == ["PSA23", "MAT5"])
    }

    @Test("Implausible chapter numbers are rejected")
    func rejectsOutOfRangeChapters() {
        #expect(ScriptureCitation.citations(in: "John 0").isEmpty)
        #expect(ScriptureCitation.citations(in: "John 4000").isEmpty)
    }

    @Test("Display name carries the readable citation")
    func buildsDisplayName() {
        let citation = ScriptureCitation.citations(in: "1 Corinthians 13").first
        #expect(citation?.displayName == "1 Corinthians 13")
    }
}
