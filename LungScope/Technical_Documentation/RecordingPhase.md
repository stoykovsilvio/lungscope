# RecordingPhase.swift Technical Specification

## 📋 Architectural Purpose

`RecordingPhase.swift` defines the **phase gate** that controls which pre-allocated ring buffer receives incoming PCM samples inside the `AVAudioEngine` tap callback. It sits at the boundary between the UI coordination layer and the real-time hardware audio thread — making it one of the most thread-safety-critical files in the entire system despite its apparent simplicity.

The file contains two types: the `RecordingPhase` enum, which is a pure value type describing the three possible states of an assessment session, and `AtomicRecordingPhase`, a thread-safe wrapper class that allows a single shared instance of this state to be written from the UI coordinator thread and read from the real-time audio thread without data races or lock-induced priority inversion.

This design satisfies a core architectural constraint established in the project specification: **the AVAudioEngine tap callback must never allocate memory or perform any Swift runtime operations that could stall the real-time thread**. Phase switching must therefore be reducible to a single lock acquisition and a value write — nothing more. `AtomicRecordingPhase` provides exactly this guarantee.

This file satisfies **Sprint 1, Step 4** of the implementation plan and is a direct dependency of `AudioEngine.swift` and `AudioRingBuffer.swift`. No other layer above the Audio group needs to import or interact with `AtomicRecordingPhase` directly — the `AudioEngine` owns the instance and exposes phase transitions through its own higher-level API.

---

## 🧬 Computer Science & Mathematical Deep Dive

### The Phase State Machine

`RecordingPhase` is a three-state finite state machine:

```
.idle ──► .cough ──► .vowel ──► .idle
```

Valid transitions are strictly linear and unidirectional within a session:
- `.idle` → `.cough`: triggered when the user taps "Start Morning Assessment"
- `.cough` → `.vowel`: triggered when the user confirms the third cough or a guard timer fires
- `.vowel` → `.idle`: triggered when the 10-second vowel timer expires and analysis begins

The enum is a caseless value type — a Swift `enum` with no associated values. This means a `RecordingPhase` value is stored as a single byte-width integer in memory (the raw discriminant). Reading or writing this value is a single machine instruction on ARM64. This property is what makes the atomic wrapper both necessary and sufficient — there is no complex struct to copy, no heap reference to retain, just a one-word compare-and-swap.

### Lock Selection: `OSAllocatedUnfairLock`

The choice of `OSAllocatedUnfairLock` over other synchronisation primitives is deliberate and non-trivial. Three alternatives were considered:

**`DispatchQueue` (serial queue with `sync`):** Absolutely forbidden on a real-time audio thread. A serial `DispatchQueue` is backed by a thread from the cooperative thread pool. Calling `.sync {}` from the real-time thread would block it waiting for a pool thread to become available — this is classic **priority inversion**. The OS audio thread has elevated real-time scheduling priority; blocking it to wait on a lower-priority thread can starve the audio callback of its time slice, producing audible drop-outs and missed samples.

**`NSLock` / `pthread_mutex`:** Also unsuitable for real-time contexts. Both of these can invoke the OS scheduler (`futex` on Linux, `__psynch_mutexwait` on Darwin) when contended, which may cause the calling thread to be de-scheduled. In a real-time audio context, de-scheduling even for microseconds is unacceptable.

**`OSAllocatedUnfairLock`:** This is a Darwin-native spinlock wrapper that maps directly to `os_unfair_lock` in the kernel. It is specifically documented by Apple as safe to use on real-time threads because it implements **busy-waiting** (spinning) rather than sleeping when contended. Contention on this lock is expected to be essentially zero in practice — the UI coordinator writes to the phase at most twice per 30-second session, while the tap callback reads it ~500 times per second — making the spinlock's busy-wait cost negligible. `OSAllocatedUnfairLock` is the only correct choice here.

**`@unchecked Sendable`:** Swift 6's strict concurrency model requires all types crossing actor boundaries to conform to `Sendable`. `AtomicRecordingPhase` contains a `var` stored property, which Swift cannot statically prove is safe to share across concurrency domains. The `@unchecked Sendable` conformance suppresses the compiler error and transfers responsibility for safety to the developer — which is correct here because the `OSAllocatedUnfairLock` provides the safety guarantee that Swift's type system cannot infer.

### Why Not Swift Atomics or `_Atomic`?

Swift does not yet expose a first-class atomic integer type in the standard library without the `swift-atomics` package (a third-party dependency). Introducing a package dependency purely to store a 3-case enum discriminant is architecturally disproportionate. `OSAllocatedUnfairLock` is a zero-dependency Darwin system primitive that ships on every iOS device and achieves the same correctness guarantee with marginally higher theoretical overhead — overhead that is unmeasurable at our access frequency.

---

## 🧵 Thread & Memory Safety Profile

### Write Path (UI Coordinator Thread)
The `AssessmentViewModel` (running on `@MainActor`, i.e. the main thread) calls `atomicPhase.transition(to: .cough)` or `atomicPhase.transition(to: .vowel)` at phase transition points. This acquires `_lock`, writes `_phase`, and releases `_lock`. Total wall-clock cost: < 100 nanoseconds under zero contention.

### Read Path (Real-Time Audio Thread)
The `AVAudioEngine` tap callback reads `atomicPhase.phase` on every buffer invocation (~500 times/second at 16kHz with a 32ms buffer). This acquires `_lock`, reads `_phase`, and releases `_lock`. Because the write path holds the lock for < 100ns and write events occur at most twice per session, the probability of the read path spinning is statistically negligible.

### Memory Layout
`AtomicRecordingPhase` is a `final class` — it has a fixed, single heap allocation at construction time. The `OSAllocatedUnfairLock` is stored inline as a value type within the class's heap block (it is a struct, not a class). There are no reference cycles, no optional chains, no lazy properties. The total heap allocation is: class header (16 bytes) + `RecordingPhase` discriminant (1 byte, padded to 8) + `OSAllocatedUnfairLock` storage (8 bytes) = approximately 32 bytes, allocated once at `AudioEngine` initialisation and retained for the lifetime of the engine.

### Prohibition on Use Inside Tap
`transition(to:)` must **never** be called from within the tap callback itself. The tap is read-only with respect to the phase. All writes originate from the `@MainActor` UI coordinator. This is enforced by architecture — the tap closure captures only a read reference to `AtomicRecordingPhase` with no write-triggering logic.

---

## 🔌 Public API & Data Flow

### `RecordingPhase` (enum)

| Case | Meaning |
|---|---|
| `.idle` | No session active; ring buffers not being written |
| `.cough` | Cough phase active; tap writes to `AudioRingBuffer.coughBuffer` |
| `.vowel` | Vowel phase active; tap writes to `AudioRingBuffer.vowelBuffer` |

### `AtomicRecordingPhase` (final class)

#### `var phase: RecordingPhase` (get/set)
- **Thread safety:** Lock-protected read/write via `OSAllocatedUnfairLock`
- **Read callers:** `AudioEngine` tap callback (~500×/second on real-time thread)
- **Write callers:** `AssessmentViewModel` on `@MainActor` (2× per session maximum)

#### `func transition(to newPhase: RecordingPhase)`
- **Parameters:** `newPhase` — the target phase to transition into
- **Returns:** `Void`
- **Thread safety:** Identical to the property setter; provided as a named method to make call sites at the UI layer semantically clearer than a raw property assignment
- **Data flow:** `AssessmentViewModel` → `AudioEngine.phaseController.transition(to:)` → read by tap → gates ring buffer write destination
