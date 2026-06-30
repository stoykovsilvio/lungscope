# MelFilterbank.swift Technical Specification

## 📋 Architectural Purpose

`MelFilterbank.swift` bridges the linear-frequency magnitude spectrum output of `FFTProcessor` to the perceptually-scaled frequency representation required by `MFCCExtractor`. It implements the **Mel-scale triangular filterbank** — the second stage in the classic MFCC extraction pipeline — converting a per-frame magnitude spectrum of 257 linear-frequency bins into 26 log-compressed Mel-scale filter energies per frame.

The Mel scale is a psychoacoustic frequency scale that models the non-linear frequency sensitivity of the human auditory system. The cochlea resolves frequency differences more finely at low frequencies (below ~1kHz) and more coarsely at high frequencies. By mapping FFT bins onto this perceptual scale before extracting cepstral coefficients, the MFCC features capture respiratory sound characteristics in a way that correlates more strongly with perceptually meaningful acoustic events — the low-frequency turbulent rumble of a constrained airway, the mid-frequency harmonic structure of a healthy vowel — than a linear-frequency representation would.

This file satisfies **Sprint 2, Step 8** of the implementation plan. It is a pure computation class with no side effects, making it fully unit-testable: given a known synthetic spectrum, the expected filterbank energy output is mathematically deterministic.

---

## 🧬 Computer Science & Mathematical Deep Dive

### The Mel Scale

The Mel scale maps physical frequency (Hz) to perceived pitch (Mel) via the O'Shaughnessy (1987) formula:

```
mel(f) = 2595 × log₁₀(1 + f / 700)
```

The inverse is:

```
hz(m) = 700 × (10^(m / 2595) − 1)
```

Key property: at low frequencies (< 500 Hz), the Mel scale is nearly linear. Above 1kHz it becomes increasingly logarithmic. This means Mel filters are narrow at low frequencies (high resolution) and wide at high frequencies (low resolution) — exactly matching the cochlea's tonotopic frequency resolution.

At 16kHz with 26 filters spanning 80–7,600 Hz:
- Filter 1 centre ≈ 154 Hz (bandwidth ≈ 75 Hz — narrow, resolves cough fundamental)
- Filter 13 centre ≈ 1,340 Hz (bandwidth ≈ 260 Hz — mid, resolves vocal harmonics)
- Filter 26 centre ≈ 6,900 Hz (bandwidth ≈ 1,400 Hz — wide, broad high-frequency envelope)

### Triangular Filter Construction

Each of the 26 filters is a triangular weighting function over the FFT magnitude bins:

```
H_m(k) = 0                           if k < f(m−1)
        = (k − f(m−1)) / (f(m) − f(m−1))    if f(m−1) ≤ k < f(m)
        = (f(m+1) − k) / (f(m+1) − f(m))    if f(m) ≤ k < f(m+1)
        = 0                           if k ≥ f(m+1)
```

where `f(m−1)`, `f(m)`, `f(m+1)` are the left edge, centre, and right edge bin indices of filter `m`, computed by equally spacing `filterCount + 2` points on the Mel scale and converting back to FFT bin indices.

These 26 filter functions are pre-computed at `init` time and stored as a row-major matrix of shape `[26 × 257]`. The vast majority of entries are zero (each filter only spans a contiguous range of bins); the non-zero weights are the rising and falling triangular slopes.

### Matrix-Vector Multiply (`vDSP_mmul`)

Applying all 26 filters to a single magnitude spectrum reduces to one matrix-vector multiply:

```
energies[26] = filterMatrix[26 × 257] × spectrum[257]
```

`vDSP_mmul` executes this via BLAS-level NEON SIMD, performing 26 × 257 = 6,682 multiply-accumulate operations in a single vectorised call. On an A-series chip this completes in approximately 2–5 microseconds per frame.

### Log Compression (`vvlogf`)

After the matrix multiply, filter energies are log-compressed:

```
logEnergy[m] = log(max(energy[m], ε))    ε = 1×10⁻¹⁰
```

The `max` floor prevents `log(0)` (which would produce `-inf`) when a filter energy is zero — possible for very quiet frames or when a filter spans a spectral null. `vvlogf` computes the natural logarithm of all 26 values in a single vectorised call using Apple's `vForce` framework, which maps to hardware-accelerated transcendental function evaluation on ARM64.

The result is 26 log-compressed Mel filterbank energies per frame, each typically in the range `[-23, 0]` (since input energies are normalised magnitudes in `[0, 1]`). These are the direct input to the DCT in `MFCCExtractor`.

---

## 🧵 Thread & Memory Safety Profile

### Filter Matrix Pre-computation

`buildFilterMatrix` is called once inside `init`, on the background actor's executor. The resulting `[Float]` array is stored as an immutable `let` property — it is never modified after construction. This makes `MelFilterbank` safe to read from multiple concurrent contexts without locking, although in practice it is only called sequentially from `AudioAnalysisActor`.

### Per-Frame Local Allocations

`apply(to:)` allocates `energies`, `floored`, and `logEnergies` as local `[Float]` arrays per frame. These are small (26 floats = 104 bytes) and short-lived. Given that a typical cough segment produces ~100–200 frames, the total allocation per analysis pass is ~20KB — negligible on modern iOS hardware and appropriately bounded.

### No Shared Mutable State

`MelFilterbank` has no mutable instance properties after `init`. All computation is functional: a frame spectrum goes in, log-energies come out. There are no write dependencies between frames, making the computation trivially parallelisable (though `AudioAnalysisActor` processes frames sequentially for simplicity).

---

## 🔌 Public API & Data Flow

### `init(filterCount:fftSize:sampleRate:lowFreqHz:highFreqHz:)`
- **filterCount:** 26 (standard for 13-coefficient MFCC). Increase to 40 for higher-resolution features.
- **fftSize:** Must match the `FFTProcessor` instance. Default 512.
- **sampleRate:** Must match `AudioFormat.sampleRate`. Default 16,000 Hz.
- **lowFreqHz / highFreqHz:** Frequency bounds of the filterbank. 80–7,600 Hz captures full cough and vowel range.
- Pre-computes and stores `filterMatrix` of shape `[filterCount × magnitudeBinCount]`.

### `func apply(to spectra: [[Float]]) -> [[Float]]`
- **Input:** `[[Float]]` of shape `[frameCount × 257]` from `FFTProcessor.magnitudeSpectra(from:)`
- **Output:** `[[Float]]` of shape `[frameCount × 26]`, log-compressed Mel filterbank energies
- **Data flow:** `FFTProcessor` → `MelFilterbank.apply(to:)` → `MFCCExtractor.extract(from:)`
- **Threading:** Background actor only
