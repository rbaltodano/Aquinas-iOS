//
//  ModelTaskQueue.swift
//  Aquinas-iOS
//

import Foundation
import Observation

enum ModelTaskKind: Hashable {
    case userQuestion(branchID: UUID, responseIndex: Int)
    case defineInsight(key: String, name: String)
    case createMidpoint
    case makeNode
    case updateInsightTree
    case refreshInsightTree
    case refreshQuestionOfTheDay

    var title: String {
        switch self {
        case .userQuestion:
            return String(localized: "User Question")
        case .defineInsight(_, let name):
            return String(localized: "Define “\(name.localizedCapitalized)”")
        case .createMidpoint:
            return String(localized: "Create Midpoint")
        case .makeNode:
            return String(localized: "Make Node")
        case .updateInsightTree, .refreshInsightTree:
            return String(localized: "Update Insight Tree")
        case .refreshQuestionOfTheDay:
            return String(localized: "Consolidate information")
        }
    }

    var definitionKey: String? {
        guard case .defineInsight(let key, _) = self else { return nil }
        return key
    }

    var userQuestionBranchID: UUID? {
        guard case .userQuestion(let branchID, _) = self else { return nil }
        return branchID
    }

    var isInsightTreeTask: Bool {
        switch self {
        case .updateInsightTree, .refreshInsightTree:
            return true
        default:
            return false
        }
    }

    var standardStatusText: String {
        switch self {
        case .userQuestion, .makeNode:
            return String(localized: "Thinking...")
        case .defineInsight:
            return String(localized: "Parsing...")
        case .createMidpoint:
            return String(localized: "Plotting...")
        case .updateInsightTree, .refreshInsightTree:
            return String(localized: "Mapping...")
        case .refreshQuestionOfTheDay:
            return String(localized: "Consolidating...")
        }
    }

    var defaultOriginPage: ModelTaskOriginPage {
        switch self {
        case .userQuestion, .defineInsight:
            return .conversation
        case .createMidpoint, .makeNode, .updateInsightTree, .refreshInsightTree:
            return .insights
        case .refreshQuestionOfTheDay:
            return .home
        }
    }
}

enum ModelTaskOriginPage: Hashable {
    case home
    case conversation
    case openConversations
    case settings
    case insights
    case studyTopics
}

enum FunModelStatusCopy {
    static let general = [
        "Uhhh...",
        "On it...",
        "Aye capin!",
        "Gimme a sec...",
        "Yawn...",
        "Dancing...",
        "la la la...",
        "Lemme think...",
        ":^)",
        "*beep boop*",
        "Roboting..."
    ]

    static let loading = [
        "Wakin up...",
        "Need Coffee...",
        "Zzzzz...",
        "*falls over*",
        ":^)"
    ]

    static func randomStatus(for kind: ModelTaskKind) -> String {
        randomStatus(from: taskSpecificBank(for: kind))
    }

    static func randomThinkingStatus() -> String {
        randomStatus(from: ["Lemme think..."])
    }

    static func randomLoadingStatus() -> String {
        randomStatus(from: loading)
    }

    private static func taskSpecificBank(for kind: ModelTaskKind) -> [String] {
        switch kind {
        case .userQuestion, .makeNode:
            return ["Lemme think..."]
        case .defineInsight:
            return ["Defining...", "Naming..."]
        case .createMidpoint:
            return ["Watch this...", "Connecting...", "Graphing..."]
        case .updateInsightTree, .refreshInsightTree:
            return ["Scribbling...", "Jotting...", "Planting...", "Trimming...", "Prunning..."]
        case .refreshQuestionOfTheDay:
            return ["Packin up..."]
        }
    }

    private static func randomStatus(from specificBank: [String]) -> String {
        let selectedBank = Bool.random() ? specificBank : general
        return selectedBank.randomElement() ?? general[0]
    }
}

enum ModelTaskPhase: Equatable {
    case completed
    case current
    case upcoming
}

enum ModelTaskPriority: Int, Comparable {
    case background = 0
    case foreground = 1

    static func < (lhs: ModelTaskPriority, rhs: ModelTaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ModelTaskSnapshot: Identifiable, Equatable {
    let id: UUID
    let kind: ModelTaskKind
    let originPage: ModelTaskOriginPage
    /// The specific conversation this task belongs to, when its origin page is `.conversation`.
    /// Lets task navigation reopen the exact conversation instead of whichever one happens to
    /// be active.
    let conversationID: UUID?
    let phase: ModelTaskPhase
    let funStatusText: String?
    let funLoadingStatusText: String?

    var title: String {
        kind.title
    }
}

@MainActor
@Observable
final class ModelTaskQueue {
    private struct Job {
        let id: UUID
        let kind: ModelTaskKind
        let originPage: ModelTaskOriginPage
        let conversationID: UUID?
        let priority: ModelTaskPriority
        let funStatusText: String?
        let funLoadingStatusText: String?
        let onStart: () -> Void
        let onCancel: () -> Void
        let operation: () async -> Void
    }

    private(set) var completedTasks: [ModelTaskSnapshot] = []
    /// The most recent successful completion, retained after the transient completed-task list
    /// clears so page-level refresh policies can react exactly once to completed model work.
    private(set) var latestCompletedTask: ModelTaskSnapshot?
    private(set) var currentTask: ModelTaskSnapshot?
    private(set) var upcomingTasks: [ModelTaskSnapshot] = []
    private(set) var isRuntimeLoading = false
    private(set) var personality: ConversationPersonality = .balanced
    /// User-question completions that have not yet been viewed in their conversation.
    private(set) var completedUserQuestionBranchIDs: Set<UUID> = []

    @ObservationIgnored private var currentJob: Job?
    @ObservationIgnored private var waitingJobs: [Job] = []
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var completedTasksClearTask: Task<Void, Never>?
    @ObservationIgnored private let runtimeLifecycle: ModelRuntimeLifecycleManager
    @ObservationIgnored private var lifecycleTransitionTask: Task<Void, Never>?
    /// Invalidates a superseded unload transition so its tail can't clear state that a newer
    /// foreground return (or newer unload) now owns. See `setApplicationActive`.
    @ObservationIgnored private var lifecycleTransitionGeneration = 0
    @ObservationIgnored private var isExecutionSuspended = false
    @ObservationIgnored private var applicationIsActive = true

    init(
        runtimeLifecycle: ModelRuntimeLifecycleManager = ModelRuntimeLifecycleManager()
    ) {
        self.runtimeLifecycle = runtimeLifecycle
    }

    var allTasks: [ModelTaskSnapshot] {
        completedTasks + [currentTask].compactMap { $0 } + upcomingTasks
    }

    var pendingCount: Int {
        (currentTask == nil ? 0 : 1) + upcomingTasks.count
    }

    var totalCount: Int {
        allTasks.count
    }

    var currentPosition: Int {
        guard currentTask != nil else { return completedTasks.count }
        return completedTasks.count + 1
    }

    var isBusy: Bool {
        currentTask != nil || !upcomingTasks.isEmpty
    }

    @discardableResult
    func enqueue(
        kind: ModelTaskKind,
        originPage: ModelTaskOriginPage? = nil,
        conversationID: UUID? = nil,
        priority: ModelTaskPriority = .foreground,
        onStart: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        operation: @escaping () async -> Void
    ) -> UUID {
        completedTasksClearTask?.cancel()
        completedTasksClearTask = nil
        if let branchID = kind.userQuestionBranchID {
            completedUserQuestionBranchIDs.remove(branchID)
        }

        if !isBusy {
            completedTasks.removeAll()
        }

        let job = Job(
            id: UUID(),
            kind: kind,
            originPage: originPage ?? kind.defaultOriginPage,
            conversationID: conversationID,
            priority: priority,
            funStatusText: personality == .fun
                ? FunModelStatusCopy.randomStatus(for: kind)
                : nil,
            funLoadingStatusText: personality == .fun
                ? FunModelStatusCopy.randomLoadingStatus()
                : nil,
            onStart: onStart,
            onCancel: onCancel,
            operation: operation
        )
        if priority == .foreground,
           let currentJob,
           currentJob.priority == .background {
            runningTask?.cancel()
            runningTask = nil
            self.currentJob = nil
            currentTask = nil
            waitingJobs.insert(currentJob, at: 0)
        }
        waitingJobs.insert(job, at: defaultInsertionIndex(for: priority))
        publishUpcomingTasks()
        startNextIfNeeded()
        return job.id
    }

    func contains(where predicate: (ModelTaskSnapshot) -> Bool) -> Bool {
        allTasks.contains(where: predicate)
    }

    func setPersonality(_ personality: ConversationPersonality) {
        self.personality = personality
    }

    func stopCurrent() {
        guard let job = currentJob else { return }
        runningTask?.cancel()
        runningTask = nil
        currentJob = nil
        currentTask = nil
        job.onCancel()
        startNextIfNeeded()
    }

    func removeUpcoming(id: UUID) {
        guard let index = waitingJobs.firstIndex(where: { $0.id == id }) else { return }
        let job = waitingJobs.remove(at: index)
        job.onCancel()
        publishUpcomingTasks()
    }

    @discardableResult
    func moveUpcoming(id: UUID, relativeTo targetID: UUID, placeAfterTarget: Bool) -> Bool {
        guard id != targetID,
              let sourceIndex = waitingJobs.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let originalOrder = waitingJobs.map(\.id)
        let job = waitingJobs.remove(at: sourceIndex)
        guard let targetIndex = waitingJobs.firstIndex(where: { $0.id == targetID }) else {
            waitingJobs.insert(job, at: min(sourceIndex, waitingJobs.count))
            return false
        }

        let insertionIndex = min(
            targetIndex + (placeAfterTarget ? 1 : 0),
            waitingJobs.count
        )
        waitingJobs.insert(job, at: insertionIndex)
        guard waitingJobs.map(\.id) != originalOrder else {
            return false
        }

        publishUpcomingTasks()
        return true
    }

    func cancelTasks(where predicate: (ModelTaskSnapshot) -> Bool) {
        if let currentTask, predicate(currentTask) {
            let job = currentJob
            runningTask?.cancel()
            runningTask = nil
            currentJob = nil
            self.currentTask = nil
            job?.onCancel()
        }

        let cancelledJobs = waitingJobs.filter {
            predicate(snapshot(for: $0, phase: .upcoming))
        }
        waitingJobs.removeAll {
            predicate(snapshot(for: $0, phase: .upcoming))
        }
        cancelledJobs.forEach { $0.onCancel() }
        publishUpcomingTasks()
        startNextIfNeeded()
    }

    func clearCompletedTasks() {
        completedTasksClearTask?.cancel()
        completedTasksClearTask = nil
        completedTasks.removeAll()
    }

    func markUserQuestionsViewed(branchIDs: Set<UUID>) {
        completedUserQuestionBranchIDs.subtract(branchIDs)
    }

    func setApplicationActive(_ isActive: Bool) {
        applicationIsActive = isActive
        if isActive {
            // Returning to the foreground must ALWAYS resume execution. This previously bailed
            // out whenever an unload transition was still in flight
            // (`guard lifecycleTransitionTask == nil else { return }`), deferring entirely to
            // that task to clear `isExecutionSuspended` on its way out. But that task waits for
            // every generation lease to be released, so a generation that never finishes pinned
            // it forever: `isExecutionSuspended` stayed true, `startNextIfNeeded()` never ran
            // again, and the queue sat permanently dead — Model Status reading "Idle" while the
            // user's question waited in `upcomingTasks` — until the app was relaunched. Coming
            // back to the foreground is exactly when we want the pending unload abandoned, so
            // cancel it and resume unconditionally.
            lifecycleTransitionGeneration &+= 1
            lifecycleTransitionTask?.cancel()
            lifecycleTransitionTask = nil
            isExecutionSuspended = false
            startNextIfNeeded()
        } else {
            beginImmediateUnload(reason: .background)
        }
    }

    func handleMemoryPressure() {
        beginImmediateUnload(reason: .memoryPressure)
    }

    func updateThermalPressure(_ pressure: ModelRuntimeThermalPressure) {
        Task { [weak self] in
            guard let self else { return }
            await runtimeLifecycle.updateThermalPressure(pressure)
            guard pressure == .critical else { return }
            beginImmediateUnload(reason: .criticalThermalPressure)
        }
    }

    private func startNextIfNeeded() {
        guard !isExecutionSuspended,
              currentJob == nil,
              !waitingJobs.isEmpty else {
            publishUpcomingTasks()
            scheduleCompletedTasksClearIfIdle()
            return
        }

        completedTasksClearTask?.cancel()
        completedTasksClearTask = nil
        let job = waitingJobs.removeFirst()
        currentJob = job
        currentTask = snapshot(for: job, phase: .current)
        publishUpcomingTasks()
        job.onStart()

        runningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let requiresLoading = await runtimeLifecycle.requiresLoadingForNextLease()
            setRuntimeLoading(requiresLoading, for: job.id)
            guard let lease = await runtimeLifecycle.acquireLease() else {
                setRuntimeLoading(false, for: job.id)
                guard !Task.isCancelled else { return }
                failCurrent(id: job.id)
                return
            }
            setRuntimeLoading(false, for: job.id)
            guard !Task.isCancelled else {
                await runtimeLifecycle.releaseLease(lease)
                return
            }
            await job.operation()
            await runtimeLifecycle.releaseLease(lease)
            guard !Task.isCancelled else { return }
            completeCurrent(id: job.id)
        }
    }

    private func setRuntimeLoading(_ isLoading: Bool, for jobID: UUID) {
        guard currentJob?.id == jobID else { return }
        isRuntimeLoading = isLoading
    }

    private func failCurrent(id: UUID) {
        guard let job = currentJob, job.id == id else { return }
        isRuntimeLoading = false
        currentJob = nil
        currentTask = nil
        runningTask = nil
        job.onCancel()
        startNextIfNeeded()
    }

    private func completeCurrent(id: UUID) {
        guard let job = currentJob, job.id == id else { return }
        isRuntimeLoading = false
        let completedTask = snapshot(for: job, phase: .completed)
        completedTasks.append(completedTask)
        latestCompletedTask = completedTask
        if let branchID = job.kind.userQuestionBranchID {
            completedUserQuestionBranchIDs.insert(branchID)
        }
        currentJob = nil
        currentTask = nil
        runningTask = nil
        startNextIfNeeded()
    }

    private func beginImmediateUnload(reason: ModelRuntimeUnloadReason) {
        isExecutionSuspended = true
        preemptCurrentBackgroundPreservingJob()
        guard lifecycleTransitionTask == nil else { return }

        lifecycleTransitionGeneration &+= 1
        let generation = lifecycleTransitionGeneration
        lifecycleTransitionTask = Task { [weak self] in
            guard let self else { return }
            await runtimeLifecycle.unloadAsSoonAsIdle(reason: reason)
            // A foreground return (or a newer unload) bumps the generation and takes ownership
            // of this state — never let a superseded transition clear a live task or unsuspend
            // execution behind it.
            guard generation == lifecycleTransitionGeneration else { return }
            lifecycleTransitionTask = nil
            guard applicationIsActive else { return }
            isExecutionSuspended = false
            startNextIfNeeded()
        }
    }

    private func preemptCurrentBackgroundPreservingJob() {
        guard let currentJob,
              currentJob.priority == .background else {
            return
        }
        runningTask?.cancel()
        runningTask = nil
        self.currentJob = nil
        currentTask = nil
        isRuntimeLoading = false
        waitingJobs.insert(currentJob, at: 0)
        publishUpcomingTasks()
    }

    private func publishUpcomingTasks() {
        upcomingTasks = waitingJobs.map { snapshot(for: $0, phase: .upcoming) }
    }

    /// Inserts newly queued work into its normal priority group without disturbing any
    /// explicit ordering the person has already established by dragging pending tasks.
    private func defaultInsertionIndex(for priority: ModelTaskPriority) -> Int {
        guard priority == .foreground else {
            return waitingJobs.endIndex
        }

        if let lastForegroundIndex = waitingJobs.lastIndex(where: {
            $0.priority == .foreground
        }) {
            return waitingJobs.index(after: lastForegroundIndex)
        }

        return waitingJobs.firstIndex(where: {
            $0.priority == .background
        }) ?? waitingJobs.endIndex
    }

    private func scheduleCompletedTasksClearIfIdle() {
        guard !isBusy, !completedTasks.isEmpty else { return }

        completedTasksClearTask?.cancel()
        completedTasksClearTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, !self.isBusy else { return }
            self.completedTasks.removeAll()
            self.completedTasksClearTask = nil
        }
    }

    private func snapshot(for job: Job, phase: ModelTaskPhase) -> ModelTaskSnapshot {
        ModelTaskSnapshot(
            id: job.id,
            kind: job.kind,
            originPage: job.originPage,
            conversationID: job.conversationID,
            phase: phase,
            funStatusText: job.funStatusText,
            funLoadingStatusText: job.funLoadingStatusText
        )
    }
}
