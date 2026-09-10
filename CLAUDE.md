# Aquinas-iOS

SwiftUI iOS app for Aquinas, a Thomistic study/conversation app. Full repository guidelines (structure, style, commit conventions) live in [Aquinas-iOS/AGENTS.md](Aquinas-iOS/AGENTS.md) — read that before making changes.

Code safety checkpoint `35819d9` (`Integrate local Aquinas runtime and conversation workflows`)
is preserved in Git history. The working tree intentionally contains later uncommitted grounding,
topic-isolation, response-presentation, and Insight Tree fixes; inspect and preserve those changes
rather than resetting to the checkpoint merely because the tree is dirty.

## Model integration is live

**Corpus updates, September 7–9, 2026:** the bundled corpus now contains
**51,836 passages**. September 7 added Percival's *Seven Ecumenical Councils*,
Schaff's ecumenical creeds and the 1921 *Baltimore Catechism No. 3*; September
9 added Waterworth's 1848 *Canons and Decrees of the Council of Trent* and
Donovan's 1829 *Catechism of the Council of Trent*. Both backend export scripts
were rerun and all four assets copied into `Aquinas-iOS/LocalGrounding/` after
the final update; MiniLM remains FP32 and both fidelity checks passed. The fixed
curated-off eval remains **46/56 (82%)**. The September 7 expansion improved
church history 4/7 → 5/7 and creeds 1/2 → 2/2, but regressed out-of-scope
screening 7/7 → 5/7 (current pope and Vatican II now retrieve historical council
passages). The two September 9 primary-source additions made no result change on
that fixed set, which includes no Council of Trent or Roman Catechism question.
Do not describe either expansion as a net reliability improvement. Edition,
license, before/after and asset-hash evidence is in
`../Aquinas_Backend/corpus/expansion-2026-09-07/` and
`../Aquinas_Backend/corpus/authority-expansion-2026-09-09/`.

**Named-source routing, September 9, 2026:** an exact title such as “Council
of Trent,” “Roman Catechism,” “Nicene Creed,” or “Arius” now constrains ranking
to its exported document before the normal corpus-wide semantic search. Inside
that selected source, meaningful question terms rank matching passages; an
exact source-plus-term hit is a document lookup and may be below the global
semantic floor. It supplies no hand-written answer and leaves the 0.45/0.38
relevance floors unchanged. The Trent case requires the actual Session VI,
Chapter VII wording (“not remission of sins merely”), rather than a nearby
heading. With that stricter evidence, the 65-case evaluation is **59/65
(91%)**, including 9/10 church-history cases, 6/6 sacraments cases, and 4/4
catechism cases. The routing table is parsed from
`MiniLMGroundingProvider.swift` by the evaluator so its behavior cannot silently
diverge from the app. A second, narrower authority-section table resolves a
named authority plus its topic to a heading in the imported primary text:
Trent/justification, Eucharist, or penance; Nicaea/Christ; Chalcedon/Christ;
and the Roman Catechism on Baptism, Eucharist, or penance. These are
source-location pointers, never generated answers, and run before broad source
ranking. Each pointer retrieves the following chunks from the same source as
well, so a short heading is accompanied by its actual explanation. The direct-
evidence suite includes natural-language variants for each pointer and
retrieves the intended primary formulation.

**Evidence-first authority answers, September 10, 2026:** when an
authority-section pointer supplies the grounding, normal generation receives a
primary-source-only instruction and its required factual audit sees only those
section chunks. Both passes must remove claims not stated or plainly entailed
by the text; they must not fill gaps from general model knowledge. This is a
generation constraint, not a curated answer and not yet an end-to-end
generation-quality score. The prompt contract has a focused retrieval test;
the iPhone 17 simulator currently launches test suites but reports zero tests
executed with an unknown result, so validate the actual wording on device.

Before changing any model-facing code, read
[MODEL-INTEGRATION.md](../Aquinas-Foundations/MODEL-INTEGRATION.md). It is the cross-repo source of
truth for backend contracts, iOS seams, MiniLM relatedness, persistence, current status, and the
remaining implementation order.

An embedding-precision requantization is in progress to fix unreliable chapter/reference recall
(the shipped `dynamic_wi8_emb4_afp32` package's 4-bit embeddings were confirmed as the cause via a
controlled comparison, not the fine-tune). Full scoping, evidence, hard-won on-device testing
notes, and the phased game plan live in
[WI8AFP32-REQUANTIZATION-SCOPING.md](../Aquinas-Foundations/WI8AFP32-REQUANTIZATION-SCOPING.md) —
read it before touching model quantization/promotion. Delete that file and fold its lasting facts
in here once the initiative ships.

The live app is local-first when a verified LiteRT-LM package is available.
`AquinasApplicationRuntime` owns one process-scoped `LiteRTAquinasRuntime`, injects the same
runtime into `LiteRTAquinasModel` and `ModelTaskQueue`, and preserves serialized lifecycle,
streaming, and cancellation semantics. Ordinary local conversation is a single generation call:
the model writes the visible prose answer and marks important concepts, subjects, named ideas, and
specialized words inline at roughly Wikipedia-link frequency, wrapping just that word or short term
in `{{double curly braces}}`
exactly where it occurs. `LiteRTAquinasModel.inlineAnnotatedResponse` strips those markers back
out and turns each into a `KeyTerm`. Because the marker is removed in place — the surrounding
prose never moves — `displayText` is always an exact substring of the final answer by
construction, so there is no separate "recall this exactly" step for the model to get wrong the
way a second structured JSON pass repeatedly did. That two-pass design (full prose answer, then a
second full generation call re-reading it to produce a `key_terms` JSON array) and the
deterministic `NLTagger`/curated-vocabulary heuristic that briefly replaced it are both retired:
highlighting is solely the model's own in-context judgment on that single pass. Truly conversational
or trivial answers can legitimately carry zero highlighted terms, while substantive answers are
prompted to mark roughly 3-5 terms when short and 6-10 when concept-rich, with a validated ceiling
of 12 for genuinely subject-dense prose; there is still no heuristic
fallback if the model disobeys. Metadata can never replace, truncate, or leak into the visible answer,
since
stripping the markers is how the visible text is produced in the first place, not a downstream
validation step that can fail open or closed. While generation is incomplete, the UI reports
progress without presenting canned text as model reasoning. The completed public approach summary
is persisted in the branch and remains available through **Show Thinking** after view recreation
or relaunch. Ordinary conversation stays deterministic because sampled decoding was unsafe for
the retired 4-bit checkpoint; structured application operations are also deterministic. Direct
definition requests return Insight metadata. Special actions remain neutral and use validated
structured outputs. A non-cancellation local failure gets one local recovery attempt;
substantial separated phrase repetition and mixed-script token corruption are rejected.
When a repeated tail is detected, the runtime preserves the coherent prefix instead of discarding
the entire draft. Do not restore prompt-forced word targets or automatic short-answer retries: the
exact package entered slow rejected loops under that experiment.
LiteRT-LM currently emits the generated text only after native decoding finishes, so generation
has no automatic time cutoff; the Model Task Stop action remains available to the user.
The vendored `Vendor/LiteRTLM/swift/Engine.swift`/`Conversation.swift` wrapper (not upstream
pristine — a locally-modified SPM bump, safe to patch) runs `createConversation`, engine
initialization, and both types' native `deinit` teardown on a dedicated, disposable `Thread`
rather than directly on the `Engine`/`LiteRTAquinasRuntime` actor's own executor. A confirmed
upstream deadlock (`DEADLINE_EXCEEDED` in the native library's single-worker
`callback_thread_pool`, surfaced via live device console capture) can hang any of these calls
indefinitely; run on the actor's executor, a hang there permanently consumes one of the app's few
Swift Concurrency cooperative-pool threads, which can starve every other actor-isolated task in
the app — including the generation stall watchdog that exists specifically to detect and recover
from this exact hang. Never move this logic back onto the actor's own executor.
The Thinking summary is an app-generated public approach description, never private model
reasoning or chain-of-thought. It must describe the relevant concepts or checks without pretending
to expose hidden scratch work.
`AquinasGroundingProviding` is the factual-retrieval boundary. Do not assume this is still a small
hardcoded stopgap — the backend side of this is already a real general-corpus retrieval system, not
just a handful of curated chapters. `Aquinas_Backend/corpus/sources.yaml` manifests dozens of
public-domain sources (the full Bible, Aquinas's own works, patristic and conciliar texts, the
philosophical/historical sources he cites); `ingest_corpus.py` has already fetched most of them and
embedded them with MiniLM into a persisted Chroma collection (`grounding_retrieval.py`), and
`server.py` already retrieves nearest passages from that corpus and passes them into generation for
real conversation requests — this is live, not planned.
On-device parity is now closed, as of September 2026. `MiniLMGroundingProvider`/
`OnDeviceGroundingStore` (iOS) consume a flat pre-embedded export of the backend's corpus —
`Aquinas-iOS/LocalGrounding/` bundles `MiniLM.mlpackage` (a Core ML conversion of
`all-MiniLM-L6-v2`, verified at ~0.9999 cosine fidelity against the reference PyTorch model),
`vocab.txt`, `embeddings.bin`, and `passages.json` (48,048 passages exported from the backend's
Chroma collection via `Aquinas_Backend/scripts/export_on_device_grounding.py` and
`export_minilm_coreml.py`). `AquinasApplicationRuntime` tries `MiniLMGroundingProvider()` first and
only falls back to the small hardcoded `LocalAquinasGroundingProvider` stopgap (Nicaea (325),
Constantinople (381), Nicaea II (787), Didache notes, a curated Scripture subset) if those bundled
assets are somehow missing/corrupt. Re-run the two export scripts and re-copy `LocalGrounding/`
whenever the backend corpus grows meaningfully; there is no live sync between them. See
MODEL-INTEGRATION.md's "Backend retrieval-first grounding checkpoint" for the backend-side history,
and `Aquinas-Foundations/QWEN-TESTING-CASE-STUDY.md` for how this on-device gap was discovered.

"Retrieval returns real ranked passages" was the bar that closed parity; it is not the bar for
*correct* grounding, and a measured audit of the shipped export found semantic search alone failing
two whole classes of question. `MiniLMGroundingProvider` therefore assembles grounding in three
layers, most authoritative first — alias-matched curated facts, then explicitly cited scripture
chapters, then semantic search filling the remaining slots. Do not collapse this back into a single
nearest-neighbour call:

- **The corpus has almost no conciliar or creedal text.** Across all 48,048 passages "Nicene Creed"
  appears once (incidentally, in the Thirty-Nine Articles) and "begotten, not made" once, while
  roughly 28% of the corpus is classical secular history (Livy alone is 5,937 chunks against 5,973
  for the entire Bible). "What did the Council of Nicaea decide about the Son?" consequently ranked
  five straight Livy/Herodotus/Plutarch passages, matching on "council" and on *Nicaea the Greek
  city*. `LocalAquinasGroundingProvider.aliasMatchedReferences` supplies the curated anti-confusion
  facts that gap would otherwise lose. It matches on retrieval *aliases* only — the looser
  two-token overlap used by the fallback path is the right bar when those entries are the entire
  corpus, and far too loose when they are merged ahead of MiniLM for every question.
- **A citation is a lookup key, not a topic.** "John chapter 14" ranked Augustine's *Confessions*
  first and reached the Gospel of John only through a passage about *John Hyrcanus*, while the same
  question in prose retrieved the right chapter at 0.69 similarity. `ScriptureCitation` +
  `OnDeviceGroundingStore.chapter(for:)` resolve explicit references lexically against the corpus's
  own `[JHN14]` chapter tags (1,616 chapters index cleanly) before semantic search runs.
- **The relevance floor is a measured separation point, not a confidence level.**
  `defaultMaxDistance` was 1.0, which admits any non-negative similarity and so screened nothing —
  the Livy passages above (0.55) reached the prompt as grounding. Retrieving nothing is the correct
  outcome when the corpus has no real answer: generation proceeds ungrounded, which is strictly
  better than grounding it in Roman history.

  The floor is **tiered**, and a single global value provably cannot do this job. Loose enough to
  retrieve ordinary narrative scripture is also loose enough to readmit those Livy passages. So a
  semantic passage standing on its own only needs the standard floor (0.45 distance / 0.55
  similarity), while one added *alongside* an authoritative curated fact or cited chapter must
  clear `corroborationMaxDistance` (0.38 / 0.62). Padding a prompt that already contains the answer
  is not neutral: it is how the model ended up writing about John 4 when it had been handed John 14.

  Both numbers come from sweeping them against
  `Aquinas_Backend/evaluation/evaluate_retrieval.py`, not from eyeballing queries. An earlier 0.38
  global floor was calibrated only on doctrinal questions — where the Summa's "Whether X..."
  phrasing mirrors the question — and silently discarded the Lord's Prayer, the Good Samaritan and
  the prodigal son despite all three being in the corpus (61% overall). Do not retune either value
  without re-running that eval.

Reference ids from this provider are stable strings (`corpus-…`, `citation-…`) and the curated
layer keeps its own (`nicaea-325`, `constantinople-381`, …). That matters beyond tidiness:
`LiteRTAquinasModel.verifiedGroundedResponse` gates its verified answers on those exact curated ids,
so while the provider minted ids containing the float distance that path was silently unreachable
whenever MiniLM was active. Any future provider must keep emitting the curated ids.

The bundled `MiniLM.mlpackage` must be exported at **FP32** (`compute_precision=ct.precision.FLOAT32`
in `export_minilm_coreml.py`). coremltools defaults `mlprogram` conversion to FP16, and this model's
FP16 CPU execution path is numerically broken: it returns NaN under `ComputeUnit.CPU_ONLY` on macOS,
and in the iOS Simulator returns finite but badly wrong vectors. Because `MiniLMEmbedder` forces
`.cpuOnly` on the Simulator (the FP16 MPSGraph path is device-only), every Simulator retrieval
measurement was silently taken in a degraded embedding space — correct Summa hits scored ~0.50
against the corpus instead of ~0.84, and correct passages fell several ranks. This is what made
early smoke tests look like a corpus/chunking problem ("John chapter 14" ranking *Metaphysics*)
when the corpus was fine. The export's original fidelity check passed because it only exercised
Core ML's default compute path; it now verifies the CPU-only path explicitly, and that check is the
thing standing between this regression and a re-ship, so do not remove it. FP32 doubles the model
to ~86 MB, which is the correct trade for retrieval that works.

Retrieval reliability is measured, not asserted: `Aquinas_Backend/evaluation/evaluate_retrieval.py`
scores 65 questions against the real corpus and the real bundled Core ML model in seconds, with no
device needed. The historical fixed-set baseline is **46/56 (82%) with the curated layer off**;
the current expanded source-routing set is **59/65 (91%) under its stricter direct-evidence
checks**. The hand-written curated entries add
only a few points on top, which is the honest measure of how little they generalize, so adding more
of them is not a reliability strategy. Doctrine, sacraments, catechism, and creeds sit at 100%, church
history at 90%, and scripture at 100%. Run the eval before and after any change to chunking, weighting, thresholds,
or corpus contents.

Scripture retrieval was 50% until named passages were resolved lexically. Three hypotheses were
measured and two rejected: chunk boilerplate (`[MAT05]`, the WEB header, footnote cross-references
spliced mid-sentence) costs only ~0.05 similarity, and prepending descriptive headers gains
0.16-0.30 but is diluted by the 128-token window. The actual cause is that **MiniLM matches topics,
not names**. A descriptor containing the literal words "the Our Father" scores 0.345 against "What
is the Our Father?", and Matthew 5 scores 0.213 against "What are the Beatitudes?" because the word
"Beatitudes" never occurs in the chapter — it says "Blessed are...". No chunking or weighting change
fixes an embedder that does not do names, so `ScriptureCitation.namedPassages` resolves them the way
`John 14` is resolved: lexically, to a location in the real corpus. It hardcodes no answers, so it
serves any question about the passage rather than the one someone anticipated.

Some named stories begin after a chapter's opening chunk: the Good Samaritan is in the fourth Luke
10 chunk, while the chapter begins with the mission of the seventy. Those names now carry a literal
phrase from their primary text as an anchor, so retrieval begins at the passage itself; a missing
anchor returns no citation rather than silently falling back to unrelated material from the chapter.
An explicit question about the resurrection of Jesus or Christ is similarly a Gospel-event location:
it selects the opening resurrection chapters in all four Gospels, up to the normal passage limit.

The remaining 6 measured misses have distinct causes: absent coverage for lying, forgiveness, the
Didache, and Bible reliability; and false grounding for current-Pope and Vatican II questions. Do
not mask any of these with a curated answer. Source ingestion addresses only the absent-coverage
cases; the false-grounding cases need their own measured routing or abstention work.

One corpus-side gap remains open and needs backend ingestion plus a re-export: translation mismatch.
The export is the World English Bible, so familiar KJV phrasings miss ("Let not your heart be
troubled" scores 0.42 and retrieves Sirach, against a WEB text reading "Don't let your heart be
troubled").
Ordinary conversation generation stays fully deterministic (`topK: 1, temperature: 0`) even after
the meta-commentary/hedging guard below. A brief experiment added modest sampling to help escape a
hedge/clarification failure mode, but the direct fix (detecting that failure shape and retrying
once with an explicit anti-hedging instruction) already covers it, and the added randomness only
made hallucinated answers less consistent from run to run — it was reverted.
A response — on either the first generation pass or the factual-accuracy audit pass — that reads as
confused meta-commentary about the model's own draft or the user's question (for example, asking
the user to clarify an ordinary question, or describing a discrepancy it noticed in its own draft
rather than answering) is detected and never shown to the user: the audit pass discards such output
and keeps the prior draft, and the first pass gets one bounded retry with an explicit instruction to
answer directly instead.
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

The on-device fallback's Node-seeding pipeline (`LocalInsightTreeSeedStore`,
`insightTreeSeedCandidate`, `enqueueLocalInsightTreeSeedingTask`) asks the model to extract a
turn's main subject (label + summary) unconditionally, every turn — it no longer asks the model to
judge for itself whether that subject is "genuinely new." That self-judgment (`new_subject:
true/false` in the same call) was tried first and found unreliable and order-dependent: comparing
the same two subjects in one order the model correctly detected a pivot, in the reverse order on a
fresh conversation it didn't. The "is this actually new" decision is now made deterministically by
the caller via on-device `NLEmbedding` cosine similarity against the Node Concepts already seeded
for that conversation (`newSubjectThreshold`, currently `0.60`) — below it counts as new and gets
appended; at or above it, the turn is already covered and no seed is added. Quoting an Insight into
a new conversation seeds this store from that Insight immediately (`startNewConversation`) rather
than waiting on the first answer to generate one.

Local seed Nodes are fed into `InsightTreeViewModel.makeClusteredTree` as pre-existing anchor
clusters (`setLocalSeedAnchors`) rather than rendered through a separate `applyPersistedTree`
snapshot. An earlier version used `applyPersistedTree` for this, which permanently switches the
view model into backend-tree rendering mode; a saved Insight afterward would render once, then the
next seed update (or even just reopening the tree) would silently replace it with the bare
Node-only snapshot again, or vice versa — the two paths fought over which one owned the tree.
Routing both through the same clustering pass means a saved Insight close enough to a seeded
subject attaches under it like a real backend Node would, and one that isn't buds off into its own
cluster, using the same `localMembershipThreshold` (currently `0.60`; raised from MiniLM's default
`0.40` after on-device `NLEmbedding` was observed clustering distinct Bible/theology subjects
together at that lower bar). `InsightTreeViewModel`'s local-seed-aware `init` reads
`LocalInsightTreeSeedStore` synchronously at construction rather than only through the async
`.task`-driven load, so a fresh mount doesn't render a guaranteed blank-then-populated flash before
the seed catches up.

The production Aquinas package uses 8-bit decoder weights with 4-bit embeddings
(`dynamic_wi8_emb4_afp32`). It is 3,862,121,696 bytes with SHA-256
`9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282`, exactly matching
`LiteRTModelManifest.aquinas` and the bundled development seed. This package replaced the retired
2,722,385,120-byte 4-bit artifact because the latter exhibited repetition/looping. The 8-bit
package's initial Simulator GPU failure was confirmed to be Simulator-only; it runs on the 8 GB
base iPhone 17. A development bundle seed may provide the package today.
`LiteRTModelInstaller` can download, size-check, hash-check, and atomically install the package
into Application Support, but release delivery still needs a hosted model URL,
resumable/background transfer, storage/settings UI, and removal of the 3.86 GB bundled
development seed. Debug probes may pass `--litert-model-path /absolute/path/to/model.litertlm`
to test another exact package without replacing it. Never promote a candidate before base-iPhone
load, latency, memory, stability, and blind answer-quality gates pass; Simulator GPU initialization
alone is not a valid rejection signal for this LiteRT package family.

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
- Removing a quoted Insight's chip from the composer (`pendingStudyTopicQuoteReturn`, despite the
  name) returns to whichever tree it was quoted from — a Study Topic tree or the global Insight
  Tree — with that Insight hovered, rather than just clearing the chip. `topicID == nil` on the
  quote request routes to `onReturnToGlobalInsights`; non-nil routes to the existing
  `onReturnToStudyTopicTree`.
- The Home Question of the Day's source conversation is chosen deterministically
  (`DailyQuestionSourceSelector`), not randomly: Study Topic conversations are excluded, the
  currently active conversation is tried first, then the rest ordered by most-recently-created;
  within each, the first branch with both a real question and a ≥80-character answer wins. Cited
  Insights are scoped to that same chosen conversation's own concept words, matched against saved
  Insights.

## Sibling repos (context lives outside this repo)

- `../Aquinas-Foundations` — product source of truth: MISSION.md, DESIGN.md, SPECIFICATION.md,
  FUNCTIONALITY.md, MODEL-INTEGRATION.md, and INSIGHT-TREE.md. Consult DESIGN.md before visual work.
- `../Aquinas_Backend` — FastAPI + MLX backend used for structured conversation and definition
  generation plus MiniLM relatedness and persistent Insight Tree assignment.

## Build & verify

```sh
xcodebuild -project Aquinas-iOS.xcodeproj -scheme Aquinas-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The bundled LiteRT xcframework only ships an arm64 simulator slice, so `generic/platform=iOS
Simulator` fails to link (it also targets x86_64). Always build against a concrete arm64
simulator destination, not the generic one. The exact bundled fine-tuned LiteRT package supports
the arm64 iOS Simulator. Launching with
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

`ContentView` conditionally mounts `CurrentConversationView` only while `displayedPage ==
.conversation`; every other page switch fully tears it down and later recreates it, so any `@State`
that needs to survive a page switch (a pending navigation target, a "have I already handled this
request" counter) must be owned by `ContentView` and passed down as a `@Binding`, never declared as
local `@State` inside the conversation view itself. Two real bugs came from this: a fresh mount's
`.onAppear` used to pick the conversation purely from what was last persisted as active, ignoring a
pending `requestedConversationID` set before the view existed (fixed by checking it first); and
`handledNewConversationRequest` was local `@State`, defaulting to `0` on every remount, while the
`newConversationRequest` counter it's compared against is shared and persists for the whole app
session — once that counter had been incremented even once, every later remount spuriously
re-fired `startNewConversation()`, silently replacing whatever conversation had just correctly
loaded, including one still mid-generation. The underlying generation itself is unaffected by any
of this — it's owned by the shell-level `ModelTaskQueue`, not the view — but the completion
handlers a torn-down instance registered can still write into now-disconnected state.

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
- `Persistence/LocalInsightTreeSeedStore.swift` — on-device Node Concept seeds (label, summary,
  `NLEmbedding` vector) per conversation, used only when the backend-owned tree is unreachable.
