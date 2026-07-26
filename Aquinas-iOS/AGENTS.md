# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftUI iOS app organized by feature. App entry and shell code live in `App/`. Shared visual tokens, typography, colors, and reusable style helpers live in `DesignSystem/`. Feature screens and components are grouped under `Features/`, including `Conversation`, `Home`, `InsightTree`, `InsightLibrary`, `StudyTopics`, `Settings`, and `Canvas`. App-wide data models are in `Models/`, navigation components are in `Navigation/`, and lightweight local persistence helpers are in `Persistence/`. Assets are in `Assets.xcassets`; custom fonts are in `Fonts/`.

There is currently no dedicated test target in the project. Add tests in a new Xcode test target when introducing logic with meaningful regression risk.

## Current Architecture

- `ContentView` owns the app shell, global navigation state, the global Insight Library canvas,
  settings, and handoff into `CurrentConversationView`.
- `CurrentConversationView` owns the active conversation/branch state, Model Task queue,
  conversation-scoped definition state, slash-command execution, and Insight Tree analysis retry
  pipeline.
- All generative calls go through `AquinasModel`; `BackendAquinasModel` is the live default.
  `MockAquinasModel` is for previews and explicit task fallbacks, not the normal conversation path.
- `ModelTaskQueue` serializes user questions, dynamic definitions, and Insight Tree updates. Keep
  cancellation handlers synchronized with visible pending/breathing state.
- `InsightTreeService` owns backend-persisted conversation tree operations. Do not recompute its
  MiniLM topology with the on-device `NLEmbeddingProvider`; the latter is for the global in-memory
  Insight Library canvas and client-only features.
- Conversation UI state is still JSON-encoded to `UserDefaults`. The backend separately stores
  conversation-scoped definitions and Insight Tree topology in SQLite.

## Current Product Behaviors

- Deep-think is always enabled. The visible thinking copy is a model-generated, user-facing
  approach summary, not private chain-of-thought.
- Only `/compact` and `/clear` are supported. `/compact` stores a hidden branch checkpoint while
  preserving the visible transcript; `/clear` resets the active conversation in place.
- The dock contains Model Status and a non-spinning context gauge. Model Status is available in
  Branch and conversation Canvas modes but hides while an Insight is hovered.
- Cached contextual definitions must open immediately even while the model is occupied. Check the
  conversation/source cache before enqueueing a definition.
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
xcodebuild -project ../Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'generic/platform=iOS Simulator' build
```

Builds the app for the iOS Simulator. Use this before handing off changes.

If a test target is added later, prefer:

```sh
xcodebuild -project ../Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'platform=iOS Simulator,name=iPhone 16' test
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
