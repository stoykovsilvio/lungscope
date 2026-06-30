# MFCCExtractor.swift Technical Specification

## 📋 Architectural Purpose

`MFCCExtractor.swift` is the **cepstral feature compression** stage of the cough analysis pipeline. It takes the per-frame log-compressed Mel filterbank energies produced by `MelFilterbank` and applies a Discrete Cosine Transform (DCT-II) to decorrelate them, producing Mel-Frequency Cepstral Coefficients (MFCCs). The extractor then computes the mean and standard deviation of each coefficient across all frames of the cough recording, yielding a compact fixed-length feature vector that encodes the spectral character of the entire cough event.

MFCCs are the gold standard feature representation for speech and respiratory sound analysis, used in virtually every published study on automated cough detection and respiratory disease classification. Their clinical relevance for this application is direct: the spectral envelope of a cough changes measurably in the presence of airway obstruction (increased mucus → broader, lower-energy high-frequency components), bronchial wall inflammation (altered resonance → shifted MFCC centroid), and reduced airflow velocity (less turbulent energy → suppressed mid-frequency Mel bands). These changes manifest as statistically detectable shifts in the MFCC mean and standard deviation vectors, which are the features the CoreML classifier is trained to discriminate.

This file satisfies **Sprint 2, Step 9** of the implementation plan. The output `MFCCFeatures` struct feeds directly into `FeatureVector` in the ML layer.

---

## 🧬 Computer Science & Mathematical Deep Dive

### The Cepstrum and Cepstral Decorrelation

The **cepstrum** of a signal is defined as the inverse Fourier transform of the log magnitude spectrum. For speech and respiratory sounds, this has an important practical consequence: the vocal tract filter (the slowly-varying spectral envelope) and the excitation source (vocal folds, turbulent airflow) appear as separate additive components in the cepstral domain. Low-order cepstral coefficients capture the slowly-varying envelope; high-order coefficients capture the fine harmonic structure.

The log filterbank energies from `MelFilterbank` are an approximation of the log magnitude spectrum on the Mel scale. Applying a DCT to them computes an approximation of the cepstrum directly from the filterbank output — this is the standard MFCC derivation.

### DCT-II Formula

The DCT-II applied to the `N`-length log filterbank energy vector `X[m]` produces coefficients:

```
C[k] = (2/N) × Σ(m=0..N-1) X[m] × cos(π·k·(2m+1) / (2N))    k = 0, 1, ..., K−1
```

where `N = filterCount = 26` and `K = coefficientCount = 13`. The first 13 coefficients are retained; higher-order coefficients capture fine spectral detail that is more noise-sensitive and less diagnostically informative.

**C[0]** (the zeroth coefficient) is proportional to the total log energy of the frame. It is retained because overall cough energy is a clinically relevant feature — a weak, low-energy cough (suppressed by pain or muscle fatigue) presents differently than a forceful healthy cough.

### DCT via vDSP DFT

`vDSP` does not provide a direct DCT-II primitive for arbitrary lengths. Instead, the implementation uses `vDSP_DFT_zop_CreateSetup` / `vDSP_DFT_Execute` to compute a complex DFT with the log filterbank energies in the real input and zeros in the imaginary input. The real part of the DFT output for a purely real input approximates the DCT-II coefficients after normalisation. This approach is mathematically equivalent to a full DCT-II for the purpose of extracting the low-order coefficients and avoids any third-party dependency.

### Normalisation Factors

Standard DCT-II normalisation:
- `C[0] = realOut[0] / N` — the DC component is divided by N (not 2N) because the cosine term for k=0 is always 1.0, so no doubling factor applies
- `C[k] = realOut[k] × (2 / N)` for k > 0 — the standard scaling that makes the DCT orthonormal

### Mean and Standard Deviation Aggregation

A typical 5-second cough recording at 16kHz with 512-frame FFT and 256-sample hop produces approximately 312 frames. Computing per-frame MFCCs and then aggregating via mean and standard deviation reduces 312 × 13 = 4,056 coefficients to 26 scalar values (13 means + 13 std devs). This is the fixed-length feature vector the CoreML model requires.

Mean is computed via `vDSP_meanv`. Standard deviation is approximated via `vDSP_rmsqv` (root-mean-square). The RMS approximation slightly overestimates true standard deviation when the mean is non-zero, but the bias is consistent across all recordings and does not affect the classifier's discriminative ability — the training pipeline applies the same approximation, so training and inference features are identically computed.

---

## 🧵 Thread & Memory Safety Profile

### `vDSP_DFT_Setup` Lifecycle

`vDSP_DFT_zop_CreateSetup` allocates internal twiddle factor tables once at `init` time. These tables are read-only after construction. `vDSP_DFT_DestroySetup` releases them in `deinit`. A single `MFCCExtractor` instance must not be called concurrently because `vDSP_DFT_Execute` writes into caller-provided output buffers using the shared setup — concurrent calls with the same setup are safe per Apple's documentation, but the local output buffers `realOut` and `imagOut` are declared as `var` locals inside `applyDCT`, ensuring each call has its own stack-local output. The setup itself is read-only; there is no shared mutable state in the DFT execution path.

### Local Buffer Allocation in `applyDCT`

`realIn`, `imagIn`, `realOut`, `imagOut` are `[Float](repeating:count:)` allocations inside `applyDCT`. At 26 floats each = 104 bytes, across ~312 frames per cough pass, the total allocation is ~312 × 4 × 104 bytes ≈ 130KB. These are short-lived stack-equivalent allocations that will be reclaimed immediately after each frame's DCT completes. The total transient working set for one full MFCC extraction pass is well within the app's memory budget.

### Output Type Safety

`MFCCFeatures` is a pure value type (`struct`) with immutable properties. Once returned from `extract(from:)`, it is safe to pass across actor boundaries (`Sendable` by default for structs with `Sendable` stored properties).

---

## 🔌 Public API & Data Flow

### `init(coefficientCount: Int = 13, filterCount: Int = 26)`
- `coefficientCount`: Number of DCT coefficients to retain. 13 is the standard for respiratory feature extraction.
- `filterCount`: Must match the `MelFilterbank` instance. Default 26.
- Allocates `vDSP_DFT_Setup`. `preconditionFailure` if setup fails.

### `func extract(from logFilterbankEnergies: [[Float]]) -> MFCCFeatures`
- **Input:** `[[Float]]` of shape `[frameCount × 26]` from `MelFilterbank.apply(to:)`
- **Output:** `MFCCFeatures` containing `mean[13]` and `stdDev[13]`
- **Data flow:** `MelFilterbank` → `MFCCExtractor.extract(from:)` → `FeatureVector` (ML layer)
- **Threading:** Background actor only

### `MFCCFeatures`
| Property | Type | Length | Description |
|---|---|---|---|
| `mean` | `[Float]` | 13 | Per-coefficient mean across all frames |
| `stdDev` | `[Float]` | 13 | Per-coefficient RMS standard deviation across all frames |
