"""
generate_synthetic_dataset.py

Generates a synthetic dataset.csv with realistic feature distributions for
testing the full training pipeline end-to-end before real recordings are available.

Healthy subjects have:  lower jitter/shimmer, more tonal MFCCs (lower flatness)
Impaired subjects have: higher jitter/shimmer, flatter spectra (higher flatness)

The distributions are plausible but NOT clinically validated.
Replace this file with real extracted features before reporting results.

Usage:
    python generate_synthetic_dataset.py --n 100 --out dataset.csv
    python generate_synthetic_dataset.py --n 200 --balance 0.5 --out dataset.csv

Requirements:
    pip install numpy pandas
"""

import argparse
import numpy as np
import pandas as pd

FEATURE_COLUMNS = (
    [f"mfcc_mean_{i}" for i in range(13)] +
    [f"mfcc_std_{i}"  for i in range(13)] +
    ["spectral_flatness", "jitter", "shimmer"]
)


def generate_subject(label: str, rng: np.random.Generator) -> dict:
    healthy = (label == "healthy")

    # MFCC means: C0 is energy (more negative = quieter), C1-C12 are spectral shape.
    # Impaired subjects tend to have flatter spectra → less variation in higher coefficients.
    mfcc_mean = np.zeros(13, dtype=np.float32)
    mfcc_mean[0] = rng.normal(-12.0 if healthy else -10.0, 2.0)     # C0: energy
    for i in range(1, 13):
        mfcc_mean[i] = rng.normal(0.0, 3.0 if healthy else 1.5)     # C1-C12

    # MFCC std devs: higher std = more dynamic spectral variation across frames.
    mfcc_std = np.abs(rng.normal(2.0 if healthy else 1.2, 0.5, 13)).astype(np.float32)

    # Spectral flatness: noise-like spectrum = high flatness.
    # Impaired coughs tend to be breathier (flatter spectrum).
    spectral_flatness = float(np.clip(
        rng.normal(0.25 if healthy else 0.55, 0.08), 0.0, 1.0
    ))

    # Jitter: healthy < 1%, impaired 2-5%
    jitter = float(np.clip(
        rng.normal(0.008 if healthy else 0.025, 0.003), 0.001, 0.15
    ))

    # Shimmer: healthy < 3%, impaired 5-10%
    shimmer = float(np.clip(
        rng.normal(0.02 if healthy else 0.06, 0.01), 0.001, 0.20
    ))

    row = {}
    for i, v in enumerate(mfcc_mean):
        row[f"mfcc_mean_{i}"] = float(v)
    for i, v in enumerate(mfcc_std):
        row[f"mfcc_std_{i}"] = float(v)
    row["spectral_flatness"] = spectral_flatness
    row["jitter"]            = jitter
    row["shimmer"]           = shimmer
    row["label"]             = label
    return row


def main():
    parser = argparse.ArgumentParser(
        description="Generate a synthetic LungScope training dataset."
    )
    parser.add_argument("--n",       type=int,   default=100,
                        help="Total number of subjects (default: 100).")
    parser.add_argument("--balance", type=float, default=0.5,
                        help="Fraction of healthy subjects (default: 0.5).")
    parser.add_argument("--seed",    type=int,   default=42)
    parser.add_argument("--out",     default="dataset.csv",
                        help="Output CSV path (default: dataset.csv).")
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    n_healthy  = int(args.n * args.balance)
    n_impaired = args.n - n_healthy

    rows = (
        [generate_subject("healthy",  rng) for _ in range(n_healthy)] +
        [generate_subject("impaired", rng) for _ in range(n_impaired)]
    )
    rng.shuffle(rows)

    df = pd.DataFrame(rows, columns=FEATURE_COLUMNS + ["label"])
    df.to_csv(args.out, index=False)

    print(f"Generated {len(df)} subjects → {args.out}")
    print(f"  healthy:  {n_healthy}")
    print(f"  impaired: {n_impaired}")
    print(f"\nNext step:")
    print(f"  python train_model.py --data {args.out}")


if __name__ == "__main__":
    main()
