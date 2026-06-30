import Accelerate

/// Computes Spectral Flatness Measure (SFM) per frame from FFT magnitude spectra.
/// SFM quantifies how noise-like vs. tonal a spectrum is:
///   - SFM ≈ 1.0 → perfectly flat (white noise / turbulent airflow)
///   - SFM ≈ 0.0 → highly tonal (sinusoidal / clear vocal tone)
///
/// For cough analysis, elevated SFM in mid-frequency bands indicates
/// increased turbulent airflow characteristic of airway obstruction or
/// mucus accumulation.
enum SpectralFlatness {

    // MARK: - Public API

    /// Computes the mean SFM across all frames of a magnitude spectrum sequence.
    ///
    /// - Parameter spectra: Output of FFTProcessor.magnitudeSpectra(from:).
    ///   Shape: [frameCount × magnitudeBinCount].
    /// - Returns: Mean spectral flatness in [0.0, 1.0].
    static func compute(from spectra: [[Float]]) -> Float {
        guard !spectra.isEmpty else { return 0 }
        let perFrameSFM = spectra.map { computeFrameSFM($0) }
        var mean: Float = 0
        var mutableSFM = perFrameSFM
        vDSP_meanv(&mutableSFM, 1, &mean, vDSP_Length(perFrameSFM.count))
        return mean
    }

    /// Computes SFM for each frame individually.
    ///
    /// - Returns: [Float] of length frameCount, each value in [0.0, 1.0].
    static func computePerFrame(from spectra: [[Float]]) -> [Float] {
        spectra.map { computeFrameSFM($0) }
    }

    // MARK: - Private

    /// SFM = geometric_mean(X) / arithmetic_mean(X)
    ///
    /// Computed as: exp( mean(log(X)) ) / mean(X)
    /// to avoid numerical overflow in the geometric mean product.
    private static func computeFrameSFM(_ spectrum: [Float]) -> Float {
        let binCount = spectrum.count
        guard binCount > 0 else { return 0 }

        // Floor near-zero bins to avoid log(0) = -inf.
        var floored = spectrum.map { max($0, 1e-10) }

        // Arithmetic mean via vDSP.
        var arithmeticMean: Float = 0
        vDSP_meanv(&floored, 1, &arithmeticMean, vDSP_Length(binCount))
        guard arithmeticMean > 1e-10 else { return 0 }

        // Log of each bin value: log(x_i)
        var logValues = [Float](repeating: 0, count: binCount)
        var n = Int32(binCount)
        vvlogf(&logValues, &floored, &n)

        // Mean of log values: (1/N) × Σ log(x_i)
        var meanOfLog: Float = 0
        vDSP_meanv(&logValues, 1, &meanOfLog, vDSP_Length(binCount))

        // Geometric mean: exp( mean(log(x)) )
        let geometricMean = expf(meanOfLog)

        // SFM = geometric_mean / arithmetic_mean, clamped to [0, 1].
        return min(max(geometricMean / arithmeticMean, 0), 1)
    }
}
