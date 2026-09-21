import Accelerate

/// Computes the amplitude perturbation ratio (shimmer) from the vowel signal
/// using the same F0 segmentation produced by PitchDetector.
///
/// Shimmer quantifies cycle-to-cycle instability in vocal fold closure
/// amplitude — the amplitude-domain counterpart to jitter.
enum ShimmerCalculator {

    /// Computes the dimensionless shimmer ratio.
    ///
    /// Formula: Σ|A_i − A_{i+1}| / (N − 1) / Ā
    ///
    /// - Parameters:
    ///   - signal: Normalised Float32 vowel samples from AudioRingBuffer.
    ///   - periods: Per-frame period estimates in samples from PitchDetector.
    /// - Returns: Dimensionless ratio in [0, ∞). Healthy: < 0.03. Elevated: > 0.07.
    ///   Returns 0.0 when fewer than two periods are supplied.
    static func compute(from signal: [Float], periods: [Float]) -> Float {
        let n = periods.count
        guard n >= 2 else { return 0.0 }

        let amplitudes = extractCyclePeaks(from: signal, periods: periods)
        guard amplitudes.count >= 2 else { return 0.0 }

        let cycleCount = amplitudes.count
        var leading  = Array(amplitudes.dropLast())
        var trailing = Array(amplitudes.dropFirst())
        var diffs = [Float](repeating: 0, count: cycleCount - 1)
        vDSP_vsub(&leading, 1, &trailing, 1, &diffs, 1, vDSP_Length(cycleCount - 1))

        var absDiffs = [Float](repeating: 0, count: cycleCount - 1)
        var count = Int32(cycleCount - 1)
        vvfabsf(&absDiffs, &diffs, &count)

        var sumAbsDiff: Float = 0
        vDSP_sve(&absDiffs, 1, &sumAbsDiff, vDSP_Length(cycleCount - 1))

        var meanAmplitude: Float = 0
        var mutableAmplitudes = amplitudes
        vDSP_meanv(&mutableAmplitudes, 1, &meanAmplitude, vDSP_Length(cycleCount))

        guard meanAmplitude > 0 else { return 0.0 }

        return (sumAbsDiff / Float(cycleCount - 1)) / meanAmplitude
    }

    // MARK: - Private

    /// Extracts the peak amplitude of each vocal cycle using the period array
    /// as boundary markers. Cycle i spans samples [offset, offset + T_i).
    private static func extractCyclePeaks(from signal: [Float], periods: [Float]) -> [Float] {
        var amplitudes = [Float]()
        amplitudes.reserveCapacity(periods.count)

        var offset = 0
        for period in periods {
            let cycleLength = Int(period.rounded())
            let end = offset + cycleLength

            guard end <= signal.count else { break }

            var slice = Array(signal[offset..<end])
            var peak: Float = 0
            vDSP_maxmgv(&slice, 1, &peak, vDSP_Length(slice.count))
            amplitudes.append(peak)

            offset = end
        }

        return amplitudes
    }
}
