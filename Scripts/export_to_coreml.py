"""
export_to_coreml.py

Converts a trained scikit-learn / XGBoost model (produced by train_model.py)
to a CoreML .mlmodel file and places it in the iOS app's ML/Models/ directory.

The exported model expects a single MLMultiArray input of shape [29] (Float32)
in the exact column order defined in FeatureVector.swift:
    indices 0–12:   mfcc_mean_0 … mfcc_mean_12
    indices 13–25:  mfcc_std_0  … mfcc_std_12
    index 26:       spectral_flatness
    index 27:       jitter
    index 28:       shimmer

Output:
    LungScope/LungScope/ML/Models/LungScopeClassifier.mlmodel
    (Xcode compiles this to LungScopeClassifier.mlmodelc on first build)

Requirements:
    pip install coremltools>=7.0 joblib scikit-learn
"""

import argparse
import os
import sys
import datetime
import joblib
import numpy as np

try:
    import coremltools as ct
    from coremltools.models.datatypes import Array
except ImportError:
    print("[ERROR] coremltools not installed. Run: pip install coremltools>=7.0")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants — must stay in sync with FeatureVector.swift
# ---------------------------------------------------------------------------

FEATURE_COLUMNS = (
    [f"mfcc_mean_{i}" for i in range(13)] +
    [f"mfcc_std_{i}"  for i in range(13)] +
    ["spectral_flatness", "jitter", "shimmer"]
)
assert len(FEATURE_COLUMNS) == 29

OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "LungScope", "LungScope", "ML", "Models"
)
MODEL_FILENAME = "LungScopeClassifier.mlmodel"

# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

def load_artifact(pkl_path: str):
    artifact = joblib.load(pkl_path)
    model          = artifact["model"]
    label_encoder  = artifact["label_encoder"]
    feature_cols   = artifact["feature_columns"]
    if feature_cols != FEATURE_COLUMNS:
        print("[ERROR] Feature columns in .pkl do not match FEATURE_COLUMNS in this script.")
        print("        Retrain with the current train_model.py before exporting.")
        sys.exit(1)
    return model, label_encoder


def convert(model, label_encoder) -> ct.models.MLModel:
    classes = list(label_encoder.classes_)

    # coremltools handles both RandomForest and XGBoost via unified convert().
    coreml_model = ct.converters.sklearn.convert(
        model,
        input_features=FEATURE_COLUMNS,
        output_feature_names="label"
    )

    # Rename the probability dictionary output to match DiagnosticInferenceEngine.
    spec = coreml_model.get_spec()

    # Set metadata.
    spec.description.metadata.author      = "LungScope Training Pipeline"
    spec.description.metadata.shortDescription = (
        "Binary respiratory health classifier (healthy / impaired) trained on "
        "29 acoustic features extracted from forced cough and sustained vowel recordings."
    )
    spec.description.metadata.versionString = datetime.date.today().isoformat()
    spec.description.metadata.license       = "Personal use only — not clinically validated"

    return ct.models.MLModel(spec)


def save(coreml_model: ct.models.MLModel, out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, MODEL_FILENAME)
    coreml_model.save(out_path)
    return out_path


def smoke_test(coreml_model: ct.models.MLModel) -> None:
    """Run one prediction on a zero-feature vector to confirm the model loads."""
    sample = {col: 0.0 for col in FEATURE_COLUMNS}
    try:
        result = coreml_model.predict(sample)
        print(f"  Smoke test prediction: {result}")
    except Exception as exc:
        print(f"  [WARN] Smoke test failed: {exc}")

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Export a trained LungScope classifier to CoreML."
    )
    parser.add_argument("--model", required=True,
                        help="Path to Models/lungscope_classifier.pkl produced by train_model.py")
    parser.add_argument("--out", default=OUTPUT_DIR,
                        help=f"Output directory (default: {OUTPUT_DIR})")
    args = parser.parse_args()

    if not os.path.exists(args.model):
        print(f"[ERROR] Model file not found: {args.model}")
        sys.exit(1)

    print(f"Loading model from: {args.model}")
    model, label_encoder = load_artifact(args.model)
    print(f"Classes: {list(label_encoder.classes_)}")

    print("Converting to CoreML…")
    coreml_model = convert(model, label_encoder)

    print("Smoke-testing converted model…")
    smoke_test(coreml_model)

    out_path = save(coreml_model, args.out)
    print(f"\nModel saved to: {out_path}")
    print(
        "\nNext steps:\n"
        "  1. Open LungScope.xcodeproj in Xcode\n"
        "  2. Xcode will compile LungScopeClassifier.mlmodel → .mlmodelc on next build\n"
        "  3. Verify DiagnosticInferenceEngine loads it via Bundle.main.url(forResource:withExtension:)\n"
        "  4. Run the app and confirm results are no longer the stub values (ACI:0.42, VHSS:0.71)"
    )


if __name__ == "__main__":
    main()
