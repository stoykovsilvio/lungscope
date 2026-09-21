import Foundation

/// Orchestrates the complete DSP analysis pipeline over a finished recording.
///
/// Called exactly once per session, after AudioEngine.stopAndDrain() returns.
/// Never called concurrently with the AVAudioEngine tap callback.
actor AudioAnalysisActor {

    // MARK: - Owned DSP Instances (pre-allocated at init)

    private let fftProcessor   = FFTProcessor()
    private let melFilterbank  = MelFilterbank()
    private let mfccExtractor  = MFCCExtractor()
    private let pitchDetector  = PitchDetector()

    // SpectralFlatness, JitterCalculator, ShimmerCalculator are stateless
    // enums — no stored instances needed.

    // MARK: - Public API

    /// Runs the full cough-side and vowel-side DSP pipelines and assembles
    /// a FeatureVector ready for CoreML inference.
    ///
    /// - Parameters:
    ///   - cough: Float32 samples from AudioRingBuffer.coughBuffer.
    ///   - vowel: Float32 samples from AudioRingBuffer.vowelBuffer.
    /// - Returns: A fully populated FeatureVector.
    /// - Throws: AudioAnalysisError.insufficientSamples if either buffer is
    ///   shorter than half its expected window size.
    func analyse(cough: [Float], vowel: [Float]) throws -> FeatureVector {
        try validateInputLengths(cough: cough, vowel: vowel)

        // --- Cough side ---
        let spectra      = fftProcessor.magnitudeSpectra(from: cough)
        let logEnergies  = melFilterbank.apply(to: spectra)
        let mfccFeatures = mfccExtractor.extract(from: logEnergies)
        let sfm          = SpectralFlatness.compute(from: spectra)

        // --- Vowel side ---
        let periods = pitchDetector.extractPeriods(from: vowel)
        let jitter  = JitterCalculator.compute(from: periods)
        let shimmer = ShimmerCalculator.compute(from: vowel, periods: periods)

        return FeatureVector(
            mfccMean:         mfccFeatures.mean,
            mfccStdDev:       mfccFeatures.stdDev,
            spectralFlatness: sfm,
            jitter:           jitter,
            shimmer:          shimmer
        )
    }

    // MARK: - Private

    private func validateInputLengths(cough: [Float], vowel: [Float]) throws {
        let minCough = AudioFormat.coughWindowSamples / 2
        let minVowel = AudioFormat.vowelWindowSamples / 2

        if cough.count < minCough {
            throw AudioAnalysisError.insufficientSamples(
                phase: "cough", count: cough.count, minimum: minCough)
        }
        if vowel.count < minVowel {
            throw AudioAnalysisError.insufficientSamples(
                phase: "vowel", count: vowel.count, minimum: minVowel)
        }
    }
}

// MARK: - Errors

enum AudioAnalysisError: LocalizedError {
    case insufficientSamples(phase: String, count: Int, minimum: Int)

    var errorDescription: String? {
        switch self {
        case let .insufficientSamples(phase, count, minimum):
            return "Recording too short (\(phase) phase: \(count) samples, minimum \(minimum)). Please try again."
        }
    }
}
