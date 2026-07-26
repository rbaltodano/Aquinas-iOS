//
//  ModelTaskQueue.swift
//  Aquinas-iOS
//

import Foundation
import Observation

enum ModelTaskKind: Hashable {
    case userQuestion(branchID: UUID, responseIndex: Int)
    case defineInsight(key: String, name: String)
    case updateInsightTree

    var title: String {
        switch self {
        case .userQuestion:
            return String(localized: "User Question")
        case .defineInsight(_, let name):
            return String(localized: "Define “\(name)”")
        case .updateInsightTree:
            return String(localized: "Update Insight Tree")
        }
    }

    var definitionKey: String? {
        guard case .defineInsight(let key, _) = self else { return nil }
        return key
    }
}

enum ModelTaskPhase: Equatable {
    case completed
    case current
    case upcoming
}

struct ModelTaskSnapshot: Identifiable, Equatable {
    let id: UUID
    let kind: ModelTaskKind
    let phase: ModelTaskPhase

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
        let onStart: () -> Void
        let onCancel: () -> Void
        let operation: () async -> Void
    }

    private(set) var completedTasks: [ModelTaskSnapshot] = []
    private(set) var currentTask: ModelTaskSnapshot?
    private(set) var upcomingTasks: [ModelTaskSnapshot] = []

    @ObservationIgnored private var currentJob: Job?
    @ObservationIgnored private var waitingJobs: [Job] = []
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var completedTasksClearTask: Task<Void, Never>?

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
        onStart: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        operation: @escaping () async -> Void
    ) -> UUID {
        completedTasksClearTask?.cancel()
        completedTasksClearTask = nil

        if !isBusy {
            completedTasks.removeAll()
        }

        let job = Job(
            id: UUID(),
            kind: kind,
            onStart: onStart,
            onCancel: onCancel,
            operation: operation
        )
        waitingJobs.append(job)
        publishUpcomingTasks()
        startNextIfNeeded()
        return job.id
    }

    func contains(where predicate: (ModelTaskSnapshot) -> Bool) -> Bool {
        allTasks.contains(where: predicate)
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

    func moveUpcoming(id: UUID, relativeTo targetID: UUID, placeAfterTarget: Bool) {
        guard id != targetID,
              let sourceIndex = waitingJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        let job = waitingJobs.remove(at: sourceIndex)
        guard let targetIndex = waitingJobs.firstIndex(where: { $0.id == targetID }) else {
            waitingJobs.insert(job, at: min(sourceIndex, waitingJobs.count))
            return
        }

        let insertionIndex = min(
            targetIndex + (placeAfterTarget ? 1 : 0),
            waitingJobs.count
        )
        waitingJobs.insert(job, at: insertionIndex)
        publishUpcomingTasks()
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

    private func startNextIfNeeded() {
        guard currentJob == nil, !waitingJobs.isEmpty else {
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

        runningTask = Task { [weak self] in
            await job.operation()
            guard !Task.isCancelled else { return }
            self?.completeCurrent(id: job.id)
        }
    }

    private func completeCurrent(id: UUID) {
        guard let job = currentJob, job.id == id else { return }
        completedTasks.append(snapshot(for: job, phase: .completed))
        currentJob = nil
        currentTask = nil
        runningTask = nil
        startNextIfNeeded()
    }

    private func publishUpcomingTasks() {
        upcomingTasks = waitingJobs.map { snapshot(for: $0, phase: .upcoming) }
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
        ModelTaskSnapshot(id: job.id, kind: job.kind, phase: phase)
    }
}
