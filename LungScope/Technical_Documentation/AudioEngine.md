# AudioEngine.swift Technical Specification

## 📋 Architectural Purpose

`AudioEngine.swift` is the **Audio Layer orchestrator** — the file that wires `AudioFormat`, `AudioRingBuffer`, and `AtomicRecordingPhase` into a single cohesive audio capture session. It owns the `AVAudioEngine` instance, installs the hardware tap, manages microphone permission, routes incoming buffers to the correct ring buffer via the phase gate, and exposes a clean async API to the `AssessmentViewModel` above it.

This file represents the top of the Audio group and is the sole point of contact between the real-time hardware world and the structured concurrency world above it. All public methods are `async` and decorated with `@MainActor`, enforcing that session control always originates from the main thread — consistent with SwiftUI's threading model. The tap callback is the single synchronous, real-time boundary, and it crosses into safe territory exclusively through pointer writes into pre-allocated ring buffers.

This file satisfies **Sprint 1, Step 5** of the implementation plan — the final step that makes raw PCM audio flow end-to-end from the iPhone microphone into the DSP-ready ring buffers.

Within the Clean Architecture layering:
- **`AudioEngine`** is an infrastructure service in the Data layer
- **`AssessmentViewModel`** (UI layer) calls it through a protocol in a future sprint
- **`AudioAnalysisActor`** (DSP layer) receives the drained `[Float]` arrays from `stopAndDrain()` and performs all signal processing

---

## 🧬 Computer Science & Mathematical Deep Dive

### AVAudioEngine Tap Mechanism

`AVAudioEngine` is built on top of `AUGraph` / `AudioUnit` rendering. When `installTap(onBus:bufferSize:format:)` is called on the input node, the OS schedules the provided closure as a **render callback** on a real-time Mach thread with elevated scheduling priority. The `bufferSize` parameter (4096 frames) is a hint — the actual delivery size is determined by the hardware I/O buffer duration (typically 512–4096 frames at 16kHz, i.e. 32–256ms).

At 16kHz with a 4096-frame buffer, the tap fires approximately every **256ms**, delivering a pointer to a contiguous `Float32` array of 4096 samples. The tap does not own this memory — it is a view into an internal `AudioUnit` render buffer that will be overwritten on the next callback. The ring buffer write must therefore complete before the next callback fires.

### Sample Rate Conversion

iPhones hardware-sample at 48kHz natively. When `AudioFormat.makeConverter` returns a non-nil `AVAudioConverter`, the tap callback routes each incoming buffer through `convertBuffer(_:using:)`. This function:

1. Allocates a new `AVAudioPCMBuffer` for the output — **this allocation is unavoidable** inside the converter path and is why the converter path is a separate function from the zero-allocation fast path
2. Calls `converter.convert(to:error:inputBlock:)` with a pull-model callback
3. Returns the 16kHz Float32 output buffer

The allocation of the output buffer inside `convertBuffer` is a known cost of using `AVAudioConverter` in a tap. On devices that already run at 16kHz natively (or where the app's `AVAudioSession` category forces 16kHz), `makeConverter` returns `nil` and this allocation never occurs. For the thesis, the architecture explicitly documents this tradeoff.

### Phase-Gated Ring Buffer Write (`writeBuffer`)

`writeBuffer(_:to:)` performs a single `switch` on the current `RecordingPhase` value (a one-byte integer read under `OSAllocatedUnfairLock`) and dispatches to either `coughBuffer.write` or `vowelBuffer.write`. This is the hottest path in the entire application — it executes ~4 times per second at 4096-frame buffers and must complete in microseconds.

The `guard phase != .idle else { return }` early-exit in `handleBuffer` ensures the ring buffers receive zero writes before `startCoughPhase()` is called or after `stopAndDrain()` transitions to `.idle` — providing a clean session boundary with no sample leakage between sessions.

### `@MainActor` Isolation

`AudioEngine` is marked `@MainActor`. This means all public methods (`prepare()`, `startCoughPhase()`, `startVowelPhase()`, `stopAndDrain()`) are isolated to the main actor and are safe to call directly from `AssessmentViewModel`. The tap callback closure captures `[weak self]` — a deliberate choice to avoid the tap holding a strong reference to the engine after `stopAndDrain()` is called, which would prevent deallocation until the tap is fully torn down by the OS.

The tap itself executes on a real-time OS thread — entirely outside the main actor's execution context. This is the correct and expected behaviour: the tap is not `async`, it is a C-level callback, and it communicates with the actor-isolated state only through the lock-protected `AtomicRecordingPhase` read and the pre-allocated ring buffer pointer writes.

---

## 🧵 Thread & Memory Safety Profile

### Three Concurrent Contexts

| Context | Who Runs Here | What They Access |
|---|---|---|
| `@MainActor` (main thread) | `AssessmentViewModel`, `AudioEngine` public methods | `engine`, `phaseController.transition()`, `stopAndDrain()` |
| Real-time audio thread | `AVAudioEngine` tap callback | `phaseController.phase` (read), ring buffer `write()` |
| Background (optional) | `convertBuffer` converter allocation | Temporary `AVAudioPCMBuffer` |

These three contexts access disjoint state except for `phaseController`, which uses `OSAllocatedUnfairLock` to guarantee safe concurrent access (see `RecordingPhase.md` for full analysis).

### `[weak self]` in Tap Closure

The tap closure captures `self` weakly. If `AudioEngine` is deallocated while the tap is still installed (e.g. due to an error path), the closure safely becomes a no-op rather than accessing dangling memory. `stopAndDrain()` calls `removeTap(onBus:)` and `engine.stop()` before returning — ensuring the tap is torn down before the `AudioEngine` instance can be released.

### `AVAudioConverter` Output Buffer Allocation

`convertBuffer(_:using:)` allocates one `AVAudioPCMBuffer` per tap invocation on devices requiring sample rate conversion. This allocation occurs on the real-time thread but is **unavoidable** given `AVAudioConverter`'s API contract. It is isolated to the converter path (exercised only when hardware rate ≠ 16kHz) and documented explicitly here. Devices where `makeConverter` returns `nil` have zero allocations in the tap.

### `os_log` in Tap (Prohibited)

`os_log` calls in `handleBuffer` and `writeBuffer` are intentionally absent. `os_log` is not real-time safe — it acquires internal locks and may call into the system logger. All `os_log` usage in `AudioEngine` is confined to the main-thread lifecycle methods (`prepare`, `startCoughPhase`, `stopAndDrain`).

---

## 🔌 Public API & Data Flow

### `func prepare() async throws`
- Requests `AVAudioApplication.requestRecordPermission()`, configures engine, installs tap, starts engine
- Throws `AudioEngineError.microphonePermissionDenied` if user denies access
- Must be called once before any phase methods
- Data flow: `AssessmentViewModel.startAssessment()` → `prepare()`

### `func startCoughPhase()`
- Resets `coughBuffer`, transitions phase to `.cough`
- Data flow: phase gate opens for `coughBuffer` writes in tap

### `func startVowelPhase()`
- Resets `vowelBuffer`, transitions phase to `.vowel`
- Data flow: phase gate switches from `coughBuffer` to `vowelBuffer` writes in tap

### `func stopAndDrain() -> (cough: [Float], vowel: [Float])`
- Transitions phase to `.idle`, removes tap, stops engine
- Returns `(coughBuffer.drainToFloat(), vowelBuffer.drainToFloat())`
- Data flow: `AssessmentViewModel` → `stopAndDrain()` → tuple passed to `AudioAnalysisActor`

### `AudioEngineError`
| Case | Description |
|---|---|
| `.microphonePermissionDenied` | User denied microphone access; surface via alert in `AssessmentViewModel` |
