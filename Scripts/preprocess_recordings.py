"""
preprocess_recordings.py

Reads .m4a recordings from the Recordings/ folder, resamples to 16kHz mono,
extracts the 29 LungScope features, and writes dataset.csv ready for train_model.py.

Labels are assigned by subject ID range — edit LABEL_MAP below if your split changes.

Usage:
    python preprocess_recordings.py
    python preprocess_recordings.py --recordings ../Recordings --out dataset.csv

Requirements:
    pip install numpy librosa soundfile pandas
    brew install ffmpeg   (needed by librosa to decode .m4a)
"""

import argparse
import os
import sys
import numpy as np
import pandas as pd

try:
    import librosa
except ImportError:
    print("[ERROR] librosa not installed. Run: pip install librosa")
    sys.exit(1)

SAMPLE_RATE = 16_000

# ---------------------------------------------------------------------------
# Label map — subject ID → label.
# Edit this if your healthy/impaired split is different.
# ---------------------------------------------------------------------------

def get_label(subject_id: int) -> str:
    if 1 <= subject_id <= 10:
        return "impaired"
    if 11 <= subject_id <= 20:
        return "healthy"
    raise ValueError(f"No label defined for subject {subject_id:03d}")

# ---------------------------------------------------------------------------
# Feature extraction (mirrors Swift DSP modules)
# ---------------------------------------------------------------------------

def load_audio(path: str) -> np.ndarray:
    signal, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True)
    return signal.astype(np.float32)


def extract_mfcc(signal: np.ndarray) -> dict:
    mfccs = librosa.feature.mfcc(y=signal, sr=SAMPLE_RATE,
                                   n_mfcc=13, n_mels=26,
                                   n_fft=512, hop_length=256)
    return {"mean": mfccs.mean(axis=1).astype(np.float32),
            "std":  mfccs.std(axis=1).astype(np.float32)}


def extract_spectral_flatness(signal: np.ndarray) -> float:
    stft = np.abs(librosa.stft(signal, n_fft=512, hop_length=256)) + 1e-10
    geo  = np.exp(np.mean(np.log(stft), axis=0))
    arith = np.mean(stft, axis=0)
    return float(np.mean(geo / arith))


def extract_f0(signal: np.ndarray) -> np.ndarray:
    f0, voiced, _ = librosa.pyin(signal, fmin=85.0, fmax=400.0,
                                  sr=SAMPLE_RATE,
                                  frame_length=2048, hop_length=512)
    return f0[voiced == 1] if voiced is not None else np.array([])


def extract_jitter(signal: np.ndarray) -> float:
    f0 = extract_f0(signal)
    if len(f0) < 2:
        return 0.0
    periods = SAMPLE_RATE / f0
    return float(np.abs(np.diff(periods)).mean() / (periods.mean() + 1e-10))


def extract_shimmer(signal: np.ndarray) -> float:
    f0 = extract_f0(signal)
    if len(f0) < 2:
        return 0.0
    periods = (SAMPLE_RATE / f0).astype(int)
    amps, pos = [], 0
    for p in periods:
        end = pos + p
        if end > len(signal):
            break
        amps.append(float(np.max(np.abs(signal[pos:end]))))
        pos = end
    if len(amps) < 2:
        return 0.0
    amps = np.array(amps, dtype=np.float32)
    return float(np.abs(np.diff(amps)).mean() / (amps.mean() + 1e-10))


def extract_features(cough_path: str, vowel_path: str) -> dict:
    cough = load_audio(cough_path)
    vowel = load_audio(vowel_path)

    mfcc    = extract_mfcc(cough)
    flat    = extract_spectral_flatness(cough)
    jitter  = extract_jitter(vowel)
    shimmer = extract_shimmer(vowel)

    row = {}
    for i, v in enumerate(mfcc["mean"]):
        row[f"mfcc_mean_{i}"] = float(v)
    for i, v in enumerate(mfcc["std"]):
        row[f"mfcc_std_{i}"] = float(v)
    row["spectral_flatness"] = flat
    row["jitter"]            = jitter
    row["shimmer"]           = shimmer
    return row

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Extract LungScope features from .m4a recordings."
    )
    parser.add_argument("--recordings", default="../Recordings",
                        help="Path to folder containing NNN_cough.m4a and NNN_vowel.m4a files.")
    parser.add_argument("--out", default="dataset.csv",
                        help="Output CSV path (default: dataset.csv).")
    args = parser.parse_args()

    recordings_dir = os.path.abspath(
        os.path.join(os.path.dirname(__file__), args.recordings)
    )

    if not os.path.isdir(recordings_dir):
        print(f"[ERROR] Recordings folder not found: {recordings_dir}")
        sys.exit(1)

    # Discover subject IDs from cough files.
    subject_ids = sorted(
        int(f.replace("_cough.m4a", ""))
        for f in os.listdir(recordings_dir)
        if f.endswith("_cough.m4a")
    )

    if not subject_ids:
        print(f"[ERROR] No NNN_cough.m4a files found in {recordings_dir}")
        sys.exit(1)

    print(f"Found {len(subject_ids)} subjects in {recordings_dir}")

    rows = []
    for sid in subject_ids:
        cough_path = os.path.join(recordings_dir, f"{sid:03d}_cough.m4a")
        vowel_path = os.path.join(recordings_dir, f"{sid:03d}_vowel.m4a")

        if not os.path.exists(vowel_path):
            print(f"  [WARN] Missing vowel file for subject {sid:03d} — skipping")
            continue

        label = get_label(sid)
        print(f"  Processing {sid:03d} ({label})…", end=" ", flush=True)

        try:
            features = extract_features(cough_path, vowel_path)
            features["label"] = label
            rows.append(features)
            print("done")
        except Exception as exc:
            print(f"FAILED — {exc}")

    if not rows:
        print("[ERROR] No subjects processed successfully.")
        sys.exit(1)

    df = pd.DataFrame(rows)
    out_path = os.path.join(os.path.dirname(__file__), args.out)
    df.to_csv(out_path, index=False)

    label_counts = df["label"].value_counts().to_dict()
    print(f"\nDataset saved to: {out_path}")
    print(f"  Total subjects: {len(df)}")
    for lbl, count in label_counts.items():
        print(f"  {lbl}: {count}")
    print(f"\nNext step:")
    print(f"  python train_model.py --data {out_path}")


if __name__ == "__main__":
    main()
