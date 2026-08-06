# Aquinas-iOS

SwiftUI iOS app for Aquinas, a Thomistic study/conversation app. Full repository guidelines (structure, style, commit conventions) live in [Aquinas-iOS/AGENTS.md](Aquinas-iOS/AGENTS.md) — read that before making changes.

Code safety checkpoint `35819d9` (`Integrate local Aquinas runtime and conversation workflows`)
is preserved in Git history. The working tree intentionally contains later uncommitted grounding,
topic-isolation, response-presentation, and Insight Tree fixes; inspect and preserve those changes
rather than resetting to the checkpoint merely because the tree is dirty.

## Model integration is live

Before changing any model-facing code, read
[MODEL-INTEGRATION.md](../Aquinas-Foundations/MODEL-INTEGRATION.md). It is the cross-repo source of
truth for backend contracts, iOS seams, MiniLM relatedness, persistence, current status, and the
remaining implementation order.

The live app is local-first when a verified LiteRT-LM package is available.
`AquinasApplicationRuntime` owns one process-scoped `LiteRTAquinasRuntime`, injects the same
runtime into `LiteRTAquinasModel` and `ModelTaskQueue`, and preserves serialized lifecycle,
streaming, and cancellation semantics. Ordinary local conversation generates visible prose only.
A separate short structured pass selects `key_terms`; the adapter validates exact term/excerpt
matches before adding tappable links, and metadata failure cannot replace or leak into the answer.
While generation is incomplete, the UI reports progress without
presenting canned text as model reasoning. The completed public approach summary is persisted in
the branch and remains available through **Show Thinking** after view recreation or relaunch.
Ordinary conversation stays deterministic because sampled decoding corrupts this 4-bit
checkpoint; structured application operations are also deterministic. Foundational and
interesting key terms come from the validated payload, with heuristic extraction used only when
the checkpoint fails the JSON contract, while
direct definition requests return Insight metadata. Special actions remain neutral and use
validated structured outputs. A non-cancellation local failure gets one local recovery attempt;
substantial separated phrase repetition and mixed-script token corruption are rejected.
When a repeated tail is detected, the runtime preserves the coherent prefix instead of discarding
the entire draft. Do not restore prompt-forced word targets or automatic short-answer retries: the
exact package entered slow rejected loops under that experiment.
LiteRT-LM currently emits the generated text only after native decoding finishes, so generation
has no automatic time cutoff; the Model Task Stop action remains available to the user.
The Thinking summary is an app-generated public approach description, never private model
reasoning or chain-of-thought. It must describe the relevant concepts or checks without pretending
to expose hidden scratch work.
`AquinasGroundingProviding` is the factual-retrieval boundary. The current offline lexical
bootstrap includes trusted Nicaea (325), Constantinople (381), Nicaea II (787), and Didache notes.
It fixes those known regressions but is not broad RAG coverage; production ranking still needs the
MiniLM query encoder and a versioned trusted corpus.
The local conversation adapter protects explicit authorship corrections: prompts preserve named
entities/negation, internally conflicting attribution/unknown-author drafts are rejected, and one
corrective retry is allowed without assuming the user is automatically right. The Insight Tree
canvas collapses a same-named Insight chip into its owning Node while retaining the Insight in
storage and the Node card.
Clear changes of subject start with fresh model history, and a response that exactly repeats an
earlier assistant answer triggers one bounded engine reload and fresh-context retry. Direct Insight
cards use explicit/standalone definition intent; the literal words `what is` do not by themselves
turn a broad question into a definition card.
`BackendAquinasModel` remains a development recovery path, but a physical iPhone never attempts a
loopback (`127.0.0.1`/`localhost`) backend. Ordinary on-device use does not require `uvicorn`.
`MockAquinasModel` remains previews/tests only.

Conversation Insight Tree analysis and `all-MiniLM-L6-v2` topology are still backend-only. With a
physical-device loopback URL, iOS skips and clears unreachable tree-analysis jobs, releases the
persisted-tree entrance gate, and displays the limited local fallback instead of staying on
`Mapping…`. This fallback is not MiniLM parity; use a reachable Mac LAN URL during development or
port MiniLM plus assignment/persistence on-device for full offline behavior.

The fine-tuned Aquinas package is 2,722,385,120 bytes with SHA-256
`5cb26c8e29d52ecf3e2b651e590761fe593dddcab0cbcdac7dc0692605ee5569`. The production
FP16/Metal probe passed on the 8 GB base iPhone 17 on July 30, 2026 with a 4.33-second cold load
and 1.27-second one-sentence generation, then remained alive for more than 25 seconds. A
development bundle seed may provide the package today. `LiteRTModelInstaller` can download,
size-check, hash-check, and atomically install the package into Application Support, but release
delivery still needs a hosted model URL, resumable/background transfer, storage/settings UI, and
removal of the 2.72 GB bundled development seed.

An experimental higher-precision `8fc4emb` package exists in the backend workspace, but its first
simulator probe failed LiteRT GPU engine creation (`Failed to initialize kernel`) before generation.
The app therefore still intentionally uses the verified 4-bit manifest. Debug probes may pass
`--litert-model-path /absolute/path/to/model.litertlm` to test another exact package without
replacing the bundled seed. Never promote a candidate before simulator and base-iPhone load,
latency, memory, stability, and blind answer-quality gates pass.

The 2,659,057,664-byte `litert-community/Qwen3-4B` mixed-INT4 candidate (SHA-256
`f0794bc77efeaaf4f7af815f04c483b19b8f2ae4a102cef1b7b760a25848a18e`) is also rejected. It
failed simulator Metal initialization because a 388,956,160-byte tensor exceeded the 256 MB
per-allocation limit; the base iPhone 17 was terminated with signal 9 during initialization. It
never generated a token and must not replace Gemma. `LiteRTDeviceProbe` supports external Mac paths
and diagnostic files in the app Documents directory, but future physical tests must use a separate
probe bundle/container.

Never run `xcrun devicectl device copy to` with `--domain-type appDataContainer
--remove-existing-content true` against `com.ryanbaltodano.Aquinas-iOS`. A source commit/build does
not preserve `UserDefaults`. Export a verified app-data backup, record Home counts before and after
installation, and use a disposable bundle identifier for multi-gigabyte candidate tests.

Factual reliability is retrieval-first. A replacement raw model may improve reasoning, but
production still needs an automatically ingested licensed/versioned corpus, MiniLM passage
retrieval, evidence-bound answers, citations, claim validation, and explicit uncertainty or an
approved online lookup when local evidence is insufficient. Fine-tuning is for Aquinas behavior
and voice, not for storing facts.

Uploaded images are normalized to bounded JPEG payloads and included with their user transcript
message. The backend validates them and passes up to the eight most recent images to Gemma 4's
vision tower; non-image file attachments remain display-only.

A quoted Insight remains structured alongside its submitted `ChatBlock.user`. Both the local and
backend model boundaries render it as an escaped `<insight_quote>` block containing its title and
definition immediately before `User question:`; the visible transcript continues to show only the
Insight chip and the user's original question.

Conversation-scoped definitions first use
`POST /conversation/{conversation_id}/concept/lookup`, then the corresponding `/define` route
only when needed. `/compact` calls `POST /conversation/compact`; `/clear` is client-side. Model
work is scheduled by the priority-aware `ModelTaskQueue`. Questions and definitions are foreground
work; response-driven tree analysis waits for an idle debounce and is preemptible. A failed
conversation request returns an explicit backend-unavailable response. Definitions, Node labels,
Midpoint candidates, Make Node children, and Questions of the Day fail explicitly, preserve
existing state, and offer or schedule retry rather than substituting mock content. Mock generation
is restricted to previews and tests. Do not restore it as a live availability fallback or
reimplement these contracts without checking the integration document.

## Current frontend checkpoint

- The Home Question of the Day disappears once answered. When it is absent or expired, eligible
  non-conversation pages schedule `Consolidate information` after 15 idle seconds. The task remains
  queued if the user opens an active conversation, displays `Consolidating...` while active, and
  uses at most four relevant Insights.
- `/compact` and `/clear` are the only supported slash commands.
- The old Thinking toggle is gone. The dock shows a Model Status control: `Idle`, `Thinking`, or
  `n/total Thinking`. It appears in Branch and conversation Insight Tree modes, except while an
  Insight is hovered.
- Tapping Model Status opens the 345-point Model Tasks card. The queue currently serializes user
  questions, contextual definitions, Insight Tree updates, and Question of the Day consolidation.
  Current tasks can be stopped; upcoming tasks can be removed or reordered; completed rows fade
  away once the queue returns idle.
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

The exact bundled fine-tuned LiteRT package supports the arm64 iOS Simulator. Launching with
`--litert-probe --litert-probe-auto` verifies local inference on an Apple-silicon Mac without a
phone cable. Use simulator results for answer-quality iteration, but keep final sustained thermal,
memory, and lifecycle checks on the base supported iPhone.

For pre-LiteRT quality testing, run the Mac backend and launch a Debug simulator build with
`--force-backend-model`. This bypasses the bundled mobile package only in Debug so the simulator
uses `BackendAquinasModel` at `127.0.0.1`; release builds ignore the flag.

- The app scheme and target are `Aquinas-iOS`; the `Aquinas-iOSTests` target contains focused
  model-availability and runtime-lifecycle regression tests.
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
- `Services/AquinasModel.swift` / `LiteRTAquinasModel.swift` — generative boundary and local-first
  implementation; `BackendAquinasModel.swift` is the recovery/API client.
- `Services/AquinasGrounding.swift` — replaceable factual-retrieval boundary and current offline
  bootstrap reference catalog.
- `Services/AquinasApplicationRuntime.swift` / `LiteRTAquinasRuntime.swift` — process-scoped model
  and queue ownership plus the long-lived LiteRT engine/session driver.
- `Services/LiteRTModelStore.swift` / `LiteRTModelInstaller.swift` — verified model resolution and
  post-install download primitives.
- `Services/InsightTreeService.swift` — persistent conversation-tree API boundary.
- `Persistence/InquiryPersistence.swift` — current whole-snapshot `UserDefaults` conversation
  persistence.
- `Persistence/ConversationInsightMembershipStore.swift` — identifiers connecting global saved
  Insights to a conversation.
- `Persistence/InsightTreeAnalysisQueue.swift` — identifiers-only durable response-analysis queue.
