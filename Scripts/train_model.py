"""
train_model.py

Trains a tabular ensemble classifier on the 29-feature LungScope FeatureVector
and serialises the trained model to Models/lungscope_classifier.pkl.

Expected CSV schema (column order must match FeatureVector.toMLMultiArray()):
    mfcc_mean_0 … mfcc_mean_12      (13 columns)
    mfcc_std_0  … mfcc_std_12       (13 columns)
    spectral_flatness                (1 column)
    jitter                           (1 column)
    shimmer                          (1 column)
    label                            (target: "healthy" or "impaired")

Usage:
    python train_model.py --data path/to/dataset.csv [--model rf|xgb] [--out Models/]

Requirements:
    pip install numpy pandas scikit-learn xgboost joblib
"""

import argparse
import os
import sys
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedKFold, cross_validate
from sklearn.metrics import (classification_report, confusion_matrix,
                              roc_auc_score)
from sklearn.preprocessing import LabelEncoder

try:
    from xgboost import XGBClassifier
    HAS_XGB = True
except ImportError:
    HAS_XGB = False

# ---------------------------------------------------------------------------
# Feature column names — must exactly match FeatureVector.toMLMultiArray() order
# ---------------------------------------------------------------------------

FEATURE_COLUMNS = (
    [f"mfcc_mean_{i}" for i in range(13)] +
    [f"mfcc_std_{i}"  for i in range(13)] +
    ["spectral_flatness", "jitter", "shimmer"]
)
assert len(FEATURE_COLUMNS) == 29, "Feature count mismatch — update FeatureVector.swift"

LABEL_COLUMN = "label"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_dataset(path: str) -> tuple[np.ndarray, np.ndarray]:
    df = pd.read_csv(path)
    missing = [c for c in FEATURE_COLUMNS + [LABEL_COLUMN] if c not in df.columns]
    if missing:
        print(f"[ERROR] Missing columns in dataset: {missing}")
        sys.exit(1)

    X = df[FEATURE_COLUMNS].values.astype(np.float32)
    le = LabelEncoder()
    y = le.fit_transform(df[LABEL_COLUMN].values)
    print(f"Classes: {list(le.classes_)}  (0 = {le.classes_[0]}, 1 = {le.classes_[1]})")
    print(f"Dataset: {len(X)} samples, {X.shape[1]} features")
    print(f"Label distribution: {dict(zip(*np.unique(y, return_counts=True)))}")
    return X, y, le


def build_model(model_type: str):
    if model_type == "rf":
        return RandomForestClassifier(
            n_estimators=300,
            max_depth=8,
            min_samples_leaf=2,
            class_weight="balanced",
            random_state=42,
            n_jobs=-1,
        )
    if model_type == "xgb":
        if not HAS_XGB:
            print("[ERROR] xgboost not installed. Run: pip install xgboost")
            sys.exit(1)
        return XGBClassifier(
            n_estimators=300,
            max_depth=5,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            use_label_encoder=False,
            eval_metric="logloss",
            random_state=42,
            n_jobs=-1,
        )
    print(f"[ERROR] Unknown model type: {model_type}. Choose 'rf' or 'xgb'.")
    sys.exit(1)


def evaluate(model, X: np.ndarray, y: np.ndarray) -> None:
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores = cross_validate(model, X, y, cv=cv,
                            scoring=["accuracy", "f1", "roc_auc"],
                            return_train_score=False)
    print("\n── 5-fold cross-validation ──────────────────────────────────────")
    print(f"  Accuracy : {scores['test_accuracy'].mean():.3f} ± {scores['test_accuracy'].std():.3f}")
    print(f"  F1       : {scores['test_f1'].mean():.3f} ± {scores['test_f1'].std():.3f}")
    print(f"  ROC-AUC  : {scores['test_roc_auc'].mean():.3f} ± {scores['test_roc_auc'].std():.3f}")


def train_final(model, X: np.ndarray, y: np.ndarray) -> None:
    model.fit(X, y)
    y_pred = model.predict(X)
    y_prob = model.predict_proba(X)[:, 1]
    print("\n── Full-dataset metrics (training set — for sanity check only) ──")
    print(classification_report(y, y_pred, target_names=["healthy", "impaired"]))
    print("Confusion matrix:")
    print(confusion_matrix(y, y_pred))
    print(f"ROC-AUC (train): {roc_auc_score(y, y_prob):.3f}")


def feature_importance(model, model_type: str) -> None:
    if model_type == "rf":
        importances = model.feature_importances_
    elif model_type == "xgb":
        importances = model.feature_importances_
    else:
        return
    ranked = sorted(zip(FEATURE_COLUMNS, importances), key=lambda x: -x[1])
    print("\n── Top-10 feature importances ───────────────────────────────────")
    for name, imp in ranked[:10]:
        bar = "█" * int(imp * 40)
        print(f"  {name:25s} {imp:.4f}  {bar}")

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Train the LungScope classifier.")
    parser.add_argument("--data",  required=True, help="Path to the labelled CSV dataset.")
    parser.add_argument("--model", default="rf", choices=["rf", "xgb"],
                        help="Model type: rf (Random Forest) or xgb (XGBoost). Default: rf.")
    parser.add_argument("--out",   default="Models", help="Output directory for the .pkl file.")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)

    X, y, label_encoder = load_dataset(args.data)
    model = build_model(args.model)

    evaluate(model, X, y)
    train_final(model, X, y)
    feature_importance(model, args.model)

    out_path = os.path.join(args.out, "lungscope_classifier.pkl")
    joblib.dump({"model": model, "label_encoder": label_encoder,
                 "feature_columns": FEATURE_COLUMNS}, out_path)
    print(f"\nModel saved to: {out_path}")
    print("Next step: python export_to_coreml.py --model", out_path)


if __name__ == "__main__":
    main()
