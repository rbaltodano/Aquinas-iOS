# iOS development workflow

## Build and test

Run commands from the repository root:

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Use an installed concrete arm64 simulator. `generic/platform=iOS Simulator` cannot link the
bundled LiteRT framework. When working from a worktree, verify that the project path passed to
`xcodebuild` belongs to that worktree rather than another local checkout.

## UI work

Use the Figma source of truth when a design node is available; do not approximate it from a
screenshot. Use `AquinasTheme` from `DesignSystem/SharedTypography.swift` for typography and
color. Before handing off UI work, check small phone widths, light and dark modes, navigation,
and empty states.

## Device work

Simulator checks are not final validation for model behavior. Run sustained model, thermal,
memory, and lifecycle checks on the base supported iPhone. Preserve user data: create and verify
an app-data backup before installing experimental local models or running device probes.
