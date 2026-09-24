//
//  LiteRTAquinasRuntime.swift
//  Aquinas-iOS
//

import Foundation
import LiteRTLM
import OSLog

/// Resumes a `CheckedContinuation` at most once, whichever of two racing unstructured `Task`s
/// gets there first. A plain `Task.isCancelled` check isn't enough here since the loser (a
/// wedged native call) never reaches its own cancellation checkpoint — this lock is what actually
/// prevents a double-resume when both sides eventually try.
nonisolated private final class StallRaceBox<T>: @unchecked Sendable {
    private let continuation: CheckedContinuation<T, Error>
    private let lock = NSLock()
    private var didResume = false

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let shouldResume = !didResume
        didResume = true
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: result)
    }
}

nonisolated enum LiteRTAquinasRuntimeError: LocalizedError, Sendable {
    case modelNotLoaded
    case emptyResponse
    case repetitiveResponse
    case corruptResponse
    case stalledGeneration

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
        case .stalledGeneration:
            "The on-device model stopped producing output."
        }
    }
}

/// Owns the process-wide LiteRT engine and at most one active native conversation. The
/// `ModelTaskQueue` supplies exclusive generation leases; actor isolation additionally protects
/// direct callers and makes cancellation safe.
actor LiteRTAquinasRuntime: ModelRuntimeDriver {
    let supportsUnloading = true

    private let modelStore: LiteRTModelStore
#if DEBUG
    private var evidenceExperimentUsesCPU = false

    func configureEvidenceExperimentCPU() {
        precondition(engine == nil)
        evidenceExperimentUsesCPU = true
    }
#endif
    private var engine: Engine?
    private var activeConversation: Conversation?
    private var lastLoadError: Error?
    private var completedGenerations = 0
    private var pendingTeardownDrain = false
    private var generationSlotHeld = false
    private var generationWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastTokenAt: ContinuousClock.Instant = .now
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aquinas",
        category: "LiteRTAquinasRuntime"
    )

    private static let generationsBeforeRefresh = 4
    /// Native decoding has no built-in time cutoff (by design — see MODEL-INTEGRATION.md), so a
    /// wedged call would otherwise hang indefinitely with no recovery short of the user finding
    /// Model Tasks and tapping Stop. This only fires when literally nothing has streamed back for
    /// this long — generous relative to the ~1.3s/sentence baseline — so it never interrupts a
    /// merely slow but progressing generation, only a genuinely stalled one.
    private static let stallTimeout: Duration = .seconds(45)
    /// Guards `initializeEngine()` specifically — cold load has measured ~4-5s in production, so
    /// this stays well clear of ordinary variance while still catching a genuinely wedged load.
    private static let loadStallTimeout: Duration = .seconds(60)

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
        // Deliberately no `activeConversation.cancel()` here — confirmed via device console
        // capture that `litert_lm_conversation_cancel_process` can leave the native
        // `callback_thread_pool` (a single-worker pool) permanently stuck on
        // DEADLINE_EXCEEDED, wedging every later generation for the rest of the process. This
        // runs on every periodic engine refresh (`generationsBeforeRefresh`) and error-recovery
        // reinit — among the most frequently hit automatic paths in the app — so it was the
        // single biggest source of the "works once, then hangs forever" pattern. Simply
        // dropping the references is safe: the orphaned native call (if any) keeps running
        // against its own ARC-retained `Conversation`/`Engine` until it finishes on its own;
        // nothing dangles.
        //
        // v0.14.0 of the vendored LiteRTLM package removed explicit close() from both
        // Conversation and Engine; native cleanup now happens in deinit when the last
        // strong reference is released, so dropping these references is the teardown.
        activeConversation = nil
        engine = nil
    }

    func generate(
        systemInstruction: String,
        initialMessages: [Message] = [],
        message: Message,
        sampling: LiteRTSampling = .conversation,
        onText: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        try await withGenerationSlot(sampling: sampling) { attemptSampling in
            try await self.generateOnce(
                systemInstruction: systemInstruction,
                initialMessages: initialMessages,
                message: message,
                sampling: attemptSampling,
                onText: onText
            )
        }
    }

    /// Shared serialization/refresh/retry scaffolding behind `generate`, parameterized by the
    /// actual per-attempt work so callers don't duplicate the slot, teardown-drain,
    /// periodic-refresh, or one-shot-recovery-retry logic.
    private func withGenerationSlot<T: Sendable>(
        sampling: LiteRTSampling,
        _ attempt: @Sendable (LiteRTSampling) async throws -> T
    ) async throws -> T {
        try await acquireGenerationSlot()
        defer { releaseGenerationSlot() }
        try Task.checkCancellation()

        if pendingTeardownDrain {
            try await drainNativeTeardown()
            pendingTeardownDrain = false
        }

        if completedGenerations >= Self.generationsBeforeRefresh {
            await unloadModelWeights()
            try await initializeEngineWithWatchdog()
            try await drainNativeTeardown()
        }

        do {
            let result = try await attempt(sampling)
            completedGenerations += 1
            return result
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            logger.error(
                "Local generation attempt failed: \(String(reflecting: error), privacy: .public)"
            )
            Self.debugConsoleLog("attempt failed: \(String(reflecting: error))")

            // A genuine stall (the watchdog gave up waiting for any native progress at all —
            // see `racingStall`) has been observed, via device console capture, to reproduce
            // identically on an immediate reinit-and-retry: the native engine reloads cleanly
            // both times, but conversation creation itself hangs the same way again, so the
            // retry just pays the full stall window a second time for no benefit — 90+ seconds
            // of "Thinking..." with zero user-visible feedback before the eventual failure.
            // Fail fast instead; only retry for other error shapes, where a fresh session has
            // actually been observed to recover.
            if case LiteRTAquinasRuntimeError.stalledGeneration = error {
                throw error
            }

            // A completed native Conversation can occasionally leave the mobile session unable
            // to create the next conversation. Rebuild the engine once and retry locally before
            // allowing the model boundary to use network recovery.
            await unloadModelWeights()
            try await initializeEngineWithWatchdog()
            try await drainNativeTeardown()
            do {
                let result = try await attempt(sampling.retryVariant)
                completedGenerations += 1
                return result
            } catch {
                logger.error(
                    "Local generation retry failed: \(String(reflecting: error), privacy: .public)"
                )
                Self.debugConsoleLog("retry failed: \(String(reflecting: error))")
                throw error
            }
        }
    }

    nonisolated private static func debugConsoleLog(_ message: String) {
#if DEBUG
        guard let data = "[LiteRTAquinasRuntime] \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
#endif
    }

    private func acquireGenerationSlot() async throws {
        if !generationSlotHeld {
            generationSlotHeld = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                generationWaiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelGenerationWait(id: id) }
        }
    }

    /// Removes a still-waiting caller from the FIFO queue and resumes it with cancellation,
    /// instead of leaving it queued forever. Without this, a background task (e.g. Question of
    /// the Day) preempted while still waiting for the slot — its wrapping Task gets cancelled by
    /// `ModelTaskQueue`, but a plain non-throwing continuation ignores cancellation entirely —
    /// would sit as a permanent squatter, later winning the slot ahead of the actually-desired
    /// next request and forcing it to wait behind an abandoned generation nobody is listening
    /// for anymore.
    private func cancelGenerationWait(id: UUID) {
        guard let index = generationWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = generationWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseGenerationSlot() {
        if generationWaiters.isEmpty {
            generationSlotHeld = false
        } else {
            let waiter = generationWaiters.removeFirst()
            waiter.continuation.resume()
        }
    }

    // The dynamic_wi8_emb4_afp32 package's vision tower fails to load (STABLEHLO_COMPOSITE
    // prepare failure). Text generation is unaffected. Ship text-only until that's fixed;
    // re-enable (.gpu) once a vision-capable package passes the same load gate.
    private static let visionBackend: Backend? = nil

    /// `Engine.close()` deletes the native handle synchronously, but the GPU backend's own
    /// worker pool can still be finishing teardown from the just-closed engine when the next
    /// engine starts its first Prefill. Give that teardown time to fully drain before use.
    private func drainNativeTeardown() async throws {
        try? await Task.sleep(for: .milliseconds(400))
    }

    private func initializeEngine() async throws {
        let modelURL = try modelStore.installedModelURL()
        let cacheURL = try modelStore.cacheDirectory()
        var backend: Backend = .gpu
#if DEBUG
        if evidenceExperimentUsesCPU { backend = .cpu() }
#endif
        let config = try EngineConfig(
            modelPath: modelURL.path,
            backend: backend,
            visionBackend: Self.visionBackend,
            maxNumTokens: 4_096,
            cacheDir: cacheURL.path
        )
        let newEngine = Engine(engineConfig: config)
        try await newEngine.initialize()
        engine = newEngine
        lastLoadError = nil
        completedGenerations = 0
    }

    /// A hung `initializeEngine()` sits outside `generateOnce`'s own watchdog entirely — it runs
    /// in `generate()` before that call even starts — and would otherwise leave the actor's
    /// generation slot held forever, blocking every later call (including from unrelated model
    /// tasks) behind it indefinitely. Generous relative to the ~4-5s cold load this build has
    /// measured, so it only fires on a genuine hang, not ordinary load variance.
    private func initializeEngineWithWatchdog() async throws {
        try await Self.abandoningStall(timeout: Self.loadStallTimeout) {
            try await self.initializeEngine()
        } onTimeout: {}
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

        // Conversation creation is itself a native call and has hung in practice — it needs its
        // own watchdog race, not to run unguarded before streaming's, or a wedged create leaves
        // this whole call (and the generation slot every later call queues behind) blocked
        // forever with no watchdog ever having started.
        let conversation = try await racingStall {
            try await self.makeConversation(
                engine: engine,
                systemInstruction: systemInstruction,
                initialMessages: initialMessages,
                sampling: sampling
            )
        }
        do {
            let result = try await racingStall {
                try await self.streamText(
                    on: conversation,
                    message: message,
                    // The repetition/corruption guard was built for — and, per its own doc
                    // comment, deliberately requires substantial repetition before firing — free
                    // -form conversational prose, where a genuine degenerate greedy-decoding loop
                    // is the real risk. Confirmed via device console capture that it also fires
                    // on short structured JSON payloads: cutting a ~26-word label+summary off
                    // mid-string, before the closing `"}`, guarantees a JSON parse failure — a
                    // worse outcome than the rare case this guard exists to prevent. Structured
                    // calls are short and bounded already; skip it.
                    appliesDegenerateOutputGuard: !sampling.isStructured,
                    onText: onText
                )
            }
            await finishConversation()
            return result
        } catch {
            await finishConversation()
            throw error
        }
    }

    /// v0.14.0 removed explicit close(); dropping the last strong reference (here and by letting
    /// `activeConversation` go out of scope) triggers native cleanup in deinit.
    private func finishConversation() {
        activeConversation = nil
        pendingTeardownDrain = true
    }

    /// Races `operation` against a stall timeout WITHOUT `TaskGroup`'s implicit "wait for every
    /// child before returning" guarantee. That guarantee is exactly what made the previous
    /// task-group-based watchdog useless in practice: a genuinely wedged native call doesn't
    /// respect Swift's cooperative cancellation, so `withThrowingTaskGroup` kept blocking this
    /// function's return until the wedged child eventually finished (which was never) — the
    /// watchdog "won" internally but the caller never found out. Firing `operation` as a truly
    /// unstructured `Task` detaches it from that guarantee: a wedged call is simply abandoned
    /// (left running harmlessly in the background) instead of blocking the caller forever.
    private static func abandoningStall<T: Sendable>(
        timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T,
        onTimeout: @escaping @Sendable () -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let box = StallRaceBox(continuation)
            var watchdog: Task<Void, Never>?
            let work = Task {
                do {
                    let value = try await operation()
                    box.resume(.success(value))
                } catch {
                    box.resume(.failure(error))
                }
                watchdog?.cancel()
            }
            watchdog = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                onTimeout()
                box.resume(.failure(LiteRTAquinasRuntimeError.stalledGeneration))
                work.cancel()
            }
        }
    }

    /// Polls `runtime.lastTokenAt` every 5s instead of using a flat deadline, so streaming
    /// activity keeps resetting the clock and only a true no-progress stall fires the timeout.
    private static func abandoningStall<T: Sendable>(
        pollingAgainst runtime: LiteRTAquinasRuntime,
        _ operation: @escaping @Sendable @concurrent () async throws -> T,
        onTimeout: @escaping @Sendable () -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let box = StallRaceBox(continuation)
            var watchdog: Task<Void, Never>?
            let work = Task {
                do {
                    let value = try await operation()
                    box.resume(.success(value))
                } catch {
                    box.resume(.failure(error))
                }
                watchdog?.cancel()
            }
            watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    guard await runtime.secondsSinceLastToken() >= Self.seconds(Self.stallTimeout) else {
                        continue
                    }
                    onTimeout()
                    box.resume(.failure(LiteRTAquinasRuntimeError.stalledGeneration))
                    work.cancel()
                    return
                }
            }
        }
    }

    private func secondsSinceLastToken() -> Double {
        Self.seconds(lastTokenAt.duration(to: .now))
    }

    /// Convenience over `abandoningStall(pollingAgainst:)`: resets the stall clock and races
    /// `operation`. Used to guard each native phase (conversation creation, main answer,
    /// follow-up) as its own independent stall window rather than one window spanning all of
    /// them — so a stall in a later phase can be caught and swallowed by its caller without
    /// discarding an already-produced result from an earlier phase.
    ///
    /// Deliberately does NOT call `cancelCurrentGeneration()` on timeout or on the wrapping
    /// Task being cancelled (covers both a stall-watchdog firing and `ModelTaskQueue` preempting
    /// or stopping this job — they're indistinguishable at this layer). Confirmed via device
    /// console capture that `Conversation.cancel()` can leave the native `callback_thread_pool`
    /// (a single-worker pool) permanently stuck on DEADLINE_EXCEEDED, wedging every later
    /// generation for the rest of the process — far worse than just abandoning the call.
    private func racingStall<T: Sendable>(
        _ operation: @escaping @Sendable @concurrent () async throws -> T
    ) async throws -> T {
        lastTokenAt = .now
        return try await Self.abandoningStall(pollingAgainst: self, operation, onTimeout: {})
    }

    private func makeConversation(
        engine: Engine,
        systemInstruction: String,
        initialMessages: [Message],
        sampling: LiteRTSampling
    ) async throws -> Conversation {
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
        return conversation
    }

    private func streamText(
        on conversation: Conversation,
        message: Message,
        appliesDegenerateOutputGuard: Bool,
        onText: (@Sendable (String) async -> Void)?
    ) async throws -> String {
        var accumulated = ""
        do {
            for try await chunk in conversation.sendMessageStream(message) {
                try Task.checkCancellation()
                lastTokenAt = .now
                let text = chunk.toString
                guard !text.isEmpty else { continue }
                accumulated += text
                if appliesDegenerateOutputGuard {
                    if LiteRTGenerationGuard.hasMixedScriptCorruption(in: accumulated) {
                        throw LiteRTAquinasRuntimeError.corruptResponse
                    }
                    if let prefix = LiteRTGenerationGuard.responseBeforeRepetition(
                        in: accumulated
                    ) {
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
                }
                if let onText {
                    await onText(accumulated)
                }
            }
        } catch {
            if Task.isCancelled {
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
    }

    nonisolated private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

nonisolated struct LiteRTSampling: Sendable {
    static let conversation = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 0,
        isStructured: false
    )
    static let structured = LiteRTSampling(
        topK: 1,
        topP: 1,
        temperature: 0,
        seed: 7,
        isStructured: true
    )

    let topK: Int
    let topP: Float
    let temperature: Float
    let seed: Int
    /// Short, bounded JSON-contract calls (key terms, labels, definitions, this Insight Tree
    /// seed) vs. free-form conversational prose. Governs whether `streamText` applies the
    /// degenerate-repetition/corruption guard — see its call site's doc comment for why that
    /// guard is conversation-only.
    let isStructured: Bool

    var retryVariant: LiteRTSampling {
        guard seed == Self.conversation.seed else { return self }
        return LiteRTSampling(
            topK: 1,
            topP: 1,
            temperature: 0,
            seed: 0,
            isStructured: isStructured
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
