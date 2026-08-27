//
//  LiteRTDeviceProbe.swift
//  Aquinas-iOS
//

import LiteRTLM
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class LiteRTDeviceProbeModel {
    enum Phase: Equatable {
        case ready
        case locatingModel
        case loadingModel
        case generating
        case completed
        case failed

        var title: LocalizedStringResource {
            switch self {
            case .ready:
                "Ready"
            case .locatingModel:
                "Locating model"
            case .loadingModel:
                "Loading Aquinas"
            case .generating:
                "Generating on device"
            case .completed:
                "Probe passed"
            case .failed:
                "Probe failed"
            }
        }
    }

    private(set) var phase: Phase = .ready
    private(set) var detail = "The probe has not run yet."
    private(set) var response = ""
    private(set) var loadSeconds: Double?
    private(set) var generationSeconds: Double?
    private(set) var modelSizeBytes: Int64?
    private(set) var didStart = false

    private var engine: Engine?
    private var conversation: Conversation?
    private var productionRuntime: LiteRTAquinasRuntime?

    var copySummary: String {
        let sizeText = modelSizeBytes.map {
            ByteCountFormatStyle(
                style: .file,
                allowedUnits: [.gb],
                spellsOutZero: false,
                includesActualByteCount: false
            ).format($0)
        } ?? "—"
        let loadText = loadSeconds.map { "\($0.formatted(.number.precision(.fractionLength(2))))s" } ?? "—"
        let generationText = generationSeconds.map { "\($0.formatted(.number.precision(.fractionLength(2))))s" } ?? "—"
        return """
        Model size: \(sizeText)
        Cold load: \(loadText)
        Generation: \(generationText)
        Response: \(response)
        """
    }

    var isRunning: Bool {
        switch phase {
        case .locatingModel, .loadingModel, .generating:
            true
        case .ready, .completed, .failed:
            false
        }
    }

    func run() async {
        guard !didStart else { return }
        didStart = true

        if ProcessInfo.processInfo.arguments.contains("--litert-quality-probe") {
            await runConversationQualityProbe()
            return
        }

        phase = .locatingModel
        detail = "Looking for the local Aquinas LiteRT-LM package."
        response = ""
        loadSeconds = nil
        generationSeconds = nil
        modelSizeBytes = nil

        do {
            let modelURL = try Self.locateModel()
            modelSizeBytes = try modelURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)

            let cacheURL = try Self.cacheDirectory()
            let usesCPU = ProcessInfo.processInfo.arguments.contains(
                "--litert-probe-cpu"
            )
            let config = try EngineConfig(
                modelPath: modelURL.path,
                backend: usesCPU ? .cpu() : .gpu,
                maxNumTokens: 2_048,
                cacheDir: cacheURL.path
            )
            let engine = Engine(engineConfig: config)
            self.engine = engine

            phase = .loadingModel
            detail = "Initializing the Aquinas checkpoint with the Metal backend."
            let loadClock = ContinuousClock.now
            try await engine.initialize()
            loadSeconds = Self.seconds(since: loadClock)

            let sampler = try SamplerConfig(
                topK: 40,
                topP: 0.95,
                temperature: 0.2,
                seed: 7
            )
            let conversation = try await engine.createConversation(
                with: ConversationConfig(
                    systemMessage: Message(
                        "Answer clearly and in one concise sentence.",
                        role: .system
                    ),
                    samplerConfig: sampler
                )
            )
            self.conversation = conversation

            phase = .generating
            detail = "The response is being generated entirely on this iPhone."
            let generationClock = ContinuousClock.now
            let message = try await conversation.sendMessage(
                Message("What is prudence?")
            )
            generationSeconds = Self.seconds(since: generationClock)
            response = message.toString
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LiteRTDeviceProbeError.emptyResponse
            }

            phase = .completed
            detail = "Aquinas loaded and generated a non-empty response on device."
        } catch {
            phase = .failed
            detail = error.localizedDescription
        }
    }

    private func runConversationQualityProbe() async {
        phase = .locatingModel
        detail = "Looking for the local Aquinas LiteRT-LM package."
        response = ""
        loadSeconds = nil
        generationSeconds = nil
        modelSizeBytes = nil

        do {
            let modelURL = try Self.locateModel()
            modelSizeBytes = try modelURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize.map(Int64.init)

            let modelStore = LiteRTModelStore(
                manifest: LiteRTModelManifest(
                    fileName: modelURL.lastPathComponent,
                    byteCount: modelSizeBytes ?? 0,
                    sha256: "development-probe"
                ),
                developmentModelURL: modelURL
            )
            let runtime = LiteRTAquinasRuntime(modelStore: modelStore)
            productionRuntime = runtime
            phase = .loadingModel
            detail = "Initializing the production Aquinas conversation runtime."
            let loadClock = ContinuousClock.now
            try await runtime.loadModelWeights()
            loadSeconds = Self.seconds(since: loadClock)

            let question = Self.launchArgumentValue(
                after: "--litert-probe-question"
            ) ?? "How can justice and mercy work together when someone repeatedly does wrong?"
            let context = ConversationContext(
                transcript: [.user(question, nil, [])]
            )
            let model = LiteRTAquinasModel(
                runtime: runtime,
                fallback: BackendAquinasModel(
                    baseURL: URL(string: "http://127.0.0.1:9")!
                )
            )

            phase = .generating
            detail = "Testing production answer depth and repetition safeguards."
            let generationClock = ContinuousClock.now
            let result = await model.respond(
                to: context,
                thinkingEnabled: false,
                onUpdate: { _ in }
            )
            generationSeconds = Self.seconds(since: generationClock)
            response = result.text
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LiteRTDeviceProbeError.emptyResponse
            }
            if response.contains("couldn't reach the local Aquinas backend")
                || response.contains("on-device Aquinas model couldn't complete") {
                throw LiteRTDeviceProbeError.productionPathFailed(response)
            }

            phase = .completed
            detail = "The production conversation path completed locally with \(result.keyTerms.count) validated Insight links."
        } catch {
            phase = .failed
            detail = error.localizedDescription
        }
    }

    private static func locateModel() throws -> URL {
        let fileManager = FileManager.default
        let arguments = ProcessInfo.processInfo.arguments
        if let fileName = launchArgumentValue(
            after: "--litert-model-document"
        ),
        let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            let documentURL = documentsURL.appending(path: fileName)
            guard fileManager.fileExists(atPath: documentURL.path) else {
                throw LiteRTDeviceProbeError.modelMissing
            }
            return documentURL
        }
        if let flagIndex = arguments.firstIndex(of: "--litert-model-path"),
           arguments.indices.contains(flagIndex + 1) {
            let explicitURL = URL(filePath: arguments[flagIndex + 1])
            guard fileManager.fileExists(atPath: explicitURL.path) else {
                throw LiteRTDeviceProbeError.modelMissing
            }
            return explicitURL
        }
        let candidateURLs = [
            Bundle.main.url(
                forResource: "gemma-4-E2B-it",
                withExtension: "litertlm",
                subdirectory: "LocalModels"
            ),
            Bundle.main.url(
                forResource: "gemma-4-E2B-it",
                withExtension: "litertlm"
            ),
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appending(
                path: "Models/gemma-4-E2B-it.litertlm"
            )
        ].compactMap { $0 }

        guard let modelURL = candidateURLs.first(
            where: { fileManager.fileExists(atPath: $0.path) }
        ) else {
            throw LiteRTDeviceProbeError.modelMissing
        }
        return modelURL
    }

    private static func launchArgumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        let value = arguments[flagIndex + 1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func cacheDirectory() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTDeviceProbeError.cacheUnavailable
        }
        let directory = root.appending(path: "LiteRTLM")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func seconds(
        since start: ContinuousClock.Instant
    ) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}

private enum LiteRTDeviceProbeError: LocalizedError {
    case modelMissing
    case cacheUnavailable
    case emptyResponse
    case productionPathFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The Aquinas LiteRT-LM model is not installed in this build."
        case .cacheUnavailable:
            "The app could not create a writable LiteRT-LM cache."
        case .emptyResponse:
            "Aquinas initialized but returned an empty response."
        case .productionPathFailed(let message):
            "The production local path failed: \(message)"
        }
    }
}

struct LiteRTDeviceProbeView: View {
    @State private var model = LiteRTDeviceProbeModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LiteRTProbeHeader()
                LiteRTProbeStatus(model: model)
                LiteRTProbeMetrics(
                    modelSizeBytes: model.modelSizeBytes,
                    loadSeconds: model.loadSeconds,
                    generationSeconds: model.generationSeconds
                )
                LiteRTProbeResponse(response: model.response)
                Button {
                    Task {
                        await model.run()
                    }
                } label: {
                    Text(
                        model.isRunning
                            ? "Running…"
                            : model.didStart
                                ? "Probe finished"
                                : "Run device probe"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.didStart)
                if model.didStart {
                    Button {
                        UIPasteboard.general.string = model.copySummary
                    } label: {
                        Label("Copy results", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(AquinasTheme.Spacing.screenPadding)
        }
        .background(AquinasTheme.Colors.canvas)
        .task {
            guard ProcessInfo.processInfo.arguments.contains(
                "--litert-probe-auto"
            ) else {
                return
            }
            await model.run()
        }
    }
}

private struct LiteRTProbeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On-device model probe")
                .font(AquinasTheme.Typography.title)
                .foregroundStyle(AquinasTheme.Colors.headingText)
            Text(
                "This isolated diagnostic loads the fine-tuned Aquinas checkpoint through LiteRT-LM and generates one response entirely on this device or simulator."
            )
            .font(AquinasTheme.Typography.bodyLarge)
            .foregroundStyle(AquinasTheme.Colors.paragraphText)
        }
    }
}

private struct LiteRTProbeStatus: View {
    let model: LiteRTDeviceProbeModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.isRunning {
                ProgressView()
            } else {
                Image(
                    systemName: model.phase == .completed
                        ? "checkmark.circle.fill"
                        : model.phase == .failed
                            ? "xmark.circle.fill"
                            : "circle"
                )
                .foregroundStyle(
                    model.phase == .failed
                        ? AquinasTheme.Colors.accentRed
                        : AquinasTheme.Colors.accentGreen
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.phase.title)
                    .font(AquinasTheme.Typography.uiSubheading)
                Text(model.detail)
                    .font(AquinasTheme.Typography.body)
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
            }
        }
        .padding(AquinasTheme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AquinasTheme.Colors.componentBackground,
            in: RoundedRectangle(
                cornerRadius: AquinasTheme.Spacing.smallCardRadius
            )
        )
    }
}

private struct LiteRTProbeMetrics: View {
    let modelSizeBytes: Int64?
    let loadSeconds: Double?
    let generationSeconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements")
                .font(AquinasTheme.Typography.uiSubheading)
            LabeledContent(
                "Model size",
                value: modelSizeBytes.map(Self.formattedBytes) ?? "—"
            )
            LabeledContent(
                "Cold load",
                value: loadSeconds.map(Self.formattedSeconds) ?? "—"
            )
            LabeledContent(
                "Generation",
                value: generationSeconds.map(Self.formattedSeconds) ?? "—"
            )
        }
        .font(AquinasTheme.Typography.body)
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.gb],
            spellsOutZero: false,
            includesActualByteCount: false
        ).format(bytes)
    }

    private static func formattedSeconds(_ seconds: Double) -> String {
        seconds.formatted(
            .number.precision(.fractionLength(2))
        ) + " s"
    }
}

private struct LiteRTProbeResponse: View {
    let response: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response")
                .font(AquinasTheme.Typography.uiSubheading)
            Text(response.isEmpty ? "No response yet." : response)
                .font(AquinasTheme.Typography.bodyLarge)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
