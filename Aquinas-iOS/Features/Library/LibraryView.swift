import SwiftUI

extension Notification.Name {
    static let openGroundingSourceInLibrary = Notification.Name("openGroundingSourceInLibrary")
}

struct LibraryPassage: Decodable, Identifiable {
    let text: String
    let title: String
    let sourceId: String
    let chunkIndex: Int
    var id: String { "\(sourceId)-\(chunkIndex)" }
}

struct LibraryWork: Identifiable, Equatable {
    let id: String
    let title: String
    let passageCount: Int
}

private struct LibrarySection: Identifiable {
    let id: String
    let title: String
    let chunks: ClosedRange<Int>
    let children: [LibrarySection]

    init(id: String, title: String, chunks: ClosedRange<Int>, children: [LibrarySection] = []) {
        self.id = id
        self.title = title
        self.chunks = chunks
        self.children = children
    }
}

private extension Array where Element == LibrarySection {
    func node(withID id: String) -> LibrarySection? {
        for node in self {
            if node.id == id { return node }
            if let match = node.children.node(withID: id) { return match }
        }
        return nil
    }

    func path(to id: String) -> [LibrarySection]? {
        for node in self {
            if node.id == id { return [node] }
            if let childPath = node.children.path(to: id) { return [node] + childPath }
        }
        return nil
    }
}

private extension LibrarySection {
    var firstReadableDescendant: LibrarySection {
        children.first?.firstReadableDescendant ?? self
    }
}

private struct LibraryDocument {
    let title: String
    let context: String
    let navigationUnit: String
    let passages: [LibraryPassage]
    let sections: [LibrarySection]

    static func load(_ work: LibraryWork) -> LibraryDocument? {
        guard let url = Bundle.main.url(forResource: "passages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONDecoder().decode([LibraryPassage].self, from: data)
        else { return nil }

        let passages = corpus.filter { $0.sourceId == work.id }.sorted { $0.chunkIndex < $1.chunkIndex }
        guard let first = passages.first, let last = passages.last else { return nil }
        let sections = outline(
            for: work.id,
            passages: passages,
            firstChunkIndex: first.chunkIndex,
            lastChunkIndex: last.chunkIndex
        )

        return LibraryDocument(
            title: work.title,
            context: work.id == "us-declaration-of-independence"
                ? "The unanimous Declaration of the thirteen united States of America, adopted by Congress on July 4, 1776."
                : "A work from the Aquinas research corpus.",
            navigationUnit: navigationUnit(for: work.id),
            passages: passages,
            sections: sections
        )
    }

    private static func navigationUnit(for sourceID: String) -> String {
        switch sourceID {
        case "summa-theologica":
            "Article"
        case "web-bible":
            "Book"
        case "council-of-trent":
            "Session"
        case "ecumenical-creeds-schaff":
            "Creed"
        case "seven-ecumenical-councils":
            "Council"
        case "augsburg-confession", "belgic-confession", "thirty-nine-articles":
            "Article"
        case "heidelberg-catechism", "roman-catechism-donovan":
            "Part"
        case "baltimore-catechism-3":
            "Lesson"
        case "us-declaration-of-independence", "westminster-confession",
             "aristotle-categories", "machiavelli-the-prince", "anselm-proslogion":
            "Chapter"
        case "aristotle-nicomachean-ethics", "aristotle-metaphysics", "boethius-consolation",
             "adam-smith-wealth-of-nations", "bede-ecclesiastical-history",
             "eusebius-ecclesiastical-history", "herodotus-histories", "josephus-antiquities",
             "livy-history-of-rome", "tacitus-annals-histories", "thucydides-peloponnesian-war",
             "augustine-city-of-god", "irenaeus-against-heresies":
            "Book"
        case "plutarch-parallel-lives":
            "Life"
        case "magna-carta":
            "Clause"
        case "us-constitution":
            "Article"
        case "gibbon-decline-and-fall", "athanasius-on-incarnation", "didache",
             "justin-martyr-first-apology":
            "Section"
        default:
            "Section"
        }
    }

    private static func outline(
        for sourceID: String,
        passages: [LibraryPassage],
        firstChunkIndex: Int,
        lastChunkIndex: Int
    ) -> [LibrarySection] {
        let anchors: [(chunkIndex: Int, title: String)]

        switch sourceID {
        case "web-bible":
            return bibleSections(from: passages)
        case "summa-theologica":
            return summaTreatiseSections(from: passages)
        case "us-declaration-of-independence":
            anchors = [
                (0, "Chapter 1"), (2, "Chapter 2"), (4, "Chapter 3"),
                (6, "Chapter 4"), (7, "Chapter 5"),
            ]
        case "council-of-trent":
            anchors = [
                (0, "Introduction"),
                (36, "Session I"), (39, "Session II"), (42, "Session III"),
                (48, "Session IV"), (57, "Session V"), (70, "Session VI"),
                (107, "Session VII"), (132, "Session VIII"), (134, "Session IX"),
                (138, "Session X"), (145, "Session XI"), (147, "Session XII"),
                (149, "Session XIII"), (180, "Session XIV"), (233, "Session XV"),
                (244, "Session XVI"), (260, "Session XVII"), (262, "Session XVIII"),
                (270, "Session XIX"), (275, "Session XX"), (278, "Session XXI"),
                (293, "Session XXII"), (323, "Session XXIII"), (353, "Session XXIV"),
                (421, "Session XXV"),
            ]
        case "ecumenical-creeds-schaff":
            anchors = [
                (0, "Apostles' Creed"),
                (20, "Niceno-Constantinopolitan Creed"),
                (48, "Athanasian Creed"),
                (59, "Christological Definitions"),
            ]
        case "seven-ecumenical-councils":
            anchors = [
                (0, "General Introduction"),
                (70, "First Council of Nicea"),
                (501, "First Council of Constantinople"),
                (599, "Council of Ephesus"),
                (734, "Council of Chalcedon"),
                (938, "Second Council of Constantinople"),
                (1024, "Third Council of Constantinople"),
                (1559, "Second Council of Nicea"),
            ]
        case "augsburg-confession":
            anchors = [
                (0, "Preface"),
                (14, "Articles I–V"),
                (24, "Articles VI–X"),
                (35, "Articles XI–XVI"),
                (45, "Articles XVII–XXI"),
                (55, "Articles XXII–XXVIII"),
            ]
        case "belgic-confession":
            anchors = [
                (0, "Introduction"),
                (1, "Articles I–III"),
                (4, "Articles IV–VII"),
                (8, "Articles VIII–XI"),
                (14, "Articles XII–XV"),
                (20, "Articles XVI–XX"),
                (27, "Articles XXI–XXVII"),
                (37, "Articles XXVIII–XXXVII"),
            ]
        case "heidelberg-catechism":
            anchors = [
                (0, "Introduction"),
                (4, "Part I: The Misery of Man"),
                (8, "Part II: The Redemption of Man"),
                (59, "Part III: Thankfulness"),
            ]
        case "thirty-nine-articles":
            anchors = [
                (0, "Royal Declaration"),
                (3, "Articles I–IV"),
                (6, "Articles V–IX"),
                (10, "Articles X–XIV"),
                (13, "Articles XV–XIX"),
                (16, "Articles XX–XXIV"),
                (19, "Articles XXV–XXXIX"),
            ]
        case "westminster-confession":
            anchors = [
                (0, "Chapter I: Holy Scripture"),
                (6, "Chapters II–IV"),
                (10, "Chapters V–VIII"),
                (15, "Chapters IX–XII"),
                (19, "Chapters XIII–XVI"),
                (23, "Chapters XVII–XX"),
                (27, "Chapters XXI–XXV"),
                (31, "Chapters XXVI–XXXIII"),
            ]
        case "baltimore-catechism-3":
            anchors = [
                (0, "Prayers and Instructions"),
                (28, "Lessons I–IV: Faith and Creation"),
                (46, "Lessons V–VII: The Fall and Redemption"),
                (72, "Lessons VIII–IX: Christ's Passion and Ascension"),
                (89, "Lessons X–XII: Grace and the Church"),
                (116, "Lessons XIII–XVI: The Sacraments"),
                (145, "Lessons XVII–XVIII: Christian Virtue"),
                (165, "Lessons XIX–XXI: Penance and Eucharist"),
                (188, "Lessons XXII–XXV: Mass and Holy Orders"),
                (225, "Lessons XXVI–XXVIII: Matrimony and Prayer"),
                (258, "Lessons XXIX–XXXI: The Commandments"),
                (281, "Lessons XXXII–XXXV: The Commandments Continued"),
                (307, "Lessons XXXVI–XXXVII: Precepts and Indulgences"),
            ]
        case "roman-catechism-donovan":
            anchors = [
                (0, "Part I: The Apostles' Creed"),
                (214, "Part II: The Sacraments"),
                (594, "Part III: The Commandments"),
                (806, "Part IV: Prayer"),
            ]
        case "aristotle-categories":
            anchors = [
                (0, "Chapters I–II: Terms and Things"),
                (8, "Chapters III–IV: Substance"),
                (16, "Chapters V–VI: Quantity"),
                (24, "Chapters VII–VIII: Relatives and Quality"),
                (32, "Chapters IX–X: Contraries"),
                (40, "Chapters XI–XII: Quality and Opposition"),
                (48, "Chapters XIII–XV: Motion and Possession"),
                (60, "Closing Distinctions"),
            ]
        case "aristotle-nicomachean-ethics":
            anchors = [
                (0, "Book I: The Good and Happiness"),
                (44, "Book II: Moral Virtue"),
                (71, "Book III: Choice and Courage"),
                (120, "Book IV: Particular Virtues"),
                (168, "Book V: Justice"),
                (224, "Book VI: Intellectual Virtue"),
                (258, "Book VII: Continence and Pleasure"),
                (309, "Book VIII: Friendship"),
                (350, "Book IX: Friendship Continued"),
                (394, "Book X: Pleasure and Contemplation"),
            ]
        case "aristotle-metaphysics":
            anchors = [
                (0, "Book I"),
                (53, "Book X"),
                (90, "Book XI"),
                (91, "Book XII"),
                (94, "Book XIII"),
                (99, "Book XIV"),
                (100, "Book II"),
                (109, "Book III"),
                (151, "Book IV"),
                (206, "Book V"),
                (270, "Book VI"),
                (288, "Book VII"),
                (301, "Book VIII"),
                (302, "Book IX"),
            ]
        case "boethius-consolation":
            anchors = [
                (0, "Book I: The Prisoner and Philosophy"),
                (50, "Book II: Fortune's Gifts"),
                (110, "Book III: The Highest Good"),
                (170, "Book IV: Providence and Fate"),
                (225, "Book V: Free Will and Foreknowledge"),
            ]
        case "magna-carta":
            anchors = [
                (0, "Preamble and Liberties of the Church"),
                (4, "Justice, Trade, and Local Government"),
                (9, "Royal Administration and Forests"),
                (14, "Enforcement and the Security Clause"),
            ]
        case "us-constitution":
            anchors = [
                (0, "Annotated Overview"),
                (6, "Bill of Rights"),
                (21, "Civil War Amendments"),
                (58, "Early Amendments"),
                (64, "Twentieth-Century Amendments"),
                (85, "Individual Rights"),
                (102, "Constitutional Interpretation"),
                (152, "Proposed Amendments"),
                (169, "Structure and Separation of Powers"),
                (209, "Article I: Congress"),
            ]
        case "machiavelli-the-prince":
            anchors = [
                (0, "Chapter 1"),
                (1, "Chapter 10"), (4, "Chapter 11"), (9, "Chapter 12"),
                (19, "Chapter 13"), (24, "Chapter 14"), (29, "Chapter 15"),
                (32, "Chapter 16"), (36, "Chapter 17"), (41, "Chapter 18"),
                (47, "Chapter 19"), (64, "Chapter 2"), (65, "Chapter 20"),
                (73, "Chapter 21"), (80, "Chapter 22"), (82, "Chapter 23"),
                (85, "Chapter 24"), (88, "Chapter 25"), (94, "Chapter 26"),
                (100, "Chapter 3"), (115, "Chapter 4"), (120, "Chapter 5"),
                (122, "Chapter 6"), (128, "Chapter 7"), (141, "Chapter 8"),
                (150, "Chapter 9"), (190, "Notes and End Matter"),
            ]
        case "adam-smith-wealth-of-nations":
            anchors = [
                (0, "Appendix and Introduction"),
                (3, "Book I: Productive Powers of Labour"),
                (536, "Book II: Nature of Stock"),
                (745, "Book III: Progress of Opulence"),
                (829, "Book IV: Systems of Political Economy"),
                (1372, "Book V: Revenue of the Sovereign"),
            ]
        case "bede-ecclesiastical-history":
            anchors = [
                (0, "Book I"), (114, "Book II"), (200, "Book III"),
                (316, "Book IV"), (457, "Book V"),
            ]
        case "eusebius-ecclesiastical-history":
            anchors = [
                (0, "Books I–II: Origins of the Church"),
                (18, "Books III–IV: Apostolic Succession"),
                (38, "Books V–VI: Persecution and Heresy"),
                (58, "Books VII–VIII: The Great Persecution"),
                (72, "Books IX–X: Constantine and Peace"),
            ]
        case "gibbon-decline-and-fall":
            anchors = [
                (0, "Introduction"),
                (4, "The Roman Empire"),
                (8, "Decline and Transformation"),
                (12, "Notes and References"),
            ]
        case "herodotus-histories":
            anchors = [
                (0, "Book I: Clio"), (203, "Book II: Euterpe"),
                (370, "Book III: Thalia"), (520, "Book IV: Melpomene"),
                (674, "Book V: Terpsichore"), (780, "Book VI: Erato"),
                (893, "Book VII: Polyhymnia"), (1071, "Book VIII: Urania"),
                (1182, "Book IX: Calliope"),
            ]
        case "josephus-antiquities":
            anchors = [
                (0, "Book I"), (106, "Book II"), (220, "Book III"),
                (326, "Book IV"), (441, "Book IX"), (539, "Book V"),
                (656, "Book VI"), (800, "Book VII"), (941, "Book VIII"),
                (1090, "Book X"), (1186, "Book XI"), (1286, "Book XII"),
                (1414, "Book XIII"), (1544, "Book XIV"), (1691, "Book XIX"),
                (1825, "Book XV"), (1961, "Book XVI"), (2080, "Book XVII"),
                (2200, "Book XVIII"), (2351, "Book XX"),
            ]
        case "livy-history-of-rome":
            anchors = [
                (0, "Founding of Rome"),
                (427, "Early Republic"),
                (838, "The Second Punic War"),
                (1563, "Rome's Mediterranean Expansion"),
                (2307, "The Mature Republic"),
                (3107, "Later Republican Rome"),
                (3916, "Roman Expansion Eastward"),
                (4698, "The Macedonian Settlement"),
                (5264, "Later Books and Epitomes"),
            ]
        case "plutarch-parallel-lives":
            anchors = [
                (0, "Greek Founders and Lawgivers"),
                (260, "Athenian and Spartan Lives"),
                (520, "The Persian Wars"),
                (780, "The Peloponnesian War"),
                (1040, "Theban and Macedonian Lives"),
                (1300, "Roman Republic"),
                (1560, "The Late Republic"),
                (1820, "Caesar and the Imperial Age"),
            ]
        case "tacitus-annals-histories":
            anchors = [
                (0, "Annals: Book I"), (98, "Annals: Book XI"),
                (135, "Annals: Book XII"), (197, "Annals: Book XIII"),
                (269, "Annals: Book XIV"), (339, "Annals: Book XV"),
                (418, "Annals: Book XVI"), (457, "Annals: Book II"),
                (551, "Annals: Book III"), (633, "Annals: Book IV"),
                (721, "Annals: Book V"), (730, "Annals: Book VI"),
            ]
        case "thucydides-peloponnesian-war":
            anchors = [
                (0, "Book I"), (167, "Book II"), (295, "Book III"),
                (415, "Book IV"), (561, "Book V"), (664, "Book VI"),
                (791, "Book VII"), (902, "Book VIII"),
            ]
        case "anselm-proslogion":
            anchors = [
                (0, "Preface and Chapters I–VIII"),
                (17, "Chapters IX–XVII"),
                (35, "Chapters XVIII–XXVI"),
            ]
        case "athanasius-on-incarnation":
            anchors = [
                (0, "Introduction and Creation"),
                (42, "The Fall and Divine Dilemma"),
                (84, "The Incarnation of the Word"),
                (126, "The Cross and Resurrection"),
                (168, "Defence and Conclusion"),
            ]
        case "augustine-city-of-god":
            anchors = [
                (0, "Book I"), (108, "Book II"), (215, "Book III"),
                (323, "Book IV"), (433, "Book V"), (563, "Book VI"),
                (633, "Book VII"), (757, "Book VIII"), (876, "Book IX"),
                (946, "Book X"), (1091, "Book XI"), (1216, "Book XII"),
                (1318, "Book XIII"), (1418, "Book XIV"), (1541, "Book XV"),
                (1682, "Book XVI"), (1839, "Book XVII"), (1969, "Book XVIII"),
                (2160, "Book XIX"), (2293, "Book XX"), (2477, "Book XXI"),
                (2619, "Book XXII"),
            ]
        case "didache":
            anchors = [
                (0, "The Two Ways"),
                (6, "Baptism, Fasting, and Prayer"),
                (11, "Eucharist, Ministry, and the End Times"),
            ]
        case "irenaeus-against-heresies":
            anchors = [
                (0, "Book I: The Gnostic Systems"),
                (450, "Book II: Refutation by Reason"),
                (900, "Book III: Apostolic Tradition"),
                (1350, "Book IV: God and Humanity"),
                (1800, "Book V: Resurrection and the Kingdom"),
            ]
        case "justin-martyr-first-apology":
            anchors = [
                (0, "Address to the Emperor"),
                (32, "Christian Worship and Ethics"),
                (64, "Christ and the Prophets"),
                (96, "Conclusion and Petition"),
            ]
        default:
            anchors = [(firstChunkIndex, "Chapter 1")]
        }

        let validAnchors = anchors
            .filter { $0.chunkIndex >= firstChunkIndex && $0.chunkIndex <= lastChunkIndex }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        let flatSections = validAnchors.enumerated().map { index, anchor in
            let finalChunkIndex = index + 1 < validAnchors.count
                ? validAnchors[index + 1].chunkIndex - 1
                : lastChunkIndex
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: anchor.title,
                chunks: anchor.chunkIndex...finalChunkIndex
            )
        }
        return addingSubsections(to: flatSections, from: passages)
    }

    private static func bibleSections(from passages: [LibraryPassage]) -> [LibrarySection] {
        let starts = bibleBooks.compactMap { book in
            passages.first(where: { $0.text.hasPrefix("[\(book.marker)]") })
                .map { (chunkIndex: $0.chunkIndex, title: book.title, marker: book.marker) }
        }
        .sorted { $0.chunkIndex < $1.chunkIndex }

        return starts.enumerated().map { index, start in
            let finalChunkIndex = index + 1 < starts.count
                ? starts[index + 1].chunkIndex - 1
                : passages.last?.chunkIndex ?? start.chunkIndex
            let bookPassages = passages.filter { start.chunkIndex...finalChunkIndex ~= $0.chunkIndex }
            let chapterPrefix = start.marker == "PSA001" ? "PSA" : String(start.marker.dropLast(2))
            let chapterStarts = bookPassages.compactMap { passage -> (Int, Int)? in
                guard passage.text.hasPrefix("[\(chapterPrefix)"), let end = passage.text.firstIndex(of: "]") else { return nil }
                let marker = String(passage.text[passage.text.index(after: passage.text.startIndex)..<end])
                let suffix = String(marker.dropFirst(chapterPrefix.count))
                guard let chapter = Int(suffix) else { return nil }
                return (passage.chunkIndex, chapter)
            }
            let chapters = chapterStarts.enumerated().map { chapterIndex, chapterStart in
                let finalChapterChunk = chapterIndex + 1 < chapterStarts.count ? chapterStarts[chapterIndex + 1].0 - 1 : finalChunkIndex
                return LibrarySection(id: "chapter-\(index + 1)-sub-\(chapterStart.1)", title: "Chapter \(chapterStart.1)", chunks: chapterStart.0...finalChapterChunk)
            }
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: start.title,
                chunks: start.chunkIndex...finalChunkIndex,
                children: chapters
            )
        }
    }

    private static func summaTreatiseSections(from passages: [LibraryPassage]) -> [LibrarySection] {
        var starts: [(chunkIndex: Int, title: String)] = [
            (passages.first?.chunkIndex ?? 0, "Introduction")
        ]

        starts += passages.compactMap { passage in
            let prefix = String(passage.text.prefix(240))
            guard let range = prefix.range(of: "TREATISE ", options: .caseInsensitive) else {
                return nil
            }

            let heading = String(prefix[range.lowerBound...])
                .replacingOccurrences(of: "\n", with: " ")
                .components(separatedBy: "(QQ")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let heading, !heading.isEmpty else { return nil }
            return (chunkIndex: passage.chunkIndex, title: heading.capitalized)
        }

        let orderedStarts = Dictionary(grouping: starts, by: \.chunkIndex)
            .compactMap { $0.value.first }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        let flatSections = orderedStarts.enumerated().map { index, start in
            let finalChunkIndex = index + 1 < orderedStarts.count
                ? orderedStarts[index + 1].chunkIndex - 1
                : passages.last?.chunkIndex ?? start.chunkIndex
            return LibrarySection(
                id: "chapter-\(index + 1)",
                title: start.title,
                chunks: start.chunkIndex...finalChunkIndex
            )
        }
        return addingSubsections(to: flatSections, from: passages)
    }

    private static func addingSubsections(
        to sections: [LibrarySection],
        from passages: [LibraryPassage]
    ) -> [LibrarySection] {
        sections.map { section in
            let starts = passages.compactMap { passage -> (chunkIndex: Int, title: String, level: Int)? in
                guard section.chunks.contains(passage.chunkIndex),
                      let heading = subsectionHeading(in: passage.text),
                      passage.chunkIndex != section.chunks.lowerBound
                else { return nil }
                return (passage.chunkIndex, heading.title, heading.level)
            }
            return LibrarySection(
                id: section.id,
                title: section.title,
                chunks: section.chunks,
                children: subsectionTree(
                    starts: starts,
                    within: section.chunks,
                    parentLevel: 0,
                    parentID: section.id,
                    depth: 1
                )
            )
        }
    }

    private static func subsectionTree(
        starts: [(chunkIndex: Int, title: String, level: Int)],
        within chunks: ClosedRange<Int>,
        parentLevel: Int,
        parentID: String,
        depth: Int
    ) -> [LibrarySection] {
        guard depth <= 5 else { return [] }
        let eligible = starts.filter { $0.level > parentLevel }.sorted { $0.chunkIndex < $1.chunkIndex }
        guard let directLevel = eligible.map(\.level).min() else { return [] }
        let directStarts = eligible.filter { $0.level == directLevel }

        return directStarts.enumerated().map { index, start in
            let end = index + 1 < directStarts.count ? directStarts[index + 1].chunkIndex - 1 : chunks.upperBound
            let childChunks = start.chunkIndex...end
            let childStarts = eligible.filter { childChunks.contains($0.chunkIndex) && $0.chunkIndex != start.chunkIndex }
            return LibrarySection(
                id: "\(parentID)-sub-\(start.chunkIndex)",
                title: start.title,
                chunks: childChunks,
                children: subsectionTree(
                    starts: childStarts,
                    within: childChunks,
                    parentLevel: directLevel,
                    parentID: "\(parentID)-sub-\(start.chunkIndex)",
                    depth: depth + 1
                )
            )
        }
    }

    private static func subsectionHeading(in text: String) -> (title: String, level: Int)? {
        let prefix = String(text.prefix(260))
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
        let pattern = "(?i)^(?:\\[[^\\]]+\\]\\s*)?((?:book|part|treatise|session|chapter|question|article|section|lesson)\\s*(?:[IVXLCDM]+|\\d+)(?:\\s*[:.\\-]\\s*[^.]{0,110})?)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
              let range = Range(match.range(at: 1), in: prefix)
        else { return nil }

        let title = String(prefix[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = title.split(separator: " ").first?.lowercased() ?? ""
        let level: Int
        switch firstWord {
        case "book", "part", "treatise", "session": level = 1
        case "chapter", "question": level = 2
        case "article", "section", "lesson": level = 3
        default: return nil
        }
        return (title, level)
    }

    private static let bibleBooks: [(marker: String, title: String)] = [
        ("1CH01", "1 Chronicles"), ("1CO01", "1 Corinthians"),
        ("1ES01", "1 Esdras"), ("1JN01", "1 John"),
        ("1KI01", "1 Kings"), ("1MA01", "1 Maccabees"),
        ("1PE01", "1 Peter"), ("1SA01", "1 Samuel"),
        ("1TH01", "1 Thessalonians"), ("1TI01", "1 Timothy"),
        ("2CH01", "2 Chronicles"), ("2CO01", "2 Corinthians"),
        ("2ES01", "2 Esdras"), ("2JN01", "2 John"),
        ("2KI01", "2 Kings"), ("2MA01", "2 Maccabees"),
        ("2PE01", "2 Peter"), ("2SA01", "2 Samuel"),
        ("2TH01", "2 Thessalonians"), ("2TI01", "2 Timothy"),
        ("3JN01", "3 John"), ("3MA01", "3 Maccabees"),
        ("4MA01", "4 Maccabees"), ("ACT01", "Acts"), ("AMO01", "Amos"),
        ("BAR01", "Baruch"), ("COL01", "Colossians"),
        ("DAG01", "Daniel (Greek)"), ("DAN01", "Daniel"),
        ("DEU01", "Deuteronomy"), ("ECC01", "Ecclesiastes"),
        ("EPH01", "Ephesians"), ("ESG01", "Esther (Greek)"),
        ("EST01", "Esther"), ("EXO01", "Exodus"), ("EZK01", "Ezekiel"),
        ("EZR01", "Ezra"), ("FRT01", "Preface"), ("GAL01", "Galatians"),
        ("GEN01", "Genesis"), ("GLO01", "Glossary"), ("HAB01", "Habakkuk"),
        ("HAG01", "Haggai"), ("HEB01", "Hebrews"), ("HOS01", "Hosea"),
        ("ISA01", "Isaiah"), ("JAS01", "James"), ("JDG01", "Judges"),
        ("JDT01", "Judith"), ("JER01", "Jeremiah"), ("JHN01", "John"),
        ("JOB01", "Job"), ("JOL01", "Joel"), ("JON01", "Jonah"),
        ("JOS01", "Joshua"), ("JUD01", "Jude"), ("LAM01", "Lamentations"),
        ("LEV01", "Leviticus"), ("LUK01", "Luke"), ("MAL01", "Malachi"),
        ("MAN01", "Prayer of Manasses"), ("MAT01", "Matthew"),
        ("MIC01", "Micah"), ("MRK01", "Mark"), ("NAM01", "Nahum"),
        ("NEH01", "Nehemiah"), ("NUM01", "Numbers"), ("OBA01", "Obadiah"),
        ("PHM01", "Philemon"), ("PHP01", "Philippians"),
        ("PRO01", "Proverbs"), ("PS2001", "Psalm 151"),
        ("PSA001", "Psalms"), ("REV01", "Revelation"), ("ROM01", "Romans"),
        ("RUT01", "Ruth"), ("SIR01", "Sirach"), ("SNG01", "Song of Songs"),
        ("TIT01", "Titus"), ("TOB01", "Tobit"),
        ("WIS01", "Wisdom of Solomon"), ("ZEC01", "Zechariah"),
        ("ZEP01", "Zephaniah"),
    ]
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case smartSort
    case alphabet
    case subject

    var id: Self { self }

    var title: String {
        switch self {
        case .smartSort: "Smart Sort"
        case .alphabet: "Alphabet"
        case .subject: "Subject"
        }
    }
}

private struct LibraryWorkCollection: Identifiable {
    let id: String
    let title: String
    let works: [LibraryWork]

    static func alphabetized(from works: [LibraryWork]) -> [LibraryWorkCollection] {
        let grouped = Dictionary(grouping: works) { work in
            work.title.first.map { String($0).uppercased() } ?? "#"
        }
        return grouped.map { letter, works in
            LibraryWorkCollection(
                id: "alphabet-\(letter)",
                title: letter,
                works: works.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func bySubject(from works: [LibraryWork]) -> [LibraryWorkCollection] {
        let subjectOrder = [
            "Sacred Scripture",
            "Thomistic Theology",
            "Early & Medieval Christianity",
            "Councils & Creeds",
            "Catechisms & Confessions",
            "Philosophy",
            "History",
            "Political & Economic Thought",
        ]
        let grouped = Dictionary(grouping: works) { subject(for: $0) }
        return subjectOrder.compactMap { subject in
            guard let subjectWorks = grouped[subject], !subjectWorks.isEmpty else { return nil }
            return LibraryWorkCollection(
                id: "subject-\(subject)",
                title: subject,
                works: subjectWorks.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            )
        }
    }

    private static func subject(for work: LibraryWork) -> String {
        switch work.id {
        case "web-bible":
            "Sacred Scripture"
        case "summa-theologica":
            "Thomistic Theology"
        case "council-of-trent", "ecumenical-creeds-schaff", "seven-ecumenical-councils":
            "Councils & Creeds"
        case "baltimore-catechism-3", "roman-catechism-donovan", "augsburg-confession",
             "belgic-confession", "heidelberg-catechism", "thirty-nine-articles",
             "westminster-confession":
            "Catechisms & Confessions"
        case "aristotle-categories", "aristotle-metaphysics", "aristotle-nicomachean-ethics",
             "boethius-consolation":
            "Philosophy"
        case "bede-ecclesiastical-history", "eusebius-ecclesiastical-history",
             "gibbon-decline-and-fall", "herodotus-histories", "josephus-antiquities",
             "livy-history-of-rome", "plutarch-parallel-lives", "tacitus-annals-histories",
             "thucydides-peloponnesian-war":
            "History"
        case "adam-smith-wealth-of-nations", "machiavelli-the-prince", "magna-carta",
             "us-constitution", "us-declaration-of-independence":
            "Political & Economic Thought"
        default:
            "Early & Medieval Christianity"
        }
    }
}

/// Mirrors `StudyTopicsView`: a list remains mounted below an opaque detail layer, while the
/// shared navigation button morphs in place as the detail transitions from the trailing edge.
struct LibraryView: View {
    let onOpenMenu: () -> Void
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let onReaderVisibilityChange: (Bool) -> Void
    let navigationRequest: LibraryNavigationRequest?
    @State private var works: [LibraryWork] = []
    @State private var searchText = ""
    @State private var selectedWorkID: String?
    @State private var activeFilter: LibraryFilter = .smartSort

    private var selectedWork: LibraryWork? {
        works.first { $0.id == selectedWorkID }
    }

    private var visibleWorks: [LibraryWork] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? works
            : works.filter { $0.title.localizedCaseInsensitiveContains(query) }
        switch activeFilter {
        case .smartSort:
            return filtered
        case .alphabet:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .subject:
            return filtered.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
    }

    var body: some View {
        ZStack {
            libraryList

            if let selectedWork {
                LibraryDocumentDetail(
                    work: selectedWork,
                    targetTitle: navigationRequest?.sourceTitle,
                    modelTasks: modelTasks,
                    modelTasksPopupState: modelTasksPopupState
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            VStack {
                HStack {
                    AquinasNavButton(
                        isDetailVisible: selectedWorkID != nil,
                        backLabel: "Library",
                        onMenuTap: onOpenMenu,
                        onBackTap: closeDocument
                    )
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(20)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selectedWorkID)
        .onChange(of: selectedWorkID) { _, id in
            modelTasksPopupState.reset()
            onReaderVisibilityChange(id != nil)
        }
        .onDisappear { onReaderVisibilityChange(false) }
        .task { works = Self.loadWorks() }
        .onChange(of: navigationRequest) { _, request in
            guard let request,
                  let work = works.first(where: {
                      $0.title.caseInsensitiveCompare(request.sourceTitle) == .orderedSame
                      || $0.title.caseInsensitiveCompare(request.sourceName) == .orderedSame
                  }) else { return }
            selectedWorkID = work.id
        }
    }

    private var libraryList: some View {
        ZStack {
            AquinasTheme.Colors.canvas.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 72)
                    VStack(spacing: 8) {
                        Text("Library")
                            .font(.custom("LibreBaskerville-Regular", size: 30))
                            .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)

                    StudyTopicsSearchField(searchText: $searchText, prompt: Text("Search Library"))
                        .padding(.top, 28)

                    HStack(spacing: 24) {
                        ForEach(LibraryFilter.allCases) { filter in
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    activeFilter = filter
                                }
                            } label: {
                                Text(filter.title)
                                    .font(AquinasTheme.Typography.uiSubheading)
                                    .foregroundStyle(
                                        activeFilter == filter
                                            ? AquinasTheme.Colors.lightGreen
                                            : AquinasTheme.Colors.placeholderText
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.top, 16)

                    LibraryCatalogResults(
                        activeFilter: activeFilter,
                        works: visibleWorks,
                        onOpenWork: { work in
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                selectedWorkID = work.id
                            }
                        }
                    )
                    .padding(.top, 32)
                    .padding(.bottom, 120)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func closeDocument() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            selectedWorkID = nil
        }
    }

    private static func loadWorks() -> [LibraryWork] {
        guard let url = Bundle.main.url(forResource: "passages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let passages = try? JSONDecoder().decode([LibraryPassage].self, from: data)
        else { return [] }
        return Dictionary(grouping: passages, by: \.sourceId).compactMap { sourceID, entries in
            entries.first.map { LibraryWork(id: sourceID, title: $0.title, passageCount: entries.count) }
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

private struct LibraryCatalogResults: View {
    let activeFilter: LibraryFilter
    let works: [LibraryWork]
    let onOpenWork: (LibraryWork) -> Void

    var body: some View {
        LazyVStack(spacing: 16) {
            switch activeFilter {
            case .smartSort:
                ForEach(works) { work in
                    LibraryDocumentCard(work: work) {
                        onOpenWork(work)
                    }
                }
            case .alphabet:
                ForEach(LibraryWorkCollection.alphabetized(from: works)) { collection in
                    LibraryCollectionCard(collection: collection, onOpenWork: onOpenWork)
                }
            case .subject:
                ForEach(LibraryWorkCollection.bySubject(from: works)) { collection in
                    LibraryCollectionCard(collection: collection, onOpenWork: onOpenWork)
                }
            }
        }
    }
}

private struct LibraryDocumentCard: View {
    let work: LibraryWork
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.closed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                }
                Text(work.title)
                    .font(.custom("LibreBaskerville-Regular", size: 20))
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                    .multilineTextAlignment(.leading)
                Text("\(work.passageCount) passages")
                    .font(.figtreeParagraph)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryCollectionCard: View {
    let collection: LibraryWorkCollection
    let onOpenWork: (LibraryWork) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(collection.title)
                .font(.custom("LibreBaskerville-Regular", size: 20))
                .foregroundStyle(AquinasTheme.Colors.headingText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: -28) {
                    ForEach(Array(collection.works.enumerated()), id: \.element.id) { index, work in
                        LibraryCollectionTitleCard(
                            work: work,
                            rotation: titleRotation(for: index),
                            action: { onOpenWork(work) }
                        )
                        .zIndex(Double(collection.works.count - index))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .frame(height: 144)
        }
        .padding(20)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func titleRotation(for index: Int) -> Angle {
        let degrees = [-4.0, 2.5, -1.5, 4.0, -3.0, 1.5]
        return .degrees(degrees[index % degrees.count])
    }
}

private struct LibraryCollectionTitleCard: View {
    let work: LibraryWork
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                Text(work.title)
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 148, height: 106, alignment: .topLeading)
            .background(AquinasTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .rotationEffect(rotation)
        .accessibilityLabel(work.title)
        .accessibilityHint("Open work")
    }
}

private struct LibraryDocumentDetail: View {
    let work: LibraryWork
    let targetTitle: String?
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @State private var document: LibraryDocument?
    @State private var selectedSectionID = "chapter-1"
    @State private var selectedOutlineID = "chapter-1"
    @State private var isContentsOpen = false
    @State private var isPageTextVisible = true
    @State private var pageTransitionTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            AquinasTheme.Colors.canvas.ignoresSafeArea()
            if let document {
                let selectedIndex = document.sections.firstIndex(where: { $0.id == selectedSectionID }) ?? 0
                let selectedSection = document.sections[selectedIndex]
                let selectedOutline = document.sections.node(withID: selectedOutlineID) ?? selectedSection
                let visibleChunks = selectedOutline.chunks
                ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            Color.clear.frame(height: 72)
                            VStack(alignment: .leading, spacing: 16) {
                                Text(document.title)
                                    .font(.custom("LibreBaskerville-Regular", size: 28))
                                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                                Text(document.context)
                                    .font(.figtreeParagraph)
                                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                            }
                            LibraryTextSection(
                                title: selectedOutline.title,
                                passages: document.passages.filter { visibleChunks.contains($0.chunkIndex) },
                                animationID: selectedOutline.id,
                                isVisible: isPageTextVisible
                            )
                            .id(selectedOutline.id)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 240)
                }
                .id(selectedOutline.id)
                    .safeAreaInset(edge: .bottom) {
                        LibraryModelControls(
                            modelTasks: modelTasks,
                            modelTasksPopupState: modelTasksPopupState,
                            isContentsOpen: $isContentsOpen,
                            previousChapterTitle: selectedIndex > 0 ? "\(document.navigationUnit) \(selectedIndex)" : nil,
                            nextChapterTitle: selectedIndex < document.sections.count - 1 ? "\(document.navigationUnit) \(selectedIndex + 2)" : nil,
                            onPreviousChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex - 1].id,
                                    outlineID: document.sections[selectedIndex - 1].firstReadableDescendant.id
                                )
                            },
                            onNextChapter: {
                                transitionToPage(
                                    sectionID: document.sections[selectedIndex + 1].id,
                                    outlineID: document.sections[selectedIndex + 1].firstReadableDescendant.id
                                )
                            }
                        ) {
                            LibraryContentsCard(
                                sections: document.sections,
                                selectedOutlineID: selectedOutlineID,
                                onSelectOutline: { outlineID in
                                    let sectionID = document.sections.first(where: { $0.id == outlineID })?.id
                                        ?? selectedSectionID
                                    transitionToPage(sectionID: sectionID, outlineID: outlineID)
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                        isContentsOpen = true
                                    }
                                }
                            )
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .onDisappear {
            pageTransitionTask?.cancel()
        }
        .task(id: work.id) {
            document = LibraryDocument.load(work)
            selectedSectionID = document?.sections.first?.id ?? "chapter-1"
            selectedOutlineID = document?.sections.first?.firstReadableDescendant.id ?? "chapter-1"
            isPageTextVisible = true
            if let targetTitle,
               let match = document?.sections.first(where: { $0.title.caseInsensitiveCompare(targetTitle) == .orderedSame }) {
                selectedSectionID = match.id
                selectedOutlineID = match.firstReadableDescendant.id
            }
        }
    }

    private func transitionToPage(sectionID: String, outlineID: String) {
        pageTransitionTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            isPageTextVisible = false
        }

        pageTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            selectedSectionID = sectionID
            selectedOutlineID = outlineID
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.2)) {
                isPageTextVisible = true
            }
        }
    }
}

private struct LibraryTextSection: View {
    let title: String
    let passages: [LibraryPassage]
    let animationID: String
    let isVisible: Bool
    @State private var visibleSegmentCount = 0

    private var segments: [LibraryTextSegment] {
        let segmentTexts = passages.flatMap { passage in
            let sourceLines = passage.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let units = sourceLines.flatMap { line -> [String] in
                var sentences: [String] = []
                line.enumerateSubstrings(
                    in: line.startIndex..<line.endIndex,
                    options: [.bySentences, .localized]
                ) { substring, _, _, _ in
                    let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !sentence.isEmpty { sentences.append(sentence) }
                }
                return sentences.isEmpty ? [line] : sentences
            }
            return units.map { (passage.id, $0) }
        }
        return segmentTexts.enumerated().map { index, segment in
            LibraryTextSegment(id: "\(segment.0)-\(index)", text: segment.1, index: index)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.custom("Figtree-Bold", size: 18)).foregroundStyle(AquinasTheme.Colors.headingText)
            ForEach(segments) { segment in
                Text(segment.text)
                    .font(.figtreeParagraph)
                    .lineSpacing(6)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .opacity(segment.index < visibleSegmentCount ? 1 : 0)
                    .offset(x: segment.index < visibleSegmentCount ? 0 : 28)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .task(id: animationID) {
            visibleSegmentCount = 0
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            for count in 1...max(segments.count, 1) {
                guard count <= segments.count else { break }
                withAnimation(.easeOut(duration: 0.28)) {
                    visibleSegmentCount = count
                }
                try? await Task.sleep(for: .milliseconds(45))
                guard !Task.isCancelled else { return }
            }
        }
    }
}

private struct LibraryTextSegment: Identifiable {
    let id: String
    let text: String
    let index: Int
}

private struct LibraryContentsCard: View {
    let sections: [LibrarySection]
    let selectedOutlineID: String
    let onSelectOutline: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Table of Contents").font(.custom("Figtree-Bold", size: 18)).foregroundStyle(AquinasTheme.Colors.headingText)
            if let path = sections.path(to: selectedOutlineID), let selected = path.last {
                LibraryContentsBreadcrumb(path: path, onSelectOutline: onSelectOutline)
                let visibleNodes = selected.children.isEmpty ? (path.dropLast().last?.children ?? sections) : selected.children
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(visibleNodes) { node in
                            ContentsRow(title: node.title, isSelected: node.id == selectedOutlineID) {
                                onSelectOutline(node.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            } else {
                ForEach(sections) { section in
                    ContentsRow(title: section.title, isSelected: section.id == selectedOutlineID) { onSelectOutline(section.id) }
                }
            }
        }
        .padding(24).frame(width: 369, alignment: .leading).background(AquinasTheme.Colors.canvasSecondary).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LibraryContentsBreadcrumb: View {
    let path: [LibrarySection]
    let onSelectOutline: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(path.dropLast()) { node in
                Button { onSelectOutline(node.id) } label: {
                    Text(node.title)
                        .font(.custom("Figtree-SemiBold", size: 14))
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if node.id != path.dropLast().last?.id {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContentsRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(AquinasTheme.Colors.lightGreen).transition(.scale.combined(with: .opacity))
                    }
                    Text(title).font(.custom(isSelected ? "Figtree-SemiBold" : "Figtree-Regular", size: 14)).foregroundStyle(isSelected ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.paragraphText)
                }
                .fixedSize().animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
