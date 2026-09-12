# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftUI iOS app organized by feature. App entry and shell code live in `App/`. Shared visual tokens, typography, colors, and reusable style helpers live in `DesignSystem/`. Feature screens and components are grouped under `Features/`, including `Conversation`, `Home`, `InsightTree`, `InsightLibrary`, `StudyTopics`, `Settings`, and `Canvas`. App-wide data models are in `Models/`, navigation components are in `Navigation/`, and lightweight local persistence helpers are in `Persistence/`. Assets are in `Assets.xcassets`; custom fonts are in `Fonts/`.

Focused regression tests live in the `Aquinas-iOSTests` target. Add behavior-oriented coverage
there when introducing logic with meaningful regression risk.

## Current Architecture

- `ContentView` owns the app shell, global navigation state, the global Insight Library canvas,
  settings, and handoff into `CurrentConversationView`.
- `CurrentConversationView` owns the active conversation/branch state, Model Task queue,
  conversation-scoped definition state, slash-command execution, and Insight Tree analysis retry
  pipeline.
- All generative calls go through `AquinasModel`. `AquinasApplicationRuntime` selects
  `LiteRTAquinasModel` when a verified package is available and injects its exact
  `LiteRTAquinasRuntime` into `ModelTaskQueue`; never create separate live runtime instances for
  the model and queue. `BackendAquinasModel` is recovery when local generation fails or the model
  is not installed. `MockAquinasModel` is for previews and tests only. Live special actions fail
  explicitly and must never substitute mock content that could be mistaken for generated
  knowledge.
- `ModelTaskQueue` serializes user questions, dynamic definitions, Insight Tree updates, and
  Question of the Day consolidation. Keep cancellation handlers synchronized with visible
  pending/breathing state.
- `InsightTreeService` owns backend-persisted conversation tree operations. Do not recompute its
  MiniLM topology with the on-device `NLEmbeddingProvider`; the latter is for the global in-memory
  Insight Library canvas and client-only features.
- Conversation UI state is still JSON-encoded to `UserDefaults`. The backend separately stores
  conversation-scoped definitions and Insight Tree topology in SQLite.

## Current Product Behaviors

- The visible thinking copy is an app-generated, question-specific public approach summary, not
  private chain-of-thought. Local LiteRT generation currently delivers its answer after native
  decoding completes rather than as reliable token deltas.
- Ordinary conversation stays deterministic because sampled decoding corrupts the 4-bit
  checkpoint. Substantial separated phrase loops preserve their coherent prefix, while
  mixed-script token corruption is rejected. Do not add prompt-forced word targets or automatic
  short-answer retries without a new checkpoint comparison; the exact package failed that test.
- Only `/compact` and `/clear` are supported. `/compact` stores a hidden branch checkpoint while
  preserving the visible transcript; `/clear` resets the active conversation in place.
- The dock contains Model Status and a non-spinning context gauge. Model Status is available in
  Branch and conversation Canvas modes but hides while an Insight is hovered.
- Cached contextual definitions must open immediately even while the model is occupied. Check the
  conversation/source cache before enqueueing a definition.
- A direct definition request such as “What does X mean?” renders once as ordinary response prose.
  Tapping an inline term in a substantive response opens its contextual definition. Saved terms
  deduplicate by normalized title and append a new context-definition entry when the same term is
  encountered with a different meaning.
- Question of the Day generation is queued as `Consolidate information`, shows
  `Consolidating...`, and does not cancel when an active conversation opens.
- Automatic response analysis may create a Node Concept; it must never create an automatic
  Insight. Manual definition saves create Insights.
- Conversation Node-to-Node lines have a 360-point minimum. Insight-to-Node bonds use a separate
  floor and mapping.

## Build, Test, and Development Commands

Run commands from `Aquinas-iOS/`:

```sh
xcodebuild -list -project ../Aquinas-iOS.xcodeproj
```

Lists available schemes and targets.

```sh
xcodebuild -project ../Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Builds the app for the iOS Simulator. Use this before handing off changes.

The exact bundled LiteRT package only has an arm64 simulator slice, so `generic/platform=iOS
Simulator` fails to link — always target a concrete arm64 simulator destination instead. Use
`--litert-probe --litert-probe-auto` for cable-free local-inference checks on Apple-silicon Macs;
simulator timing does not replace final physical-device thermal and memory verification.
For pre-LiteRT comparison, launch a Debug simulator build with `--force-backend-model` while the
Mac backend is running; release builds ignore this diagnostic override.

Run focused simulator tests with:

```sh
xcodebuild -project ../Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

## Coding Style & Naming Conventions

Use SwiftUI-first patterns. Keep multi-section screens split into small `View` structs with narrow inputs rather than large computed view properties. Prefer existing theme tokens from `AquinasTheme` over new ad hoc colors or fonts. Use 4-space indentation, descriptive type names like `HomeDashboardView`, and feature-prefixed private helper views where practical.

Keep user-facing strings clear and concise. Use SF Symbols through `Image(systemName:)` for controls when possible.

## Testing Guidelines

At minimum, verify builds with `xcodebuild`. For UI-heavy changes, manually check small iPhone widths, light mode, dark mode, navigation actions, and empty states. When adding tests, name them around behavior, for example `HomeDashboardContentTests` and `testUnfinishedConversationDetection()`.

For model-queue UI changes, also verify idle, one-task, multi-task, cancellation, and reorder
states. For Insight Tree changes, verify both the global library canvas and a persisted
conversation tree because they use different relatedness providers.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries, sometimes with scope, such as `Extract Canvas Mode state into @Observable CanvasModeModel` or `Theme and canvas updates: color refinements and insight tree polish`. Follow that style.

Pull requests should include a short summary, verification steps, screenshots or screen recordings for visible UI changes, and notes about any persistence or navigation behavior changes.

## Security & Configuration Tips

Do not commit secrets. Keep local configuration in `Config.xcconfig` or user-specific Xcode
settings. Conversation persistence currently uses `UserDefaults`, so avoid storing sensitive user
content without an explicit product decision. The local backend's SQLite tree store is a separate
development-time persistence boundary and must not be mistaken for production cloud storage.

Source control and Xcode builds do not back up the app's `UserDefaults`. Before physical-device
model probes, export and verify the app data, record Home counts before and after installation, and
use a disposable probe bundle/container. Never run `xcrun devicectl device copy to` with
`--domain-type appDataContainer --remove-existing-content true` against the production bundle,
even when a nested destination is provided.
