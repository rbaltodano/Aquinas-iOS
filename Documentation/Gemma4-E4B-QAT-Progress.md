# Gemma 4 E4B QAT migration — progress ledger

> This is the **mutable** record for [`Gemma4-E4B-QAT-Plan.md`](Gemma4-E4B-QAT-Plan.md).
> Update it at the start and end of every checkpoint and commit each update on
> `feature/gemma4-e4b-qat`. Never delete earlier entries; if evidence is superseded, strike it
> through (`~~old~~`) and add the new value with a date.
>
> Status values: `todo` · `in-progress` · `done` · `failed` · `blocked` · `skipped`

## Status board

| ID | Checkpoint | Status | Owner / session | Last updated | Notes |
| --- | --- | --- | --- | --- | --- |
| C0 | Baseline and workspace | todo | | | |
| C1 | Acquire E4B package | todo | | | |
| C2 | QAT classification | todo | | | |
| C3a | Simulator compatibility (prebuilt) | todo | | | |
| C3b | Conversion fallback (conditional) | todo | | | |
| C4 | DEBUG model-path override | todo | | | |
| C5 | Full-app functional parity (sim) | todo | | | |
| C6 | Quality A/B | todo | | | |
| C7 | Physical-device gate | todo | | | |
| C8 | Promotion (needs user approval) | todo | | | |
| C9 | Optional vision probe | todo | | | |

**Next action:** Start C0.

## Open questions for the user

_None yet. Add a dated entry for anything that blocks progress. Say what the question is, why it
blocks, and what options you recommend._

## Decisions log

| Date | Decision | Made by | Reason |
| --- | --- | --- | --- |
| 2026-09-25 | Adopt plan D1–D6 (prebuilt package first, GPU, single engine, no fine-tune, 4,096 tokens, reversible promotion) | User + planning session | See plan §3 |

## Evidence

### C0 — Baseline and workspace

- Worktree path / branch:
- Baseline manifest (file · bytes · SHA-256):
- LiteRT-LM vendored version:
- Xcode / simulator runtime:
- Free disk at start:
- Build result:

| prompt-id | Load s | Gen s | Words | `{{term}}` count | Pass / notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

### C1 — Acquire E4B package

- File(s):
- Bytes:
- SHA-256:
- Source URL + HF commit:
- Downloaded on:

### C2 — QAT classification

- Classification (QAT / not QAT / unknown):
- Supporting signals:
- Decoder dtype histogram:
- `prefer_activation_type`:
- LiteRT-LM #2497 status when checked:

### C3a — Simulator compatibility

| Mode | Backend | Load s | Gen s | Activation type | Result |
| --- | --- | --- | --- | --- | --- |
| Raw probe | GPU | | | | |
| Quality probe | GPU | | | | |

- Relevant log lines (quoted exactly):

### C3b — Conversion fallback

- Ran? (yes / skipped + reason):
- Toolchain versions and command:
- Output file · bytes · SHA-256:
- Gate result:

### C4 — DEBUG model-path override

- Commit:
- Tests added:
- Full test suite result:
- Screenshot / log proving E4B loaded in the full app:

### C5 — Full-app functional parity

| Action | Result | Notes |
| --- | --- | --- |
| Conversation (3 questions + 1 follow-up) | | |
| Topic-shift reset | | |
| Contextual definition | | |
| Save Insight / Node label | | |
| Make Node (exactly 3) | | |
| Midpoint | | |
| Question of the Day | | |
| Compaction | | |
| Cancel in-flight answer | | |
| Queue reorder | | |
| Background / foreground | | |

### C6 — Quality A/B

| prompt-id | Baseline words / markers | E4B words / markers | Factual trap correct? (B / E) | Rejects | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

- Blind sheet location: `LocalModels/e4b-eval/blind.md` (key: `blind-key.json`)
- User scores received? (date):
- Mean subjective score, baseline vs E4B:
- Sampling (temperature 0.2) observations:
- Gate result:

### C7 — Physical-device gate

- Device / iOS version:
- Backup taken (location) · Home data counts before → after:

| Metric | Threshold | Result |
| --- | --- | --- |
| Cold load | ≤ 12 s | |
| Cached load | ≤ 3 s | |
| One-sentence answer | ≤ 4 s | |
| Justice-and-mercy answer | ≤ 60 s | |
| Peak resident memory | no jetsam or warnings | |
| Max thermal state over 20 turns | < critical | |
| 5× background / foreground | survives | |
| Memory warning | recovers | |
| Idle after generation | alive > 60 s | |

### C8 — Promotion

- User approval (date / quote):
- Rollback values (old manifest file · bytes · SHA-256; old file location):
- Commits:
- PR URL:

### C9 — Vision probe

- Result:

## Final summary

_Fill this in when the effort ends. State whether E4B was promoted or rejected, which gate
decided it, and any recommended follow-ups (for example, a QAT-preserving fine-tune, raising
`maxNumTokens`, or re-enabling vision)._
