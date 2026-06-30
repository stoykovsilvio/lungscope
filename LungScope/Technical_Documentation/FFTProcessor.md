# FFTProcessor.swift Technical Specification

## 📋 Architectural Purpose

`FFTProcessor.swift` is the **spectral decomposition engine** of the Acoustic LungScope DSP pipeline. It transforms time-domain Float32 PCM samples from the cough ring buffer into a two-dimensional array of magnitude spectra — one spectrum per overlapping analysis frame — that serves as the input to both `MelFilterbank` (for MFCC extraction) and `SpectralFlatness` (for airway obstruction scoring).

This file is the first purely mathematical component in the system. It has no knowledge of audio capture, UI state, or machine learning. It is a pure function over `[Float]` → `[[Float]]`, making it independently unit-testable by feeding a synthetic sine wave and asserting that the expected frequency bin carries the expected energy.

Within the DSP layer architecture, `FFTProcessor` sits at the bottom of the analysis stack. Every higher-level feature — Mel filterbank energies, MFCCs, spectral flatness — is derived from the magnitude spectra it produces. Correctness here propagates upward to every downstream feature and ultimately to the CoreML model's predictions. A bug in the FFT scaling or windowing would corrupt the entire feature vector silently.

This file satisfies **Sprint 2, Step 7** of the implementation plan.

---

## 🧬 Computer Science & Mathematical Deep Dive

### Discrete Fourier Transform (DFT) and vDSP FFT

The Discrete Fourier Transform decomposes a finite discrete-time signal `x[n]` of length `N` into `N` complex frequency components:

```
X[k] = Σ(n=0..N-1) x[n] · e^(−j·2π·k·n/N)    k = 0, 1, ..., N−1
```

Because our input signal is real-valued (not complex), the output spectrum is Hermitian-symmetric: `X[N−k] = X[k]*`. This means only the first `N/2 + 1` bins are unique (DC component through the Nyquist frequency). The remaining bins are redundant conjugate mirrors. `vDSP_fft_zrip` exploits this symmetry — "zrip" stands for **z**ero-padded **r**eal **i**n-**p**lace — processing a length-`N` real input using an `N/2`-point complex FFT, halving the computation.

At our parameters (fftSize = 512, sampleRate = 16,000 Hz):
- **Frequency resolution:** Δf = sampleRate / fftSize = 16,000 / 512 = **31.25 Hz per bin**
- **Frame duration:** fftSize / sampleRate = 512 / 16,000 = **32ms per frame**
- **Number of unique bins:** 512 / 2 + 1 = **257 bins** (0 Hz to 8,000 Hz)
- **Nyquist bin:** bin 256 = 256 × 31.25 = **8,000 Hz**

### Hann Window

A rectangular window (no windowing) treats the signal as if it repeats periodically at the frame boundary. When the frame does not contain an integer number of cycles of a frequency component, this periodicity assumption creates a discontinuity, causing energy from that frequency to "leak" into neighbouring bins — **spectral leakage**. This artificially broadens spectral peaks and reduces frequency resolution.

The Hann window mitigates leakage by tapering the frame to zero at both edges:

```
w(n) = 0.5 × (1 − cos(2π·n / (N−1)))    n = 0, 1, ..., N−1
```

Applied via pointwise multiplication (`vDSP_vmul`) before the FFT, it ensures edge discontinuities are suppressed. The cost is a slight reduction in frequency resolution (the effective bandwidth of each bin widens to ~2 bins), which is acceptable for our spectral analysis — we are measuring broad spectral shape features (Mel filterbank energies, spectral flatness) rather than individual sharp tonal components.

`vDSP_hann_window` with flag `vDSP_HANN_NORM` applies the normalised variant, which compensates for the energy reduction caused by windowing so that the total power of the windowed frame matches the original frame.

### Split-Complex Packing (`vDSP_ctoz`)

`vDSP_fft_zrip` requires its input in **split-complex format**: real parts and imaginary parts in separate contiguous arrays (`DSPSplitComplex`). For a real input signal, the standard trick is to interpret even-indexed samples as the real part of a complex number and odd-indexed samples as the imaginary part, packing the length-`N` real array into a length-`N/2` complex array. `vDSP_ctoz` performs this packing using a stride-2 read with a `withMemoryRebound` cast from `Float` to `DSPComplex`.

### Magnitude Computation and vDSP Scaling

After `vDSP_fft_zrip`, `vDSP_zvabs` computes `|X[k]| = sqrt(real[k]² + imag[k]²)` across all bins simultaneously using NEON SIMD.

`vDSP_fft_zrip` returns values scaled by a factor of 2 relative to a standard DFT (a known vDSP convention). Dividing by `fftSize` (`vDSP_vsdiv`) normalises the output so that a pure sinusoid of amplitude `A` produces a magnitude peak of exactly `A/2` at its frequency bin — consistent with the standard DFT definition.

### Nyquist Bin Extraction

The `vDSP_fft_zrip` convention packs the Nyquist bin's real value into `imag[0]` of the split-complex output (since the Nyquist component is real-valued and has no imaginary part, this slot would otherwise be wasted). The final step extracts `abs(splitComplex.imagp[0]) / fftSize` and places it at `result[fftSize/2]`, completing the 257-bin output.

### Frame Overlap

With `hopSize = 256` and `fftSize = 512`, consecutive frames overlap by 50%. This is standard practice in audio signal processing: it ensures that a transient event (such as the explosive phase of a cough) is captured at full energy in at least one frame, rather than being split across two adjacent frames with reduced amplitude in each.

---

## 🧵 Thread & Memory Safety Profile

### Pre-allocation Strategy

All intermediate buffers (`windowBuffer`, `real`, `imag`, `windowed` inside `computeMagnitudeSpectrum`) are allocated at `init` time or as local stack arrays. The `vDSP_create_fftsetup` call allocates internal sine/cosine lookup tables once and reuses them for every FFT call — this is the primary reason `FFTProcessor` is a `class` rather than a `struct`, since the `FFTSetup` opaque pointer must be managed and destroyed exactly once.

`computeMagnitudeSpectrum` allocates `windowed` and `magnitudes` and `result` as local `[Float]` arrays on each call. This is a deliberate pragmatic choice: these are small (512–257 floats = 1–2KB), short-lived, and their allocation is dwarfed by the FFT computation time. Pre-allocating them as instance properties would require locking for concurrent use — adding complexity for negligible gain given that `FFTProcessor` is called sequentially from `AudioAnalysisActor`.

### Single-Instance Concurrency

A single `FFTProcessor` instance must not be called concurrently — the `splitComplex` property holds mutable pointers into `real` and `imag`. If two concurrent calls wrote to `real` and `imag` simultaneously, results would be corrupted. `AudioAnalysisActor` calls `FFTProcessor` sequentially from its isolated executor, so no locking is needed. This constraint is documented here rather than enforced at runtime to avoid overhead on the hot path.

### `vDSP_destroy_fftsetup`

Called in `deinit` to release the internal sine/cosine lookup tables allocated by `vDSP_create_fftsetup`. Failure to call this would leak approximately 8–32KB of memory per `FFTProcessor` instance (depending on `log2n`). Since `AudioAnalysisActor` holds a single long-lived `FFTProcessor` instance, the leak would be bounded but is still unacceptable in a well-engineered system.

---

## 🔌 Public API & Data Flow

### `init(fftSize: Int = 512, hopSize: Int = 256)`
- `fftSize`: Must be a power of two. 512 = 32ms frame at 16kHz, 31.25 Hz/bin resolution.
- `hopSize`: Frame advance in samples. 256 = 50% overlap between consecutive frames.
- Allocates `FFTSetup` and `windowBuffer`. `preconditionFailure` if setup fails.

### `var magnitudeBinCount: Int`
- Returns `fftSize / 2 + 1` (257 for default fftSize=512).
- Used by `MelFilterbank.init` to validate filterbank bin alignment.

### `func magnitudeSpectra(from signal: [Float]) -> [[Float]]`
- **Input:** Normalised Float32 samples from `AudioRingBuffer.drainToFloat()`
- **Output:** `[[Float]]` of shape `[frameCount × 257]`, linear magnitude scale
- **Frame count formula:** `floor((signal.count − fftSize) / hopSize) + 1`
- **Data flow:** `AudioAnalysisActor` → `magnitudeSpectra(from:)` → `MelFilterbank.apply(to:)` and `SpectralFlatness.compute(from:)`
- **Threading:** Background actor only (called from `AudioAnalysisActor`)
