import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Library homepage")
struct LibraryHomeTests {
    private func passage(_ sourceID: String, _ chunk: Int, _ text: String) -> LibraryPassage {
        LibraryPassage(text: text, title: sourceID.capitalized, sourceId: sourceID, chunkIndex: chunk)
    }

    @Test("Excerpts skip the clipped first and last sentences of a chunk")
    func excerptUsesOnlyInteriorSentences() throws {
        let text = "ends a sentence begun in the prior chunk. "
            + "The soul is in some sense all things, for it knows every form it receives. "
            + "Every agent acts for an end, and the end is what first moves the will to act. "
            + "This last sentence is clipped by the chunk bound"
        let excerpt = try #require(LibraryFeaturedPassage.excerpt(from: text))
        #expect(excerpt.hasPrefix("The soul is in some sense all things"))
        #expect(!excerpt.contains("prior chunk"))
        #expect(!excerpt.contains("clipped"))
    }

    @Test("Excerpts reject citations, scaffolding, and context-dependent openers")
    func excerptRejectsNoise() {
        let citation = "clipped start. Whether any virtue is caused in us by habituation (Q[49], A[3]) remains open here. "
            + "Objection 1: It seems that not every being is good for the reasons given above. "
            + "Therefore goodness limits being in the way that every addition limits a thing. "
            + "trailing fragment"
        #expect(LibraryFeaturedPassage.excerpt(from: citation) == nil)
    }

    @Test("Excerpts stay within the card's length bounds")
    func excerptRespectsLength() throws {
        let long = String(repeating: "word ", count: 90).trimmingCharacters(in: .whitespaces)
        let text = "clipped start. Word \(long). "
            + "Justice is the constant and perpetual will to render to each his due. "
            + "Mercy does not destroy justice, but is in a sense the fulness thereof. "
            + "clipped end"
        let excerpt = try #require(LibraryFeaturedPassage.excerpt(from: text))
        #expect(excerpt.count <= LibraryFeaturedPassage.maximumExcerptLength)
        #expect(excerpt.count >= LibraryFeaturedPassage.minimumExcerptLength)
        #expect(excerpt.hasPrefix("Justice"))
    }

    @Test("The passage of the day is stable within a day and skips works without prose")
    func dailySelectionIsDeterministic() throws {
        let prose = "clipped start. "
            + "Love is the first gift, and every other gift is given freely on account of it. "
            + "Beauty is that which pleases when it is seen, and it delights the one who knows it. "
            + "clipped end"
        let passages = [
            passage("a-headings", 0, "Book I. Chapter 1. Chapter 2."),
            passage("b-prose", 0, prose),
            passage("b-prose", 1, prose),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8)))
        let evening = morning.addingTimeInterval(12 * 60 * 60)

        let first = try #require(LibraryFeaturedPassage.select(from: passages, on: morning, calendar: calendar))
        let second = LibraryFeaturedPassage.select(from: passages, on: evening, calendar: calendar)
        #expect(first == second)
        #expect(first.workID == "b-prose")
        #expect(LibraryFeaturedPassage.select(from: [], on: morning, calendar: calendar) == nil)
    }

    @Test("Opening a work moves it to the front of recents without duplicates")
    func recentsOrdering() {
        let ids = ["didache", "summa-theologica", "web-bible"]
        #expect(LibraryRecents.opening("web-bible", in: ids) == ["web-bible", "didache", "summa-theologica"])
        let full = (0..<LibraryRecents.limit).map { "work-\($0)" }
        let updated = LibraryRecents.opening("new", in: full)
        #expect(updated.count == LibraryRecents.limit)
        #expect(updated.first == "new")
        #expect(LibraryRecents.decode(LibraryRecents.encode(ids)) == ids)
        #expect(LibraryRecents.decode("").isEmpty)
    }

    @Test("Catalog groups works by subject and searches titles and subjects")
    func catalogGroupingAndSearch() {
        let catalog = LibraryCatalog(
            passages: [
                passage("aristotle-metaphysics", 0, "text"),
                passage("aristotle-metaphysics", 1, "text"),
                passage("web-bible", 0, "text"),
            ],
            date: Date()
        )
        #expect(catalog.passageCount == 3)
        #expect(catalog.works(in: .philosophy).map(\.id) == ["aristotle-metaphysics"])
        #expect(catalog.works(in: .philosophy).first?.passageCount == 2)
        #expect(catalog.search("scripture").map(\.id) == ["web-bible"])
        #expect(catalog.search("  ").count == 2)
    }
}
