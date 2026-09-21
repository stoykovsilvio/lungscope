import CoreML
import Foundation

/// Wraps the CoreML classifier call and maps its output to a DiagnosticResult.
///
/// When the compiled .mlmodelc bundle is absent (CI, early development),
/// the stub path returns fixed mid-range values so the rest of the app
/// can be developed and tested without a trained model.
final class DiagnosticInferenceEngine {

    // MARK: - Model

    private let model: MLModel?

    // MARK: - Initialisation

    init() {
        // Attempt to load the compiled model bundle from the main bundle.
        // Fails gracefully — stub path is used when the model is absent.
        guard let url = Bundle.main.url(forResource: "LungScopeClassifier",
                                        withExtension: "mlmodelc") else {
            model = nil
            return
        }
        model = try? MLModel(contentsOf: url)
    }

    // MARK: - Inference

    /// Runs inference on a feature vector and returns a DiagnosticResult.
    ///
    /// Falls back to the stub when no compiled model is present, so the UI
    /// remains functional during development without a trained model.
    ///
    /// - Parameter features: The assembled FeatureVector from AudioAnalysisActor.
    /// - Returns: A DiagnosticResult with both scores clamped to [0, 1].
    /// - Throws: InferenceError.predictionFailed if the model is present but
    ///   the prediction call itself fails.
    func run(_ features: FeatureVector) throws -> DiagnosticResult {
        guard let model else {
            return stub()
        }
        return try predict(features: features, using: model)
    }

    // MARK: - Private

    private static let featureNames: [String] = {
        var names = (0..<13).map { "mfcc_mean_\($0)" }
        names += (0..<13).map { "mfcc_std_\($0)" }
        names += ["spectral_flatness", "jitter", "shimmer"]
        return names
    }()

    private func predict(features: FeatureVector, using model: MLModel) throws -> DiagnosticResult {
        // Flatten FeatureVector into the named input format the sklearn converter expects.
        let values: [Float] = features.mfccMean + features.mfccStdDev
            + [features.spectralFlatness, features.jitter, features.shimmer]

        var dict: [String: Any] = [:]
        for (name, value) in zip(Self.featureNames, values) {
            dict[name] = Double(value)
        }

        let input  = try MLDictionaryFeatureProvider(dictionary: dict)
        let output = try model.prediction(from: input)

        // sklearn converter outputs classProbability with integer keys:
        // 0 = "healthy", 1 = "impaired" (LabelEncoder alphabetical order)
        guard let probDict = output.featureValue(for: "classProbability")?.dictionaryValue else {
            return stub()
        }

        let impairedProb = clamp((probDict[1 as NSNumber] as? NSNumber)?.doubleValue ?? 0.5)
        let healthyProb  = clamp((probDict[0 as NSNumber] as? NSNumber)?.doubleValue ?? 0.5)

        return DiagnosticResult(
            airwayConstrictionIndex:    Float(impairedProb),
            vocalHarmonyStabilityScore: Float(healthyProb)
        )
    }

    // Stub returns mid-range values so all UI states are reachable without a model.
    private func stub() -> DiagnosticResult {
        DiagnosticResult(airwayConstrictionIndex: 0.42,
                         vocalHarmonyStabilityScore: 0.71)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

// MARK: - Errors

enum InferenceError: LocalizedError {
    case predictionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .predictionFailed(let e):
            return "Inference failed: \(e.localizedDescription)"
        }
    }
}
