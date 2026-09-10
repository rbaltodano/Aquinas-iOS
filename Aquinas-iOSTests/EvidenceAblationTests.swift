import Foundation
import LiteRTLM
import Testing
@testable import Aquinas_iOS

/// Opt-in simulator experiment. prepare.py creates the marker; remove it after use.
/// No corpus, application preferences, or saved conversations are modified.
struct EvidenceAblationTests {
    struct Reference: Codable { let title: String; let text: String }
    struct Job: Codable {
        let id: String
        let caseID: String
        let condition: String
        let question: String
        let references: [Reference]
    }
    struct Request: Decodable {
        let modelPath: String
        let outputPath: String
        let useCPU: Bool?
        let jobs: [Job]
    }
    struct Result: Codable {
        let job: Job
        let systemInstruction: String
        let answer: String?
        let error: String?
        let seconds: Double
    }

    @Test @MainActor
    func compareEvidence() async throws {
        let marker = URL(filePath: "/tmp/aquinas-evidence-ablation-request.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: marker))
        let output = URL(filePath: request.outputPath)
        var results = (try? JSONDecoder().decode([Result].self, from: Data(contentsOf: output))) ?? []
        let done = Set(results.map { $0.job.id })
        let runtime = LiteRTAquinasRuntime(modelStore: LiteRTModelStore(
            developmentModelURL: URL(filePath: request.modelPath)
        ))
        if request.useCPU == true { await runtime.configureEvidenceExperimentCPU() }
        try await runtime.loadModelWeights()
        for job in request.jobs where !done.contains(job.id) {
            let context = ConversationContext(transcript: [.user(job.question, nil, [])])
            let placeholder = AquinasGroundingReference(
                id: "experiment", title: "EVIDENCE_PLACEHOLDER", sourceName: "Corpus",
                facts: "EVIDENCE_PLACEHOLDER", retrievalAliases: []
            )
            // Keep every instruction identical across conditions, including the
            // relevance caveat in the production grounded prompt. Only evidence changes.
            let template = LiteRTAquinasModel.evidenceExperimentInstruction(
                context: context, references: [placeholder]
            )
            let evidence = job.references.isEmpty ? "No source passages supplied." :
                job.references.map { "[\($0.title) — Corpus]\n\($0.text)" }.joined(separator: "\n\n")
            let system = template.replacingOccurrences(of: placeholder.promptText, with: evidence)
            let start = Date()
            print("ABLATION START \(job.id)")
            let result: Result
            do {
                let answer = try await runtime.generate(
                    systemInstruction: system, message: Message(job.question), sampling: .conversation
                )
                result = Result(job: job, systemInstruction: system, answer: answer,
                                error: nil, seconds: Date().timeIntervalSince(start))
            } catch {
                result = Result(job: job, systemInstruction: system, answer: nil,
                                error: error.localizedDescription, seconds: Date().timeIntervalSince(start))
            }
            results.append(result)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .atomic)
            print("ABLATION DONE \(job.id) \(result.seconds)s error=\(result.error ?? "none")")
        }
        await runtime.unloadModelWeights()
        #expect(results.count == request.jobs.count)
    }
}
