//
//  LiteRTAquinasRuntime.swift
//  Aquinas-iOS
//

import Foundation
import LiteRTLM

nonisolated enum LiteRTAquinasRuntimeError: LocalizedError, Sendable {
    case modelNotLoaded
    case emptyResponse
    case repetitiveResponse
    case corruptResponse

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "The Aquinas on-device runtime is not loaded."
        case .emptyResponse:
            "Aquinas returned an empty response."
        case .repetitiveResponse:
            "The on-device model entered a repetitive response loop."
        case .corruptResponse:
            "The on-device model returned malformed mixed-script tokens."
        }
    }
}

/// Owns the process-wide LiteRT engine and at most one active native conversation. The
/// `ModelTaskQueue` supplies exclusive generation leases; actor isolation additionally protects
/// direct callers and makes cancellation safe.
actor LiteRTAquinasRuntime: ModelRuntimeDriver {
    let supportsUnloading = true

    private let modelStore: LiteRTModelStore
    private var engine: Engine?
    private var activeConversation: Conversation?
    private var lastLoadError: Error?
    private var completedGenerations = 0
    private var generationSlotHeld = false
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []

    private static let generationsBeforeRefresh = 4

    init(modelStore: LiteRTModelStore = LiteRTModelStore()) {
        self.modelStore = modelStore
    }

    func loadModelWeights() async throws {
        if let engine, await engine.isInitialized() {
            return
        }

        var finalError: Error?
        for attempt in 1...2 {
            do {
                try await initializeEngine()
                return
            } catch {
                engine = nil
                lastLoadError = error
                finalError = error
#if DEBUG
                print("Aquinas on-device model load attempt \(attempt) failed: \(error.localizedDescription)")
#endif
                if attempt == 1 {
                    try await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw finalError ?? LiteRTAquinasRuntimeError.modelNotLoaded
    }

    func unloadModelWeights() async {
        if let activeConversation {
            try? activeConversation.cancel()
            activeConversation.close()
        }
        activeConversation = nil
        if let engine {
            await engine.close()
        }
        engine = nil
    }

    func cancelCurrentGeneration() {
        try? activeConversation?.cancel()
    }

    func generate(
        systemInstruction: String,
        initialMessages: [Message] = [],
        message: Message,
        sampling: LiteRTSampling = .conversation,
        onText: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        await acquireGenerationSlot()
        defer { releaseGenerationSlot() }
        try Task.checkCancellation()

        if completedGenerations >= Self.generationsBeforeRefresh {
            await unloadModelWeights()
            try await initializeEngine()
        }

        do {
            let result = try await generateOnce(
                systemInstruction: systemInstruction,
                initialMessages: initialMessages,
                message: message,
                sampling: sampling,
                onText: onText
            )
            completedGenerations += 1
            return result
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
#if DEBUG
            print("Aquinas local generation attempt failed: \(String(reflecting: error))")
#endif

            // A completed native Conversation can occasionally leave the mobile session unable
            // to create the next conversation. Rebuild the engine once and retry locally before
            // allowing the model boundary to use network recovery.
            await unloadModelWeights()
            try await initializeEngine()
            do {
                let result = try await generateOnce(
                    systemInstruction: systemInstruction,
                    initialMessages: initialMessages,
                    message: message,
                    sampling: sampling.retryVariant,
                    onText: onText
                )
                completedGenerations += 1
                return result
            } catch {
#if DEBUG
                print("Aquinas local generation retry failed: \(String(reflecting: error))")
#endif
                throw error
            }
        }
    }

    private func acquireGenerationSlot() async {
        if !generationSlotHeld {
            generationSlotHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            generationWaiters.append(continuation)
        }
    }

    private func releaseGenerationSlot() {
        if generationWaiters.isEmpty {
            generationSlotHeld = false
        } else {
            generationWaiters.removeFirst().resume()
        }
    }

    private func initializeEngine() async throws {
        let modelURL = try modelStore.installedModelURL()
        let cacheURL = try modelStore.cacheDirectory()
        let config = try EngineConfig(
            modelPath: modelURL.path,
            backend: .gpu,
            visionBackend: .gpu,
            maxNumTokens: 4_096,
            cacheDir: cacheURL.path
        )
        let newEngine = Engine(engineConfig: config)
        try await newEngine.initialize()
        engine = newEngine
        lastLoadError = nil
        completedGenerations = 0
    }

    private func generateOnce(
        systemInstruction: String,
        initialMessages: [Message],
        message: Message,
        sampling: LiteRTSampling,
        onText: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        guard let engine, await engine.isInitialized() else {
            throw lastLoadError ?? LiteRTAquinasRuntimeError.modelNotLoaded
        }

        let sampler = try SamplerConfig(
            topK: sampling.topK,
            topP: sampling.topP,
            temperature: sampling.temperature,
            seed: sampling.seed
        )
        let conversation = try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: Message(systemInstruction, role: .system),
                initialMessages: initialMessages,
                samplerConfig: sampler
            )
        )
        activeConversation = conversation
        defer {
            conversation.close()
            activeConversation = nil
        }

        return try await withTaskCancellationHandler {
            var accumulated = ""
            do {
                for try await chunk in conversation.sendMessageStream(message) {
                    try Task.checkCancellation()
                    let text = chunk.toString
                    guard !text.isEmpty else { continue }
                    accumulated += text
                    if LiteRTGenerationGuard.hasMixedScriptCorruption(in: accumulated) {
                        try? conversation.cancel()
                        throw LiteRTAquinasRuntimeError.corruptResponse
                    }
                    if let prefix = LiteRTGenerationGuard.responseBeforeRepetition(
                        in: accumulated
                    ) {
                        try? conversation.cancel()
                        let cleanedPrefix = prefix.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard cleanedPrefix.split(whereSeparator: { $0.isWhitespace }).count >= 12 else {
                            throw LiteRTAquinasRuntimeError.repetitiveResponse
                        }
                        if let onText {
                            await onText(cleanedPrefix)
                        }
                        return cleanedPrefix
                    }
                    if let onText {
                        await onText(accumulated)
                    }
                }
            } catch {
                if Task.isCancelled {
                    try? conversation.cancel()
                    throw CancellationError()
                }
                throw error
            }

            let cleaned = accumulated.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !cleaned.isEmpty else {
                throw LiteRTAquinasRuntimeError.emptyResponse
            }
            return cleaned
        } onCancel: {
            Task {
                await self.cancelCurrentGeneration()
            }
        }
    }
}

nonisolated struct LiteRTSampling: Sendable {
    static let conversation = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 0
    )
    static let structured = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 7
    )

    let topK: Int
    let topP: Float
    let temperature: Float
    let seed: Int

    var retryVariant: LiteRTSampling {
        guard seed == Self.conversation.seed else { return self }
        return LiteRTSampling(
            topK: 1,
            topP: 1,
            temperature: 0,
            seed: 0
        )
    }
}

/// Rejects the exact phrase/sentence loops that greedy decoding can produce with quantized
/// weights. It deliberately requires substantial consecutive repetition so normal rhetorical
/// emphasis is not treated as a generation failure.
nonisolated enum LiteRTGenerationGuard {
    static func hasDegenerateOutput(in text: String) -> Bool {
        hasDegenerateRepetition(in: text) || hasMixedScriptCorruption(in: text)
    }

    static func hasDegenerateRepetition(in text: String) -> Bool {
        responseBeforeRepetition(in: text) != nil
    }

    static func responseBeforeRepetition(in text: String) -> String? {
        let sentences = text
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map(normalizedText)
            .filter { !$0.isEmpty }
        if sentences.count >= 2,
           let last = sentences.last,
           last.count >= 40,
           last == sentences[sentences.count - 2] {
            let repeatedSentence = String(
                text.split(whereSeparator: { ".!?\n".contains($0) }).last ?? ""
            )
            if let range = text.range(of: repeatedSentence, options: .backwards) {
                return String(text[..<range.lowerBound])
            }
        }

        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) else {
            return nil
        }
        let source = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        let words = matches.map {
            source.substring(with: $0.range).lowercased()
        }
        var earliestRepeatedLocation: Int?
        // A loop is not always adjacent or aligned with the end of the output. Find any exact,
        // substantial phrase that appears twice without overlapping itself.
        for windowSize in [10, 16, 24] where words.count >= windowSize * 2 {
            var firstPositionByPhrase: [String: Int] = [:]
            for start in 0...(words.count - windowSize) {
                let phrase = words[start..<(start + windowSize)]
                    .joined(separator: " ")
                if let firstPosition = firstPositionByPhrase[phrase],
                   start - firstPosition >= windowSize {
                    let location = matches[start].range.location
                    earliestRepeatedLocation = min(
                        earliestRepeatedLocation ?? location,
                        location
                    )
                    break
                }
                firstPositionByPhrase[phrase] = firstPositionByPhrase[phrase] ?? start
            }
        }
        guard let earliestRepeatedLocation else { return nil }
        return source.substring(
            with: NSRange(location: 0, length: earliestRepeatedLocation)
        )
    }

    /// The 4-bit checkpoint can collapse under sampling into long runs that mix CJK, Arabic, and
    /// Hangul fragments with malformed code-like tokens. A few non-Latin terms are valid, so this
    /// requires both a meaningful count and proportion before rejecting a draft.
    static func hasMixedScriptCorruption(in text: String) -> Bool {
        let letters = text.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        guard letters.count >= 40 else { return false }
        let suspiciousCount = letters.count(where: isUnexpectedScript)
        return suspiciousCount >= 12
            && Double(suspiciousCount) / Double(letters.count) >= 0.08
    }

    private static func isUnexpectedScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana and Katakana
             0x3400...0x9FFF, // CJK ideographs
             0xAC00...0xD7AF, // Hangul syllables
             0x0600...0x06FF: // Arabic
            true
        default:
            false
        }
    }

    private static func normalizedText<S: StringProtocol>(_ text: S) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
