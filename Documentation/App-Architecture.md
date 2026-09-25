# iOS application architecture

This document describes iOS-owned composition and state. Cross-repository model and persistence
contracts remain in [`MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md).

## Composition and ownership

`ContentView` owns the app shell: global navigation, settings, the global Insight Library canvas,
and handoff into `CurrentConversationView`. It conditionally mounts the conversation screen, so
state that must survive changing pages belongs at the shell level and is passed down through a
binding or durable store—not local `@State` in `CurrentConversationView`.

`CurrentConversationView` owns active conversation and branch presentation, the visible model-task
experience, conversation-scoped definition flow, slash-command handling, and durable retry of
response-driven Insight Tree analysis. `ModelTaskQueue` serializes questions, contextual
definitions, tree updates, and Question of the Day consolidation. Cancellation must keep the
visible pending/breathing state in sync.

The global Insight Library canvas is an in-memory, client-side semantic experience. The
conversation Insight Tree uses `InsightTreeService` and backend-owned MiniLM topology. Do not
recompute its persisted topology with the client `NLEmbeddingProvider`.

## Persistence boundaries

Conversation branches and chat blocks are persisted as one Codable snapshot in
`Application Support/Aquinas/ConversationStore/conversations-v1.json`. The file store writes
atomically, keeps up to five rotating JSON backups, and migrates either prior conversation
snapshot from `UserDefaults` on first successful load. `InquiryPersistenceStore` is the
process-facing boundary; `CurrentConversationsStore` is its compatibility name at existing call
sites. All snapshot I/O runs on one serial background queue (`SerializedInquiryStore`): saves
return immediately, loads and imports wait behind queued writes, and the shell flushes the queue
when the scene moves to the background. Saved Insights and identifiers-only coordination stores remain in `UserDefaults`, including
conversation-to-global-Insight membership and pending tree-analysis IDs. See
[`PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md`](../../Aquinas-Foundations/PERSISTENT_MEMORY_IMPLEMENTATION_PLAN.md)
for the planned SwiftData migration.

The backend separately persists conversation-scoped definitions and Insight Tree content in
SQLite. It is a development-time persistence boundary, not cloud sync.

## Important seams

| Area | Primary location |
| --- | --- |
| App shell and page handoff | `Aquinas-iOS/App/ContentView.swift` |
| Conversation orchestration | `Features/Conversation/CurrentConversation.swift` |
| Transcript and response lifecycle | `Features/Conversation/ConversationComponents.swift` |
| Visible model tasks | `Features/Conversation/ModelTaskQueue.swift` |
| Model status and context controls | `Features/Conversation/InquiryControlDock.swift` |
| Model boundary and local implementation | `Services/AquinasModel.swift`, `Services/LiteRTAquinasModel.swift` |
| Runtime ownership | `Services/AquinasApplicationRuntime.swift`, `Services/LiteRTAquinasRuntime.swift` |
| Backend tree boundary | `Services/InsightTreeService.swift` |
| Durable tree-analysis retry IDs | `Persistence/InsightTreeAnalysisQueue.swift` |

## Current product constraints

Only `/compact` and `/clear` are supported slash commands. A cached contextual definition must
open immediately even while model work is active; queue a definition only on cache miss. The
context control is a non-spinning gauge, while Model Status describes active work. Question of the
Day generation is background consolidation work and remains queued when an active conversation is
opened.
