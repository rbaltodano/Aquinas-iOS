//
//  InsightTreeAnalysisQueue.swift
//  Aquinas-iOS
//

import Foundation

struct PendingInsightTreeAnalysis: Codable, Equatable, Identifiable {
    let responseID: UUID
    let conversationID: UUID
    let branchID: UUID
    let responseIndex: Int
    var attemptCount: Int

    var id: UUID { responseID }
}

enum InsightTreeAnalysisQueue {
    // v2 intentionally leaves the original transcript-backfill queue behind. Analysis is now
    // enrolled only when a response finishes, so reopening a conversation cannot manufacture a
    // burst of historical Insight mutations.
    private static let storageKey = "aquinas.pendingInsightTreeAnalysis.v2"

    static func load() -> [PendingInsightTreeAnalysis] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let jobs = try? JSONDecoder().decode([PendingInsightTreeAnalysis].self, from: data) else {
            return []
        }
        return jobs
    }

    static func enqueue(_ job: PendingInsightTreeAnalysis) {
        var jobs = load()
        guard !jobs.contains(where: { $0.responseID == job.responseID }) else { return }
        jobs.append(job)
        save(jobs)
    }

    static func remove(responseID: UUID) {
        save(load().filter { $0.responseID != responseID })
    }

    static func recordFailedAttempt(responseID: UUID) {
        var jobs = load()
        guard let index = jobs.firstIndex(where: { $0.responseID == responseID }) else { return }
        jobs[index].attemptCount += 1
        save(jobs)
    }

    private static func save(_ jobs: [PendingInsightTreeAnalysis]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
