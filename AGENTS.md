# Aquinas iOS repository guide

This is the canonical instruction file for coding agents. `CLAUDE.md` imports it so Claude Code
and Codex follow the same project guidance. Keep this file short: it routes work; it does not
duplicate architecture specifications.

## Read the right document

| When changing… | Read… |
| --- | --- |
| Any iOS code | This file, then the relevant feature source and tests |
| Product behavior | [`../Aquinas-Foundations/FUNCTIONALITY.md`](../Aquinas-Foundations/FUNCTIONALITY.md) |
| Design or interaction | [`../Aquinas-Foundations/DESIGN.md`](../Aquinas-Foundations/DESIGN.md) |
| Model, API, retrieval, persistence, or privacy boundary | [`../Aquinas-Foundations/MODEL-INTEGRATION.md`](../Aquinas-Foundations/MODEL-INTEGRATION.md) |
| Insight Tree | [`../Aquinas-Foundations/INSIGHT-TREE.md`](../Aquinas-Foundations/INSIGHT-TREE.md) |
| iOS composition, ownership, and persistence | [`Documentation/App-Architecture.md`](Documentation/App-Architecture.md) |
| LiteRT runtime or backend recovery | [`Documentation/Model-Runtime.md`](Documentation/Model-Runtime.md) |
| Builds, tests, device work, or Figma | [`Documentation/Development-Workflow.md`](Documentation/Development-Workflow.md) |
| Study mode | [`Documentation/Study-Tool.md`](Documentation/Study-Tool.md) |

## Non-negotiable rules

- Preserve unrelated and uncommitted work. Do not reset, discard, or overwrite it.
- Use `AquinasTheme` typography and color tokens. Do not introduce ad hoc system colors or raw
  visual constants when an existing semantic token applies.
- All live generation goes through `AquinasModel` and the shared runtime/queue. `MockAquinasModel`
  is for previews and tests only; live actions fail explicitly rather than inventing fallback
  content.
- User-facing approach summaries are safe public explanations, never hidden chain-of-thought.
- Keep the LiteRT runtime process-scoped. Do not create competing live engines or queues.
- Automatic response analysis can create a Node Concept, never an automatic Insight. Manual
  definition saves create Insights.
- Treat API schemas and structured output as cross-repository contracts. Update iOS decoding and
  Foundation documentation in the same change.
- Keep the Mac HTTP backend clearly labeled as a development topology, not a hosted production
  service or a relaxation of the local-first product boundary.

## Working conventions

- The app source lives in `Aquinas-iOS/`; focused tests are in `Aquinas-iOSTests/`.
- Prefer small SwiftUI views with narrow inputs. Keep feature code under
  `Aquinas-iOS/Features/<Feature>/` and shared visual primitives under `DesignSystem/`.
- Add behavior-oriented regression coverage for logic with meaningful regression risk.
- Before handing off a visible change, inspect small-phone layouts, light/dark appearance,
  navigation, and empty states as applicable.
- For queue changes, verify idle, one-task, multi-task, cancellation, and reorder states. For
  tree changes, verify both the global library canvas and the persisted conversation tree.

## Standard verification

Run from the repository root. Always use a concrete arm64 simulator; the bundled LiteRT framework
does not support the generic simulator destination.

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run focused tests when relevant:

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Use a physical base supported iPhone for final sustained model, thermal, memory, and lifecycle
validation. Never use `devicectl ... --remove-existing-content true` against the production app
container; back up app data before model experiments.
