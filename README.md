<p align="center">
  <img src="design_assets/logo-1.svg" alt="Aquinas" width="193" height="54">
</p>

# Aquinas

**A private, local-first space for serious questions.**

Aquinas is an iOS study and conversation app for exploring philosophy, theology, Scripture, and
the questions that deserve more than a quick answer. Inspired by the Thomistic tradition, it pairs
thoughtful conversation with source-grounded study and a visual map of the ideas a person is
developing over time.

It is being built for people who want room to think: students, seekers, teachers, and anyone
working through questions of faith, meaning, truth, or human flourishing.

## What it does

- **Supports sustained inquiry.** Start a conversation, follow an idea into a branch, and return
  to the thread later without losing the shape of the question.
- **Keeps study close to sources.** Aquinas can retrieve relevant passages from a bundled local
  library—including Scripture, Aquinas, patristic writing, creeds, and conciliar texts—so
  source-dependent answers are tied to available evidence.
- **Builds an Insight Tree.** Save contextual definitions and important concepts, then explore the
  relationships between them in a spatial, evolving map.
- **Stays local by design.** The intended product keeps conversations, retrieval, and model work
  under the user's control rather than requiring an account or a cloud conversation history.

## A note on privacy and current development

Aquinas is a local-first project, not a hosted chat service. The iOS app is designed to use an
on-device language model and local source retrieval. A Mac-hosted backend remains part of the
development workflow for integration, validation, and some advanced tree features; it is not the
intended production data boundary.

This repository is an active development project. The local model and grounding assets are large
and intentionally excluded from source control, so a full on-device experience requires the
corresponding development assets.

## Repository guide

| Path | What you'll find |
| --- | --- |
| `Aquinas-iOS/App` | App entry point and overall navigation shell |
| `Aquinas-iOS/Features` | Conversation, Home, Insight Tree, Library, and settings experiences |
| `Aquinas-iOS/DesignSystem` | Typography, colors, and shared interface elements |
| `Aquinas-iOS/Services` | Model runtime, local grounding, and development-backend boundaries |
| `Aquinas-iOS/Persistence` | Local conversation and Insight state |
| `Aquinas-iOSTests` | Focused behavior and regression coverage |

## Open the project

Open `Aquinas-iOS.xcodeproj` in Xcode. The project targets iOS 26.4 and uses a concrete arm64
simulator destination when building from the command line:

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For contributor architecture notes, implementation guardrails, and test guidance, see
[`Aquinas-iOS/AGENTS.md`](Aquinas-iOS/AGENTS.md). The broader product and technical documentation
is maintained alongside this project in the Aquinas Foundations repository.
