# AudioRingBuffer.swift Technical Specification
*(Updated: Float32 revision)*

## 📋 Architectural Purpose

`AudioRingBuffer.swift` is the **memory contract** between the real-time hardware audio thread and the background DSP analysis layer. It is the most safety-critical file in the Audio group because it is directly written to by the `AVAudioEngine` tap callback — a function executing on a high-priority real-time OS thread where heap allocation, ARC retain/release, and Swift runtime calls are forbidden.

The class implements a classic **circular buffer** backed by a manually managed block of `UnsafeMutableBufferPointer<Float>` memory. All memory is allocated once at initialisation. The write path performs only pointer arithmetic and `initialize(from:count:)` memory copies — no Swift objects are created, no reference counts are modified, no allocator is called.

Two instances exist, both owned by `AudioEngine`:
- `coughBuffer`: capacity `AudioFormat.coughWindowSamples` (80,000 samples / 5 seconds / 320KB)
- `vowelBuffer`: capacity `AudioFormat.vowelWindowSamples` (160,000 samples / 10 seconds / 640KB)

**Revision note:** Storage type updated from `Int16` to `Float32` to match `AudioFormat.canonical`'s Float32 PCM format. The `drainToFloat()` method now uses `vDSP_mmov` (a vectorised memory copy) instead of `vDSP_vflt16` + `vDSP_vsdiv`, since samples arrive pre-normalised from the hardware driver — no integer-to-float conversion or normalisation step is required.

This file satisfies **Sprint 1, Step 3** of the implementation plan.

---

## 🧬 Computer Science & Mathematical Deep Dive

### Ring Buffer Algorithm

A ring buffer treats a fixed-size array as circular by wrapping a write head pointer modulo the array capacity:

```
writeHead = (writeHead + samplesWritten) % capacity
```

This produces O(1) writes regardless of buffer fullness and retains the most recent `capacity` samples automatically when the buffer fills — correct semantics for a bounded recording window.

A write of `N` samples decomposes into at most two contiguous `memcpy`-equivalent operations:

```
firstChunk  = min(N, capacity - writeHead)   // samples until end of array
secondChunk = N - firstChunk                  // samples that wrap to index 0
```

When `writeHead + N ≤ capacity`, `secondChunk == 0` and one copy suffices. This two-copy maximum is a proven property of ring buffers and is the basis for their universal adoption in real-time audio systems.

### Float32 Storage

Samples are stored as `Float32` matching `AudioFormat.canonical`. At 4 bytes per sample:
- Cough buffer: 80,000 × 4 = 320KB
- Vowel buffer: 160,000 × 4 = 640KB

Both fit comfortably within L3 cache on A-series chips (~8–16MB), meaning `drainToFloat()` reads are served from cache rather than main memory — important for keeping DSP latency under the 3-second target.

### Accelerate-Backed Read (`vDSP_mmov`)

`drainToFloat()` uses `vDSP_mmov` to copy the Float32 samples from the ring buffer into the output array. `vDSP_mmov` maps to NEON SIMD on ARM64, processing 4 floats per cycle. For the 160,000-sample vowel buffer this completes in ~40,000 NEON cycles — under 15 microseconds on an A15 Bionic.

Chronological reconstruction when the buffer has wrapped: the oldest sample is at `writeHead`, so the read is split identically to the write — `firstChunk` from `writeHead` to end, `secondChunk` from 0 to the remaining count. If the buffer has not wrapped (`storedCount < capacity`), all samples are at indices 0..storedCount-1 and a single copy suffices.

---

## 🧵 Thread & Memory Safety Profile

### Manual Memory Management
- `allocate(capacity:)` — one `malloc` at `init` time
- `initialize(repeating:0, count:)` — zero-fills the allocation, preventing reads of uninitialised memory
- `deallocate()` in `deinit` — one `free` when `AudioEngine` is torn down
- No ARC-managed objects in the backing store; no reference cycles

### Write Path — Real-Time Thread Safety
`write(from:count:)` performs only pointer arithmetic and `initialize(from:count:)`. No allocations, no ARC, no locks. The force-unwrap on `buffer.baseAddress!` resolves to a direct pointer dereference at compile time — not an optional chain that touches the runtime.

### Read/Write Non-Overlap Guarantee
There are no locks between the write path and `drainToFloat()`. Safety is enforced by the session state machine: `AudioEngine` transitions `AtomicRecordingPhase` to `.idle` and removes the tap before calling `AudioAnalysisActor`, which is the sole caller of `drainToFloat()`. If a Thread Sanitiser violation appears on `writeHead` or `storedCount`, the root cause is in `AudioEngine`'s phase transition sequencing, not in `AudioRingBuffer`.

---

## 🔌 Public API & Data Flow

### `init(capacity: Int)`
- Allocates `capacity × 4` bytes. Call before engine starts, on any non-real-time thread.

### `func write(from pointer: UnsafePointer<Float>, count: Int)`
- Real-time thread safe. Writes `count` samples from `floatChannelData[0]` into the ring.
- Data flow: `AVAudioEngine tap` → `AudioEngine.writeBuffer(_:to:)` → `write(from:count:)`

### `func drainToFloat() -> [Float]`
- Returns chronologically ordered `[Float]`, normalised `[-1.0, 1.0]`. Background thread only.
- Data flow: `AudioEngine.stopAndDrain()` → `drainToFloat()` → `AudioAnalysisActor`

### `func reset()`
- Resets `writeHead` and `storedCount` to 0. Does not zero backing memory. Background thread only.

### Diagnostics
| Property | Type | Description |
|---|---|---|
| `count` | `Int` | Number of valid samples currently stored |
| `isFull` | `Bool` | `true` when `storedCount == capacity` |
