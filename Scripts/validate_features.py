"""
validate_features.py

Sanity-checks the DSP feature extraction pipeline against synthetic reference
signals before any model training. Run this before train_model.py to confirm
the feature pipeline is behaving correctly.

Requirements:
    pip install numpy scipy librosa
"""

import numpy as np
from scipy.signal import butter, filtfilt
import librosa

SAMPLE_RATE = 16_000
PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

# ---------------------------------------------------------------------------
# Signal generators
# ---------------------------------------------------------------------------

def make_sine(freq_hz: float, duration_s: float, amplitude: float = 0.5) -> np.ndarray:
    t = np.linspace(0, duration_s, int(SAMPLE_RATE * duration_s), endpoint=False)
    return (amplitude * np.sin(2 * np.pi * freq_hz * t)).astype(np.float32)


def make_white_noise(duration_s: float, amplitude: float = 0.3) -> np.ndarray:
    rng = np.random.default_rng(seed=42)
    return (amplitude * rng.standard_normal(int(SAMPLE_RATE * duration_s))).astype(np.float32)


def make_perturbed_sine(freq_hz: float, duration_s: float,
                         jitter_ratio: float = 0.02,
                         shimmer_ratio: float = 0.03) -> np.ndarray:
    """Sine wave with cycle-by-cycle period and amplitude jitter."""
    rng = np.random.default_rng(seed=0)
    nominal_period = SAMPLE_RATE / freq_hz
    samples = []
    t = 0.0
    while t / SAMPLE_RATE < duration_s:
        period = nominal_period * (1 + rng.uniform(-jitter_ratio, jitter_ratio))
        amp    = 0.5 * (1 + rng.uniform(-shimmer_ratio, shimmer_ratio))
        n_samp = int(round(period))
        phase  = np.linspace(0, 2 * np.pi, n_samp, endpoint=False)
        samples.append((amp * np.sin(phase)).astype(np.float32))
        t += n_samp
    signal = np.concatenate(samples)
    return signal[:int(SAMPLE_RATE * duration_s)]

# ---------------------------------------------------------------------------
# Feature extractors (Python equivalents of the Swift DSP modules)
# ---------------------------------------------------------------------------

def extract_mfcc(signal: np.ndarray, n_mfcc: int = 13, n_mels: int = 26) -> dict:
    mfccs = librosa.feature.mfcc(y=signal, sr=SAMPLE_RATE,
                                   n_mfcc=n_mfcc, n_mels=n_mels,
                                   n_fft=512, hop_length=256)
    return {"mean": mfccs.mean(axis=1), "std": mfccs.std(axis=1)}


def spectral_flatness(signal: np.ndarray) -> float:
    stft = np.abs(librosa.stft(signal, n_fft=512, hop_length=256))
    geometric_mean = np.exp(np.mean(np.log(stft + 1e-10), axis=0))
    arithmetic_mean = np.mean(stft, axis=0) + 1e-10
    flatness_per_frame = geometric_mean / arithmetic_mean
    return float(np.mean(flatness_per_frame))


def _yin_f0(signal: np.ndarray, frame_size: int = 2048, hop_size: int = 512,
             fmin: float = 85.0, fmax: float = 400.0) -> np.ndarray:
    f0, voiced, _ = librosa.pyin(signal, fmin=fmin, fmax=fmax,
                                  sr=SAMPLE_RATE,
                                  frame_length=frame_size,
                                  hop_length=hop_size)
    return f0[voiced == 1]


def jitter(signal: np.ndarray) -> float:
    f0 = _yin_f0(signal)
    if len(f0) < 2:
        return 0.0
    periods = SAMPLE_RATE / f0
    diffs = np.abs(np.diff(periods))
    return float(diffs.mean() / periods.mean())


def shimmer(signal: np.ndarray) -> float:
    f0 = _yin_f0(signal)
    if len(f0) < 2:
        return 0.0
    periods = (SAMPLE_RATE / f0).astype(int)
    amplitudes = []
    pos = 0
    for p in periods:
        end = pos + p
        if end > len(signal):
            break
        amplitudes.append(np.max(np.abs(signal[pos:end])))
        pos = end
    amplitudes = np.array(amplitudes, dtype=np.float32)
    if len(amplitudes) < 2:
        return 0.0
    diffs = np.abs(np.diff(amplitudes))
    return float(diffs.mean() / (amplitudes.mean() + 1e-10))

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check(name: str, condition: bool, detail: str = "") -> bool:
    status = PASS if condition else FAIL
    print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))
    return condition


def run_checks() -> int:
    failures = 0

    print("\n── MFCC checks ──────────────────────────────────────────────────")
    cough_sine = make_sine(1_000, 5.0, amplitude=0.25)
    mfcc = extract_mfcc(cough_sine)
    c0 = float(mfcc["mean"][0])
    failures += not check("C0 energy in [-20, -5] for -12 dBFS sine",
                           -20 <= c0 <= -5, f"C0 = {c0:.2f}")
    failures += not check("MFCC mean has 13 coefficients",
                           len(mfcc["mean"]) == 13)
    failures += not check("MFCC std has 13 coefficients",
                           len(mfcc["std"]) == 13)

    print("\n── Spectral flatness checks ─────────────────────────────────────")
    noise_sf = spectral_flatness(make_white_noise(5.0))
    sine_sf  = spectral_flatness(make_sine(1_000, 5.0))
    failures += not check("White noise flatness in [0.40, 0.95]",
                           0.40 <= noise_sf <= 0.95, f"sf = {noise_sf:.3f}")
    failures += not check("Pure sine flatness in [0.0, 0.15]",
                           0.0 <= sine_sf <= 0.15,   f"sf = {sine_sf:.3f}")
    failures += not check("Noise flatness > sine flatness",
                           noise_sf > sine_sf)

    print("\n── Jitter checks ────────────────────────────────────────────────")
    j_perfect    = jitter(make_sine(200, 10.0))
    j_perturbed  = jitter(make_perturbed_sine(200, 10.0, jitter_ratio=0.02))
    failures += not check("Jitter < 0.005 for perfect 200 Hz sine",
                           j_perfect < 0.005, f"jitter = {j_perfect:.5f}")
    failures += not check("Jitter > 0.005 for 2% perturbed sine",
                           j_perturbed > 0.005, f"jitter = {j_perturbed:.5f}")

    print("\n── Shimmer checks ───────────────────────────────────────────────")
    s_perfect   = shimmer(make_sine(200, 10.0))
    s_perturbed = shimmer(make_perturbed_sine(200, 10.0, shimmer_ratio=0.05))
    failures += not check("Shimmer < 0.01 for constant-amplitude sine",
                           s_perfect < 0.01, f"shimmer = {s_perfect:.5f}")
    failures += not check("Shimmer > 0.01 for 5% perturbed sine",
                           s_perturbed > 0.01, f"shimmer = {s_perturbed:.5f}")

    print()
    if failures == 0:
        print(f"\033[92mAll checks passed.\033[0m")
    else:
        print(f"\033[91m{failures} check(s) failed. Fix DSP pipeline before training.\033[0m")
    return failures


if __name__ == "__main__":
    import sys
    sys.exit(run_checks())
