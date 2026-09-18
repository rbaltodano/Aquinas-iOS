# iOS model runtime and recovery

Read the cross-repository [`MODEL-INTEGRATION.md`](../../Aquinas-Foundations/MODEL-INTEGRATION.md)
first. This document records iOS-specific runtime boundaries and validation rules.

## Runtime selection

`AquinasApplicationRuntime` selects `LiteRTAquinasModel` when a verified local package is
available and injects the same `LiteRTAquinasRuntime` into `ModelTaskQueue`. There must be one
process-scoped live engine and queue. `BackendAquinasModel` is a development recovery path when
local generation is unavailable; `MockAquinasModel` is restricted to previews and tests.

On-device conversation decoding is deterministic because sampled decoding corrupts the current
4-bit checkpoint. Local decoding currently yields completed text rather than reliable token
deltas. The app may present a safe, question-specific approach summary, but it must never expose
provider scratch work or chain-of-thought.

## Development backend and tree fallback

The FastAPI/MLX backend is useful for development integration, structured generation, and
MiniLM-backed conversation topology. A physical phone must not attempt a loopback backend URL.
When a backend is unreachable, iOS must clear unreachable tree-analysis work and show its limited
local fallback rather than remain indefinitely in a mapping state. That fallback is not MiniLM
parity.

## Model package and device safety

The local package is a large, gitignored artifact. Do not commit models, generated corpora, or
device data. Simulator inference is useful for iteration but does not replace real-device
memory, thermal, lifecycle, latency, or quality validation. The bundled framework supports arm64
simulators only; use a concrete arm64 destination.

Before device model experiments, back up the app's data. Do not use `devicectl` with
`--remove-existing-content true` against the production bundle. For an intentional backend quality
comparison, a Debug build may use `--force-backend-model`; release builds must ignore that
diagnostic override.
