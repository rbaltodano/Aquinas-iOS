//
//  CurrentConversation.swift
//  Aquinas-iOS
//
//  Conversation tab — horizontal branch layout.
//  Each branch is a full-screen vertical ScrollView of ChatThreadColumn.
//  Swipe left / right to move between branches (TabView pager).
//  Swipe left from anywhere to enter Canvas Mode (InsightTreeView).
//

import SwiftUI
import UIKit
import PhotosUI
import CryptoKit
import Observation

private final class MiniScrollButtonVisibilityRelay {
    var isAtBottom: Bool = true
}

struct ConversationInsightWord: Identifiable, Equatable {
    let text: String
    let sourceResponseBlock: String?

    var id: String {
        Self.key(for: text, sourceResponseBlock: sourceResponseBlock)
    }

    static func key(for text: String, sourceResponseBlock: String?) -> String {
        "\(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock ?? "")"
    }
}

@MainActor
@Observable
final class ConversationDefinitionState {
    var activeWord: ConversationInsightWord?
    var loadingWord: ConversationInsightWord?
    var completedWords: [ConversationInsightWord] = []
    var definitionsByKey: [String: ConceptDefinition] = [:]
    var lookupKeys: Set<String> = []
    var sheetContentHeight: CGFloat = 178
    var failedWord: ConversationInsightWord?

    func reset() {
        loadingWord = nil
        completedWords.removeAll()
        definitionsByKey.removeAll()
        lookupKeys.removeAll()
        activeWord = nil
        failedWord = nil
        sheetContentHeight = 178
    }

    func present(_ word: ConversationInsightWord) {
        if activeWord == nil {
            activeWord = word
        } else if activeWord != word,
                  !completedWords.contains(where: { $0.id == word.id }) {
            completedWords.append(word)
        }
    }

    func takeNextCompletedWord() -> ConversationInsightWord? {
        guard activeWord == nil, !completedWords.isEmpty else { return nil }
        return completedWords.removeFirst()
    }
}


struct CurrentConversationView: View {
    var onOpenMenu: () -> Void = {}
    var onCanvasModeChange: (Bool) -> Void = { _ in }
    /// Reports whether the Insight drawer is up so the shell can ignore swipes that land on it.
    var onInsightLibraryVisibilityChange: (Bool) -> Void = { _ in }
    var onRequestConversationPage: () -> Void = {}
    var onReturnToStudyTopicTree: (StudyTopicTreeSelectionRequest) -> Void = { _ in }
    /// Mirrors `onReturnToStudyTopicTree` for an Insight quoted from the global Insight Tree
    /// (`topicID == nil`) rather than a Study Topic's — removing the quoted chip should land
    /// back on that same tree with the Insight hovered, not just clear the composer.
    var onReturnToGlobalInsights: (ConceptDefinition) -> Void = { _ in }
    var onQuestionOfTheDayAnswered: () -> Void = {}
    var onTodayInHistoryAnswered: () -> Void = {}
    @Binding var collectedDefinitions:         [ConceptDefinition]
    @Binding var sideMenuConversations:        [InquiryConversation]
    @Binding var sideMenuCurrentTitle:         String
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var requestedConversationID:      UUID?
    @Binding var newConversationRequest:       Int
    /// Owned by ContentView, not local state here — see its declaration for why: this view is
    /// torn down and recreated on every page switch, so a locally-reset counter would forget
    /// it had already handled a request and spuriously re-fire `startNewConversation()` on
    /// every later remount once `newConversationRequest` had ever been incremented.
    @Binding var handledNewConversationRequest: Int
    @Binding var pendingNewConversationQuestion: String
    @Binding var pendingNewConversationEyebrow: String
    @Binding var pendingNewConversationPromptContext: String
    /// Visible paragraph shown beneath the header title (e.g. a Today in History description) --
    /// distinct from `pendingNewConversationPromptContext`, which the model sees but never renders.
    @Binding var pendingNewConversationSubtitle: String
    /// Set by ContentView before incrementing `newConversationRequest` when the
    /// user taps "New Conversation" inside a study topic. The new conversation
    /// is tagged with this ID, then the binding is cleared.
    @Binding var newConversationTopicID:       UUID?
    /// Set to `true` by ContentView before incrementing `newConversationRequest`
    /// when the user taps "New Study Topic". The created conversation is marked
    /// as a topic container, then this binding is cleared.
    @Binding var newConversationIsStudyTopic:  Bool
    @Binding var deletedConversationID:        UUID?
    @Binding var requestedForkConcept:         ConceptDefinition?
    @Binding var insightConversationQuoteRequest: InsightConversationQuoteRequest?
    @Binding var newConversationInsightQuoteRequest: NewConversationInsightQuoteRequest?
    let conversationFontSize: ConversationFontSizeOption
    let conversationTextAlignment: ConversationTextAlignmentOption
    let inputFont: ConversationFontOption
    let responseFont: ConversationFontOption
    let conversationTitlePolicy: ConversationTitleOption
    @Binding var conversationPersonality: ConversationPersonality
    let userName: String
    let isPageVisible: Bool
    /// App-shell-owned task state. Keeping these references above page navigation lets model
    /// work continue and keeps one shared popup/status surface throughout the app.
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState

    @Environment(\.aquinasModel) private var aquinasModel
    @Environment(\.embeddingProvider) private var embeddingProvider
    @Environment(\.insightTreeService) private var insightTreeService
    @Environment(\.homeBackendService) private var homeBackendService
    @Environment(\.modelCompletionNotifications) private var modelCompletionNotifications
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // MARK: Conversation list (source of truth for side menu)
    @State private var conversations: [InquiryConversation] = []
    @State private var activeConversationID: UUID? = nil

    // MARK: Branch state (working copy of the active conversation's branches)
    @State private var activeBranches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    @State private var focusedBranchID: UUID? = nil
    @State private var pendingFocusBranchID: UUID? = nil

    // MARK: Quoted insight chip
    @State private var attachedConcept: ConceptDefinition? = nil
    @State private var pendingStudyTopicQuoteReturn: InsightConversationQuoteRequest? = nil

    // MARK: Scroll / upload helpers
    @State private var externalSubmitTrigger: Int = 0
    @State private var scrollToBottomRequest: Int = 0
    @State private var scrollToTopRequest: Int = 0
    // Stores the scroll anchor that was most recently focused so the
    // keyboardDidShow handler can re-scroll after the system auto-scroll fires.
    @State private var lastFocusedAnchor: String? = nil
    @State private var miniScrollButtonVisibilityRelay = MiniScrollButtonVisibilityRelay()
    @State private var isBranchScrolledToTop: Bool = true
    @State private var isKeyboardOpen: Bool = false
    @State private var contextCardState = ContextCardState()
    @State private var studyTopics: [StudyTopic] = []
    @State private var conversationForTopicPicker: InquiryConversation? = nil
    @State private var hasTextToSubmit: Bool = false
    /// True while the focused composer holds a bare "/token" — shows the slash-command card.
    @State private var isSlashCommandContext: Bool = false
    /// Live mirror of the typed "/token" for the picker header. Held as a plain reference so
    /// per-keystroke updates re-render only the picker, not this whole conversation view.
    @State private var slashQuery = SlashCommandQuery()
    /// Command text to insert into the focused field, applied when `insertCommandRequest` bumps.
    @State private var commandToInsert: String = ""
    @State private var insertCommandRequest: Int = 0
    @State private var isCompactingContext: Bool = false
    @State private var isCompactionErrorPresented: Bool = false
    @State private var undiscoveredInsightCount: Int = 0
    @State private var persistedTreeRefreshRequest: Int = 0
    @State private var insightTreeUpdateSignal: Int = 0
    @State private var isProcessingInsightTreeQueue = false
    @State private var insightTreeQueueRetryTask: Task<Void, Never>? = nil
    @State private var insightTreeIdleDebounceTask: Task<Void, Never>? = nil
    /// Question/response pairs awaiting on-device tree-seed evaluation (local-only fallback,
    /// backend unreachable). Debounced separately from the backend queue below so a rapid
    /// follow-up question never collides with this background call mid-flight. Each pair
    /// carries its own conversationID captured at append time — `activeConversationID` can
    /// change before this fires (e.g. the user switches conversations mid-debounce).
    @State private var pendingLocalInsightTreeSeeds:
        [(conversationID: UUID, question: String, response: String)] = []
    @State private var localInsightTreeSeedDebounceTask: Task<Void, Never>? = nil
    @State private var manuallySavedConversationInsightIDs: Set<UUID> = []
    /// Number of branch responses currently generating; drives the context wheel spinner.
    @State private var pendingResponseCount: Int = 0
    @State private var activeEmptyPromptEyebrow: String = ""
    @State private var activeEmptyPromptQuestion: String = ""
    @State private var activeEmptyPromptSubtitle: String = ""
    @Binding var uploadedFiles: [UploadedFile]
    @State private var targetSpawnY: CGFloat = 300
    @State private var targetSpawnResponseIndex: Int? = nil
    @State private var viewportSize: CGSize = .zero

    @State private var persistenceTask: Task<Void, Never>? = nil

    // MARK: Canvas mode
    @State private var canvasMode = CanvasModeModel()
    @State private var isEditingTitle: Bool = false
    @State private var titleEditDraft: String = ""

    // MARK: Model controls
    @State private var isPersonalityMenuOpen: Bool = false
    @Binding var showFilePicker: Bool
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // MARK: Context usage
    @State private var displayedContextTokenCount: Int = 0

    // MARK: Insight library sheet
    @State private var isInsightLibraryOpen: Bool = false
    @State private var insightLibraryPopupHeight: CGFloat = 520

    // MARK: Insight word sheet (aq:// links)
    @State private var definitionState = ConversationDefinitionState()

    private var queuedInsightKeys: Set<String> {
        Set(modelTasks.upcomingTasks.compactMap(\.kind.definitionKey))
    }

    // MARK: Canvas helpers
    private var activeTitle: String {
        conversations.first { $0.id == activeConversationID }?.title ?? "New Conversation"
    }

    /// The active conversation's study topic name, if it belongs to one — shown in the
    /// eyebrow above the branch title in place of "NEW CONVERSATION".
    private var activeStudyTopicTitle: String? {
        guard let topicID = conversations.first(where: { $0.id == activeConversationID })?.studyTopicID else {
            return nil
        }
        return studyTopics.first { $0.id == topicID }?.title
    }

    private var displayUserName: String {
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Ryan" : trimmedName
    }

    private var topConversationChromeOpacity: Double {
        isBranchScrolledToTop && !canvasMode.isTopicCanvasVisible ? 0 : 1
    }

    private var isNewConversationPromptMode: Bool {
        guard activeBranches.count == 1, let branch = activeBranches.first else { return false }
        return !branch.topQuestionSubmitted
            && branch.parentBranchID == nil
            && branch.startingConcept == nil
            && branch.duplicatedResponse == nil
            && branch.activeChatBlocks.isEmpty
            && !branch.showBottomInput
    }

    private func stableQuestionInsightID(for text: String) -> UUID {
        let digest = SHA256.hash(data: Data(text.utf8))
        let bytes = Array(digest.prefix(16))
        let uuidString = String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private var conversationInsights: [ConceptDefinition] {
        var seen = Set<String>()
        var result: [ConceptDefinition] = []
        for branch in activeBranches {
            for concept in [branch.startingConcept, branch.attachedConcept, branch.branchContextConcept].compactMap({ $0 }) {
                let key = concept.word.lowercased()
                if seen.insert(key).inserted { result.append(concept) }
            }
            for block in branch.activeChatBlocks {
                switch block {
                case .user(_, let concept?, _):
                    let chipKey = concept.word.lowercased()
                    if seen.insert(chipKey).inserted { result.append(concept) }
                case .user:
                    break
                case .text(let text):
                    for concept in InlineInsightMarkup.insights(in: text) {
                        let key = concept.word.lowercased()
                        if seen.insert(key).inserted { result.append(concept) }
                    }
                }
            }
        }
        for concept in collectedDefinitions
        where manuallySavedConversationInsightIDs.contains(concept.id) {
            let key = concept.word.lowercased()
            if seen.insert(key).inserted { result.append(concept) }
        }
        return result
    }

    private var hasSelectedCanvasItems: Bool {
        canvasMode.canvasSelectedItemCount > 0
    }

    private func refreshUndiscoveredInsightCountAfterResponse() {
        let currentInsightIDs = conversationInsights.map(\.id)
        _ = InsightDiscoveryStore.markNewInsightsUndiscovered(currentInsightIDs)
        undiscoveredInsightCount = InsightDiscoveryStore.visibleUndiscoveredCount(for: currentInsightIDs)
    }

    /// A completed backend mutation refreshes a mounted Canvas before announcing "Updated".
    /// When Canvas is not mounted, backend completion is already the final update boundary.
    private func finishInsightTreeMutation(for conversationID: UUID) {
        guard activeConversationID == conversationID else { return }
        persistedTreeRefreshRequest += 1
        if !canvasMode.isTopicCanvasVisible {
            insightTreeUpdateSignal += 1
        }
    }

    private func enqueueInsightTreeAnalysis(branchID: UUID, responseIndex: Int) {
        guard let conversationID = activeConversationID,
              let branch = activeBranches.first(where: { $0.id == branchID }),
              responseIndex >= 0,
              responseIndex < branch.activeChatBlocks.count,
              case .text(let responseText) = branch.activeChatBlocks[responseIndex],
              let question = precedingQuestion(in: branch, before: responseIndex) else {
            return
        }

        // A corpus-scope abstention contains no claim to organize. In particular, do not let a
        // later "take a guess" follow-up turn turn missing evidence into a durable tree subject.
        guard !LiteRTAquinasModel.isCorpusScopeAbstention(
            InlineInsightMarkup.plainText(from: responseText)
        ) else {
            return
        }

        // General-knowledge conversation is intentionally transient. It should remain a normal
        // exchange, without turning a model-only answer into a durable Insight Tree subject.
        guard branch.responsePresentation(at: responseIndex)?.evidenceBasis != .generalKnowledge else {
            return
        }

        guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else {
            // Backend-owned Node topology is unreachable on-device, so seed the tree locally
            // instead (see `enqueueLocalInsightTreeSeedingTask`). This was temporarily disabled
            // while queued work was hanging; that turned out to be the `isExecutionSuspended`
            // deadlock in `ModelTaskQueue.setApplicationActive`, not this feature — it runs as a
            // debounced `.background` job, so a foreground question always preempts it.
            pendingLocalInsightTreeSeeds.append((
                conversationID: conversationID,
                question: question,
                response: InlineInsightMarkup.plainText(from: responseText)
            ))
            scheduleLocalInsightTreeSeedingAfterIdle()
            return
        }

        saveCurrentConversation()
        persistConversations()
        let responseID = stableUUID(
            from: "response-analysis:v2:\(conversationID.uuidString):\(branchID.uuidString):\(responseIndex)"
        )
        InsightTreeAnalysisQueue.enqueue(
            PendingInsightTreeAnalysis(
                responseID: responseID,
                conversationID: conversationID,
                branchID: branchID,
                responseIndex: responseIndex,
                attemptCount: 0
            )
        )
        scheduleInsightTreeUpdateAfterIdle()
    }

    /// Waits for 5s of idle time — same debounce window the backend queue uses — before
    /// actually starting on-device tree-seed evaluation. A rapid follow-up question reschedules
    /// this instead of colliding with it: `ModelTaskQueue`'s foreground/background preemption is
    /// best-effort (a preempted background job's Swift Task keeps cooperatively finishing rather
    /// than stopping instantly), so avoiding the collision in the first place is far more
    /// reliable than depending on preemption to resolve cleanly every time.
    private func scheduleLocalInsightTreeSeedingAfterIdle() {
        guard !pendingLocalInsightTreeSeeds.isEmpty else { return }
        localInsightTreeSeedDebounceTask?.cancel()
        localInsightTreeSeedDebounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard scenePhase == .active else { return }
            enqueueLocalInsightTreeSeedingTask()
        }
    }

    /// The backend-only Node Concept path (`InsightTreeService.analyzeResponse`, MiniLM
    /// clustering) is unreachable on-device, so a conversation with no backend would otherwise
    /// never get a tree node at all. This runs as a `.updateInsightTree` background Model Task
    /// (shows "Mapping...", not "Thinking...", and never blocks the already-displayed answer).
    ///
    /// Every pending turn asks the on-device model to extract its main subject (label + summary)
    /// unconditionally — see `insightTreeSeedCandidate`'s doc comment. Whether that subject
    /// actually becomes a new Node Concept is then decided here, deterministically, by on-device
    /// bundled MiniLM cosine similarity against the Node Concepts already on the tree: below
    /// `newSubjectThreshold` similarity to every existing Node means genuinely new, so it's
    /// appended; at or above it means the turn is still within an existing Node's subject, so no
    /// new Node is added (a related, separately-saved Insight will still cluster under that
    /// existing Node via `InsightTreeViewModel`'s own clustering — see its `localMembershipThreshold`).
    ///
    /// This replaced an earlier design where the model made that new-vs-related judgment itself
    /// (`new_subject: true/false`) directly in the same call. That judgment turned out to be
    /// unreliable and order-dependent — asked to compare the same two Bible/theology subjects in
    /// one order the model correctly saw a pivot, asked in the reverse order it didn't. A binary
    /// "is this new" call is exactly the kind of judgment an LLM is inconsistent at; embedding
    /// similarity answers it the same way every time for the same inputs, and it's the same
    /// lightweight math the tree's own clustering already relies on, so it costs effectively
    /// nothing extra.
    private func enqueueLocalInsightTreeSeedingTask() {
        guard !pendingLocalInsightTreeSeeds.isEmpty,
              !modelTasks.contains(where: {
                  $0.kind == .updateInsightTree && $0.phase != .completed
              }) else {
            return
        }
        let pending = pendingLocalInsightTreeSeeds
        pendingLocalInsightTreeSeeds.removeAll()

        modelTasks.enqueue(
            kind: .updateInsightTree,
            originPage: .conversation,
            priority: .background
        ) {
            // Matches `InsightTreeViewModel.localMembershipThreshold`: below this similarity to
            // every existing Node, a subject counts as genuinely new rather than a continuation
            // of one already on the tree.
            let newSubjectThreshold = InsightTreeSemanticPolicy.newSubjectSimilarity
            for turn in pending {
                guard !Task.isCancelled else { return }
                var existingSeeds = LocalInsightTreeSeedStore.seeds(for: turn.conversationID)
                var didRefreshSeedEmbeddings = false
                for index in existingSeeds.indices
                where existingSeeds[index].embeddingVersion != embeddingProvider.version {
                    let seed = existingSeeds[index]
                    let refreshed = await embeddingProvider.embed(
                        "\(seed.label). \(seed.summary)"
                    )
                    existingSeeds[index] = LocalInsightTreeSeed(
                        id: seed.id,
                        label: seed.label,
                        summary: seed.summary,
                        embedding: refreshed,
                        embeddingVersion: embeddingProvider.version,
                        createdAt: seed.createdAt
                    )
                    didRefreshSeedEmbeddings = true
                }
                if didRefreshSeedEmbeddings {
                    LocalInsightTreeSeedStore.replaceSeeds(
                        existingSeeds,
                        for: turn.conversationID
                    )
                }
                guard let candidate = try? await self.aquinasModel.insightTreeSeedCandidate(
                    question: turn.question,
                    response: turn.response
                ) else {
                    continue
                }

                let embedding = await embeddingProvider.embed(
                    "\(candidate.label). \(candidate.summary)"
                )
                if let embedding {
                    let similarities = existingSeeds.compactMap { existing -> (String, Double)? in
                        guard let existingEmbedding = existing.embedding else { return nil }
                        return (existing.label, cosineSimilarity(embedding, existingEmbedding))
                    }
#if DEBUG
                    print("Aquinas seed new-subject check: '\(candidate.label)' vs existing \(similarities)")
#endif
                    let isAlreadyCovered = similarities.contains { $0.1 >= newSubjectThreshold }
                    guard !isAlreadyCovered else { continue }
                }

                let newSeedID = UUID()
                LocalInsightTreeSeedStore.appendSeed(
                    LocalInsightTreeSeed(
                        id: newSeedID,
                        label: candidate.label,
                        summary: candidate.summary,
                        embedding: embedding,
                        embeddingVersion: embeddingProvider.version,
                        createdAt: Date()
                    ),
                    for: turn.conversationID
                )
                // Mirrors the backend analysis path above: without marking this Node Concept
                // pending, opening the tree fresh (which tours only pending IDs, not a raw
                // diff — see `presentPersistedTree`) would silently skip its reveal animation.
                InsightDiscoveryStore.markNodesUndiscovered([newSeedID])
                InsightDiscoveryStore.markPendingTreePresentation(
                    insightIDs: [],
                    nodeIDs: [newSeedID]
                )
                self.finishInsightTreeMutation(for: turn.conversationID)
            }
        }
    }

    private func scheduleInsightTreeUpdateAfterIdle() {
        guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else {
            for pending in InsightTreeAnalysisQueue.load() {
                InsightTreeAnalysisQueue.remove(responseID: pending.responseID)
            }
            return
        }
        guard !InsightTreeAnalysisQueue.load().isEmpty else { return }
        insightTreeIdleDebounceTask?.cancel()
        insightTreeIdleDebounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard scenePhase == .active else { return }
            enqueueInsightTreeUpdateTask()
        }
    }

    private func enqueueInsightTreeUpdateTask() {
        guard !InsightTreeAnalysisQueue.load().isEmpty,
              !modelTasks.contains(where: {
                  $0.kind == .updateInsightTree && $0.phase != .completed
              }) else {
            return
        }

        modelTasks.enqueue(
            kind: .updateInsightTree,
            originPage: .conversation,
            priority: .background,
            onCancel: {
                for pending in InsightTreeAnalysisQueue.load() {
                    InsightTreeAnalysisQueue.remove(responseID: pending.responseID)
                }
            }
        ) {
            await processPendingInsightTreeAnalyses()
        }
    }

    private func precedingQuestion(in branch: ChatBranch, before responseIndex: Int) -> String? {
        if responseIndex > 0 {
            for index in stride(from: responseIndex - 1, through: 0, by: -1) {
                if case .user(let text, _, _) = branch.activeChatBlocks[index],
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }
        let topQuestion = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return topQuestion.isEmpty ? nil : topQuestion
    }

    @MainActor
    private func processPendingInsightTreeAnalyses() async {
        guard !isProcessingInsightTreeQueue else { return }
        isProcessingInsightTreeQueue = true
        defer { isProcessingInsightTreeQueue = false }

        var handledResponseIDs: Set<UUID> = []
        while let pendingJob = InsightTreeAnalysisQueue.load().first(where: {
            !handledResponseIDs.contains($0.responseID)
                && insightTreeAnalysisPayload(for: $0) != nil
        }) {
            handledResponseIDs.insert(pendingJob.responseID)
            guard let payload = insightTreeAnalysisPayload(for: pendingJob) else { continue }
            var attempt = pendingJob.attemptCount
            while true {
                do {
                    let result = try await insightTreeService.analyzeResponse(
                        conversationID: pendingJob.conversationID,
                        responseID: pendingJob.responseID,
                        branchID: pendingJob.branchID,
                        question: payload.question,
                        response: payload.response
                    )
                    InsightTreeAnalysisQueue.remove(responseID: pendingJob.responseID)
                    if result.didMutate {
                        InsightDiscoveryStore.markUndiscovered(result.addedInsightIDs)
                        InsightDiscoveryStore.markNodesUndiscovered(result.addedNodeIDs)
                        InsightDiscoveryStore.markPendingTreePresentation(
                            insightIDs: result.addedInsightIDs,
                            nodeIDs: result.addedNodeIDs
                        )
                        finishInsightTreeMutation(for: pendingJob.conversationID)
                        await Task.yield()
                    }
                    break
                } catch {
                    guard !Task.isCancelled else { return }
                    attempt += 1
                    InsightTreeAnalysisQueue.recordFailedAttempt(responseID: pendingJob.responseID)
                    guard attempt <= 3,
                          activeConversationID == pendingJob.conversationID else {
                        scheduleInsightTreeQueueRetry()
                        break
                    }
                    let delays = [1, 3, 8]
                    try? await Task.sleep(for: .seconds(delays[min(attempt - 1, delays.count - 1)]))
                }
            }
        }
    }

    private func scheduleInsightTreeQueueRetry() {
        guard !InsightTreeAnalysisQueue.load().isEmpty else { return }
        insightTreeQueueRetryTask?.cancel()
        insightTreeQueueRetryTask = Task {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard scenePhase == .active else { return }
            scheduleInsightTreeUpdateAfterIdle()
        }
    }

    private func insightTreeAnalysisPayload(
        for job: PendingInsightTreeAnalysis
    ) -> (question: String, response: String)? {
        let branches: [ChatBranch]
        if job.conversationID == activeConversationID {
            branches = activeBranches
        } else {
            branches = conversations.first(where: { $0.id == job.conversationID })?.branches ?? []
        }
        guard let branch = branches.first(where: { $0.id == job.branchID }),
              job.responseIndex >= 0,
              job.responseIndex < branch.activeChatBlocks.count,
              case .text(let response) = branch.activeChatBlocks[job.responseIndex],
              let question = precedingQuestion(in: branch, before: job.responseIndex) else {
            return nil
        }
        return (question, InlineInsightMarkup.plainText(from: response))
    }

    private func contextTokenCount(in branch: ChatBranch?) -> Int {
        guard let branch else { return 0 }
        var textParts: [String] = []

        if let compactedContext = branch.compactedContext?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !compactedContext.isEmpty {
            textParts.append(compactedContext)
        } else if branch.topQuestionSubmitted {
            let topQuestion = branch.topQuestionText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !topQuestion.isEmpty {
                textParts.append(topQuestion)
            }
        }

        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        for block in branch.activeChatBlocks.dropFirst(compactedBlockCount) {
            switch block {
            case .text(let text):
                textParts.append(InlineInsightMarkup.plainText(from: text))
            case .user(let text, _, _):
                textParts.append(text)
            }
        }

        return AquinasContextBudget.estimatedTokenCount(in: textParts.joined(separator: "\n"))
    }

    private var canCompactFocusedContext: Bool {
        guard let branch = activeBranches.first(where: { $0.id == effectiveFocusedID })
                ?? activeBranches.first else {
            return false
        }

        if branch.compactedContext == nil,
           branch.topQuestionSubmitted,
           !branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        return branch.activeChatBlocks.dropFirst(compactedBlockCount).contains { block in
            switch block {
            case .text(let text):
                return !InlineInsightMarkup.plainText(from: text)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .user(let text, _, _):
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func refreshDisplayedContextWordCount(animated: Bool = true) {
        let branch = activeBranches.first(where: { $0.id == effectiveFocusedID })
            ?? activeBranches.first
        let count = contextTokenCount(in: branch)

        if animated {
            withAnimation(.easeInOut(duration: 0.65)) {
                displayedContextTokenCount = count
            }
        } else {
            displayedContextTokenCount = count
        }
    }

    // MARK: Helpers
    private var effectiveFocusedID: UUID? {
        focusedBranchID ?? activeBranches.first?.id
    }

    private var insightSheetHeight: CGFloat {
        let measured   = max(definitionState.sheetContentHeight, 178)
        let available  = max(viewportSize.height, 1)
        return min(measured + 24, available * 0.82)
    }

    private func pendingFocusBranchTarget() -> ChatBranch? {
        if let pendingFocusBranchID,
           let branch = activeBranches.first(where: { $0.id == pendingFocusBranchID }) {
            return branch
        }

        return activeBranches.last
    }

    private var focusedBranchSelection: Binding<UUID?> {
        Binding(
            get: { effectiveFocusedID },
            set: { newID in
                if let newID {
                    focusedBranchID = newID
                }
            }
        )
    }

    @ViewBuilder
    private func branchPager(in geo: GeometryProxy) -> some View {
        TabView(selection: focusedBranchSelection) {
            ForEach($activeBranches) { branch in
                let branchID = branch.wrappedValue.id
                branchPage(branch: branch, geo: geo)
                    .tag(Optional(branchID))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
    }

    private func closeTopicCanvas() {
        canvasMode.isCanvasSearchActive = false
        canvasMode.canvasSearchQuery = ""
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            canvasMode.isTopicCanvasVisible = false
        }
    }

    private func enterCanvasMode() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            isKeyboardOpen = false
            canvasMode.isTopicCanvasVisible = true
        }
    }

    private func forkCanvasInsight(_ concept: ConceptDefinition) {
        closeTopicCanvas()
        requestedForkConcept = concept
    }

    @ViewBuilder
    private var topicCanvasLayer: some View {
        // Only bookmarked Insights belong in the tree; un-bookmarking removes the node.
        let savedIDs = Set(collectedDefinitions.map(\.id))
        return InsightTreeView(
            insights: conversationInsights.filter { savedIDs.contains($0.id) },
            conversationID: activeConversationID,
            selectionRequest: canvasMode.canvasSelectionRequest,
            persistedTreeRefreshRequest: persistedTreeRefreshRequest,
            clearSelectionRequest: canvasMode.canvasClearSelectionRequest,
            dismissHoverRequest: canvasMode.canvasDismissHoverRequest,
            createConceptRequest: canvasMode.canvasCreateConceptRequest,
            studyRequest: canvasMode.canvasStudyRequest,
            studyExitRequest: canvasMode.canvasStudyExitRequest,
            studyToolsToggleRequest: canvasMode.canvasStudyToolsToggleRequest,
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyModeChange: { canvasMode.isCanvasStudyMode = $0 },
            onStudyToolsActiveChange: { canvasMode.isCanvasStudyToolsActive = $0 },
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            promotedInsightIDs: canvasMode.promotedCanvasInsightIDs,
            onRemoveInsight: removeConversationInsight,
            onRestoreInsight: restoreConversationInsight,
            onForkInsight: forkCanvasInsight,
            onQuoteInsight: { canvasMode.canvasQuoteTarget = $0 },
            onSelectionStateChange: { canvasMode.hasCanvasHover = $0 },
            onInsightSelectionStateChange: { canvasMode.hasHoveredCanvasInsight = $0 },
            onSelectedCanvasItemCountChange: { canvasMode.canvasSelectedItemCount = $0 },
            onPromotedInsightIDsChange: { canvasMode.promotedCanvasInsightIDs = $0 },
            savedConceptIDs: Set(collectedDefinitions.map(\.id)),
            onToggleSavedConcept: { concept in
                toggleSavedConcept(concept)
            },
            onBookmarkConcepts: { concepts in
                for concept in concepts {
                    setSavedConcept(concept, isSaved: true)
                }
            },
            inquireConnectionRequest: canvasMode.canvasInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                canvasMode.canvasConnectionConcepts = concepts
                closeTopicCanvas()
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    scrollToBottomRequest += 1
                }
            },
            midpointEnterRequest: canvasMode.canvasMidpointEnterRequest,
            midpointCenterRequest: canvasMode.canvasMidpointCenterRequest,
            midpointPlaceRequest: canvasMode.canvasMidpointPlaceRequest,
            searchQuery: canvasMode.canvasSearchQuery,
            searchPreviousRequest: canvasMode.canvasSearchPreviousRequest,
            searchNextRequest: canvasMode.canvasSearchNextRequest,
            onSearchResultsChange: { current, total in
                canvasMode.canvasSearchResultIndex = current
                canvasMode.canvasSearchResultCount = total
            },
            onMidpointModeChange: { canvasMode.isCanvasMidpointMode = $0 },
            onMidpointGeneratingChange: { canvasMode.isCanvasInsightGenerating = $0 },
            onUndiscoveredInsightCountChange: { undiscoveredInsightCount = $0 },
            onPersistedTreeRefreshCompleted: {
                insightTreeUpdateSignal += 1
            },
            inputFont: inputFont,
            conversationFontSize: conversationFontSize,
            showQuestionBar: false,
            modelTasks: modelTasks,
            modelTaskOriginPage: .conversation,
            model: aquinasModel,
            embeddingProvider: embeddingProvider,
            insightTreeService: insightTreeService
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .zIndex(1)
    }

    private func quoteConceptIntoCurrentConversation(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            attachedConcept = concept
            if focusedBranchID == nil {
                focusedBranchID = activeBranches.first?.id
            }
            canvasMode.isTopicCanvasVisible = false
            canvasMode.hasCanvasHover = false
            canvasMode.hasHoveredCanvasInsight = false
            canvasMode.canvasQuoteTarget = nil
            canvasMode.canvasSelectedItemCount = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(180))
            scrollToBottomRequest += 1
        }
    }

    private func openInsightConversationQuote(_ request: InsightConversationQuoteRequest) {
        guard let conversation = conversations.first(where: {
            $0.id == request.conversationID
                && (request.topicID == nil || $0.studyTopicID == request.topicID)
        }) else {
            insightConversationQuoteRequest = nil
            return
        }

        switchToConversation(conversation)
        pendingStudyTopicQuoteReturn = request
        insightConversationQuoteRequest = nil
        quoteConceptIntoCurrentConversation(request.insight)
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            scrollToBottomRequest += 1
        }
    }

    private func returnToStudyTopicTreeAfterQuoteCancellation() {
        guard let request = pendingStudyTopicQuoteReturn else { return }
        pendingStudyTopicQuoteReturn = nil
        attachedConcept = nil
        if let topicID = request.topicID {
            onReturnToStudyTopicTree(
                StudyTopicTreeSelectionRequest(
                    topicID: topicID,
                    insightID: request.insight.id
                )
            )
        } else {
            onReturnToGlobalInsights(request.insight)
        }
    }

    /// The slash-command card shows while the keyboard is up and the composer holds a
    /// bare "/token", in Branch mode (not the topic canvas).
    private var showSlashCommandMenu: Bool {
        isKeyboardOpen && isSlashCommandContext && !canvasMode.isTopicCanvasVisible
    }

    /// A command was tapped — insert it into the focused field and dismiss the card.
    private func selectSlashCommand(_ command: SlashCommand) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        commandToInsert = command.name + " "
        insertCommandRequest += 1
        hasTextToSubmit = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            isSlashCommandContext = false
        }
    }

    private var bottomInquiryControlDock: some View {
        InquiryControlDock(
            isCanvasMode: canvasMode.isTopicCanvasVisible,
            showFilePicker: $showFilePicker,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            selectedPersonality: Binding(
                get: { conversationPersonality.displayName },
                set: { newValue in
                    guard let personality = ConversationPersonality.allCases.first(where: {
                        $0.displayName == newValue
                    }) else { return }
                    conversationPersonality = personality
                }
            ),
            isPersonalityMenuOpen: $isPersonalityMenuOpen,
            isAtBottom: true,
            isKeyboardOpen: isKeyboardOpen,
            showsSendButton: isKeyboardOpen && hasTextToSubmit,
            hasCanvasHover: canvasMode.hasCanvasHover,
            hasCanvasInsightHover: canvasMode.hasHoveredCanvasInsight,
            hasSelectedCanvasItems: hasSelectedCanvasItems,
            selectedCanvasItemCount: canvasMode.canvasSelectedItemCount,
            onScrollToBottom: { scrollToBottomRequest += 1 },
            onViewEntireCanvas: { },
            onOpenInsights: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isInsightLibraryOpen = true
                }
            },
            onSend: {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    hasTextToSubmit = false
                    isKeyboardOpen = false
                }
                externalSubmitTrigger += 1
            },
            onSelectCanvasItem: { canvasMode.canvasSelectionRequest += 1 },
            onCreateCanvasConcept: { canvasMode.canvasCreateConceptRequest += 1 },
            onStudyCanvasInsight: { canvasMode.canvasStudyRequest += 1 },
            onInquireConnection: { canvasMode.canvasInquireConnectionRequest += 1 },
            onQuoteCanvasItem: {
                guard let target = canvasMode.canvasQuoteTarget else { return }
                quoteConceptIntoCurrentConversation(target)
            },
            onMidpointConcepts: { canvasMode.canvasMidpointEnterRequest += 1 },
            isMidpointMode: canvasMode.isCanvasMidpointMode,
            isStudyMode: canvasMode.isCanvasStudyMode,
            isStudyToolsActive: canvasMode.isCanvasStudyToolsActive,
            onToggleStudyTools: { canvasMode.canvasStudyToolsToggleRequest += 1 },
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            isCanvasInsightLoading: canvasMode.isCanvasInsightGenerating,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            canvasSearchText: Binding(
                get: { canvasMode.canvasSearchQuery },
                set: { canvasMode.canvasSearchQuery = $0 }
            ),
            isCanvasSearchActive: Binding(
                get: { canvasMode.isCanvasSearchActive },
                set: { canvasMode.isCanvasSearchActive = $0 }
            ),
            canvasSearchResultIndex: canvasMode.canvasSearchResultIndex,
            canvasSearchResultCount: canvasMode.canvasSearchResultCount,
            onCanvasSearchPrevious: { canvasMode.canvasSearchPreviousRequest += 1 },
            onCanvasSearchNext: { canvasMode.canvasSearchNextRequest += 1 },
            onCanvasSearchActivated: {
                contextCardState.reset()
                modelTasksPopupState.reset()
                canvasMode.canvasDismissHoverRequest += 1
            },
            onMidpointCenter: { canvasMode.canvasMidpointCenterRequest += 1 },
            onMidpointPlace: { canvasMode.canvasMidpointPlaceRequest += 1 },
            onClearCanvasSelection: { canvasMode.canvasClearSelectionRequest += 1 },
            contextWordCount: displayedContextTokenCount,
            canCompactContext: canCompactFocusedContext && !modelTasks.isBusy,
            onCompactContext: {
                guard let branchID = effectiveFocusedID else { return false }
                return await performContextCompaction(in: branchID)
            },
            onClearConversation: clearCurrentConversation,
            onContextWillOpen: {
                if canvasMode.isTopicCanvasVisible { canvasMode.canvasDismissHoverRequest += 1 }
            },
            contextCard: contextCardState
        )
    }

    // MARK: Body
    var body: some View {
        conversationWithStateSync
        .onDisappear {
            persistenceTask?.cancel()
            insightTreeQueueRetryTask?.cancel()
            insightTreeIdleDebounceTask?.cancel()
            localInsightTreeSeedDebounceTask?.cancel()
            removeActiveConversationIfEmpty()
            persistConversations()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleInsightTreeUpdateAfterIdle()
                scheduleLocalInsightTreeSeedingAfterIdle()
            } else {
                insightTreeQueueRetryTask?.cancel()
                insightTreeIdleDebounceTask?.cancel()
                localInsightTreeSeedDebounceTask?.cancel()
            }
        }
        // aq:// insight links
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aq", let host = url.host else { return .systemAction }
            let word = host.removingPercentEncoding ?? host
            openDynamicDefinition(word: word, sourceResponseBlock: nil)
            return .handled
        })
        // aq:// word insight sheet
        .sheet(item: $definitionState.activeWord, onDismiss: presentNextCompletedDefinition) { sheetData in
            insightSheet(for: sheetData)
        }
        // Insight library sheet (opened from "Insights" in the + menu)
        .sheet(isPresented: $isInsightLibraryOpen) {
            InsightLibraryPopup(
                currentConversationInsights: currentConversationInsights(),
                allInsights: collectedDefinitions,
                savedInsights: $collectedDefinitions,
                onQuote: { concept in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        attachedConcept = concept
                        if focusedBranchID == nil {
                            focusedBranchID = activeBranches.first?.id
                        }
                    }
                    isInsightLibraryOpen = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        scrollToBottomRequest += 1
                    }
                },
                onFork: { concept in
                    let parentID = focusedBranchID ?? activeBranches.first?.id
                    let newBranch = ChatBranch(
                        startingConcept: concept,
                        parentBranchID: parentID,
                        parentResponseIndex: targetSpawnResponseIndex,
                        yOffset: targetSpawnY
                    )
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        insertBranch(newBranch, after: parentID)
                    }
                    isInsightLibraryOpen = false
                },
                onToggleSaved: { concept in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if collectedDefinitions.contains(where: { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }) {
                            collectedDefinitions.removeAll { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }
                        } else {
                            collectedDefinitions.append(concept)
                        }
                    }
                }
            )
            .onPreferenceChange(InsightLibraryPopupHeightKey.self) { height in
                insightLibraryPopupHeight = height
            }
            .presentationDetents([.height(insightLibrarySheetHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .onChange(of: isInsightLibraryOpen) { _, isOpen in
            onInsightLibraryVisibilityChange(isOpen)
        }
        .onDisappear { onInsightLibraryVisibilityChange(false) }
    }

    /// Split out of `body` so each piece stays small enough to type-check quickly; the
    /// modifiers are applied in the same order as a single chain.
    private var conversationWithStateSync: some View {
        conversationScaffold
        .onChange(of: focusedBranchID) { _, _ in
            refreshDisplayedContextWordCount()
        }
        .onChange(of: activeBranches.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let target = pendingFocusBranchTarget()
            pendingFocusBranchID = nil
            guard let target else { return }
            let targetID = target.id
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    focusedBranchID = targetID
                }
            }
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, completedTask in
            guard let completedTask,
                  case .userQuestion(let branchID, _) = completedTask.kind,
                  completedTask.conversationID == activeConversationID,
                  let snapshot = CurrentConversationsStore.load(),
                  let persistedConversation = snapshot.conversations.first(where: {
                      $0.id == completedTask.conversationID
                  }),
                  let persistedBranch = persistedConversation.branches.first(where: {
                      $0.id == branchID
                  }) else {
                return
            }

            // A conversation view mounted while this task was already running has its own local
            // value state. Pull in only the completed branch, preserving drafts and edits on all
            // other branches while making the finished answer appear immediately.
            if let branchIndex = activeBranches.firstIndex(where: { $0.id == branchID }) {
                activeBranches[branchIndex] = persistedBranch
            }
            if let conversationIndex = conversations.firstIndex(where: {
                $0.id == persistedConversation.id
            }) {
                conversations[conversationIndex].branches = persistedConversation.branches
                conversations[conversationIndex].title = persistedConversation.title
            }
            refreshDisplayedContextWordCount()
            // Keep the reader's viewport stable when the completed response appears.
            // Scrolling to the response remains an explicit action through the dock.
        }
        // MARK: - Persistence / conversation management
        .onAppear {
            let loadedSnapshot = CurrentConversationsStore.load()
            // Untouched Question of the Day drafts saved by earlier builds are dropped rather
            // than restored; restoring one froze the app on open.
            let cleanedSnapshot = loadedSnapshot.map { snapshot in
                var cleaned = snapshot
                cleaned.conversations.removeAll { ConversationDraftRetention.isUntouchedPromptDraft($0) }
                return cleaned
            }
            if let snapshot = cleanedSnapshot, !snapshot.conversations.isEmpty {
                conversations = snapshot.conversations
                // `openModelTaskPage` (tapping a task in the Model Tasks popup from a different
                // page) sets `requestedConversationID` *before* this view is even created, so
                // the `.onChange(of: requestedConversationID)` below never fires for it — that
                // only catches a value set while this view is already mounted. Without this
                // check, a fresh mount always fell back to whatever was last persisted as
                // active, silently ignoring which conversation the tapped task actually belongs
                // to (surfacing as "tapping the task opens a different/blank conversation").
                let requestedID = requestedConversationID
                if let requestedID {
                    requestedConversationID = nil
                }
                let targetID = requestedID
                    ?? snapshot.activeConversationID
                    ?? snapshot.conversations.first?.id
                if let id = targetID, let convo = snapshot.conversations.first(where: { $0.id == id }) {
                    activeConversationID = id
                    activeBranches = convo.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : convo.branches
                    canvasMode.promotedCanvasInsightIDs = convo.promotedInsightIDs
                } else if let first = snapshot.conversations.first {
                    activeConversationID = first.id
                    activeBranches = first.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : first.branches
                    canvasMode.promotedCanvasInsightIDs = first.promotedInsightIDs
                }
            } else {
                let initial = InquiryConversation()
                conversations = [initial]
                activeConversationID = initial.id
                activeBranches = [ChatBranch(startingConcept: nil)]
                canvasMode.promotedCanvasInsightIDs = []
            }
            focusedBranchID = activeBranches.first?.id
            restoreEmptyPromptState(from: activeBranches)
            refreshDisplayedContextWordCount(animated: false)
            if let activeConversationID {
                manuallySavedConversationInsightIDs =
                    ConversationInsightMembershipStore.insightIDs(for: activeConversationID)
            }
            studyTopics = StudyTopicStore.load()
            publishShellMenuState()
            scrollToEndOfConversationAfterLayout()

            // A new-conversation request may have been fired while this view was
            // unmounted (e.g. from the Study Topics page). Handle it now so the
            // correct topic-tagged conversation is created instead of showing the
            // most-recently saved one.
            if newConversationRequest != handledNewConversationRequest {
                handledNewConversationRequest = newConversationRequest
                startNewConversation()
            }
            scheduleInsightTreeUpdateAfterIdle()
            if let request = insightConversationQuoteRequest {
                openInsightConversationQuote(request)
            }
        }
        // Save branches back into the active conversation on every change, then persist.
        // saveCurrentConversation + publishShellMenuState are cheap (memory only).
        // persistConversations is debounced so UserDefaults isn't hit on every keystroke.
        .onChange(of: activeBranches) { _, _ in
            saveCurrentConversation()
            // publishShellMenuState() intentionally omitted — side menu data doesn't
            // change while typing, so calling it here causes a full AquinasSideMenu +
            // StreamingMessageView re-render on every keystroke (the source of lag).
            // It is called from onConversationTitleChange (post-submit), switchToConversation,
            // startNewConversation, and .onAppear instead.
            persistenceTask?.cancel()
            persistenceTask = Task {
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                persistConversations()
            }
        }
        // Side menu selected a conversation.
        .onChange(of: requestedConversationID) { _, id in
            guard let id, let convo = conversations.first(where: { $0.id == id }) else { return }
            requestedConversationID = nil
            switchToConversation(convo)
        }
        .onChange(of: insightConversationQuoteRequest) { _, request in
            guard let request else { return }
            openInsightConversationQuote(request)
        }
        // "New Conversation" button in side menu.
        .onChange(of: newConversationRequest) { _, new in
            guard new != handledNewConversationRequest else { return }
            handledNewConversationRequest = new
            startNewConversation()
        }
        // Conversation deleted from side menu / Conversations page.
        .onChange(of: deletedConversationID) { _, id in
            guard let id else { return }
            deletedConversationID = nil
            ConversationInsightMembershipStore.removeConversation(id)
            LocalInsightTreeSeedStore.removeConversation(id)
            conversations.removeAll { $0.id == id }
            if activeConversationID == id {
                if let first = conversations.first {
                    switchToConversation(first)
                } else {
                    startNewConversation()
                }
            }
            persistConversations()
        }
        // Sync title renames that ContentView applies directly to the sideMenuConversations binding.
        .onChange(of: sideMenuConversations) { _, updated in
            var changed = false
            for mc in updated {
                if let idx = conversations.firstIndex(where: { $0.id == mc.id }) {
                    if conversations[idx].title != mc.title {
                        conversations[idx].title = mc.title
                        changed = true
                    }
                    if conversations[idx].studyTopicID != mc.studyTopicID {
                        conversations[idx].studyTopicID = mc.studyTopicID
                        changed = true
                    }
                }
            }
            if changed { persistConversations() }
        }
    }

    private var conversationScaffold: some View {
        GeometryReader { geo in
            let usesCompactVerticalLayout = verticalSizeClass == .compact
            ZStack(alignment: .top) {
                AquinasTheme.Colors.canvas.ignoresSafeArea()

                // Horizontal branch pager
                branchPager(in: geo)

                // Top fade gradient, independent of the nav bar.
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: AquinasTheme.Colors.canvas.opacity(0.97), location: 0.00),
                        Gradient.Stop(color: AquinasTheme.Colors.canvas.opacity(0), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0.33),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .frame(height: usesCompactVerticalLayout ? 96 : 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(topConversationChromeOpacity)
                .animation(.easeInOut(duration: 0.28), value: topConversationChromeOpacity)
                .allowsHitTesting(false)

                // Bottom fade gradient (hidden in canvas mode)
                if !canvasMode.isTopicCanvasVisible {
                    LinearGradient(
                        stops: [
                            .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 0),
                            .init(color: AquinasTheme.Colors.canvas, location: 1),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 0.84)
                    )
                    .frame(height: geo.size.height * (usesCompactVerticalLayout ? 0.28 : 0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                // Canvas Mode: per-conversation Insight Tree
                if canvasMode.isTopicCanvasVisible {
                    topicCanvasLayer
                }

                // Left-swipe trigger (UIKit-backed, passthrough)
                if isPageVisible && !canvasMode.isTopicCanvasVisible && !isInsightLibraryOpen {
                    RightEdgeCanvasSwipeTrigger {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        enterCanvasMode()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
                }

                // Top bar (replaces simple AquinasNavButton HStack)
                BranchModeTopBar(
                    isCanvasMode: canvasMode.isTopicCanvasVisible,
                    title: isNewConversationPromptMode ? "" : activeTitle,
                    titleOpacity: topConversationChromeOpacity,
                    insightTreeUpdateSignal: insightTreeUpdateSignal,
                    isEditingTitle: $isEditingTitle,
                    titleDraft: $titleEditDraft,
                    conversationFontSize: conversationFontSize,
                    isInStudyTopic: activeStudyTopicTitle != nil,
                    isStudyMode: canvasMode.isCanvasStudyMode,
                    onMenuTap: onOpenMenu,
                    onCanvasTap: enterCanvasMode,
                    onBackTap: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            if canvasMode.isCanvasStudyMode {
                                canvasMode.canvasStudyExitRequest += 1
                            } else {
                                canvasMode.isTopicCanvasVisible = false
                            }
                        }
                    },
                    onCommitTitle: { newTitle in
                        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                              let idx = conversations.firstIndex(where: { $0.id == activeConversationID }) else { return }
                        conversations[idx].title = newTitle
                        publishShellMenuState()
                        persistConversations()
                    },
                    onTapStudyTopicBadge: {
                        conversationForTopicPicker = conversations.first { $0.id == activeConversationID }
                    }
                )
                .zIndex(2)
                .animation(.easeInOut(duration: 0.28), value: topConversationChromeOpacity)
            }
            .onAppear {
                viewportSize = geo.size
                if focusedBranchID == nil {
                    focusedBranchID = activeBranches.first?.id
                }
            }
            .onChange(of: geo.size) { _, s in viewportSize = s }
        }
        .safeAreaInset(edge: .bottom) {
            bottomInquiryControlDock
        }
        .alert("Couldn’t compact context", isPresented: $isCompactionErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The conversation was left unchanged. Check that the Aquinas backend is running and try again.")
        }
        .alert("Couldn’t generate definition", isPresented: Binding(
            get: { definitionState.failedWord != nil },
            set: { if !$0 { definitionState.failedWord = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                definitionState.failedWord = nil
            }
            Button("Try Again") {
                guard let word = definitionState.failedWord else { return }
                definitionState.failedWord = nil
                enqueueDynamicDefinition(word)
            }
        } message: {
            Text("No placeholder Insight was created. Check that the Aquinas backend is available and try again.")
        }
        .onChange(of: canvasMode.isTopicCanvasVisible) { _, isVisible in
            onCanvasModeChange(isVisible)
            modelTasksPopupState.reset()
            if !isVisible {
                canvasMode.isCanvasSearchActive = false
                canvasMode.canvasSearchQuery = ""
                canvasMode.canvasSearchResultIndex = 0
                canvasMode.canvasSearchResultCount = 0
                canvasMode.hasCanvasHover = false
                canvasMode.hasHoveredCanvasInsight = false
                canvasMode.canvasQuoteTarget = nil
                canvasMode.canvasSelectedItemCount = 0
            }
        }
        .onChange(of: canvasMode.hasHoveredCanvasInsight) { _, isHoveringInsight in
            guard isHoveringInsight else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                modelTasksPopupState.reset()
            }
        }
        .onChange(of: canvasMode.canvasSelectedItemCount) { _, selectedCount in
            guard selectedCount > 0 else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                modelTasksPopupState.reset()
            }
        }
        .onChange(of: canvasMode.isCanvasMidpointMode) { _, isMakingMidpoint in
            guard isMakingMidpoint else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                modelTasksPopupState.reset()
            }
        }
        .onDisappear {
            onCanvasModeChange(false)
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { _ in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                isKeyboardOpen = false
                isSlashCommandContext = false
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       UploadedFile.isImageData(data) {
                        await MainActor.run {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                uploadedFiles.append(
                                    UploadedFile(
                                        name: "Photo",
                                        imageData: data,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    }
                }
                await MainActor.run { selectedPhotoItems.removeAll() }
            }
        }
        .sheet(item: $conversationForTopicPicker) { conversation in
            SideMenuStudyTopicPickerSheet(
                conversation: conversation,
                onSelectTopic: { topic in
                    if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                        conversations[idx].studyTopicID = topic.id
                        publishShellMenuState()
                        persistConversations()
                    }
                },
                onRemoveTopic: {
                    if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                        conversations[idx].studyTopicID = nil
                        publishShellMenuState()
                        persistConversations()
                    }
                }
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
            .onDisappear {
                studyTopics = StudyTopicStore.load()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.86) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        uploadedFiles.append(
                            UploadedFile(
                                name: "Camera Photo",
                                imageData: data,
                                rotationDegrees: Double.random(in: -5...5)
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Insight library helpers

    private var insightLibrarySheetHeight: CGFloat {
        let available = max(viewportSize.height, 1)
        return min(max(insightLibraryPopupHeight, 220), available * 0.86)
    }

    private func currentConversationInsights() -> [ConceptDefinition] {
        var parts: [String] = []
        for branch in activeBranches {
            parts.append(branch.topQuestionText)
            parts.append(branch.bottomQuestionText)
            if let dup = branch.duplicatedResponse { parts.append(dup) }
            for block in branch.activeChatBlocks {
                switch block {
                case .text(let text):
                    parts.append(InlineInsightMarkup.plainText(from: text))
                case .user(let text, _, _):
                    parts.append(text)
                }
            }
        }
        let lower = parts.joined(separator: " ").lowercased()
        return collectedDefinitions
            .filter { lower.contains($0.word.lowercased()) }
            .uniquedByWord()
    }

    // MARK: - Branch page

    @ViewBuilder
    private func branchPage(branch: Binding<ChatBranch>, geo: GeometryProxy) -> some View {
        let b = branch.wrappedValue
        let stableViewportHeight = max(geo.size.height, viewportSize.height)
        let usesCompactVerticalLayout = verticalSizeClass == .compact
        let bottomRunwayHeight = stableViewportHeight * (
            isKeyboardOpen ? (usesCompactVerticalLayout ? 0.55 : 0.85) : (usesCompactVerticalLayout ? 0.22 : 0.35)
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .background(
                        GeometryReader { topGeo in
                            Color.clear
                                .onAppear {
                                    updateTopState(for: b.id, minY: topGeo.frame(in: .named("BranchScroll-\(b.id)")).minY)
                                }
                                .onChange(of: topGeo.frame(in: .named("BranchScroll-\(b.id)")).minY) { _, newMinY in
                                    updateTopState(for: b.id, minY: newMinY)
                                }
                        }
                    )

                ChatThreadColumn(
                    branchData: branch,
                    conversationID: activeConversationID,
                    branchAnchor: "branch-top-\(b.id)",
                    targetSpawnY: $targetSpawnY,
                    uploadedFiles: $uploadedFiles,
                    showsPendingUploads: b.id == effectiveFocusedID,
                    quotedConcept: b.id == effectiveFocusedID ? attachedConcept : nil,
                    targetSpawnResponseIndex: $targetSpawnResponseIndex,
                    externalSubmitTrigger: b.id == effectiveFocusedID ? externalSubmitTrigger : 0,
                    conversationFontSize: conversationFontSize,
                    conversationTextAlignment: conversationTextAlignment,
                    inputFont: inputFont,
                    responseFont: responseFont,
                    conversationTitlePolicy: conversationTitlePolicy,
                    personality: conversationPersonality,
                    loadingInsightKey: definitionState.loadingWord?.id,
                    queuedInsightKeys: queuedInsightKeys,
                    savedInsightIDs: Set(collectedDefinitions.map(\.id)),
                    modelTasks: modelTasks,
                    isModelBusy: modelTasks.isBusy,
                    isPageVisible: isPageVisible,
                    emptyStateUserName: displayUserName,
                    emptyStateEyebrow: activeEmptyPromptEyebrow,
                    newConversationViewportHeight: stableViewportHeight,
                    usesCompactVerticalLayout: usesCompactVerticalLayout,
                    studyTopicTitle: activeStudyTopicTitle,
                    onTapEyebrow: {
                        conversationForTopicPicker = conversations.first { $0.id == activeConversationID }
                    },
                    emptyStatePromptQuestion: activeEmptyPromptQuestion,
                    emptyStatePromptSubtitle: activeEmptyPromptSubtitle,
                    showsThinkingIntro: true,
                    conversationTitle: activeTitle,
                    onSpawnYChange: { _, _ in },
                    onDuplicateResponse: { text, index in
                        let newBranch = ChatBranch(
                            startingConcept: nil,
                            parentBranchID: b.id,
                            parentResponseIndex: index,
                            duplicatedResponse: InlineInsightMarkup.plainText(from: text),
                            yOffset: targetSpawnY
                        )
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            insertBranch(newBranch, after: b.id)
                        }
                    },
                    onDeleteBranch: { deleteBranch(b) },
                    onConversationTitleChange: { newTitle in
                        if let idx = conversations.firstIndex(where: { $0.id == activeConversationID }) {
                            conversations[idx].title = newTitle
                        }
                        publishShellMenuState()
                    },
                    onTopInputFocused: {
                        lastFocusedAnchor = "top-input-anchor-\(b.id)"
                    },
                    onTopQuestionSubmitted: {
                        guard b.parentBranchID == nil else { return }
                        switch activeEmptyPromptEyebrow {
                        case "QUESTION OF THE DAY":
                            onQuestionOfTheDayAnswered()
                        case "TODAY IN HISTORY":
                            onTodayInHistoryAnswered()
                        default:
                            break
                        }
                    },
                    onBottomInputFocused: {
                        lastFocusedAnchor = "bottom-input-anchor-\(b.id)"
                    },
                    onActiveInputTextChange: { text in
                        guard b.id == effectiveFocusedID else { return }
                        hasTextToSubmit = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        // Slash-command context: the field holds a bare "/token" (no space yet).
                        // Only updates @State on the boundary crossing, so typing stays lag-free.
                        let slash = text.hasPrefix("/") && !text.contains(" ") && !text.contains("\n")
                        if slash { slashQuery.text = text }   // re-renders only the picker
                        if slash != isSlashCommandContext {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                isSlashCommandContext = slash
                            }
                        }
                    },
                    insertCommandRequest: b.id == effectiveFocusedID ? insertCommandRequest : 0,
                    commandToInsert: commandToInsert,
                    showsSlashCommandMenu: b.id == effectiveFocusedID && showSlashCommandMenu,
                    slashCommandQuery: slashQuery,
                    onSelectSlashCommand: selectSlashCommand,
                    onExecuteSlashCommand: { command in
                        executeSlashCommand(command, in: b.id)
                    },
                    onQuoteHandled: { attachedConcept = nil },
                    onQuotedConceptRemoved: {
                        returnToStudyTopicTreeAfterQuoteCancellation()
                    },
                    onQuotedConceptSubmitted: {
                        pendingStudyTopicQuoteReturn = nil
                    },
                    onQuotedConceptTap: { concept in
                        presentQuotedConcept(concept)
                    },
                    connectionConcepts: b.id == effectiveFocusedID ? canvasMode.canvasConnectionConcepts : nil,
                    onConnectionHandled: { canvasMode.canvasConnectionConcepts = nil },
                    onResponseGenerated: { responseIndex in
                        // The response is complete even if its on-screen reveal animation will
                        // never run because navigation removed this view. Save at the model
                        // completion boundary so remounting the conversation restores the answer.
                        saveCurrentConversation()
                        persistConversations()
                        refreshDisplayedContextWordCount()
                        pendingResponseCount = max(0, pendingResponseCount - 1)
                        enqueueInsightTreeAnalysis(branchID: b.id, responseIndex: responseIndex)
                    },
                    onResponseCompleted: { _ in },
                    onResponseStarted: {
                        pendingResponseCount += 1
                    },
                    onResponseCancelled: {
                        pendingResponseCount = max(0, pendingResponseCount - 1)
                    },
                    onInsightTap: { word, sourceResponseBlock in
                        openDynamicDefinition(word: word, sourceResponseBlock: sourceResponseBlock)
                    },
                    onInlineInsightQuote: { concept in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            attachedConcept = concept
                            focusedBranchID = b.id
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            scrollToBottomRequest += 1
                        }
                    },
                    onInlineInsightFork: { concept, responseIndex in
                        let newBranch = ChatBranch(
                            startingConcept: concept,
                            parentBranchID: b.id,
                            parentResponseIndex: responseIndex,
                            yOffset: targetSpawnY
                        )
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            insertBranch(newBranch, after: b.id)
                        }
                    },
                    onInlineInsightToggleSaved: { concept in
                        toggleSavedConcept(concept)
                    }
                )
                .padding(.horizontal, usesCompactVerticalLayout ? 48 : 36)
                .frame(maxWidth: usesCompactVerticalLayout ? 1_120 : .infinity)

                // Extra scroll runway lets focused question fields sit higher on screen,
                // leaving room to see recent responses above the keyboard.
                Color.clear.frame(width: 1, height: bottomRunwayHeight)
                    .animation(.easeInOut(duration: 0.2), value: isKeyboardOpen)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id("branch-bottom-\(b.id)")
                    .background(
                        GeometryReader { bottomGeo in
                            Color.clear
                                .onAppear {
                                    updateBottomState(for: b.id, maxY: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY, viewportHeight: geo.size.height)
                                }
                                .onChange(of: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY) { _, newMaxY in
                                    updateBottomState(for: b.id, maxY: newMaxY, viewportHeight: geo.size.height)
                                }
                        }
                    )
            }
            // Explicit bottom content margin larger than the dock (76 pt) so the
            // system keyboard auto-scroll places the field above the dock even when
            // TabView fails to propagate the parent's .safeAreaInset inward.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .coordinateSpace(name: "BranchScroll-\(b.id)")
            .onChange(of: scrollToBottomRequest) { _, _ in
                guard b.id == effectiveFocusedID else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    proxy.scrollTo("branch-bottom-\(b.id)", anchor: .bottom)
                }
            }
            .onChange(of: scrollToTopRequest) { _, _ in
                guard b.id == effectiveFocusedID else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    proxy.scrollTo("branch-top-\(b.id)", anchor: .top)
                }
            }
            // keyboardDidShow fires AFTER the system's own auto-scroll completes,
            // so this override always wins and places the field at the top.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidShowNotification
            )) { _ in
                guard b.id == effectiveFocusedID,
                      let anchor = lastFocusedAnchor else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
    }

    private func updateBottomState(for branchID: UUID, maxY: CGFloat, viewportHeight: CGFloat) {
        guard branchID == effectiveFocusedID else { return }
        let atBottom = maxY <= viewportHeight + 32
        guard miniScrollButtonVisibilityRelay.isAtBottom != atBottom else { return }
        miniScrollButtonVisibilityRelay.isAtBottom = atBottom
        NotificationCenter.default.post(
            name: .aquinasMiniScrollButtonVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": !atBottom]
        )
    }

    private func updateTopState(for branchID: UUID, minY: CGFloat) {
        guard branchID == effectiveFocusedID else { return }
        let atTop = minY >= -8
        guard isBranchScrolledToTop != atTop else { return }
        isBranchScrolledToTop = atTop
    }

    // MARK: - Insight sheet

    @ViewBuilder
    private func insightSheet(for sheetData: ConversationInsightWord) -> some View {
        let definition = definitionState.definitionsByKey[sheetData.id]
        let isSaved = definition.map { c in
            collectedDefinitions.contains {
                $0.word.caseInsensitiveCompare(c.word) == .orderedSame
                    && $0.containsDefinitions(from: c)
            }
        } ?? false

        return DynamicInsightSheetCard(
            word: sheetData.text,
            concept: definition,
            isSaved: isSaved,
            funStatusText: modelTasks.allTasks.first {
                $0.kind.definitionKey == sheetData.id && $0.phase != .completed
            }?.funStatusText,
            onQuote: {
                guard let concept = definition else { return }
                definitionState.activeWord = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    attachedConcept = concept
                    if focusedBranchID == nil {
                        focusedBranchID = activeBranches.first?.id
                    }
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    scrollToBottomRequest += 1
                }
            },
            onFork: {
                guard let concept = definition else { return }
                definitionState.activeWord = nil
                let newBranch = ChatBranch(
                    startingConcept: concept,
                    parentBranchID: effectiveFocusedID,
                    parentResponseIndex: targetSpawnResponseIndex,
                    yOffset: targetSpawnY
                )
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    insertBranch(newBranch, after: effectiveFocusedID)
                }
            },
            onToggleSaved: {
                guard let concept = definition else { return }
                toggleSavedConcept(concept)
            }
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightSheetContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .frame(maxWidth: .infinity)
        .background(AquinasTheme.Colors.canvas)
        .onPreferenceChange(InsightSheetContentHeightKey.self) { h in
            definitionState.sheetContentHeight = h
        }
        .presentationDetents([.height(insightSheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AquinasTheme.Colors.canvas)
    }

    // MARK: - Branch management

    private func insertBranch(_ branch: ChatBranch, after parentID: UUID?) {
        pendingFocusBranchID = branch.id
        guard let parentID,
              let parentIndex = activeBranches.firstIndex(where: { $0.id == parentID }) else {
            activeBranches.append(branch)
            return
        }
        activeBranches.insert(branch, at: min(parentIndex + 1, activeBranches.count))
    }

    private func deleteBranch(_ branch: ChatBranch) {
        guard let parentID = branch.parentBranchID,
              let parent = activeBranches.first(where: { $0.id == parentID }) else { return }

        var toRemove: Set<UUID> = [branch.id]
        var queue: [UUID] = [branch.id]
        while let current = queue.popLast() {
            for b in activeBranches where b.parentBranchID == current {
                if toRemove.insert(b.id).inserted { queue.append(b.id) }
            }
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            activeBranches.removeAll { toRemove.contains($0.id) }
        }
        let returnID = parent.id
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                focusedBranchID = returnID
            }
        }
    }

    // MARK: - Conversation management

    private func executeSlashCommand(
        _ command: SlashCommandInvocation,
        in branchID: UUID
    ) {
        switch command {
        case .clear:
            clearCurrentConversation()
        case .compact:
            compactContext(in: branchID)
        }
    }

    private func compactContext(in branchID: UUID) {
        Task {
            _ = await performContextCompaction(in: branchID)
        }
    }

    @MainActor
    private func performContextCompaction(in branchID: UUID) async -> Bool {
        guard !isCompactingContext,
              let branchIndex = activeBranches.firstIndex(where: { $0.id == branchID }) else {
            return false
        }

        let branch = activeBranches[branchIndex]
        let compactedBlockCount = min(
            branch.compactedThroughBlockCount ?? 0,
            branch.activeChatBlocks.count
        )
        var uncompactedTranscript: [ChatBlock] = []
        if branch.compactedContext == nil {
            let topQuestion = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if branch.topQuestionSubmitted, !topQuestion.isEmpty {
                uncompactedTranscript.append(
                    .user(topQuestion, branch.branchContextConcept, branch.topQuestionUploads)
                )
            }
        }
        uncompactedTranscript.append(
            contentsOf: branch.activeChatBlocks.dropFirst(compactedBlockCount)
        )

        guard !uncompactedTranscript.isEmpty else {
            return false
        }

        isCompactingContext = true
        defer { isCompactingContext = false }
        let context = ConversationContext(
            compactedContext: branch.compactedContext,
            transcript: uncompactedTranscript,
            personality: conversationPersonality
        )
        let compactedThroughBlockCount = branch.activeChatBlocks.count

        let summary = await aquinasModel.compact(context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled else { return false }
        guard !summary.isEmpty else {
            isCompactionErrorPresented = true
            return false
        }
        guard let currentIndex = activeBranches.firstIndex(where: { $0.id == branchID }) else {
            return false
        }
        activeBranches[currentIndex].compactedContext = summary
        activeBranches[currentIndex].compactedThroughBlockCount =
            min(compactedThroughBlockCount, activeBranches[currentIndex].activeChatBlocks.count)
        saveCurrentConversation()
        persistConversations()
        // Compaction succeeds silently: the context gauge drops immediately, which is the
        // feedback that matters. A full-screen confirmation interrupts the conversation to
        // report something the user can already see. Failure still alerts.
        refreshDisplayedContextWordCount()
        return true
    }

    /// Copy activeBranches back into the conversations array for the active conversation.
    private func saveCurrentConversation() {
        guard let id = activeConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].branches = activeBranches
        conversations[idx].promotedInsightIDs = canvasMode.promotedCanvasInsightIDs
    }

    /// New conversations exist only while the user is composing them. Once navigation leaves an
    /// untouched draft, discard it instead of letting an empty card accumulate in the list.
    /// A quoted Insight is first copied into the branch so it remains available after remounting.
    private func removeActiveConversationIfEmpty() {
        guard let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let attachedConcept,
           let branchIndex = activeBranches.firstIndex(where: { $0.id == focusedBranchID })
                ?? activeBranches.indices.first {
            activeBranches[branchIndex].attachedConcept = attachedConcept
            activeBranches[branchIndex].showBottomInput = true
            self.attachedConcept = nil
        }
        saveCurrentConversation()

        let conversation = conversations[index]
        let hasSavedInsights = !manuallySavedConversationInsightIDs.isEmpty
            || !ConversationInsightMembershipStore.insightIDs(for: id).isEmpty
        guard !ConversationDraftRetention.shouldKeep(
            conversation,
            hasSavedInsights: hasSavedInsights
        ) else {
            return
        }

        ConversationInsightMembershipStore.removeConversation(id)
        LocalInsightTreeSeedStore.removeConversation(id)
        conversations.remove(at: index)
        activeConversationID = conversations.first?.id
        manuallySavedConversationInsightIDs = []
        canvasMode.promotedCanvasInsightIDs = []
        publishShellMenuState()
    }

    /// Update the sideMenu bindings from the current conversations list.
    private func publishShellMenuState() {
        sideMenuConversations = conversations
        sideMenuActiveConversationID = activeConversationID
        sideMenuCurrentTitle = conversations.first { $0.id == activeConversationID }?.title ?? "New Conversation"
    }

    /// Save activeBranches → conversations, then switch to a different conversation.
    private func switchToConversation(_ conversation: InquiryConversation) {
        // Switching pages or conversations is navigation, not cancellation. Model jobs are
        // shell-owned and already carry their conversation ID, so let them finish and route their
        // result back to the originating conversation. Only destructive actions such as Clear or
        // New Conversation intentionally call `resetModelTaskPipeline()`.
        removeActiveConversationIfEmpty()
        activeConversationID = conversation.id
        let nextBranches = conversation.branches.isEmpty
            ? [ChatBranch(startingConcept: nil)]
            : conversation.branches
        activeBranches = nextBranches
        focusedBranchID = activeBranches.first?.id
        manuallySavedConversationInsightIDs =
            ConversationInsightMembershipStore.insightIDs(for: conversation.id)
        refreshDisplayedContextWordCount(animated: false)
        canvasMode.promotedCanvasInsightIDs = conversation.promotedInsightIDs
        restoreEmptyPromptState(from: nextBranches)
        pendingResponseCount = modelTasks.allTasks.filter { task in
            guard task.conversationID == conversation.id,
                  case .userQuestion = task.kind else {
                return false
            }
            return task.phase == .current || task.phase == .upcoming
        }.count
        definitionState.reset()
        modelTasksPopupState.reset()
        publishShellMenuState()
        persistConversations()
        scrollToEndOfConversationAfterLayout()
        scheduleInsightTreeUpdateAfterIdle()
    }

    /// Reconstruct the special empty-conversation presentation after navigation. The visible
    /// prompt metadata is otherwise view-local, while its source tag and pinned question are
    /// persisted on the root branch so an unanswered Question of the Day survives remounting.
    private func restoreEmptyPromptState(from branches: [ChatBranch]) {
        guard let rootBranch = branches.first(where: { $0.parentBranchID == nil }),
              rootBranch.activeChatBlocks.isEmpty,
              !rootBranch.topQuestionSubmitted,
              let question = rootBranch.pinnedHeaderQuestion?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !question.isEmpty else {
            activeEmptyPromptEyebrow = ""
            activeEmptyPromptQuestion = ""
            activeEmptyPromptSubtitle = ""
            return
        }

        let context = rootBranch.hiddenPromptContext ?? ""
        if context.localizedCaseInsensitiveContains("<question of the day>") {
            activeEmptyPromptEyebrow = "QUESTION OF THE DAY"
            activeEmptyPromptQuestion = question
            activeEmptyPromptSubtitle = ""
        } else if context.localizedCaseInsensitiveContains("<today in history>") {
            activeEmptyPromptEyebrow = "TODAY IN HISTORY"
            activeEmptyPromptQuestion = question
            activeEmptyPromptSubtitle = ""
        } else {
            activeEmptyPromptEyebrow = ""
            activeEmptyPromptQuestion = ""
            activeEmptyPromptSubtitle = ""
        }
    }

    /// Reset the active conversation in place so study-topic membership and the
    /// conversation's identity remain stable while every question/response disappears.
    private func clearCurrentConversation() {
        persistenceTask?.cancel()
        resetModelTaskPipeline(conversationID: activeConversationID)
        let freshBranches = [ChatBranch(startingConcept: nil)]
        activeBranches = freshBranches
        focusedBranchID = freshBranches.first?.id
        displayedContextTokenCount = 0
        undiscoveredInsightCount = 0
        activeEmptyPromptEyebrow = ""
        activeEmptyPromptQuestion = ""
        activeEmptyPromptSubtitle = ""
        canvasMode.promotedCanvasInsightIDs = []
        attachedConcept = nil
        uploadedFiles.removeAll()
        hasTextToSubmit = false
        canvasMode.canvasConnectionConcepts = nil
        canvasMode.canvasQuoteTarget = nil
        canvasMode.canvasSelectedItemCount = 0

        if let id = activeConversationID,
           let index = conversations.firstIndex(where: { $0.id == id }) {
            ConversationInsightMembershipStore.removeConversation(id)
            LocalInsightTreeSeedStore.removeConversation(id)
            manuallySavedConversationInsightIDs = []
            conversations[index].title = "New Conversation"
            conversations[index].branches = freshBranches
            conversations[index].promotedInsightIDs = []
        }

        publishShellMenuState()
        persistConversations()
        scrollToBottomAfterLayout()
    }

    /// Save current work, then create a fresh conversation and make it active.
    private func startNewConversation() {
        // Starting a new conversation is navigation, not cancellation: jobs already queued for
        // the conversation being left keep running and route their results back to it. Only the
        // per-conversation UI state is reset for the fresh conversation.
        pendingResponseCount = 0
        definitionState.reset()
        modelTasksPopupState.reset()
        removeActiveConversationIfEmpty()
        // Consume any pending topic tag set by a "New Conversation inside topic" action.
        let topicID = newConversationTopicID
        newConversationTopicID = nil
        // Consume any study-topic flag set by a "New Study Topic" action.
        let isStudyTopic = newConversationIsStudyTopic
        newConversationIsStudyTopic = false
        let pendingQuestion = pendingNewConversationQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingEyebrow = pendingNewConversationEyebrow.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingPromptContext = pendingNewConversationPromptContext.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let pendingSubtitle = pendingNewConversationSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingNewConversationQuestion = ""
        pendingNewConversationEyebrow = ""
        pendingNewConversationPromptContext = ""
        pendingNewConversationSubtitle = ""
        var freshBranch = ChatBranch(
            startingConcept: nil,
            hiddenPromptContext: pendingPromptContext.isEmpty ? nil : pendingPromptContext
        )
        if ["QUESTION OF THE DAY", "TODAY IN HISTORY"].contains(pendingEyebrow), !pendingQuestion.isEmpty {
            freshBranch.pinnedHeaderQuestion = pendingQuestion
        }
        var fresh = InquiryConversation(isStudyTopic: isStudyTopic, studyTopicID: topicID)
        if let pinned = freshBranch.pinnedHeaderQuestion {
            fresh.title = pinned
        }
        conversations.insert(fresh, at: 0)
        activeConversationID = fresh.id
        manuallySavedConversationInsightIDs = []
        activeBranches = [freshBranch]
        activeEmptyPromptEyebrow = pendingEyebrow
        activeEmptyPromptQuestion = pendingQuestion
        activeEmptyPromptSubtitle = pendingSubtitle
        displayedContextTokenCount = 0
        hasTextToSubmit = false
        canvasMode.promotedCanvasInsightIDs = []
        focusedBranchID = activeBranches.first?.id
        if let quoteRequest = newConversationInsightQuoteRequest {
            attachedConcept = quoteRequest.insight
            // Set regardless of whether this came from a Study Topic or the global Insight
            // Tree (`topicID` nil either way is fine — `InsightConversationQuoteRequest`
            // already models it as optional) — removing the quoted chip should return to
            // whichever tree it came from with the Insight hovered; see
            // `returnToStudyTopicTreeAfterQuoteCancellation`'s topicID branch.
            pendingStudyTopicQuoteReturn = InsightConversationQuoteRequest(
                topicID: quoteRequest.topicID,
                conversationID: fresh.id,
                insight: quoteRequest.insight
            )
            newConversationInsightQuoteRequest = nil

            // Seed the on-device Insight Tree fallback from the quoted Insight itself rather
            // than waiting for the first question's answer to generate one — the quoted
            // Insight already *is* this conversation's subject. The first answer's own
            // new-subject check (embedding similarity against existing seeds) naturally skips
            // adding a redundant second seed when it's about the same thing, so this doesn't
            // need any special-casing on that side.
            let quotedConcept = quoteRequest.insight
            LocalInsightTreeSeedStore.appendSeed(
                LocalInsightTreeSeed(
                    id: UUID(),
                    label: quotedConcept.word,
                    summary: quotedConcept.semanticDefinition,
                    embedding: computeEmbedding(for: "\(quotedConcept.word). \(quotedConcept.semanticDefinition)"),
                    createdAt: Date()
                ),
                for: fresh.id
            )
        }
        publishShellMenuState()
        persistConversations()
        scrollToTopAfterLayout()
    }

    /// An untouched draft (e.g. an unanswered Question of the Day) is one viewport-tall prompt
    /// with a long scroll runway beneath it. Restoring it must land on the prompt, not the runway.
    private func scrollToEndOfConversationAfterLayout() {
        if isNewConversationPromptMode {
            scrollToTopAfterLayout()
        } else {
            scrollToBottomAfterLayout()
        }
    }

    private func scrollToBottomAfterLayout() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            scrollToBottomRequest += 1
        }
    }

    private func scrollToTopAfterLayout() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            isBranchScrolledToTop = true
            scrollToTopRequest += 1
        }
    }

    /// Persist the current conversations through the canonical file-backed repository.
    private func persistConversations() {
        CurrentConversationsStore.save(
            InquiryPersistenceSnapshot(conversations: conversations, activeConversationID: activeConversationID)
        )
    }

    // MARK: - Insight definition

    private func openDynamicDefinition(word: String, sourceResponseBlock: String?) {
        let insightWord = ConversationInsightWord(
            text: word,
            sourceResponseBlock: sourceResponseBlock
        )

        if definitionState.definitionsByKey[insightWord.id] != nil {
            presentDefinition(insightWord)
            return
        }

        guard !definitionState.lookupKeys.contains(insightWord.id) else { return }
        definitionState.lookupKeys.insert(insightWord.id)

        let conversationID = activeConversationID
        let context = definitionContext(sourceResponseBlock: sourceResponseBlock)
        Task {
            let cached = await aquinasModel.cachedDefinition(
                for: word,
                in: context,
                conversationID: conversationID
            )
            // Always clear the lookup guard, even if the user switched conversations while
            // this was in flight — otherwise this term's key stays stuck in the lookup set
            // forever and every future tap on it silently no-ops.
            definitionState.lookupKeys.remove(insightWord.id)
            guard activeConversationID == conversationID else { return }

            if let cached {
                definitionState.definitionsByKey[insightWord.id] = stableDefinition(
                    cached,
                    requestedTerm: word
                )
                presentDefinition(insightWord)
            } else {
                enqueueDynamicDefinition(insightWord)
            }
        }
    }

    private func presentQuotedConcept(_ concept: ConceptDefinition) {
        let insightWord = ConversationInsightWord(text: concept.word, sourceResponseBlock: nil)
        definitionState.definitionsByKey[insightWord.id] = concept
        presentDefinition(insightWord)
    }

    /// Cancel only the conversation being left/cleared, not the whole shared queue — a
    /// different conversation's still-running job must survive navigating away from it.
    private func resetModelTaskPipeline(conversationID: UUID?) {
        modelTasks.cancelTasks {
            !$0.kind.isInsightTreeTask && $0.conversationID == conversationID
        }
        modelTasks.clearCompletedTasks()
        modelTasksPopupState.reset()
        pendingResponseCount = 0
        definitionState.reset()
    }

    private func enqueueDynamicDefinition(_ word: ConversationInsightWord) {
        guard !modelTasks.contains(where: {
            $0.kind.definitionKey == word.id && $0.phase != .completed
        }) else {
            return
        }

        modelTasks.enqueue(
            kind: .defineInsight(key: word.id, name: word.text),
            originPage: .conversation,
            conversationID: activeConversationID,
            onStart: {
                definitionState.sheetContentHeight = 178
                definitionState.loadingWord = word
            },
            onCancel: {
                if definitionState.loadingWord == word {
                    definitionState.loadingWord = nil
                }
            }
        ) {
            await requestDynamicDefinition(
                for: word.text,
                sourceResponseBlock: word.sourceResponseBlock
            )
        }
    }

    // Routes through BackendAquinasModel's live contextual-definition call.
    private func requestDynamicDefinition(for word: String, sourceResponseBlock: String?) async {
        let conversationID = activeConversationID
        let completedWord = ConversationInsightWord(text: word, sourceResponseBlock: sourceResponseBlock)

        let defined: ConceptDefinition
        do {
            defined = try await aquinasModel.defineTerm(
                word,
                in: definitionContext(sourceResponseBlock: sourceResponseBlock),
                conversationID: conversationID
            )
        } catch {
            guard !Task.isCancelled else { return }
            if definitionState.loadingWord == completedWord {
                definitionState.loadingWord = nil
            }
            definitionState.failedWord = completedWord
            return
        }
        guard !Task.isCancelled else { return }
        guard definitionState.loadingWord == completedWord else { return }

        // Re-stamp with a stable, term-derived id — the model assigns content, never identity
        // (see ConceptDefinition.stableID(forTerm:)) — so re-saving the same term always dedups.
        definitionState.definitionsByKey[completedWord.id] = stableDefinition(
            defined,
            requestedTerm: word
        )
        definitionState.loadingWord = nil

        postDefinitionCompletedNotification(completedWord)
    }

    private func definitionContext(sourceResponseBlock: String?) -> ConversationContext {
        guard let sourceResponseBlock else {
            return ConversationContext()
        }
        return ConversationContext(
            transcript: [.text(sourceResponseBlock.removingAquinasInsightMarkup())]
        )
    }

    private func stableDefinition(
        _ definition: ConceptDefinition,
        requestedTerm: String
    ) -> ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: requestedTerm),
            word: definition.word.capitalized,
            partOfSpeech: definition.partOfSpeech,
            pronunciation: definition.pronunciation,
            meaning: definition.meaning,
            example: definition.example,
            definitions: definition.contextualDefinitions
        )
    }

    private func presentDefinition(_ word: ConversationInsightWord) {
        definitionState.present(word)
    }

    private func postDefinitionCompletedNotification(_ word: ConversationInsightWord) {
        let title = definitionState.definitionsByKey[word.id]?.word ?? word.text.capitalized
        modelCompletionNotifications?.post(title: title, kind: .insightDefinition) {
            onRequestConversationPage()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard definitionState.definitionsByKey[word.id] != nil else { return }
                presentDefinition(word)
            }
        }
    }

    private func presentNextCompletedDefinition() {
        guard let nextWord = definitionState.takeNextCompletedWord() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard definitionState.activeWord == nil else { return }
            definitionState.activeWord = nextWord
        }
    }

    private func toggleSavedConcept(_ concept: ConceptDefinition) {
        let shouldSave = !collectedDefinitions.contains {
            $0.id == concept.id && $0.containsDefinitions(from: concept)
        }
        setSavedConcept(concept, isSaved: shouldSave)
    }

    private func setSavedConcept(_ concept: ConceptDefinition, isSaved: Bool) {
        let wasSavedToConversation = manuallySavedConversationInsightIDs.contains(concept.id)
        let existingConcept = collectedDefinitions.first { $0.id == concept.id }
        let conceptToSave = existingConcept?.mergingDefinitions(from: concept) ?? concept

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if isSaved {
                if let existingIndex = collectedDefinitions.firstIndex(
                    where: { $0.id == concept.id }
                ) {
                    collectedDefinitions[existingIndex] = conceptToSave
                } else {
                    collectedDefinitions.append(conceptToSave)
                }
            } else {
                collectedDefinitions.removeAll { $0.id == concept.id }
            }
        }

        guard let conversationID = activeConversationID else { return }
        if isSaved {
            ConversationInsightMembershipStore.add(
                insightID: concept.id,
                to: conversationID
            )
            manuallySavedConversationInsightIDs.insert(concept.id)

            if !wasSavedToConversation {
                InsightDiscoveryStore.markUndiscovered([concept.id])
                undiscoveredInsightCount = InsightDiscoveryStore.visibleUndiscoveredCount(
                    for: conversationInsights.map(\.id)
                )
            }
        } else {
            ConversationInsightMembershipStore.remove(
                insightID: concept.id,
                from: conversationID
            )
            manuallySavedConversationInsightIDs.remove(concept.id)
        }

        guard isSaved else { return }
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .conversation,
            conversationID: conversationID,
            priority: .background
        ) {
            // Insight Tree persistence is backend-only; a physical device with only a loopback
            // backend configured can never reach it, so skip immediately rather than hanging on
            // the service's 120-second request timeout.
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                // Keep the global library's merged definitions separate from this conversation's
                // tree membership. The tree must persist only the contextual definition the user
                // just saved here, even when the same stable Insight ID exists in another thread.
                let suggestedNodeLabel = try await aquinasModel.labelSubject(
                    forTitles: ["\(concept.word): \(concept.semanticDefinition)"]
                )
                let assignment = try await insightTreeService.save(
                    concept,
                    to: conversationID,
                    suggestedNodeLabel: suggestedNodeLabel
                )
                guard !Task.isCancelled,
                      activeConversationID == conversationID else { return }
                let addedNodeIDs = assignment.didCreateNode ? [assignment.nodeID] : []
                InsightDiscoveryStore.markNodesUndiscovered(addedNodeIDs)
                InsightDiscoveryStore.markPendingTreePresentation(
                    insightIDs: [concept.id],
                    nodeIDs: addedNodeIDs
                )
                finishInsightTreeMutation(for: conversationID)
                // Give the mounted tree a turn to enqueue its persisted-snapshot refresh
                // before this mutation leaves the shared model queue.
                await Task.yield()
            } catch {
                // The durable conversation-membership record lets Canvas reconcile this
                // save from the global library when the backend is reachable again.
            }
        }
    }

    private func removeConversationInsight(_ concept: ConceptDefinition) {
        guard let conversationID = activeConversationID else { return }
        ConversationInsightMembershipStore.remove(
            insightID: concept.id,
            from: conversationID
        )
        manuallySavedConversationInsightIDs.remove(concept.id)
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .conversation,
            conversationID: conversationID,
            priority: .background
        ) {
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                try await insightTreeService.remove(
                    insightID: concept.id,
                    from: conversationID
                )
                guard !Task.isCancelled,
                      activeConversationID == conversationID else { return }
                finishInsightTreeMutation(for: conversationID)
                await Task.yield()
            } catch {
                // Keep the current snapshot if the backend is unavailable.
            }
        }
    }

    private func restoreConversationInsight(_ concept: ConceptDefinition) {
        guard let conversationID = activeConversationID else { return }
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .conversation,
            conversationID: conversationID,
            priority: .background
        ) {
            // The tree-save below is backend-only; skip before spending a local model-generation
            // slot on labelSubject when it can never reach the backend anyway.
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                let suggestedNodeLabel = try await aquinasModel.labelSubject(
                    forTitles: ["\(concept.word): \(concept.semanticDefinition)"]
                )
                let assignment = try await insightTreeService.save(
                    concept,
                    to: conversationID,
                    suggestedNodeLabel: suggestedNodeLabel
                )
                guard !Task.isCancelled,
                      activeConversationID == conversationID else { return }
                let addedNodeIDs = assignment.didCreateNode ? [assignment.nodeID] : []
                InsightDiscoveryStore.markUndiscovered([concept.id])
                InsightDiscoveryStore.markNodesUndiscovered(addedNodeIDs)
                InsightDiscoveryStore.markPendingTreePresentation(
                    insightIDs: [concept.id],
                    nodeIDs: addedNodeIDs
                )
                finishInsightTreeMutation(for: conversationID)
                await Task.yield()
            } catch {
                // Undo can be retried by saving the Insight again.
            }
        }
    }
}

// MARK: - BranchModeTopBar

private struct BranchModeTopBar: View {
    let isCanvasMode: Bool
    let title: String
    let titleOpacity: Double
    let insightTreeUpdateSignal: Int
    @Binding var isEditingTitle: Bool
    @Binding var titleDraft: String
    let conversationFontSize: ConversationFontSizeOption
    var isInStudyTopic: Bool = false
    /// In Study the canvas's Back becomes the side-menu button with an Exit beside it.
    var isStudyMode: Bool = false
    var onMenuTap: () -> Void
    var onCanvasTap: () -> Void
    var onBackTap: () -> Void
    var onCommitTitle: (String) -> Void = { _ in }
    var onTapStudyTopicBadge: () -> Void = {}
    @Namespace private var titleNamespace
    @FocusState private var titleFieldFocused: Bool

    private var titleFontSize: CGFloat {
        switch conversationFontSize {
        case .large:  return 17
        case .medium: return 16
        case .small:  return 15
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Normal mode layout
            HStack(spacing: 0) {
                AquinasNavButton(onMenuTap: onMenuTap)
                    .frame(width: 88, alignment: .leading)
                Spacer(minLength: 8)
                Group {
                    if isEditingTitle {
                        TextField("Conversation title", text: $titleDraft)
                            .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                            .multilineTextAlignment(.center)
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                            .focused($titleFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isEditingTitle = false
                                onCommitTitle(titleDraft)
                            }
                    } else if isInStudyTopic {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack")
                                .font(.system(size: titleFontSize - 3, weight: .medium))
                                .foregroundColor(AquinasTheme.Colors.lightGreen)
                            Text(title)
                                .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .lineLimit(1)
                        }
                        .id(title)
                        .transition(.blurredTitleReplacement)
                        .onTapGesture(perform: onTapStudyTopicBadge)
                    } else {
                        Text(title)
                            .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                            .lineLimit(1)
                            .id(title)
                            .transition(.blurredTitleReplacement)
                            .onTapGesture {
                                titleDraft = title
                                isEditingTitle = true
                                titleFieldFocused = true
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(titleOpacity)
                .animation(.easeOut(duration: 0.22), value: title)
                Spacer(minLength: 8)
                CanvasModeToggleButton(
                    isActive: false,
                    updateSignal: insightTreeUpdateSignal,
                    action: onCanvasTap
                )
                    .matchedGeometryEffect(id: "canvasModeButton", in: titleNamespace, isSource: !isCanvasMode)
                    .frame(width: 88, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(isCanvasMode ? 0 : 1)
            .offset(x: isCanvasMode ? -96 : 0)
            .allowsHitTesting(!isCanvasMode)

            // Canvas mode layout
            HStack(spacing: 8) {
                if isStudyMode {
                    AquinasNavButton(onMenuTap: onMenuTap)
                        .transition(.blurFade)
                    StudyExitButton(action: onBackTap)
                        .transition(.studyExitGrow)
                } else {
                    CanvasModeToggleButton(
                        isActive: true,
                        updateSignal: insightTreeUpdateSignal,
                        action: onBackTap
                    )
                        .matchedGeometryEffect(id: "canvasModeButton", in: titleNamespace, isSource: isCanvasMode)
                        .opacity(isCanvasMode ? 1 : 0)
                }
                Spacer()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isStudyMode)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .allowsHitTesting(isCanvasMode)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private let aquinasInsightLinkPattern = try! NSRegularExpression(
    pattern: #"\[([^\]]+)\]\(aq://[^)]+\)"#
)

private extension String {
    func removingAquinasInsightMarkup() -> String {
        let range = NSRange(startIndex..., in: self)
        let visibleText = aquinasInsightLinkPattern.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: "$1"
        )
        return InlineInsightMarkup.plainText(from: visibleText)
    }
}

// MARK: - Canvas swipe gesture (UIKit-backed)

private final class CanvasSwipeView: UIView {
    var onTriggered: (() -> Void)?
    fileprivate var windowPan: UIPanGestureRecognizer?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowPan?.view?.removeGestureRecognizer(windowPan!)
        windowPan = nil
        guard let window else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        window.addGestureRecognizer(pan)
        windowPan = pan
    }

    deinit { windowPan?.view?.removeGestureRecognizer(windowPan!) }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let t = pan.translation(in: pan.view)
        let v = pan.velocity(in: pan.view)
        guard (t.x < -80 && abs(t.x) > abs(t.y) * 1.5) ||
              (v.x < -500 && abs(v.x) > abs(v.y) * 1.5) else { return }
        onTriggered?()
    }
}

extension CanvasSwipeView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct RightEdgeCanvasSwipeTrigger: UIViewRepresentable {
    var onTriggered: () -> Void
    func makeUIView(context: Context) -> CanvasSwipeView {
        let v = CanvasSwipeView()
        v.backgroundColor = .clear
        v.onTriggered = onTriggered
        return v
    }
    func updateUIView(_ uiView: CanvasSwipeView, context: Context) {
        uiView.onTriggered = onTriggered
    }
    static func dismantleUIView(_ uiView: CanvasSwipeView, coordinator: ()) {
        uiView.windowPan?.view?.removeGestureRecognizer(uiView.windowPan!)
        uiView.windowPan = nil
    }
}

// MARK: - Conversation persistence store

/// Compatibility name retained while call sites move onto `InquiryPersistenceStore` directly.
/// Both names now address the same canonical Application Support snapshot.
enum CurrentConversationsStore {
    static func load() -> InquiryPersistenceSnapshot? {
        InquiryPersistenceStore.load()
    }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        InquiryPersistenceStore.save(snapshot)
    }
}
