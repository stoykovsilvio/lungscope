# AudioFormat.swift Technical Specification
*(Updated: Float32 revision)*

## 📋 Architectural Purpose

`AudioFormat.swift` is the **hardware contract layer** of the Acoustic LungScope pipeline. It defines and vends the single canonical `AVAudioFormat` instance that every other component depends on, and provides the `AVAudioConverter` factory that bridges the device's native hardware sample rate to that standard.

This file exists to guarantee format determinism across the entire pipeline. The 16kHz sample rate is the recording standard used by the ICBHI 2017 Respiratory Sound Database and the majority of published pulmonary acoustics research. By encoding this as a compile-time constant, any feature vector produced by the DSP layer is numerically comparable to those produced by the Python training pipeline (`Scripts/train_model.py`). A sample rate mismatch — even 8kHz — would cause the Mel filterbank frequency bins to map to entirely different spectral regions than those the CoreML model was trained on, producing confident but clinically meaningless predictions with no runtime warning.

**Revision note:** The format was updated from `pcmFormatInt16` (interleaved) to `pcmFormatFloat32` (non-interleaved) after identifying that `AVAudioEngine.inputNode.installTap` on iOS reliably delivers only non-interleaved `Float32` buffers at the hardware driver level, regardless of the format requested. Requesting Int16 from the tap would either silently fail or require a double conversion. Float32 non-interleaved is the native format of the tap, eliminates one conversion step, and produces samples already normalised to `[-1.0, 1.0]` by the hardware driver — a prerequisite for all downstream Accelerate DSP operations without additional scaling.

This file satisfies **Sprint 1, Step 2** of the implementation plan. It sits below the Model layer — it is pure infrastructure with no dependencies on any other project file.

---

## 🧬 Computer Science & Mathematical Deep Dive

### Sample Rate: 16,000 Hz

The Nyquist-Shannon sampling theorem states a digital system can reconstruct any frequency up to half the sampling rate (the Nyquist frequency). At 16kHz, the Nyquist frequency is 8,000 Hz — a deliberate and sufficient ceiling:

- Human cough energy concentrates between **100 Hz and 5,000 Hz**, with the turbulent burst peaking at 400–1,600 Hz
- Vocal fold fundamental frequency (F0) for adult speech: **85–255 Hz**
- Harmonics carrying Jitter and Shimmer information: detectable up to ~4,000–5,000 Hz

Sampling at the iPhone's native 48kHz would triple memory consumption and FFT computation cost for zero diagnostic benefit. 16kHz is the mathematically optimal choice for this specific acoustic domain.

### Float32 Non-Interleaved PCM

`AVAudioEngine`'s tap mechanism internally uses `AudioUnit` rendering, which operates natively in non-interleaved `Float32`. For a mono channel, non-interleaved and interleaved are identical in memory layout — there is one channel plane containing samples sequentially as `[Float]`. The values are normalised to `[-1.0, 1.0]` by the hardware driver, meaning:
- Peak cough amplitude ≈ ±0.9 (near-clipping, expected for a forced cough)
- Quiet vowel breath envelope ≈ ±0.05–0.3
- All Accelerate FFT and autocorrelation functions assume unit-scale input — no pre-scaling step required

### Converter Factory

`makeConverter(from:)` returns `nil` when no conversion is needed, avoiding construction of a no-op converter. The `AVAudioConverter` holds internal state buffers and references to both format objects — creating an unnecessary one wastes heap. When the device's native rate matches 16kHz, `nil` is returned and the tap writes directly into the ring buffer without passing through the converter.

---

## 🧵 Thread & Memory Safety Profile

`AudioFormat` is a caseless `enum` — a pure value-type namespace. It cannot be instantiated. All `static let` properties use Swift's `dispatch_once`-equivalent lazy initialisation, which is thread-safe by construction without any explicit locking. Subsequent reads return the already-constructed value from static storage — no heap allocation, no lock contention.

`makeConverter(from:)` allocates one `AVAudioConverter` per call. This function is documented and architecturally enforced to be called once at engine startup from a non-real-time context. Calling it from within the tap callback would be a programmer error detectable immediately in testing.

---

## 🔌 Public API & Data Flow

### Constants

| Name | Type | Value | Purpose |
|---|---|---|---|
| `AudioFormat.sampleRate` | `Double` | `16_000.0` | Sample rate for AVAudioFormat and ring buffer sizing |
| `AudioFormat.channelCount` | `AVAudioChannelCount` | `1` | Mono channel count |
| `AudioFormat.coughWindowSamples` | `Int` | `80_000` | Ring buffer capacity for 5-second cough phase |
| `AudioFormat.vowelWindowSamples` | `Int` | `160_000` | Ring buffer capacity for 10-second vowel phase |

### Properties

#### `AudioFormat.canonical: AVAudioFormat`
- Float32, non-interleaved, 16kHz, mono
- Lazily constructed once; `preconditionFailure` if construction fails

### Methods

#### `AudioFormat.makeConverter(from hardwareFormat: AVAudioFormat) -> AVAudioConverter?`
- Returns configured converter from `hardwareFormat` → `canonical`, or `nil` if already equal
- Call once at engine startup; store result as `AudioEngine.converter`
