import Accelerate

/// Computes the Relative Average Perturbation (RAP) jitter from a per-cycle
/// fundamental period array produced by PitchDetector.
///
/// Jitter quantifies cycle-to-cycle instability in the vocal fold oscillation
/// period — the primary acoustic marker of inability to sustain steady
/// subglottal pressure during vowel phonation.
enum JitterCalculator {

    /// Computes the dimensionless jitter ratio.
    ///
    /// Formula: Σ|T_i − T_{i+1}| / (N − 1) / T̄
    ///
    /// - Parameter periods: Per-frame period estimates in samples from PitchDetector.
    /// - Returns: Dimensionless ratio in [0, ∞). Healthy: < 0.01. Elevated: > 0.03.
    ///   Returns 0.0 when fewer than two periods are supplied.
    static func compute(from periods: [Float]) -> Float {
        let n = periods.count
        guard n >= 2 else { return 0.0 }

        // Absolute differences |T_i - T_{i+1}|
        var leading  = Array(periods.dropLast())
        var trailing = Array(periods.dropFirst())
        var diffs = [Float](repeating: 0, count: n - 1)
        vDSP_vsub(&leading, 1, &trailing, 1, &diffs, 1, vDSP_Length(n - 1))

        var absDiffs = [Float](repeating: 0, count: n - 1)
        var count = Int32(n - 1)
        vvfabsf(&absDiffs, &diffs, &count)

        // Sum of absolute differences
        var sumAbsDiff: Float = 0
        vDSP_sve(&absDiffs, 1, &sumAbsDiff, vDSP_Length(n - 1))

        // Mean period T̄
        var meanPeriod: Float = 0
        var mutablePeriods = periods
        vDSP_meanv(&mutablePeriods, 1, &meanPeriod, vDSP_Length(n))

        guard meanPeriod > 0 else { return 0.0 }

        return (sumAbsDiff / Float(n - 1)) / meanPeriod
    }
}
