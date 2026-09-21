# Model Card — LungScopeClassifier

> This document must be updated whenever the model is retrained. An incomplete or outdated model card is treated as a missing model card for clinical review purposes.

---

## 1. Model Overview

| Field | Value |
|---|---|
| **Model type** | Tabular binary classifier (Random Forest or XGBoost) |
| **Framework** | scikit-learn / XGBoost → CoreML via coremltools ≥ 7.0 |
| **Task** | Binary classification: `healthy` vs `impaired` respiratory status |
| **Input** | 29-dimensional `MLMultiArray` (Float32) — see Feature Engineering below |
| **Output** | `label` (String: `"healthy"` or `"impaired"`) + class probabilities |
| **On-device runtime** | CoreML, iOS 16+, CPU/Neural Engine |
| **Training script** | `Scripts/train_model.py` |
| **Export script** | `Scripts/export_to_coreml.py` |
| **Model file** | `LungScope/LungScope/ML/Models/LungScopeClassifier.mlmodel` |

---

## 2. Training Data

| Field | Value |
|---|---|
| **Dataset name** | *(to be filled when training data is acquired)* |
| **Source** | *(e.g. COUGHVID, Coswara, internally collected)* |
| **Total samples** | *(N)* |
| **Healthy samples** | *(N_healthy)* |
| **Impaired samples** | *(N_impaired)* |
| **Collection protocol** | 3 forced coughs followed by 10-second sustained "Ahhh" vowel, recorded at 16kHz mono on an iPhone held 30–40cm from the mouth in a quiet room |
| **Label source** | *(e.g. self-reported; physician-confirmed; proxy from spirometry FEV1/FVC ratio)* |
| **Train / test split** | 80% train, 20% held-out test; stratified by label |
| **Collection date** | *(YYYY-MM-DD)* |

### Known Data Biases

- *(Document any known demographic imbalances — age, sex, BMI, smoking status)*
- *(Document any known recording environment imbalances — indoor/outdoor, background noise level)*
- *(Document any label noise — self-reported labels are less reliable than physician-confirmed)*

---

## 3. Feature Engineering

The model consumes exactly 29 features derived by `AudioAnalysisActor` from one 30-second assessment session. The feature order in the `MLMultiArray` is fixed and **must not be changed** without retraining.

| Index | Feature | Source module | Description |
|---|---|---|---|
| 0–12 | `mfcc_mean_0` … `mfcc_mean_12` | `MFCCExtractor` | Mean MFCC coefficients C0–C12 across cough frames |
| 13–25 | `mfcc_std_0` … `mfcc_std_12` | `MFCCExtractor` | Std dev of MFCC coefficients across cough frames |
| 26 | `spectral_flatness` | `SpectralFlatness` | Mean spectral flatness across cough frames; range [0, 1] |
| 27 | `jitter` | `JitterCalculator` | Relative average period perturbation from vowel phase |
| 28 | `shimmer` | `ShimmerCalculator` | Relative average amplitude perturbation from vowel phase |

Feature extraction parameters are fixed in `AudioFormat.swift` and the DSP module defaults:
- Sample rate: 16 kHz
- FFT size: 512, hop: 256 (cough side)
- Mel filters: 26
- MFCC coefficients: 13
- YIN frame size: 2048, hop: 512, threshold: 0.1

---

## 4. Performance Metrics

> Fill in after training on a held-out test set. Do not report training-set metrics as model performance.

| Metric | Value |
|---|---|
| **Accuracy** | *(%)* |
| **Precision** (impaired) | *(%)* |
| **Recall** (impaired) | *(%)* |
| **F1** (impaired) | *(%)* |
| **ROC-AUC** | *([0, 1])* |
| **Confusion matrix** | *(TP / FP / TN / FN)* |
| **5-fold CV accuracy** | *(mean ± std)* |
| **Evaluation date** | *(YYYY-MM-DD)* |

---

## 5. Hyperparameters

*(Fill in the final chosen hyperparameters after tuning. The defaults in `train_model.py` are a starting point.)*

| Parameter | Value |
|---|---|
| Algorithm | *(Random Forest / XGBoost)* |
| n_estimators | *(300)* |
| max_depth | *(8 / 5)* |
| class_weight | *(balanced)* |
| random_state | 42 |

---

## 6. Known Limitations

- **Not clinically validated.** This model has not been evaluated in a clinical setting against a gold-standard diagnostic (e.g. spirometry, chest X-ray, physician diagnosis). It must not be used to make or inform medical decisions.
- **Small training set.** Models trained on < 500 samples are unreliable out-of-distribution. Performance on demographics not represented in training data is unknown.
- **Recording environment sensitivity.** High background noise (> 50 dB SPL) degrades MFCC and jitter/shimmer estimates. The model may produce unreliable predictions in noisy environments.
- **Single device.** Trained and evaluated exclusively on iPhone microphone recordings. Generalization to other microphones is unknown.
- **Binary label only.** The model predicts `healthy` / `impaired` without a severity scale. Intermediate states are not captured.

---

## 7. Intended Use

| Use | Permitted |
|---|---|
| Personal daily wellness tracking | ✅ Yes |
| Research and academic demonstration | ✅ Yes |
| Clinical diagnosis | ❌ No |
| Screening for specific diseases (COPD, asthma, COVID-19) | ❌ No |
| Use without this model card being reviewed and updated | ❌ No |

---

## 8. Changelog

| Date | Change | Author |
|---|---|---|
| *(YYYY-MM-DD)* | Initial model trained | *(name)* |
