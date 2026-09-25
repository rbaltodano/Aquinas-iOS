# Gemma 4 E4B QAT migration — execution plan

> Status: approved plan, not yet executed. This file is the **instructions**. It changes only
> when the plan itself changes. Record all progress, measurements, and decisions in
> [`Gemma4-E4B-QAT-Progress.md`](Gemma4-E4B-QAT-Progress.md), never here.

## 0. How to use these two documents

1. Read this plan in full, then read the progress ledger.
2. In the ledger, find the first checkpoint whose status is not `done`. Resume there. Do not
   redo `done` checkpoints unless the ledger says their evidence is invalid.
3. Before you start a checkpoint, set it to `in-progress` with your session name and the date.
   Commit that change so a parallel or later agent can see it.
4. When you finish a checkpoint, fill in **every** evidence field the checkpoint requires, set
   it to `done` (or `failed` / `blocked` with a reason), and commit.
5. When a checkpoint fails, follow its **On failure** branch. Do not improvise a workaround that
   the plan forbids. If no branch applies, set the checkpoint to `blocked`, write the question
   for the user in the ledger's *Open questions*, and stop.

Required reading before any code change: [`AGENTS.md`](../AGENTS.md),
[`Model-Runtime.md`](Model-Runtime.md),
[`../../Aquinas-Foundations/MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md)
(especially the LiteRT checkpoints and §8 fine-tuning policy), and
[`Development-Workflow.md`](Development-Workflow.md).

## 1. Goal and non-goals

**Goal.** Replace the on-device conversation model with Google's **Gemma 4 E4B instruction model
in its quantization-aware-trained (QAT) mobile form**, served through the existing LiteRT-LM
runtime. Promote it only if it measurably beats the current checkpoint on factual and reasoning
quality and passes every compatibility, memory, thermal, and lifecycle gate on the base iPhone 17
(8 GB).

**Non-goals for this plan:**

- Fine-tuning E4B. See §3, decision D4. A fine-tune is a separate follow-up plan.
- Vision and multimodal input. Stay text-only, matching today's `visionBackend = nil`. A vision
  probe is optional (checkpoint C9) and never blocks promotion.
- Model hosting and download UI. Promotion replaces the development seed only. The
  hosted/resumable delivery work stays tracked in `MODEL-INTEGRATION.md`.
- Changing the decoding policy. Deterministic decoding remains the default. The sampling test
  in C6 is informational.

## 2. Background facts (verified September 2026)

| Fact | Source |
| --- | --- |
| "4B" means **E4B**: 4.5B effective parameters, about 8B including per-layer embeddings. | HF `google/gemma-4-E4B-it-qat-mobile-transformers` |
| QAT checkpoints ship as Q4_0 (GGUF/unquantized), w4a16 compressed tensors (vLLM), and **Mobile wNa8o8**. Only the mobile form targets LiteRT-LM. | Google QAT blog post; HF model cards |
| Mobile wNa8o8 means static activations, channel-wise quantization, targeted 2-bit decode layers, and an optimized KV cache. | Same |
| `litert-community/gemma-4-E4B-it-litert-lm` provides `gemma-4-E4B-it-gpu.litertlm` (2.97 GB) and `gemma-4-E4B-it.litertlm` (3.66 GB), under Apache 2.0. | HF repo file listing |
| Published iPhone 17 Pro numbers: GPU prefill 1,189 tok/s, decode 25.1 tok/s, about 3.4 GB memory. CPU decode 9.7 tok/s, about 1 GB. | Same card |
| It is **not confirmed** whether those `.litertlm` files are QAT-derived. No QAT to `.litertlm` converter is documented. LiteRT-LM issue #2497, which asks this, was unanswered at the time of writing. | GitHub `google-ai-edge/LiteRT-LM#2497` |
| The app vendors LiteRT-LM **v0.14.0** (`Vendor/LiteRTLM`). The backend's `litert_conversion_env` has `litert_lm_builder`/`litert_lm_cli` 0.14.0, `litert_torch` nightly 0.10.0.dev20260730, and `ai_edge_quantizer` nightly. | Local inspection |

Local facts:

- **Current bundled model:** `Aquinas-iOS/LocalModels/gemma-4-E2B-it.litertlm`, 3,862,121,696
  bytes, SHA-256 `9a6345f1…65282`. This is the `dynamic_wi8_emb4_afp32` E2B candidate.
  `LiteRTModelManifest.aquinas` pins it. `MODEL-INTEGRATION.md` still describes this candidate
  as having failed its simulator gate, so the docs are stale. C0 establishes the real baseline.
- **Past failures to watch for:**
  - Qwen3-4B exceeded the simulator GPU's 268,435,456-byte maximum buffer allocation, then was
    killed with signal 9 on the base iPhone 17.
  - A package without `prefer_activation_type: fp16` resolved FLOAT32 and ran about 90× slower.
  - Sampled decoding corrupted the 4-bit E2B checkpoint.
- **Existing tooling:**
  - `--litert-probe` launches `LiteRTDeviceProbeView`. `--litert-probe-auto` runs it
    automatically.
  - `--litert-quality-probe` runs the **production** `LiteRTAquinasModel` path with MiniLM
    grounding.
  - `--litert-probe-question "<q>"` sets the prompt. `--litert-probe-cpu` uses the CPU.
  - `--litert-model-path <abs path>` selects the model. In the simulator it can point straight
    at a file on the Mac. `--litert-model-document <name>` loads from the app's Documents
    folder on a device.
  - Probe prompts live in `../Aquinas_Backend/evaluation/runtime_comparison_prompts.json`.
- **Uncommitted work:** `main` carries a lot of unrelated uncommitted work. Never stage, stash,
  reset, or overwrite it.

## 3. Key decisions (already made — do not relitigate)

- **D1 — Try the prebuilt package before converting anything.** Test the `litert-community` E4B
  package first. Converting the QAT mobile checkpoint is a fallback (C3b), used only if C2 shows
  the prebuilt package is not QAT-derived **and** its quality fails C6.
- **D2 — Use the GPU/Metal backend, and the `-gpu` package first.** The app's runtime is
  GPU-first. Test the standard 3.66 GB package on GPU only if the `-gpu` package fails to load.
- **D3 — One process-scoped engine.** Never add a second live engine, a model picker, or an A/B
  runtime. Switching models means changing the single `LiteRTModelManifest.aquinas`, plus a
  DEBUG-only path override (C4).
- **D4 — Raw model first, no fine-tune in this plan.** This follows `MODEL-INTEGRATION.md` §8
  and the replacement-model checkpoint. A LoRA fine-tune followed by the existing PTQ export
  (`export_litert_aquinas.py`) would **discard the QAT benefit**, because the adapter-merged
  weights get re-quantized post-training. Any future fine-tune must keep the QAT mobile schema.
  That is a separate plan.
- **D5 — Keep `maxNumTokens` at 4,096.** This keeps the comparison like-for-like with the
  current runtime. Raising it is a follow-up.
- **D6 — Every promotion is reversible.** Record the old manifest values in the ledger. Keep the
  old package file on disk (gitignored) until the user signs off.

## 4. Environment and safety rules

- Work on a branch, `feature/gemma4-e4b-qat`, created from `main` in a **git worktree** so the
  uncommitted work in the main checkout is untouched. Stage only files this plan names.
- Run every build and simulator step on a concrete arm64 simulator:
  `-destination 'platform=iOS Simulator,name=iPhone 17'`. The generic destination cannot link
  LiteRT.
- Models live in the gitignored `LocalModels/` at the repo root. **Never commit a model**, a
  generated corpus, device data, or raw eval outputs larger than a few KB.
- Disk space: the Mac had about 28 GB free when this plan was written. Before each download,
  check `df -h /`. Stop and ask the user if there is less than 12 GB free.
- Physical device:
  - Back up app data first (see `Development-Workflow.md`).
  - Record Home data counts before and after.
  - Prefer a disposable probe bundle identifier.
  - **Never** run `devicectl … --remove-existing-content true` against the production app
    container.
- Committed `.swift` changes must pass the standard build and the full test suite from
  `AGENTS.md`.
- Commit messages end with the attribution line required by the current session.

## 5. Checkpoints

Each checkpoint lists its **Do** steps, its **Gate** (pass criteria), the **Evidence** to record
in the ledger, and what to do **On failure**. The IDs match the ledger.

### C0 — Baseline and workspace

**Do**

1. Create the worktree and branch (§4). Confirm `git status` in the worktree is clean.
2. Record the current manifest values (file name, byte count, SHA-256), the vendored LiteRT-LM
   version, the free disk space, and the Xcode and simulator versions.
3. Build the app (standard build command).
4. Run the current bundled model through the quality probe on the simulator for each prompt in
   the **eval set** (§6):
   - Launch arguments: `--litert-probe --litert-probe-auto --litert-quality-probe
     --litert-probe-question "<q>"`.
   - Capture load time, generation time, full response text, and key-term count from the probe
     UI, using `get_page_text`/screenshot or the simulator tool.
5. Save raw outputs to `LocalModels/e4b-eval/baseline/<prompt-id>.txt` (gitignored).

**Gate:** the baseline model loads and answers every eval prompt, or its failures are recorded
exactly. This checkpoint establishes truth, so a failing baseline still completes C0.

**Evidence:** the manifest values; the environment versions; a per-prompt table of load
seconds, generation seconds, word count, `{{term}}` count, and a pass/fail note.

**On failure:** if the app does not build, fix nothing beyond what the build needs. If the fix
touches unrelated code, set C0 to `blocked` and ask the user.

### C1 — Acquire the E4B package

**Do**

1. Download `gemma-4-E4B-it-gpu.litertlm` from `litert-community/gemma-4-E4B-it-litert-lm` into
   `LocalModels/`. Use `huggingface-cli download` from `../Aquinas_Backend/aquinas_env`, or
   `curl -L` with resume.
2. Record its byte count and `shasum -a 256`.
3. Download the 3.66 GB `gemma-4-E4B-it.litertlm` **only if C3a fails**.

**Gate:** the file is complete. Its size matches the Hugging Face listing, and the SHA-256 is
recorded.

**Evidence:** the file name, bytes, SHA-256, the source URL with its commit hash from the HF
repo, and the download date.

### C2 — Determine whether the package is QAT-derived

**Do**

1. Inspect the package with `litert_lm_cli` or the `litert_lm_builder` Python API from
   `../Aquinas_Backend/litert_conversion_env`. List its sections, its metadata (including
   `prefer_activation_type`), the tensor dtype distribution of the decoder, whether any tensors
   are 2-bit, and whether static activation quantization parameters are present.
2. Compare against the E2B package. Its HF card claims the mixed 2/4/8-bit mobile scheme.
3. Recheck GitHub issue `google-ai-edge/LiteRT-LM#2497` and the HF model cards for any newer
   statement.

**Gate:** none. This checkpoint classifies the package as **QAT**, **not QAT**, or **unknown**.
The answer affects C3b and the final recommendation, not whether you continue.

**Evidence:** the classification, the exact signals that support it, the dtype histogram, and
the activation-type metadata.

**On failure:** if the tools can't read the package, classify it as `unknown`, note the error,
and continue.

### C3a — Simulator compatibility gate (prebuilt package)

**Do**

1. Launch the probe in its **raw** mode with `--litert-probe --litert-probe-auto
   --litert-model-path <abs path to E4B file>`.
2. Launch the probe in **production** mode with the same arguments plus
   `--litert-quality-probe`, asking "What is prudence?".
3. From the logs, capture:
   - the Metal device creation lines;
   - the resolved activation type (it must be FLOAT16);
   - any `Failed to initialize kernel`, max-buffer, or delegate-rollback errors;
   - load and generation seconds.

**Gate:** both modes complete; the activation type is FLOAT16; the response is coherent English;
and there are no repetition or mixed-script rejects.

**Evidence:** the per-mode table and the relevant log excerpts, with the error text quoted
exactly.

**On failure**

- If there is a max-buffer or kernel failure on the simulator, retry once with
  `--litert-probe-cpu` to isolate the backend. A CPU pass with a GPU failure means the package
  cannot ship on the Metal path. Mark C3a `failed`, then try the standard 3.66 GB package once
  (the C1 fallback).
- If the activation type is FLOAT32, record it. Do **not** patch package metadata by hand.
  Go to C3b, which rebuilds with FP16 preference.
- If both packages fail, go to C3b.

### C3b — Conversion fallback (conditional)

**Run this only if:** C3a failed for both packages, **or** C2 said "not QAT" / "unknown" and C6
later fails on quality. Otherwise mark it `skipped` with the reason.

**Do**

1. Download `google/gemma-4-E4B-it-qat-mobile-transformers` into
   `../Aquinas_Backend/models/` (gitignored there). Check disk space first.
2. Try an export with `litert_torch`'s Gemma 4 generative path or `litert_lm_builder` in
   `litert_conversion_env`. Preserve the checkpoint's own quantization metadata, which means no
   extra PTQ recipe. Set `prefer_activation_type: fp16`, text-only, a KV cache of 4,096 tokens,
   and a prefill signature of 128. Write a new script, `scripts/export_litert_e4b_qat.py`, next
   to `export_litert_aquinas.py`. Do not modify that existing script.
3. Rerun the C3a gate against the output.

**Gate:** the same as C3a.

**Evidence:** the exact converter versions and command, the output bytes and SHA-256, and the
C3a-style results.

**On failure:** if the toolchain can't consume the wNa8o8 checkpoint, record the exact error.
Then add a comment to `LiteRT-LM#2497`, **but only after the user approves posting**. Set C3b
to `blocked`. The plan then continues with whichever prebuilt package passed C3a, if one did;
otherwise the whole effort is blocked.

### C4 — DEBUG model-path override for full-app testing

The probe already accepts `--litert-model-path`, but the full app always uses the manifest.
Add a narrow DEBUG-only override so the real UI and `ModelTaskQueue` can run E4B without
swapping the bundled file.

**Do**

1. In `AquinasApplicationRuntime.init`, in the same `#if DEBUG` block as
   `--force-backend-model`, read `--litert-model-path <path>`. When it is present, build
   `LiteRTModelStore(manifest: <manifest derived from that file's name and size, sha
   "development-override">, developmentModelURL: url)`. Release builds must ignore the flag,
   just as they ignore `--force-backend-model`.
2. Make `LiteRTDeviceProbe.locateModel()` fall back to `LiteRTModelManifest.aquinas.fileName`
   instead of the hard-coded `gemma-4-E2B-it` names.
3. Add a focused test in `Aquinas-iOSTests/`. It must show that the override yields a store
   resolving the given URL. If the launch-argument parsing is testable, it must also show that
   the store ignores a missing file.
4. Build and run the full test suite.

**Gate:** the build passes; all tests pass; the full app launched in the simulator with the
override answers a question with E4B. Confirm this by showing the model's file name in the
Developer view or the logs.

**Evidence:** the commit hash, the test names, and a simulator screenshot path in the ledger.

### C5 — Functional parity in the full app (simulator)

Run the app with the C4 override, then do the following:

1. Ask three conversation questions and one follow-up. Confirm the topic-shift reset still works.
2. Tap a highlighted key term to create a contextual definition.
3. Save that Insight. Trigger a Node label. Run Make Node, which must produce exactly three
   children. Run a Midpoint on two Insights.
4. Trigger the Question of the Day and context compaction, using a long conversation.
5. Cancel an in-flight answer from the Model Task control. Queue two tasks and reorder them.
6. Background the app during generation, then return. Confirm the lease unload and reload
   behavior.

**Gate:** every structured action validates without backend recovery. Confirm this by checking
the logs for recovery. Mark the backend unreachable (`127.0.0.1:9`) or leave it stopped so that
recovery cannot mask a local failure. Cancellation and the lifecycle behave as they do today.

**Evidence:** a pass/fail row per action, with any validation or repair failures quoted.

**On failure:** a structured-output failure is a **quality** finding, not a plumbing bug. Record
it. Change prompts only if the failure also reproduces on the baseline. Never add heuristic
fallbacks (`AGENTS.md`, `MODEL-INTEGRATION.md`).

### C6 — Quality A/B (simulator)

**Do**

1. Run every eval-set prompt (§6) through `--litert-quality-probe` on E4B. Save the outputs to
   `LocalModels/e4b-eval/e4b/<prompt-id>.txt`.
2. Build a **blinded** comparison sheet at `LocalModels/e4b-eval/blind.md`:
   - For each prompt, show the two answers labeled A and B in randomized order.
   - Keep the key in `blind-key.json`.
3. Ask the user to score each prompt 1–5 on accuracy, depth, and voice, and to mark any
   critical failure. Agents do not grade answers from their own generating checkpoint (per the
   evaluation policy). The agent **may** score the objective checks:
   - word count;
   - `{{term}}` compliance (the number of markers, within the 12-marker ceiling);
   - repetition or mixed-script rejects;
   - whether the known factual traps were answered correctly.
4. **Informational only:** rerun three prompts at temperature 0.2 with `seed 7` through the raw
   probe. Record whether any corruption appears. Do not change the production decoding policy.

**Gate for promotion eligibility**

- There are zero critical failures.
- E4B wins or ties on the factual-trap prompts.
- E4B's mean subjective score is ≥ the baseline's mean.
- E4B's marker compliance is ≥ the baseline's.
- There are zero repetition or garbage rejects.

**Evidence:** the objective table, the user's scores (once provided), and the sampling
observations.

**On failure:** if C2 did not classify the package as QAT, and C3b has not been attempted, go to
C3b. Otherwise mark C6 `failed` and stop before C7. Record in the ledger that the model is not
an improvement.

### C7 — Physical-device gate (base iPhone 17, 8 GB)

Requires C3a (or C3b), C5, and C6 to be `done`.

**Do**

1. Back up the app data and record the Home data counts.
2. Install a Debug build under a disposable probe bundle identifier if possible. Copy the E4B
   file into that app's Documents container. **Do not use `--remove-existing-content`.**
3. Measure the following:
   - Raw probe (`--litert-model-document <file>`): cold load, cached load, and one-sentence
     generation.
   - Production probe: the justice-and-mercy prompt.
   - A sustained run of 20 consecutive turns in the full app with the override path. Record
     peak resident memory (Instruments or the app's signposts), the thermal state over time,
     and the per-turn latency.
   - Five background/foreground cycles during generation, and one simulated memory warning.
   - That the app survives more than 60 seconds idle after generation.

**Gate**

- There is no jetsam or signal 9.
- Cold load is ≤ 12 s. Cached load is ≤ 3 s.
- The one-sentence answer takes ≤ 4 s.
- The justice-and-mercy answer finishes in ≤ 60 s.
- Thermal state never reaches `critical` during the 20 turns.
- Peak memory leaves the app running with no memory warnings in normal use.

These thresholds are about 2–3× the E2B device baseline (4.33 s load, 1.27 s answer). The user
may change them in the ledger's *Decisions*.

**Evidence:** the full measurement table, the device OS version, and the confirmation that the
backup was taken and data counts match afterward.

**On failure:** for memory or jetsam problems, try once with `maxNumTokens: 2_048`, set only
through a DEBUG experiment and not committed. If that passes, record it as a decision for the
user and do not promote. Otherwise mark C7 `failed`, and E2B stays.

### C8 — Promotion

Requires C7 to be `done` and **explicit user approval recorded in the ledger**.

**Do**

1. Update `LiteRTModelManifest.aquinas` in `Aquinas-iOS/Services/LiteRTModelStore.swift` with
   the new file name, byte count, and SHA-256. Update its comment to describe the E4B QAT
   package, and whether it is prebuilt or converted.
2. Place the package at `Aquinas-iOS/LocalModels/<new name>` as the development seed. Leave the
   old E2B file in `LocalModels/` at the repo root until the user signs off on removing it.
3. Update the comment on `LiteRTAquinasRuntime.visionBackend` so it no longer references the
   `wi8` E2B package. Stay text-only.
4. Update the docs in the same change:
   - Add a dated "Gemma 4 E4B QAT checkpoint" section to `MODEL-INTEGRATION.md`, with the
     measurements, and correct the stale `wi8` statement.
   - Update the model name in §2 "Current decisions".
   - Update `Model-Runtime.md`.
   - Mark this plan `executed` at the top.
5. Run the standard build and the full test suite. Do one final simulator smoke test without the
   override.
6. Open a PR from `feature/gemma4-e4b-qat`. Do not merge without the user.

**Gate:** the build and tests are green, the smoke test passes, and the PR is open.

**Evidence:** the commit hashes, the PR URL, and the rollback values: the old manifest and the
old file location.

### C9 — Optional: vision probe (never blocks)

With the promoted package, set `visionBackend` to `.gpu` in a DEBUG experiment. Attach one image
in the simulator and record whether the vision tower loads. Report only. Re-enabling vision is a
separate change.

## 6. Eval set

The eval set is the same for the baseline (C0) and E4B (C6). Use a stable `prompt-id` for each
prompt.

| prompt-id | Prompt | Checks |
| --- | --- | --- |
| `definition-prudence` | What is prudence? | Short, accurate |
| `moral-act-motive` | Can an otherwise good deed be morally tainted by an evil motive? | Dialectic depth |
| `mercy-justice` | Think carefully about whether mercy can conflict with justice. | Depth; no looping |
| `justice-mercy-repeat` | How can justice and mercy work together when someone repeatedly does wrong? | Probe default; depth |
| `trap-peloponnesian` | Was the Peloponnesian War part of the Greco-Persian Wars? | Must say no |
| `trap-nicaea` | When was the First Council of Nicaea and what did it address? | 325; Arianism |
| `trap-constantinople` | What did the First Council of Constantinople in 381 add to the creed? | Holy Spirit article |
| `trap-didache` | Who wrote the Didache? | States that the author is unknown or anonymous |
| `natural-law` | What is natural law? | `{{term}}` markers present |
| `essence-existence` | How does Aquinas distinguish essence from existence? | Named-entity fidelity; markers |
| `topic-shift` | Ask `mercy-justice`, then "What's the capital of Portugal?" | No stale-answer repeat |

The trap prompts come from failures recorded in `MODEL-INTEGRATION.md`. Grounding notes may
answer some of them directly. Record whether each answer came from grounding or from generation.

## 7. Definition of done

Either **promoted** (C8 `done`, PR open, docs updated) or **rejected with evidence** (a failed
gate recorded, E2B unchanged, and a ledger summary explaining why). Both outcomes are complete.
Leave the ledger with a final summary section filled in.
