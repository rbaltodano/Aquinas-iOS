//
//  HomeDashboardView.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Home Dashboard

struct HomeDashboardView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    let savedInsights: [ConceptDefinition]
    let userName: String
    let questionOfTheDay: HomeQuestionOfTheDay?
    let looseThread: LooseThreadCard?
    let todayInHistory: TodayInHistoryCard?
    let glossedTerm: GlossedTermCard?
    let yourQuote: YourQuoteCard?
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onStartQuestion: (HomeQuestionOfTheDay) -> Void
    var onOpenInsightBridge: (UUID, UUID) -> Void
    var onFocusNode: (UUID) -> Void = { _ in }
    var onStartTodayInHistory: (TodayInHistoryCard) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var onLoadHomeSections: () -> Void = {}
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Landscape has ample horizontal room but a much shorter reading lane. This lets the
    /// dashboard use the extra width while releasing vertical pressure on a phone.
    private var usesLandscapeLayout: Bool { verticalSizeClass == .compact }

    @State private var studyTopics: [StudyTopic] = []
    @State private var usageMonth = MonthlyUsageStore.currentMonth()
    @State private var activeInsight: ConceptDefinition? = nil

    private var regularConversations: [InquiryConversation] {
        conversations.filter { !$0.isStudyTopic }
    }

    private var featuredConversation: InquiryConversation? {
        HomeConversationResume.featuredConversation(
            in: regularConversations,
            activeConversationID: activeConversationID
        )
    }

    private var unfinishedConversations: [InquiryConversation] {
        regularConversations
            .filter(HomeDashboardContent.isUnfinished)
            .filter { $0.id != featuredConversation?.id }
    }

    private var bridgeSuggestion: HomeInsightBridgeSuggestion? {
        HomeDashboardContent.bridgeSuggestion(from: savedInsights)
    }

    private var displayUserName: String {
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Ryan" : trimmedName
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: usesLandscapeLayout ? 32 : 48) {
                    Color.clear.frame(height: usesLandscapeLayout ? 24 : 57)

                    VStack(alignment: .leading, spacing: 48) {
                        if let todayInHistory {
                            HomeTodayInHistorySection(
                                card: todayInHistory,
                                onStartConversation: { onStartTodayInHistory(todayInHistory) }
                            )
                        }

                        HomeFigmaOpeningSection(
                            greeting: HomeDashboardContent.greeting(),
                            userName: displayUserName,
                            month: usageMonth,
                            conversationCount: regularConversations.count,
                            insightCount: savedInsights.count,
                            studyTopicCount: studyTopics.count,
                            unfinishedCount: unfinishedConversations.count,
                            questionOfTheDay: questionOfTheDay,
                            usesLandscapeLayout: usesLandscapeLayout,
                            hidesGreetingHeader: todayInHistory != nil,
                            onStartQuestion: onStartQuestion
                        )

                        HomeFigmaDivider()

                        HomeFigmaResumeSection(
                            conversation: featuredConversation,
                            latestText: featuredConversation.map(HomeDashboardContent.latestText) ?? "",
                            insights: featuredConversation.map {
                                HomeDashboardContent.insights(for: $0, savedInsights: savedInsights)
                            } ?? [],
                            onSelectConversation: onSelectConversation,
                            onOpenInsight: { activeInsight = $0 }
                        )

                        HomeFigmaDivider()

                        if let bridgeSuggestion {
                            HomeInsightBridgeSection(
                                suggestion: bridgeSuggestion,
                                onOpenInsight: { activeInsight = $0 },
                                onOpen: {
                                    onOpenInsightBridge(
                                        bridgeSuggestion.first.id,
                                        bridgeSuggestion.second.id
                                    )
                                }
                            )

                            HomeFigmaDivider()
                        }

                        if let looseThread {
                            HomeLooseThreadSection(
                                card: looseThread,
                                onOpen: { onFocusNode(looseThread.nodeID) }
                            )

                            HomeFigmaDivider()
                        }

                        if let glossedTerm {
                            HomeGlossedTermSection(
                                card: glossedTerm,
                                onOpen: { activeInsight = glossedTerm.asConceptDefinition }
                            )

                            HomeFigmaDivider()
                        }

                        if let yourQuote {
                            HomeYourQuoteSection(card: yourQuote)

                            HomeFigmaDivider()
                        }

                        HomeFigmaReadingSection(
                            items: HomeDashboardContent.recommendedReading(from: regularConversations)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, usesLandscapeLayout ? 48 : 36)
                .frame(maxWidth: usesLandscapeLayout ? 1_120 : .infinity, alignment: .center)
            }
            .refreshable {
                refreshContent()
            }

            AquinasNavButton(onMenuTap: onOpenMenu)
                .padding(.leading, 24)
                .padding(.top, usesLandscapeLayout ? 12 : 24)
                .zIndex(2)
        }
        .onAppear {
            MonthlyUsageStore.recordVisitIfNeeded()
            usageMonth = MonthlyUsageStore.currentMonth()
            studyTopics = StudyTopicStore.load()
            onLoadHomeSections()
        }
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: .constant(savedInsights))
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    private func refreshContent() {
        usageMonth = MonthlyUsageStore.currentMonth()
        studyTopics = StudyTopicStore.load()
        onRefresh()
        onLoadHomeSections()
    }
}

// MARK: - Figma Home Sections

private struct HomeFigmaOpeningSection: View {
    let greeting: String
    let userName: String
    let month: MonthlyUsageMonth
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int
    let questionOfTheDay: HomeQuestionOfTheDay?
    let usesLandscapeLayout: Bool
    var hidesGreetingHeader: Bool = false
    var onStartQuestion: (HomeQuestionOfTheDay) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: usesLandscapeLayout ? 36 : 84) {
            VStack(alignment: .center, spacing: 48) {
                if !hidesGreetingHeader {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HomeDashboardContent.todayString())
                            .font(AquinasTheme.Typography.uiLabel)
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(greeting),")
                                .font(AquinasTheme.Typography.titleHome)

                            Text(userName)
                                .font(.custom("LibreBaskerville-Italic", size: 36))
                        }
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

                HomeFigmaUsageAndStats(
                    month: month,
                    conversationCount: conversationCount,
                    insightCount: insightCount,
                    studyTopicCount: studyTopicCount,
                    unfinishedCount: unfinishedCount
                )
            }

            if let questionOfTheDay, !usesLandscapeLayout {
                HomeFigmaQuestionCard(
                    question: questionOfTheDay.question,
                    action: { onStartQuestion(questionOfTheDay) }
                )
            }

            if let questionOfTheDay, usesLandscapeLayout {
                HomeFigmaQuestionCard(
                    question: questionOfTheDay.question,
                    action: { onStartQuestion(questionOfTheDay) }
                )
                .frame(maxWidth: 520)
            }
        }
    }
}

private struct HomeFigmaUsageAndStats: View {
    let month: MonthlyUsageMonth
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            HomeFigmaUsageGrid(month: month)

            HomeFigmaStatsGrid(
                conversationCount: conversationCount,
                insightCount: insightCount,
                studyTopicCount: studyTopicCount,
                unfinishedCount: unfinishedCount
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct HomeFigmaQuestionCard: View {
    let question: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QUESTION OF THE DAY:")
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)

                Text("\"\(question)\"")
                    .font(.custom("LibreBaskerville-Regular", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineSpacing(7)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeFigmaResumeSection: View {
    let conversation: InquiryConversation?
    let latestText: String
    let insights: [ConceptDefinition]
    var onSelectConversation: (InquiryConversation) -> Void
    var onOpenInsight: (ConceptDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Where You Left Off")

            if let conversation {
                OpenConversationCard(
                    conversation: conversation,
                    isActive: true,
                    latestAnswer: latestText,
                    insights: insights,
                    onSelect: { onSelectConversation(conversation) },
                    onOpenInsight: onOpenInsight
                )
            }
        }
    }
}

private struct HomeFigmaReadingSection: View {
    let items: [FurtherStudyItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Read Material")

            VStack(alignment: .leading, spacing: 24) {
                ForEach(items) { item in
                    Button {
                        NotificationCenter.default.post(
                            name: .openGroundingSourceInLibrary,
                            object: LibraryNavigationRequest(
                                sourceTitle: item.title,
                                sourceName: item.author
                            )
                        )
                    } label: {
                        HomeFigmaReadingRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HomeInsightBridgeSection: View {
    let suggestion: HomeInsightBridgeSuggestion
    var onOpenInsight: (ConceptDefinition) -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Midpoint to Explore")

            VStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A Bridge Between Ideas")
                        .font(AquinasTheme.Typography.uiHeading)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)

                    Text("These insights might be worth connecting in your Insight Tree. Who knows what you'll learn")
                        .font(AquinasTheme.Typography.body)
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineSpacing(7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HomeInsightBridgeDiagram(
                    firstTitle: suggestion.first.word,
                    secondTitle: suggestion.second.word,
                    onTapFirst: { onOpenInsight(suggestion.first) },
                    onTapSecond: { onOpenInsight(suggestion.second) }
                )
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
            .onTapGesture(perform: onOpen)
        }
    }
}

private struct HomeInsightBridgeDiagram: View {
    let firstTitle: String
    let secondTitle: String
    var onTapFirst: () -> Void
    var onTapSecond: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HomeInsightBridgeLabel(title: firstTitle, action: onTapFirst)
                .frame(maxWidth: .infinity, alignment: .trailing)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 18, y: 64))
                    path.addLine(to: CGPoint(x: 112, y: 8))
                }
                .stroke(
                    AquinasTheme.Colors.lightGreen.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3])
                )
            }
            .frame(width: 130, height: 64)

            HomeInsightBridgeLabel(title: secondTitle, action: onTapSecond)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 200, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeInsightBridgeLabel: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .frame(width: 14, height: 14)

                Text(title)
                    .font(AquinasTheme.Typography.uiSubheading)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeLooseThreadSection: View {
    let card: LooseThreadCard
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Loose Thread")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.nodeLabel)
                        .font(AquinasTheme.Typography.uiHeading)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)

                    Text(
                        card.insightCount == 1
                            ? "One Insight lives here, but it hasn't connected to anything else in your tree yet."
                            : "\(card.insightCount) Insights live here, but nothing has connected to them yet."
                    )
                    .font(AquinasTheme.Typography.body)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineSpacing(7)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeTodayInHistorySection: View {
    let card: TodayInHistoryCard
    var onStartConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY IN HISTORY")
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)

                Text(card.title)
                    .font(.custom("LibreBaskerville-Regular", size: 28))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
            }

            Text(card.description)
                .font(AquinasTheme.Typography.body)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .lineSpacing(7)

            Button(action: onStartConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .bold))

                    Text("Tell me more...")
                        .font(AquinasTheme.Typography.body)
                        .fontWeight(.bold)
                }
                .foregroundColor(AquinasTheme.Colors.canvas)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(AquinasTheme.Colors.lightGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeGlossedTermSection: View {
    let card: GlossedTermCard
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeFigmaSectionTitle("Terms You Glossed Over")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(AquinasTheme.Typography.uiHeading)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)

                    Text(card.definition)
                        .font(AquinasTheme.Typography.body)
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineSpacing(7)
                        .lineLimit(3)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HomeYourQuoteSection: View {
    let card: YourQuoteCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUOTE FROM YOU")
                .font(AquinasTheme.Typography.uiLabel)
                .foregroundColor(AquinasTheme.Colors.lightGreen)

            Text("\"\(card.quoteText)\"")
                .font(.custom("LibreBaskerville-Regular", size: 18))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineSpacing(7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension GlossedTermCard {
    var asConceptDefinition: ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: title),
            word: title,
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            meaning: definition,
            example: example,
            context: context
        )
    }
}

private typealias HomeFigmaSectionTitle = AquinasSectionTitle
private typealias HomeFigmaDivider = AquinasSectionDivider

private struct HomeFigmaUsageGrid: View {
    let month: MonthlyUsageMonth

    private let columns = Array(repeating: GridItem(.fixed(16), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(month.days) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.isPlaceholder ? AquinasTheme.Colors.canvas : figmaUsageColor(for: day.level))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(day.isPlaceholder ? Color.clear : AquinasTheme.Colors.controlBorder, lineWidth: 1)
                    )
                    .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
    }

    private func accessibilityLabel(for day: MonthlyUsageDay) -> String {
        guard !day.isPlaceholder, let dayNumber = day.dayNumber else {
            return "Empty calendar cell"
        }

        return "Day \(dayNumber), \(day.count) sessions"
    }
}

private struct HomeFigmaStatsGrid: View {
    let conversationCount: Int
    let insightCount: Int
    let studyTopicCount: Int
    let unfinishedCount: Int

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            HomeFigmaStat(value: conversationCount, label: "Conversations")
            HomeFigmaStat(value: insightCount, label: "Insights")
            HomeFigmaStat(value: studyTopicCount, label: "Topics")
            HomeFigmaStat(value: unfinishedCount, label: "Open")
        }
    }
}

private struct HomeFigmaStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(AquinasTheme.Typography.uiHeading)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .monospacedDigit()

            Text(label)
                .font(AquinasTheme.Typography.uiLabel)
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: 49)
        .frame(maxWidth: .infinity)
    }
}

private struct HomeFigmaReadingRow: View {
    let item: FurtherStudyItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("§")
                .font(.custom("LibreBaskerville-Regular", size: 28))
                .foregroundColor(AquinasTheme.Colors.accentRed)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(AquinasTheme.Typography.uiHeading)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)

                    Text(item.author)
                        .font(AquinasTheme.Typography.uiLabel)
                        .foregroundColor(AquinasTheme.Colors.lightGreen)
                }

                Text(item.reason)
                    .font(AquinasTheme.Typography.body)
                    .foregroundColor(AquinasTheme.Colors.placeholderText)
                    .lineSpacing(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func figmaUsageColor(for level: Int) -> Color {
    switch level {
    case 1:
        return AquinasTheme.Colors.lightGreen.opacity(0.32)
    case 2:
        return AquinasTheme.Colors.lightGreen.opacity(0.55)
    case 3:
        return AquinasTheme.Colors.lightGreen.opacity(0.78)
    case 4:
        return AquinasTheme.Colors.lightGreen
    default:
        return AquinasTheme.Colors.canvasSecondary
    }
}

// MARK: - Dashboard Content

private struct FurtherStudyItem: Identifiable {
    let id = UUID()
    let category: String
    let title: String
    let author: String
    let reason: String
}

private struct HomeInsightBridgeSuggestion {
    let first: ConceptDefinition
    let second: ConceptDefinition
    let distance: Double
}

private enum HomeDashboardContent {
    nonisolated static let furtherStudyItems: [FurtherStudyItem] = [
        FurtherStudyItem(
            category: "Primary Text",
            title: "Summa Theologica",
            author: "St. Thomas Aquinas",
            reason: "A series of theological concepts broken down by St. Thomas Aquinas"
        ),
        FurtherStudyItem(
            category: "Primary Text",
            title: "Confessions",
            author: "St. Augustine",
            reason: "An explanation of essential doctrines outlined by St. Augustine of Hippo"
        ),
        FurtherStudyItem(
            category: "Primary Text",
            title: "On the Incarnation",
            author: "Athanasius",
            reason: "An explanation of essential doctrines outlined by Augustine of Hippo"
        ),
        FurtherStudyItem(
            category: "Reference",
            title: "Catechism of the Catholic Church",
            author: "Catholic Church",
            reason: "A concise doctrinal reference when a question needs firm coordinates."
        )
    ]

    /// Ranks the library works that have actually grounded answers across the user's
    /// conversations. Because response presentations are persisted with each conversation,
    /// this naturally updates as new questions are answered without another background job.
    static func recommendedReading(from conversations: [InquiryConversation]) -> [FurtherStudyItem] {
        let sourceGroups = conversations
            .flatMap { conversation in
                conversation.branches.flatMap { branch in
                    (branch.responsePresentations ?? []).flatMap { presentation in
                        presentation.groundingSources ?? []
                    }
                }
            }
            .reduce(into: [String: (source: GroundingSourceSummary, count: Int)]()) { result, source in
                let key = source.id.isEmpty ? source.title.lowercased() : source.id
                if let current = result[key] {
                    result[key] = (current.source, current.count + 1)
                } else {
                    result[key] = (source, 1)
                }
            }

        let ranked = sourceGroups.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending
            }
            .prefix(3)
            .map { entry in
                FurtherStudyItem(
                    category: "Suggested for you",
                    title: entry.source.title,
                    author: entry.source.sourceName,
                    reason: entry.count == 1
                        ? "Referenced in one of your recent answers."
                        : "Referenced (entry.count) times across your conversations."
                )
            }

        return ranked.count == 3
            ? Array(ranked)
            : Array((Array(ranked) + furtherStudyItems).prefix(3))
    }

    nonisolated private static let dailyQuestions: [String] = [
        "What does it mean for knowledge to become wisdom?",
        "Where does faith seek understanding in your current study?",
        "Which distinction would clarify the question you keep circling?",
        "What would change if this doctrine became a habit of attention?",
        "Where is your inquiry asking for patience rather than speed?",
        "What is the strongest objection worth taking seriously today?",
        "Which saved insight belongs in conversation with another?"
    ]

    nonisolated static func greeting(date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    nonisolated static func todayString(date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    nonisolated static func questionOfTheDay(date: Date = Date()) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return dailyQuestions[(day - 1) % dailyQuestions.count]
    }

    static func bridgeSuggestion(from insights: [ConceptDefinition]) -> HomeInsightBridgeSuggestion? {
        let embeddedInsights = insights.compactMap { insight -> (ConceptDefinition, [Double])? in
            let title = insight.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = insight.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !definition.isEmpty else { return nil }
            guard let embedding = computeEmbedding(for: "\(title). \(definition)") else { return nil }
            return (insight, embedding)
        }

        guard embeddedInsights.count >= 2 else { return nil }

        var bestSuggestion: HomeInsightBridgeSuggestion?
        for leftIndex in embeddedInsights.indices {
            for rightIndex in embeddedInsights.indices where rightIndex > leftIndex {
                let distance = semanticDistance(
                    embeddedInsights[leftIndex].1,
                    embeddedInsights[rightIndex].1
                )
                if bestSuggestion == nil || distance > (bestSuggestion?.distance ?? 0) {
                    bestSuggestion = HomeInsightBridgeSuggestion(
                        first: embeddedInsights[leftIndex].0,
                        second: embeddedInsights[rightIndex].0,
                        distance: distance
                    )
                }
            }
        }

        return bestSuggestion
    }

    nonisolated static func latestText(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                switch block {
                case .text(let answer):
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                case .user(let question, _, _):
                    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }

            let bottom = branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bottom.isEmpty { return bottom }

            let top = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !top.isEmpty { return top }
        }

        return "Start a new line of inquiry."
    }

    nonisolated static func isUnfinished(_ conversation: InquiryConversation) -> Bool {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "New Conversation" {
            return true
        }

        for branch in conversation.branches {
            let hasDraft = !branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (!branch.topQuestionSubmitted && !branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if hasDraft { return true }

            if let last = branch.activeChatBlocks.last,
               case .user = last {
                return true
            }
        }

        return false
    }

    nonisolated static func insights(for conversation: InquiryConversation, savedInsights: [ConceptDefinition]) -> [ConceptDefinition] {
        // Only surface insights actually saved *within* this conversation — i.e. concepts
        // embedded in its branches — not every saved insight whose word happens to appear
        // somewhere in the conversation text.
        let conceptWords = Set(embeddedConcepts(in: conversation).map { $0.word.lowercased() })

        return savedInsights
            .filter { conceptWords.contains($0.word.lowercased()) }
            .uniquedByWordLocally()
    }

    nonisolated private static func embeddedConcepts(in conversation: InquiryConversation) -> [ConceptDefinition] {
        var concepts: [ConceptDefinition] = []

        for branch in conversation.branches {
            concepts.append(contentsOf: [
                branch.startingConcept,
                branch.attachedConcept,
                branch.branchContextConcept
            ].compactMap { $0 })

            for block in branch.activeChatBlocks {
                if case .user(_, let concept?, _) = block {
                    concepts.append(concept)
                }
            }
        }

        return concepts
    }

}

nonisolated private extension Array where Element == ConceptDefinition {
    func uniquedByWordLocally() -> [ConceptDefinition] {
        var seenWords = Set<String>()
        var uniqueInsights: [ConceptDefinition] = []

        for insight in self {
            let key = insight.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seenWords.contains(key) else { continue }
            seenWords.insert(key)
            uniqueInsights.append(insight)
        }

        return uniqueInsights
    }
}

// MARK: - Monthly Usage

private struct MonthlyUsageMonth: Equatable {
    let title: String
    let totalVisits: Int
    let days: [MonthlyUsageDay]
}

private struct MonthlyUsageDay: Identifiable, Equatable {
    let id: String
    let dayNumber: Int?
    let count: Int

    var isPlaceholder: Bool {
        dayNumber == nil
    }

    var level: Int {
        switch count {
        case 0:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        case 3...4:
            return 3
        default:
            return 4
        }
    }
}

private enum MonthlyUsageStore {
    private static let countsKey = "aquinas.home.monthly-usage.counts.v1"
    private static let lastRecordedAtKey = "aquinas.home.monthly-usage.last-recorded-at.v1"
    private static let minimumRecordInterval: TimeInterval = 30 * 60

    static func recordVisitIfNeeded(date: Date = Date()) {
        let defaults = UserDefaults.standard
        if let lastRecordedAt = defaults.object(forKey: lastRecordedAtKey) as? Date,
           date.timeIntervalSince(lastRecordedAt) < minimumRecordInterval {
            return
        }

        var counts = loadCounts()
        let key = dayKey(for: date)
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
        defaults.set(date, forKey: lastRecordedAtKey)
    }

    static func currentMonth(date: Date = Date()) -> MonthlyUsageMonth {
        let calendar = Calendar.current
        let counts = loadCounts()
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstDay = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return MonthlyUsageMonth(title: "", totalVisits: 0, days: [])
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingPlaceholderCount = max(0, firstWeekday - calendar.firstWeekday)
        var days: [MonthlyUsageDay] = (0..<leadingPlaceholderCount).map { index in
            MonthlyUsageDay(id: "placeholder-\(index)", dayNumber: nil, count: 0)
        }

        for dayNumber in dayRange {
            guard let dayDate = calendar.date(byAdding: .day, value: dayNumber - 1, to: firstDay) else {
                continue
            }
            let key = dayKey(for: dayDate)
            days.append(MonthlyUsageDay(id: key, dayNumber: dayNumber, count: counts[key, default: 0]))
        }

        return MonthlyUsageMonth(
            title: date.formatted(.dateTime.month(.wide).year()),
            totalVisits: days.reduce(0) { $0 + $1.count },
            days: days
        )
    }

    private static func loadCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
