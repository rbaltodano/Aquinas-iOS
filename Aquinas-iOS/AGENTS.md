# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftUI iOS app organized by feature. App entry and shell code live in `App/`. Shared visual tokens, typography, colors, and reusable style helpers live in `DesignSystem/`. Feature screens and components are grouped under `Features/`, including `Conversation`, `Home`, `InsightTree`, `InsightLibrary`, `StudyTopics`, `Settings`, and `Canvas`. App-wide data models are in `Models/`, navigation components are in `Navigation/`, and lightweight local persistence helpers are in `Persistence/`. Assets are in `Assets.xcassets`; custom fonts are in `Fonts/`.

There is currently no dedicated test target in the project. Add tests in a new Xcode test target when introducing logic with meaningful regression risk.

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

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries, sometimes with scope, such as `Extract Canvas Mode state into @Observable CanvasModeModel` or `Theme and canvas updates: color refinements and insight tree polish`. Follow that style.

Pull requests should include a short summary, verification steps, screenshots or screen recordings for visible UI changes, and notes about any persistence or navigation behavior changes.

## Security & Configuration Tips

Do not commit secrets. Keep local configuration in `Config.xcconfig` or user-specific Xcode settings. Persistence currently uses `UserDefaults`, so avoid storing sensitive user content without an explicit product decision.
