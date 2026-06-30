# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Acoustic LungScope** — an on-device, privacy-first iOS respiratory diagnostics app. Users perform a 30-second morning assessment (3 forced coughs + 10-second sustained "Ahhh" vocalization). The app extracts DSP features on-device and runs CoreML inference to produce an Airway Constriction Index and Vocal Harmony Stability Score. Zero network calls. Zero audio leaves the device.

## Build & Test

This is an Xcode project. All commands assume you are inside the `lungscope/` directory.

```bash
# Build (replace scheme/destination as needed)
xcodebuild -scheme LungScope -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all unit tests
xcodebuild -scheme LungScope -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class
xcodebuild -scheme LungScope -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LungScopeTests/JitterShimmerTests test

# Export CoreML model from Python training pipeline
cd Scripts && python export_to_coreml.py
```

Linting is not yet configured. When added, document it here.

## Architecture

The system enforces a strict three-layer boundary. Data flows in one direction only: **Hardware → Processing Actor → View**.

### Layer 1 — Audio/ (Real-Time Thread)

`AVAudioEngine` installs a tap on the hardware input node. The tap callback runs on a high-priority OS audio thread and must **never allocate memory or touch Swift heap-managed types**. Its only job is to copy incoming `AVAudioPCMBuffer` samples into pre-allocated ring buffers via `UnsafeMutableBufferPointer`.

- Audio is captured in a **single continuous session** spanning both assessment phases. The engine never stops between the cough phase and vowel phase — only an atomic `RecordingPhase` enum flip gates which ring buffer receives samples.
- Hardware format is locked to **16kHz / 16-bit / mono** at engine initialisation. If the device's native rate differs (common on newer iPhones which default to 48kHz), an `AVAudioConverter` is pre-warmed before the session starts.
- Ring buffer sizes are pre-calculated at engine-start: cough window ~5s (160KB), vowel window 10s (320KB).

### Layer 2 — DSP/ (Background Actor)

`AudioAnalysisActor` is a Swift `actor` that owns the read-side of both ring buffers and all signal processing. It is only ever called after a recording phase completes — never concurrently with the tap.

All float math **must** use Apple's `Accelerate` framework (`vDSP`, `vForce`). No hand-rolled float loops where an Accelerate primitive exists.

Key algorithms:
- **FFT + Mel filterbank + MFCC** — applied to the cough buffer; quantifies spectral flatness and energy distribution across the Mel scale to detect airway obstruction signatures.
- **Jitter** — YIN or autocorrelation F0 extraction cycle-by-cycle on the vowel buffer; formula: `Σ|T_i - T_{i+1}| / (N-1) × T̄`. Spikes indicate inability to maintain steady airflow.
- **Shimmer** — per-cycle peak amplitude detection under the same F0 segmentation; analogous amplitude perturbation ratio. Computed from the same vowel buffer pass as Jitter.

Each DSP module (`JitterCalculator`, `ShimmerCalculator`, `FFTProcessor`, etc.) is a pure function over `[Float]` — no side effects, no actor state — so they are independently unit-testable by feeding synthetic sine waves with known perturbation values.

### Layer 3 — UI/ (@MainActor)

`AssessmentViewModel` is the single `@MainActor`-bound source of truth. It exposes:
- `appPhase: AppPhase` — drives the `AssessmentCoordinatorView` phase-switching container
- `diagnosticResult: DiagnosticResult?` — set exactly once when the actor finishes

The only crossing point between Layer 2 and Layer 3 is `await MainActor.run { viewModel.diagnosticResult = result }`. No `DispatchQueue.main.async`. No intermediate partial state exposed to views.

**Waveform visualisation** during the cough phase uses a separate downsampled display buffer. The tap computes one RMS value per ~512 samples using `vDSP_rmsqv` and posts it at ≤30fps to a `@MainActor` display queue. Full-resolution samples are preserved in the ring buffer; the waveform animator never touches them.

### Domain/

Pure Swift value types (`DiagnosticResult`, `AssessmentSession`). No UIKit or SwiftUI imports. All DSP unit tests import only `Domain` — this must remain true so tests can run headless without the UI framework.

### ML/

`DiagnosticInferenceEngine` wraps the CoreML model call. `FeatureVector` is a typed struct mapping DSP outputs to model inputs. The compiled `.mlmodelc` binary is not committed to git; `Scripts/export_to_coreml.py` produces it from the training pipeline. Document the model's training data provenance and accuracy metrics in `ML/model_card.md`.

### Scripts/ (off-device, not compiled into the app)

Python tooling for the training pipeline:
- `train_model.py` — trains the tabular ensemble (Random Forest / XGBoost)
- `validate_features.py` — DSP output sanity checks against reference signals
- `export_to_coreml.py` — converts the trained model to `.mlmodel` via `coremltools`

## Hard Constraints

- **No memory allocation inside the AVAudioEngine tap callback.** This is the most critical invariant in the codebase. Violations cause real-time thread stalls that manifest as audio drop-outs and missed samples.
- **No network calls anywhere.** `NSAllowsArbitraryLoads` is `false`. The app requests exactly one permission: `NSMicrophoneUsageDescription`.
- **No legacy completion handlers.** All async boundaries use `async/await` and structured concurrency. The tap callback is the one unavoidable synchronous boundary — it bridges to async territory only via the pre-allocated ring buffers, never by calling into Swift's async runtime from within the tap closure.
- **Accelerate for all DSP math.** This offloads vector operations onto the iPhone's SIMD hardware and is required for the <3s inference target.
