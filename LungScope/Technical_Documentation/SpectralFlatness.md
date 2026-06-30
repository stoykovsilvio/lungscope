# SpectralFlatness.swift Technical Specification

## 📋 Architectural Purpose

`SpectralFlatness.swift` computes the **Spectral Flatness Measure (SFM)** from the FFT magnitude spectra of the cough recording. It is the second cough-phase feature alongside MFCCs, providing a complementary scalar measure of the spectral shape that directly correlates with the turbulence characteristics of airflow through the airways.

Where MFCCs capture the overall spectral envelope shape (which changes with resonance frequency shifts caused by mucus accumulation and airway narrowing), spectral flatness captures the degree to which the spectrum resembles random noise versus a structured tonal signal. This distinction is clinically meaningful: a healthy forceful cough produces a broad turbulent burst with a relatively flat spectrum across mid-frequencies, followed by a brief voiced phase with tonal structure. When airways are obstructed or inflamed, the turbulent burst is prolonged and its spectral flatness elevated across a wider frequency range — a measurable acoustic correlate of increased airway resistance.

This file is implemented as a caseless `enum` with only `static` methods, making it a pure stateless computation module. It has no setup cost, no allocation at rest, and no lifecycle management. This satisfies **Sprint 2, Step 10** of the implementation plan.

The SFM output is a scalar `Float` value (mean across frames) and an optional per-frame `[Float]` array, both of which feed into `FeatureVector` in the ML layer alongside the MFCC features.

---

## 🧬 Computer Science & Mathematical Deep Dive

### Spectral Flatness Measure Definition

The Spectral Flatness Measure is defined as the ratio of the **geometric mean** to the **arithmetic mean** of a power spectrum:

```
SFM = geometric_mean(|X[k]|) / arithmetic_mean(|X[k]|)
    = (∏ |X[k]|)^(1/N) / ( (1/N) × Σ |X[k]| )
```

where `|X[k]|` are the magnitude spectrum bins and `N` is the number of bins.

**Mathematical bounds:** By the AM-GM inequality, the geometric mean is always ≤ the arithmetic mean, so `0 ≤ SFM ≤ 1`. The bound SFM = 1 is achieved only when all bins have equal magnitude (a perfectly flat spectrum, equivalent to white noise). SFM → 0 when one bin dominates (a pure sinusoid — all energy concentrated in a single bin, with all others near zero).

**Why the ratio is clinically useful:**
- A cough with high mucus loading produces sustained turbulent noise → SFM elevated across 200–3,000 Hz bands
- A clean, healthy cough has a sharper explosive onset and faster spectral decay → SFM lower in mid-frequency bands
- A cough with bronchospasm (airway constriction) produces a characteristic wheeze tonal component superimposed on turbulence → SFM shows a complex frame-by-frame pattern distinct from both healthy and mucus-heavy coughs

### Numerical Stability: Log-Domain Geometric Mean

Direct computation of `∏ |X[k]|^(1/N)` over 257 bins risks floating-point underflow: a product of 257 values each less than 1.0 approaches zero faster than `Float` can represent. The standard numerically stable formulation converts to the log domain:

```
geometric_mean = exp( (1/N) × Σ log(|X[k]|) )
               = exp( mean(log(|X[k]|)) )
```

The floor `max(|X[k]|, 1×10⁻¹⁰)` prevents `log(0) = -∞` from corrupting the mean. The floor value `1×10⁻¹⁰` is chosen to be well below the noise floor of a typical iPhone microphone recording (approximately -60 dB ≈ 0.001 in linear amplitude) so it never artificially elevates the log mean for real signals.

### Accelerate Primitives Used

| Operation | Accelerate Function | Purpose |
|---|---|---|
| Arithmetic mean | `vDSP_meanv` | Mean of floored magnitude bins |
| Log per bin | `vvlogf` | Vectorised natural log of all bins simultaneously |
| Mean of logs | `vDSP_meanv` | Mean of the log values (log-domain geometric mean computation) |
| Final mean across frames | `vDSP_meanv` | Aggregate per-frame SFMs into a single scalar |

The entire computation avoids scalar loops over individual bins. Every per-bin operation is vectorised through `vForce` or `vDSP`, executing on NEON SIMD hardware.

### Per-Frame vs. Mean SFM

`compute(from:)` returns a single mean SFM scalar — the primary feature fed to the CoreML classifier. `computePerFrame(from:)` returns the per-frame trajectory, which is available for future work: the temporal evolution of SFM across the cough's three phases (explosive, intermediate, voiced) encodes additional information about airway dynamics that a simple mean discards. The per-frame trajectory is not used in Sprint 4's MVP classifier but is exposed here for forward compatibility.

---

## 🧵 Thread & Memory Safety Profile

`SpectralFlatness` is a caseless `enum` — it cannot be instantiated and holds no stored state whatsoever. All methods are `static`. All intermediate arrays (`floored`, `logValues`) are stack-local allocations inside `computeFrameSFM`, allocated per call and immediately reclaimed. There is no shared mutable state, no initialisation requirement, and no lifecycle to manage.

Concurrent calls to `SpectralFlatness.compute(from:)` with different input arrays are completely safe — each invocation operates on entirely independent memory. In the current architecture, `SpectralFlatness` is called sequentially from `AudioAnalysisActor`, but this safety property holds unconditionally regardless of calling context.

**Per-frame allocation cost:** `floored` and `logValues` are each `[Float]` of length 257 (1,028 bytes each) allocated per frame. For a 5-second cough at 512-frame FFT / 256 hop = ~312 frames, total transient allocation ≈ 312 × 2 × 1,028 ≈ 641KB. All reclaimed before `compute(from:)` returns.

---

## 🔌 Public API & Data Flow

### `static func compute(from spectra: [[Float]]) -> Float`
- **Input:** `[[Float]]` of shape `[frameCount × 257]` from `FFTProcessor.magnitudeSpectra(from:)`
- **Output:** Mean spectral flatness scalar in `[0.0, 1.0]`
- **Typical range for respiratory sounds:** 0.05–0.40 (healthy cough: ~0.10–0.20; obstructed: ~0.25–0.40)
- **Data flow:** `FFTProcessor` → `SpectralFlatness.compute(from:)` → `FeatureVector.spectralFlatness`
- **Threading:** Background actor only; reentrant safe

### `static func computePerFrame(from spectra: [[Float]]) -> [Float]`
- **Input:** Same as above
- **Output:** `[Float]` of length `frameCount`, one SFM value per analysis frame
- **Use case:** Future temporal trajectory analysis; not used in MVP CoreML feature vector
- **Threading:** Background actor only; reentrant safe
