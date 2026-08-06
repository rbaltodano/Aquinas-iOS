// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import OSLog
import CLiteRTLM

/// Manages the lifecycle of a LiteRT-LM engine, providing an interface for interacting with the
/// underlying native library.
///
/// Example usage:
/// ```
/// let config = try EngineConfig(modelPath: "...")
/// let engine = Engine(engineConfig: config)
/// try await engine.initialize()
/// ```
public actor Engine {
  private let logger = Logger(
    subsystem: "com.google.odml.litertlm.swift",
    category: "Engine"
  )

  /// The configuration for the engine.
  public let engineConfig: EngineConfig

  /// The native handle to the LiteRT-LM engine. A non-nil value indicates an initialized engine.
  private var handle: OpaquePointer? = nil

  /// - Parameter engineConfig: The configuration for the engine.
  public init(engineConfig: EngineConfig) {
    self.engineConfig = engineConfig
  }

  /// Returns `true` if the engine is initialized and ready for use; `false` otherwise.
  public func isInitialized() -> Bool {
    return handle != nil
  }

  /// Initializes the native LiteRT-LM engine.
  ///
  /// **Note:** This operation can take a significant amount of time (e.g., 10 seconds) depending on
  /// the model size and device hardware. It is strongly recommended to call this method on a
  /// background thread to avoid blocking the main thread.
  ///
  /// - Throws: A `LiteRTLMError` if the engine fails to initialize.
  public func initialize() async throws {
    try await initializeInternal(benchmarkPrefillTokens: nil, benchmarkDecodeTokens: nil)
  }

  /// Initializes the native LiteRT-LM engine specifically for benchmarking, avoiding global state params.
  func initializeForBenchmark(prefillTokens: Int, decodeTokens: Int) async throws {
    try await initializeInternal(
      benchmarkPrefillTokens: prefillTokens, benchmarkDecodeTokens: decodeTokens)
  }

  private func initializeInternal(
    benchmarkPrefillTokens: Int?, benchmarkDecodeTokens: Int?
  ) async throws {
    if isInitialized() {
      throw LiteRTLMError.engine(.alreadyInitialized)
    }

    let config = engineConfig
    // Runs the blocking native call off the actor's own cooperative-pool thread — see
    // `runOffCooperativePool`'s doc comment for why.
    let engine = try await Self.runOffCooperativePool {
      try Self.createNativeEngineHandle(
        config: config,
        benchmarkPrefillTokens: benchmarkPrefillTokens,
        benchmarkDecodeTokens: benchmarkDecodeTokens
      )
    }

    self.handle = engine
  }

  /// Pure construction of the native engine handle, with no actor-isolated state touched, so it
  /// can run on a dedicated off-pool thread via `runOffCooperativePool` instead of blocking the
  /// actor's own executor.
  private static func createNativeEngineHandle(
    config: EngineConfig,
    benchmarkPrefillTokens: Int?,
    benchmarkDecodeTokens: Int?
  ) throws -> OpaquePointer {
    // Convert the enums to strings for passing to the native library.
    let backendStr = config.backend.rawValue
    let visionBackendStr = config.visionBackend?.rawValue
    let audioBackendStr = config.audioBackend?.rawValue

    let settings = litert_lm_engine_settings_create(
      config.modelPath, backendStr, visionBackendStr, audioBackendStr)

    guard let settings else {
      throw LiteRTLMError.engine(.failedToCreateSettings)
    }

    defer { litert_lm_engine_settings_delete(settings) }

    if let maxNumTokens = config.maxNumTokens {
      litert_lm_engine_settings_set_max_num_tokens(settings, Int32(maxNumTokens))
    }
    if let cacheDir = config.cacheDir {
      litert_lm_engine_settings_set_cache_dir(settings, cacheDir)
    }
    if let loraRank = config.loraRank {
      litert_lm_engine_settings_set_lora_rank(settings, Int32(loraRank))
      if loraRank > 0 {
        var ranks = [Int32(loraRank)]
        let status = litert_lm_engine_settings_set_supported_lora_ranks(settings, &ranks, 1)
        guard status == 0 else {
          throw LiteRTLMError.engine(.failedToSetSupportedLoraRanks)
        }
      }
    }
    if let audioLoraRank = config.audioLoraRank {
      litert_lm_engine_settings_set_audio_lora_rank(settings, Int32(audioLoraRank))
      if audioLoraRank > 0 {
        var ranks = [Int32(audioLoraRank)]
        let status = litert_lm_engine_settings_set_supported_audio_lora_ranks(settings, &ranks, 1)
        guard status == 0 else {
          throw LiteRTLMError.engine(.failedToSetSupportedAudioLoraRanks)
        }
      }
    }
    if let prefill = benchmarkPrefillTokens, let decode = benchmarkDecodeTokens {
      litert_lm_engine_settings_enable_benchmark(settings)
      litert_lm_engine_settings_set_num_prefill_tokens(settings, Int32(prefill))
      litert_lm_engine_settings_set_num_decode_tokens(settings, Int32(decode))
    } else if ExperimentalFlags.enableBenchmark {
      litert_lm_engine_settings_enable_benchmark(settings)
    }
    if let enableSpeculativeDecoding = ExperimentalFlags.enableSpeculativeDecoding {
      litert_lm_engine_settings_set_enable_speculative_decoding(settings, enableSpeculativeDecoding)
    }

    guard let engine = litert_lm_engine_create(settings) else {
      throw LiteRTLMError.engine(.failedToCreateEngine)
    }

    return engine
  }

  /// Creates a new `Conversation` from the initialized engine.
  ///
  /// - Parameter ConversationConfig: The configuration for the conversation.
  /// - Returns: `Conversation` The created conversation.
  /// - Throws: A `LiteRTLMError` if the conversation creation fails.
  ///
  public func createConversation(with config: ConversationConfig? = nil) async throws
    -> Conversation
  {
    guard isInitialized() else {
      throw LiteRTLMError.engine(.notInitialized)
    }

    // We can force unwrap handle here because the engine is guaranteed to be initialized, and
    // initialization will set the handle.
    let engineHandle = self.handle!
    let conversationConfig = config ?? ConversationConfig()

    // Runs the blocking native call off the actor's own cooperative-pool thread. `Engine`'s
    // executor is otherwise one of the app's few Swift Concurrency worker threads, and this
    // specific native call (`litert_lm_conversation_create`) has been observed, via device
    // console capture, to occasionally hang indefinitely inside a known upstream deadlock
    // (`DEADLINE_EXCEEDED` in the native library's single-worker `callback_thread_pool`). Left
    // on the actor's executor, a hang here would tie up a shared worker thread for as long as
    // the hang lasts, which can starve every other actor-isolated task in the app — including
    // our own stall watchdog — leaving it unable to ever notice and recover. See
    // `runOffCooperativePool`'s doc comment for the mechanism.
    let (conversationHandle, toolManager) = try await Self.runOffCooperativePool {
      try Self.createNativeConversation(
        engineHandle: engineHandle,
        conversationConfig: conversationConfig
      )
    }

    return Conversation(handle: conversationHandle, toolManager: toolManager)
  }

  /// Pure construction of the native conversation handle, with no actor-isolated state touched,
  /// so it can run on a dedicated off-pool thread via `runOffCooperativePool`.
  private static func createNativeConversation(
    engineHandle: OpaquePointer,
    conversationConfig: ConversationConfig
  ) throws -> (handle: OpaquePointer, toolManager: ToolManager) {
    let systemMessage = conversationConfig.systemMessage
    let initialSystemMessageCount = conversationConfig.initialMessages.filter { $0.role == .system }
      .count

    if systemMessage != nil && initialSystemMessageCount > 0 {
      throw LiteRTLMError.config(.multipleSystemMessages)
    }
    if initialSystemMessageCount > 1 {
      throw LiteRTLMError.config(.multipleSystemMessages)
    }

    let toolManager = ToolManager(tools: conversationConfig.tools)

    let systemMessageJsonStr = (try? conversationConfig.systemMessage?.contents.jsonString) ?? ""
    let toolDescriptionJsonStr = toolManager.toolsJsonDescription

    let initialMessagesJson = conversationConfig.initialMessages.map { $0.toJson }
    let messagesJsonStr: String
    if !initialMessagesJson.isEmpty,
      let messagesData = try? JSONSerialization.data(
        withJSONObject: initialMessagesJson, options: []),
      let serializedStr = String(data: messagesData, encoding: .utf8)
    {
      messagesJsonStr = serializedStr
    } else {
      messagesJsonStr = ""
    }

    let cSessionConfig = litert_lm_session_config_create()
    guard let cSessionConfig else {
      throw LiteRTLMError.engine(.failedToCreateSessionConfig)
    }
    defer { litert_lm_session_config_delete(cSessionConfig) }

    if let samplerParams = conversationConfig.samplerConfig {
      guard let cSamplerParams = litert_lm_sampler_params_create(kLiteRtLmSamplerTypeTopP) else {
        throw LiteRTLMError.engine(.failedToCreateSessionConfig)
      }
      defer { litert_lm_sampler_params_delete(cSamplerParams) }

      litert_lm_sampler_params_set_top_k(cSamplerParams, Int32(samplerParams.topK))
      litert_lm_sampler_params_set_top_p(cSamplerParams, samplerParams.topP)
      litert_lm_sampler_params_set_temperature(cSamplerParams, samplerParams.temperature)
      litert_lm_sampler_params_set_seed(cSamplerParams, Int32(samplerParams.seed))

      litert_lm_session_config_set_sampler_params(cSessionConfig, cSamplerParams)
    }

    if let loraPath = conversationConfig.loraPath {
      let status = litert_lm_session_config_set_lora_path(cSessionConfig, loraPath)
      guard status == 0 else {
        throw LiteRTLMError.engine(.failedToSetLoraPath)
      }
    }

    if let audioLoraPath = conversationConfig.audioLoraPath {
      let status = litert_lm_session_config_set_audio_lora_path(cSessionConfig, audioLoraPath)
      guard status == 0 else {
        throw LiteRTLMError.engine(.failedToSetAudioLoraPath)
      }
    }

    guard let cConversationConfig = litert_lm_conversation_config_create() else {
      throw LiteRTLMError.engine(.failedToCreateConversationConfig)
    }
    defer { litert_lm_conversation_config_delete(cConversationConfig) }

    litert_lm_conversation_config_set_session_config(cConversationConfig, cSessionConfig)
    if !systemMessageJsonStr.isEmpty {
      litert_lm_conversation_config_set_system_message(cConversationConfig, systemMessageJsonStr)
    }
    if !toolDescriptionJsonStr.isEmpty {
      litert_lm_conversation_config_set_tools(cConversationConfig, toolDescriptionJsonStr)
    }
    if !messagesJsonStr.isEmpty {
      litert_lm_conversation_config_set_messages(cConversationConfig, messagesJsonStr)
    }
    litert_lm_conversation_config_set_enable_constrained_decoding(
      cConversationConfig, ExperimentalFlags.enableConversationConstrainedDecoding)
    litert_lm_conversation_config_set_stream_tool_calls(
      cConversationConfig,
      conversationConfig.enableToolCallStreaming
        && ExperimentalFlags.enableConversationToolCallStreaming,
      ExperimentalFlags.conversationToolCallStreamingChannelName)

    guard
      let conversationHandle = litert_lm_conversation_create(
        engineHandle, cConversationConfig)
    else {
      throw LiteRTLMError.engine(.failedToCreateConversation)
    }

    return (conversationHandle, toolManager)
  }

  /// Runs a blocking synchronous closure on a dedicated, disposable OS thread instead of one of
  /// Swift Concurrency's small, shared cooperative-pool threads (roughly one per CPU core,
  /// shared by every actor and Task in the whole app). The native LiteRT-LM calls wrapped with
  /// this are genuine blocking FFI calls that never yield back to the caller, and have been
  /// observed, via device console capture, to occasionally hang indefinitely inside a known
  /// upstream deadlock. Run directly on an actor's own executor, a hang like that would
  /// permanently consume one of the app's few shared worker threads — starving every other
  /// actor-isolated task in the app, including a stall-detection watchdog that specifically
  /// exists to notice and recover from exactly this kind of hang. A dedicated thread means a
  /// hang here costs one throwaway thread, never a shared one.
  private static func runOffCooperativePool<T>(
    _ work: @escaping @Sendable () throws -> T
  ) async throws -> T where T: Sendable {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      let thread = Thread {
        do {
          let value = try work()
          continuation.resume(returning: value)
        } catch {
          continuation.resume(throwing: error)
        }
      }
      thread.stackSize = 1 << 20
      thread.start()
    }
  }

  deinit {
    // Same reasoning as `Conversation.deinit`: never block whatever thread/executor drops the
    // last reference on a native call that can hang.
    if let handle = handle {
      let handleToDelete = handle
      Thread {
        litert_lm_engine_delete(handleToDelete)
      }.start()
    }
  }
}

extension OpaquePointer: @unchecked @retroactive Sendable {}
