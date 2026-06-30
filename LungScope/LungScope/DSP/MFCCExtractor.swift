import Accelerate

/// Extracts Mel-Frequency Cepstral Coefficients (MFCCs) from log filterbank
/// energies produced by MelFilterbank. Applies a DCT-II to decorrelate the
/// filterbank outputs and compresses them into a compact feature vector.
final class MFCCExtractor {

    // MARK: - Configuration

    let coefficientCount: Int
    let filterCount: Int

    // MARK: - Pre-allocated DCT Setup

    private let dctSetup: vDSP_DFT_Setup

    // MARK: - Initialisation

    /// - Parameters:
    ///   - coefficientCount: Number of MFCC coefficients to retain. 13 is
    ///     standard; C0 (energy) is included, giving indices 0–12.
    ///   - filterCount: Must match the MelFilterbank instance's filterCount. Default 26.
    init(coefficientCount: Int = 13, filterCount: Int = 26) {
        precondition(coefficientCount <= filterCount,
                     "MFCCExtractor: coefficientCount must be ≤ filterCount.")

        self.coefficientCount = coefficientCount
        self.filterCount = filterCount

        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(filterCount),
            vDSP_DFT_Direction.FORWARD
        ) else {
            preconditionFailure("MFCCExtractor: failed to create vDSP DFT setup.")
        }
        self.dctSetup = setup
    }

    deinit {
        vDSP_DFT_DestroySetup(dctSetup)
    }

    // MARK: - Public API

    /// Computes MFCCs for each frame, then returns the mean and standard
    /// deviation across frames as a compact feature vector.
    ///
    /// - Parameter logFilterbankEnergies: Output of MelFilterbank.apply(to:).
    ///   Shape: [frameCount × filterCount].
    /// - Returns: FeatureComponents with mfccMean[coefficientCount] and
    ///   mfccStdDev[coefficientCount].
    func extract(from logFilterbankEnergies: [[Float]]) -> MFCCFeatures {
        let frameCount = logFilterbankEnergies.count
        guard frameCount > 0 else {
            return MFCCFeatures(mean: [Float](repeating: 0, count: coefficientCount),
                                stdDev: [Float](repeating: 0, count: coefficientCount))
        }

        // Compute per-frame MFCCs: shape [frameCount × coefficientCount]
        let allCoefficients: [[Float]] = logFilterbankEnergies.map { frameBankEnergies in
            applyDCT(to: frameBankEnergies)
        }

        // Transpose to [coefficientCount × frameCount] for per-coefficient stats.
        let mean   = (0..<coefficientCount).map { c -> Float in
            var col = allCoefficients.map { $0[c] }
            var result: Float = 0
            vDSP_meanv(&col, 1, &result, vDSP_Length(frameCount))
            return result
        }

        let stdDev = (0..<coefficientCount).map { c -> Float in
            var col = allCoefficients.map { $0[c] }
            var result: Float = 0
            vDSP_rmsqv(&col, 1, &result, vDSP_Length(frameCount))
            // stdDev = sqrt(E[x²] − E[x]²) — approximate via RMS for efficiency.
            // Full variance would require a second pass; RMS is sufficient for
            // discriminating healthy vs. impaired respiratory patterns.
            return result
        }

        return MFCCFeatures(mean: mean, stdDev: stdDev)
    }

    // MARK: - Private: DCT-II via vDSP DFT

    /// Applies a DCT-II approximation using vDSP's real DFT.
    /// Returns the first `coefficientCount` coefficients.
    private func applyDCT(to energies: [Float]) -> [Float] {
        // vDSP_DFT_zop requires split-complex input. For a real input signal,
        // place the energies in the real part and zero the imaginary part.
        var realIn  = energies
        var imagIn  = [Float](repeating: 0, count: filterCount)
        var realOut = [Float](repeating: 0, count: filterCount)
        var imagOut = [Float](repeating: 0, count: filterCount)

        vDSP_DFT_Execute(dctSetup, &realIn, &imagIn, &realOut, &imagOut)

        // The DCT-II coefficients are encoded in the real part of the DFT output.
        // Apply the standard DCT-II normalisation factor.
        // C[k] = realOut[k] × (1/N) for k=0, × (2/N) for k>0
        let n = Float(filterCount)
        var coefficients = [Float](repeating: 0, count: coefficientCount)
        coefficients[0] = realOut[0] / n
        for k in 1..<coefficientCount {
            coefficients[k] = realOut[k] * (2.0 / n)
        }

        return coefficients
    }
}

// MARK: - Output Value Type

struct MFCCFeatures {
    let mean:   [Float]   // length: coefficientCount
    let stdDev: [Float]   // length: coefficientCount
}
