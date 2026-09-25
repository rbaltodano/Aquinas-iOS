//
//  LibraryHome.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Catalog

/// Subject shelves on the Library homepage, in display order.
nonisolated enum LibrarySubject: String, CaseIterable, Identifiable, Sendable {
    case scripture
    case thomisticTheology
    case earlyChristianity
    case councilsAndCreeds
    case catechismsAndConfessions
    case philosophy
    case history
    case politicalThought

    var id: Self { self }

    var title: String {
        switch self {
        case .scripture: "Sacred Scripture"
        case .thomisticTheology: "Thomistic Theology"
        case .earlyChristianity: "Early & Medieval Christianity"
        case .councilsAndCreeds: "Councils & Creeds"
        case .catechismsAndConfessions: "Catechisms & Confessions"
        case .philosophy: "Philosophy"
        case .history: "History"
        case .politicalThought: "Political & Economic Thought"
        }
    }

    var systemImage: String {
        switch self {
        case .scripture: "book.closed"
        case .thomisticTheology: "text.book.closed"
        case .earlyChristianity: "building.columns"
        case .councilsAndCreeds: "person.3.sequence"
        case .catechismsAndConfessions: "list.bullet.rectangle"
        case .philosophy: "lightbulb"
        case .history: "hourglass"
        case .politicalThought: "scroll"
        }
    }

    static func of(workID: String) -> LibrarySubject {
        switch workID {
        case "web-bible":
            .scripture
        case "summa-theologica":
            .thomisticTheology
        case "council-of-trent", "ecumenical-creeds-schaff", "seven-ecumenical-councils":
            .councilsAndCreeds
        case "baltimore-catechism-3", "roman-catechism-donovan", "augsburg-confession",
             "belgic-confession", "heidelberg-catechism", "thirty-nine-articles",
             "westminster-confession":
            .catechismsAndConfessions
        case "aristotle-categories", "aristotle-metaphysics", "aristotle-nicomachean-ethics",
             "boethius-consolation":
            .philosophy
        case "bede-ecclesiastical-history", "eusebius-ecclesiastical-history",
             "gibbon-decline-and-fall", "herodotus-histories", "josephus-antiquities",
             "livy-history-of-rome", "plutarch-parallel-lives", "tacitus-annals-histories",
             "thucydides-peloponnesian-war":
            .history
        case "adam-smith-wealth-of-nations", "machiavelli-the-prince", "magna-carta",
             "us-constitution", "us-declaration-of-independence":
            .politicalThought
        default:
            .earlyChristianity
        }
    }
}

/// A short, self-contained excerpt from the bundled corpus that rotates daily.
nonisolated struct LibraryFeaturedPassage: Equatable, Sendable {
    let workID: String
    let workTitle: String
    let chunkIndex: Int
    let excerpt: String

    static let minimumExcerptLength = 90
    static let maximumExcerptLength = 320

    /// Picks the day's passage deterministically: the day selects a work, then a starting chunk
    /// within it. Chunks are scanned forward (then on to the next work) until one yields a clean
    /// excerpt, so the same day always produces the same passage.
    static func select(
        from passages: [LibraryPassage],
        on date: Date,
        calendar: Calendar = .current
    ) -> LibraryFeaturedPassage? {
        let bySource = Dictionary(grouping: passages, by: \.sourceId)
        let sourceIDs = bySource.keys.sorted()
        guard !sourceIDs.isEmpty else { return nil }

        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        for workOffset in 0..<sourceIDs.count {
            let sourceID = sourceIDs[(day + workOffset) % sourceIDs.count]
            let chunks = (bySource[sourceID] ?? []).sorted { $0.chunkIndex < $1.chunkIndex }
            guard !chunks.isEmpty else { continue }
            let start = (day &* 7919) % chunks.count
            for chunkOffset in 0..<chunks.count {
                let passage = chunks[(start + chunkOffset) % chunks.count]
                if let excerpt = excerpt(from: passage.text) {
                    return LibraryFeaturedPassage(
                        workID: sourceID,
                        workTitle: passage.title,
                        chunkIndex: passage.chunkIndex,
                        excerpt: excerpt
                    )
                }
            }
        }
        return nil
    }

    /// Retrieval chunks start and end mid-sentence and carry inline citations, verse markers,
    /// and headings. Returns the first run of complete, citation-free prose sentences that fits
    /// the card, or nil when the chunk has none.
    static func excerpt(from text: String) -> String? {
        let sentences = sentences(in: text)
        // The first and last segments may be clipped by chunking; only interior sentences are
        // known to be whole.
        guard sentences.count >= 3 else { return nil }
        let interior = sentences[1..<(sentences.count - 1)]

        var run: [String] = []
        for sentence in interior {
            guard isReadableProse(sentence) else {
                run.removeAll()
                continue
            }
            // An excerpt must be able to stand alone, so it cannot open by leaning on the
            // sentence before it.
            if run.isEmpty, dependsOnPriorContext(sentence) { continue }
            run.append(sentence)
            let joined = run.joined(separator: " ")
            if joined.count > maximumExcerptLength {
                run = [sentence]
                if sentence.count > maximumExcerptLength { run.removeAll() }
                continue
            }
            if joined.count >= minimumExcerptLength {
                return joined
            }
        }
        return nil
    }

    private static func sentences(in text: String) -> [String] {
        let characters = Array(text.replacingOccurrences(of: "\n", with: " "))
        var sentences: [String] = []
        var current = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            let isTerminal = character == "." || character == "?" || character == "!"
            if isTerminal,
               index + 2 < characters.count,
               characters[index + 1] == " ",
               characters[index + 2].isUppercase || characters[index + 2] == "\"" || characters[index + 2] == "“" {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        // A chunk bound often clips mid-sentence in lowercase ("…thereof. and so"), which the
        // uppercase rule above won't split. Separate that fragment so the whole sentence before
        // it is not discarded along with the clipped tail.
        if let lastBreak = tail.range(of: #"[.?!] (?=\S)"#, options: [.regularExpression, .backwards]) {
            sentences.append(String(tail[..<lastBreak.upperBound]).trimmingCharacters(in: .whitespaces))
            sentences.append(String(tail[lastBreak.upperBound...]))
        } else if !tail.isEmpty {
            sentences.append(tail)
        }
        return sentences
    }

    private static func isReadableProse(_ sentence: String) -> Bool {
        guard let first = sentence.first, first.isUppercase || first == "\"" || first == "“",
              let last = sentence.last, ".?!\"”".contains(last),
              sentence.count >= 24
        else { return false }
        // Digits and brackets mark citations, verse numbers, and article references
        // ("Q[49], A[3]", "Isaiah 10:26") that read as noise out of context.
        let noise = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "[]<>{}|↑\u{FEFF}"))
        if sentence.unicodeScalars.contains(where: noise.contains) { return false }
        // OCR and extraction artifacts: detached punctuation, ellipses, and words glued across a
        // lost line break ("DidacheThe").
        let artifacts = [" ,", " ;", " :", " .", "...", "' '", "Epist."]
        if artifacts.contains(where: sentence.contains) { return false }
        if zip(sentence, sentence.dropFirst()).contains(where: { $0.isLowercase && $1.isUppercase }) {
            return false
        }
        // Short sentences are usually headings or list entries ("Of the Marriage of Priests.").
        guard sentence.split(separator: " ").count >= 8 else { return false }
        // Unbalanced delimiters mean the splitter broke on an abbreviation ("Tully (De Invent.").
        let straightQuotes = sentence.filter { $0 == "\"" }.count
        guard straightQuotes.isMultiple(of: 2),
              sentence.filter({ $0 == "(" }).count == sentence.filter({ $0 == ")" }).count,
              sentence.filter({ $0 == "“" }).count == sentence.filter({ $0 == "”" }).count
        else { return false }
        // Summa objection scaffolding reads as a fragment without its reply.
        let scaffolding = ["Objection", "Reply to", "I answer that", "On the contrary", "Further,"]
        if scaffolding.contains(where: { sentence.hasPrefix($0) }) { return false }
        // Editorial front matter and modern annotations bundled with some sources.
        let editorial = ["Public Domain", "Frequently Asked", "essay", "publish", "http", "www.", "Gutenberg"]
        return !editorial.contains { sentence.localizedCaseInsensitiveContains($0) }
    }

    private static func dependsOnPriorContext(_ sentence: String) -> Bool {
        let firstWord = sentence
            .prefix { $0.isLetter || $0 == "'" || $0 == "’" }
            .lowercased()
        let anaphoric: Set<String> = [
            "and", "but", "for", "or", "nor", "so", "yet", "therefore", "hence", "wherefore",
            "thus", "now", "then", "again", "also", "moreover", "furthermore", "accordingly",
            "consequently", "this", "these", "that", "those", "such", "it", "its", "he", "she",
            "they", "them", "his", "her", "their", "him", "here", "there", "which", "whereupon",
        ]
        return anaphoric.contains(firstWord)
    }
}

/// The bundled corpus summarized for the Library homepage. Loading decodes the full passage
/// file, so callers should build it off the main actor.
nonisolated struct LibraryCatalog: Sendable {
    let works: [LibraryWork]
    let passageCount: Int
    let featuredPassage: LibraryFeaturedPassage?

    static func loadBundled(on date: Date = Date()) -> LibraryCatalog {
        guard let url = Bundle.main.url(forResource: "passages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let passages = try? JSONDecoder().decode([LibraryPassage].self, from: data)
        else { return LibraryCatalog(works: [], passageCount: 0, featuredPassage: nil) }
        return LibraryCatalog(passages: passages, date: date)
    }

    init(works: [LibraryWork], passageCount: Int, featuredPassage: LibraryFeaturedPassage?) {
        self.works = works
        self.passageCount = passageCount
        self.featuredPassage = featuredPassage
    }

    init(passages: [LibraryPassage], date: Date) {
        works = Dictionary(grouping: passages, by: \.sourceId).compactMap { sourceID, entries in
            entries.first.map { LibraryWork(id: sourceID, title: $0.title, passageCount: entries.count) }
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        passageCount = passages.count
        featuredPassage = LibraryFeaturedPassage.select(from: passages, on: date)
    }

    func works(in subject: LibrarySubject) -> [LibraryWork] {
        works.filter { LibrarySubject.of(workID: $0.id) == subject }
    }

    func search(_ query: String) -> [LibraryWork] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return works }
        return works.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || LibrarySubject.of(workID: $0.id).title.localizedCaseInsensitiveContains(query)
        }
    }
}

/// Most-recently-opened work IDs, newest first, persisted as a comma-separated string.
nonisolated enum LibraryRecents {
    static let storageKey = "aquinas.library.recentWorkIDs"
    static let limit = 6

    static func decode(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    static func encode(_ ids: [String]) -> String {
        ids.joined(separator: ",")
    }

    static func opening(_ id: String, in ids: [String]) -> [String] {
        Array(([id] + ids.filter { $0 != id }).prefix(limit))
    }
}

// MARK: - Homepage

struct LibraryHomeView: View {
    let catalog: LibraryCatalog?
    let recentWorkIDs: [String]
    @Binding var searchText: String
    let onOpenWork: (LibraryWork) -> Void
    let onOpenPassage: (LibraryFeaturedPassage) -> Void

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AquinasTheme.Colors.canvas.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 72)

                    LibraryHomeHeader(catalog: catalog)
                        .padding(.top, 24)
                        .padding(.horizontal, 24)

                    StudyTopicsSearchField(searchText: $searchText, prompt: Text("Search titles or subjects"))
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    if let catalog {
                        if isSearching {
                            LibrarySearchResults(
                                query: searchText,
                                works: catalog.search(searchText),
                                onOpenWork: onOpenWork
                            )
                            .padding(.top, 32)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                        } else {
                            homeSections(catalog)
                                .padding(.top, 40)
                                .transition(.opacity)
                        }
                    } else {
                        ProgressView()
                            .tint(AquinasTheme.Colors.lightGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    }
                }
                .padding(.bottom, 120)
                .animation(.easeInOut(duration: 0.2), value: isSearching)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func homeSections(_ catalog: LibraryCatalog) -> some View {
        let recentWorks = recentWorkIDs.compactMap { id in catalog.works.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 48) {
            if let passage = catalog.featuredPassage {
                LibraryPassageOfTheDayCard(passage: passage) { onOpenPassage(passage) }
                    .padding(.horizontal, 24)
            }

            if !recentWorks.isEmpty {
                LibraryShelf(title: "Recently Opened", works: recentWorks, onOpenWork: onOpenWork)
            }

            ForEach(LibrarySubject.allCases) { subject in
                let works = catalog.works(in: subject)
                if !works.isEmpty {
                    LibraryShelf(title: subject.title, works: works, onOpenWork: onOpenWork)
                }
            }

            LibraryIndexCard(works: catalog.works, onOpenWork: onOpenWork)
                .padding(.horizontal, 24)
        }
    }
}

private struct LibraryHomeHeader: View {
    let catalog: LibraryCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statsLine)
                .font(AquinasTheme.Typography.uiLabel)
                .foregroundStyle(AquinasTheme.Colors.lightGreen)
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 0) {
                Text("The")
                    .font(AquinasTheme.Typography.titleHome)
                Text("Library")
                    .font(.custom("LibreBaskerville-Italic", size: 36))
            }
            .foregroundStyle(AquinasTheme.Colors.primaryReadable)

            Text("The primary sources Aquinas draws on when it grounds an answer.")
                .font(AquinasTheme.Typography.body)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .lineSpacing(4)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statsLine: String {
        guard let catalog, !catalog.works.isEmpty else { return "PRIMARY SOURCES" }
        let passages = catalog.passageCount.formatted(.number)
        return "\(catalog.works.count) WORKS · \(passages) PASSAGES"
    }
}

private struct LibraryPassageOfTheDayCard: View {
    let passage: LibraryFeaturedPassage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("PASSAGE OF THE DAY")
                        .font(AquinasTheme.Typography.uiLabel)
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    Spacer()
                    Image(systemName: "quote.opening")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                }

                Text(passage.excerpt)
                    .font(.custom("LibreBaskerville-Italic", size: 18))
                    .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                    .lineSpacing(7)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 12) {
                    Rectangle()
                        .fill(AquinasTheme.Colors.lightGreen)
                        .frame(width: 20, height: 1)
                    Text(passage.workTitle)
                        .font(AquinasTheme.Typography.uiSubheading)
                        .foregroundStyle(AquinasTheme.Colors.headingText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Text("Read")
                            .font(AquinasTheme.Typography.uiLabel)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the passage in the reader")
    }
}

private struct LibraryShelf: View {
    let title: String
    let works: [LibraryWork]
    let onOpenWork: (LibraryWork) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AquinasTheme.Typography.heading)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                Spacer(minLength: 12)
                Text(works.count == 1 ? "1 work" : "\(works.count) works")
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(works) { work in
                        LibraryBookCover(work: work) { onOpenWork(work) }
                    }
                }
                .padding(.vertical, 1)
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
        }
    }
}

/// A flat, bound-manuscript cover: a hairline spine rule on the leading edge, the subject mark,
/// and the title set in the serif face.
private struct LibraryBookCover: View {
    let work: LibraryWork
    let action: () -> Void

    private var subject: LibrarySubject { LibrarySubject.of(workID: work.id) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: subject.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .frame(height: 20, alignment: .leading)

                Spacer(minLength: 12)

                Text(work.title)
                    .font(.custom("LibreBaskerville-Regular", size: 15))
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                    .lineSpacing(3)
                    .lineLimit(5)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                Text("\(work.passageCount.formatted(.number)) passages")
                    .font(AquinasTheme.Typography.chipLabel)
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
            }
            .padding(.leading, 24)
            .padding(.trailing, 14)
            .padding(.vertical, 18)
            .frame(width: 136, height: 196, alignment: .topLeading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AquinasTheme.Colors.controlBorder)
                    .frame(width: 1)
                    .padding(.leading, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: AquinasTheme.Spacing.smallCardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AquinasTheme.Spacing.smallCardRadius, style: .continuous)
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AquinasTheme.Spacing.smallCardRadius, style: .continuous))
        }
        .buttonStyle(LibraryPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(work.title), \(work.passageCount) passages")
        .accessibilityHint("Open work")
        .accessibilityAddTraits(.isButton)
    }
}

private struct LibraryPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// The complete A–Z catalog as a ruled index card, so every work is one scan away.
private struct LibraryIndexCard: View {
    let works: [LibraryWork]
    let onOpenWork: (LibraryWork) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All Works")
                .font(AquinasTheme.Typography.heading)
                .foregroundStyle(AquinasTheme.Colors.headingText)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(works.enumerated()), id: \.element.id) { index, work in
                    if index > 0 {
                        Rectangle()
                            .fill(AquinasTheme.Colors.divider)
                            .frame(height: 1)
                    }
                    LibraryIndexRow(work: work) { onOpenWork(work) }
                }
            }
            .padding(.horizontal, 20)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AquinasTheme.Spacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AquinasTheme.Spacing.cardRadius, style: .continuous)
                    .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
            )
        }
    }
}

private struct LibraryIndexRow: View {
    let work: LibraryWork
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(work.title)
                    .font(AquinasTheme.Typography.bodyLarge)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(work.passageCount.formatted(.number))
                    .font(AquinasTheme.Typography.chipLabel)
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(work.title), \(work.passageCount) passages")
    }
}

private struct LibrarySearchResults: View {
    let query: String
    let works: [LibraryWork]
    let onOpenWork: (LibraryWork) -> Void

    var body: some View {
        if works.isEmpty {
            AquinasEmptyState(
                systemImage: "magnifyingglass",
                title: "No Matches",
                message: "No work in the library matches “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
            )
            .padding(.top, 24)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(works) { work in
                    LibrarySearchResultCard(work: work) { onOpenWork(work) }
                }
            }
        }
    }
}

private struct LibrarySearchResultCard: View {
    let work: LibraryWork
    let action: () -> Void

    private var subject: LibrarySubject { LibrarySubject.of(workID: work.id) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: subject.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subject.title.uppercased())
                        .font(AquinasTheme.Typography.uiLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                }
                .foregroundStyle(AquinasTheme.Colors.lightGreen)

                Text(work.title)
                    .font(AquinasTheme.Typography.heading)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                    .multilineTextAlignment(.leading)

                Text("\(work.passageCount.formatted(.number)) passages")
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
