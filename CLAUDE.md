# Aquinas-iOS

SwiftUI iOS app for Aquinas, a Thomistic study/conversation app. Full repository guidelines (structure, style, commit conventions) live in [Aquinas-iOS/AGENTS.md](Aquinas-iOS/AGENTS.md) — read that before making changes.

## Model integration is live

Before changing any model-facing code, read
[MODEL-INTEGRATION.md](../Aquinas-Foundations/MODEL-INTEGRATION.md). It is the cross-repo source of
truth for backend contracts, iOS seams, MiniLM relatedness, persistence, current status, and the
remaining implementation order.

`BackendAquinasModel` is the live environment default. Normal conversations use filtered NDJSON
from `POST /conversation/respond/stream`, falling back to the validated non-streaming endpoint if
the stream fails. Deep-think is always enabled in the current UI: the model returns a short,
user-facing approach summary, never raw chain-of-thought. Validated key terms become tappable
`aq://` links.

Conversation-scoped definitions first use
`POST /conversation/{conversation_id}/concept/lookup`, then the corresponding `/define` route
only when needed. `/compact` calls `POST /conversation/compact`; `/clear` is client-side. Model
work is serialized by `ModelTaskQueue`. Definitions retain a mock fallback, while a failed
conversation request returns an explicit backend-unavailable response. Do not restore the mock as
the normal path or reimplement these contracts without checking the integration document.

## Current frontend checkpoint

- `/compact` and `/clear` are the only supported slash commands.
- The old Thinking toggle is gone. The dock shows a Model Status control: `Idle`, `Thinking`, or
  `n/total Thinking`. It appears in Branch and conversation Insight Tree modes, except while an
  Insight is hovered.
- Tapping Model Status opens the 345-point Model Tasks card. The queue currently serializes user
  questions, contextual definitions, and Insight Tree updates. Current tasks can be stopped;
  upcoming tasks can be removed or reordered; completed rows fade away once the queue returns idle.
- The context control is a non-spinning gauge with no `Context` label. It opens the context card.
- Pending response cards and definition affordances use the shared breathing animation. Cancelling
  a definition task clears that state.
- Tapping a highlighted term first checks the conversation/source-scoped definition cache. A
  cached definition opens immediately even if the model is busy; only a cache miss is queued.
- Automatic response analysis creates Node Concepts, not Insights. Manual saves create Insights.
- Conversation Node-to-Node connectors have a 360-point minimum length. Insight-to-Node lengths
  retain their separate relatedness mapping.
- Model Task and hovered Insight cards use the shared bottom-up scale/translation transition;
  switching hovered Insights replaces the card rather than swapping its text in place.

## Sibling repos (context lives outside this repo)

- `../Aquinas-Foundations` — product source of truth: MISSION.md, DESIGN.md, SPECIFICATION.md,
  FUNCTIONALITY.md, MODEL-INTEGRATION.md, and INSIGHT-TREE.md. Consult DESIGN.md before visual work.
- `../Aquinas_Backend` — FastAPI + MLX backend used for structured conversation and definition
  generation plus MiniLM relatedness and persistent Insight Tree assignment.

## Build & verify

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'generic/platform=iOS Simulator' build
```

- Scheme and target are both `Aquinas-iOS`. No test target exists yet.
- Always run a simulator build before handing off changes.
- **Worktree pitfall:** when working in `.claude/worktrees/...`, run `xcodebuild` against the worktree's copy of the project (use the absolute path to the `.xcodeproj` inside the worktree). Building without checking the path has previously compiled the wrong copy and hidden real errors.

## Design workflow

- UI comes from the Figma file **"source-of-truth"** (file key `JBM9BM0Zo6JHgj7NCjxcRt`). When given a Figma node URL, pull it via the Figma MCP tools rather than eyeballing screenshots.
- Use existing `AquinasTheme` tokens ([DesignSystem/SharedTypography.swift](Aquinas-iOS/DesignSystem/SharedTypography.swift)) for colors/typography — do not introduce ad hoc values when a token exists.
- Feature UI lives under `Aquinas-iOS/Features/<Feature>/` (Conversation, Home, InsightTree, InsightLibrary, StudyTopics, Settings, Canvas).

## Important code seams

- `Features/Conversation/CurrentConversation.swift` — conversation orchestration, slash-command
  execution, definition cache/queue flow, and durable tree-analysis retries.
- `Features/Conversation/ConversationComponents.swift` — branch transcript, submission, pending
  response state, and model-response lifecycle.
- `Features/Conversation/ModelTaskQueue.swift` — serialized cancellable model jobs and task state.
- `Features/Conversation/InquiryControlDock.swift` — Model Status, Model Tasks popup, and context
  gauge/card.
- `Services/AquinasModel.swift` / `BackendAquinasModel.swift` — generative boundary and live API
  client.
- `Services/InsightTreeService.swift` — persistent conversation-tree API boundary.
- `Persistence/InquiryPersistence.swift` — current whole-snapshot `UserDefaults` conversation
  persistence.
- `Persistence/ConversationInsightMembershipStore.swift` — identifiers connecting global saved
  Insights to a conversation.
- `Persistence/InsightTreeAnalysisQueue.swift` — identifiers-only durable response-analysis queue.
