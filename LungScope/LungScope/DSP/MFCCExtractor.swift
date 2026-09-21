import Accelerate

/// Extracts Mel-Frequency Cepstral Coefficients (MFCCs) from log filterbank
/// energies produced by MelFilterbank. Applies a DCT-II to decorrelate the
/// filterbank outputs and compresses them into a compact feature vector.
final class MFCCExtractor {

    // MARK: - Configuration

    let coefficientCount: Int
    let filterCount: Int

    // MARK: - Pre-allocated DCT Setup

    // vDSP DFT only supports lengths of the form 2^a × 3^b × 5^c (a ≥ 3).
    // 26 is not supported, so we zero-pad to the next valid size (32) and
    // discard the extra output bins. Only the first coefficientCount bins are used.
    private let dctSize: Int
    private let dctSetup: vDSP_DFT_Setup

    // MARK: - Initialisation

    init(coefficientCount: Int = 13, filterCount: Int = 26) {
        precondition(coefficientCount <= filterCount,
                     "MFCCExtractor: coefficientCount must be ≤ filterCount.")

        self.coefficientCount = coefficientCount
        self.filterCount = filterCount

        // Find the smallest vDSP-compatible DFT length ≥ filterCount.
        var size = 8
        while size < filterCount { size *= 2 }
        self.dctSize = size

        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(size),
            vDSP_DFT_Direction.FORWARD
        ) else {
            preconditionFailure("MFCCExtractor: failed to create vDSP DFT setup for size \(size).")
        }
        self.dctSetup = setup
    }

    deinit {
        vDSP_DFT_DestroySetup(dctSetup)
    }

    // MARK: - Public API

    func extract(from logFilterbankEnergies: [[Float]]) -> MFCCFeatures {
        let frameCount = logFilterbankEnergies.count
        guard frameCount > 0 else {
            return MFCCFeatures(mean: [Float](repeating: 0, count: coefficientCount),
                                stdDev: [Float](repeating: 0, count: coefficientCount))
        }

        let allCoefficients: [[Float]] = logFilterbankEnergies.map { applyDCT(to: $0) }

        let mean = (0..<coefficientCount).map { c -> Float in
            var col = allCoefficients.map { $0[c] }
            var result: Float = 0
            vDSP_meanv(&col, 1, &result, vDSP_Length(frameCount))
            return result
        }

        let stdDev = (0..<coefficientCount).map { c -> Float in
            var col = allCoefficients.map { $0[c] }
            var result: Float = 0
            vDSP_rmsqv(&col, 1, &result, vDSP_Length(frameCount))
            return result
        }

        return MFCCFeatures(mean: mean, stdDev: stdDev)
    }

    // MARK: - Private: DCT-II via zero-padded vDSP DFT

    private func applyDCT(to energies: [Float]) -> [Float] {
        // Zero-pad filterCount (26) values up to dctSize (32).
        var realIn = energies + [Float](repeating: 0, count: dctSize - filterCount)
        var imagIn  = [Float](repeating: 0, count: dctSize)
        var realOut = [Float](repeating: 0, count: dctSize)
        var imagOut = [Float](repeating: 0, count: dctSize)

        vDSP_DFT_Execute(dctSetup, &realIn, &imagIn, &realOut, &imagOut)

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
    let mean:   [Float]
    let stdDev: [Float]
}
