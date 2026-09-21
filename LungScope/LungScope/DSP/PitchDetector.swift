import Accelerate

/// Extracts the fundamental frequency (F0) period array from a voiced vowel
/// signal using the YIN algorithm. The returned array of per-frame period
/// estimates (in samples) is consumed by JitterCalculator and ShimmerCalculator.
final class PitchDetector {

    // MARK: - Configuration

    let frameSize: Int
    let hopSize: Int
    let minPeriod: Int
    let maxPeriod: Int
    let threshold: Float

    // MARK: - Pre-allocated Buffers

    private var differenceBuffer: [Float]
    private var cmndfBuffer: [Float]

    // MARK: - Initialisation

    /// - Parameters:
    ///   - frameSize: Analysis window in samples. 2048 = 128ms at 16kHz.
    ///   - hopSize: Frame advance in samples. 512 = 32ms step.
    ///   - minF0Hz: Minimum detectable F0. Frames below this are treated as unvoiced.
    ///   - maxF0Hz: Maximum detectable F0. Frames above this are treated as unvoiced.
    ///   - threshold: YIN CMNDF threshold. Lower = fewer false detections.
    init(
        frameSize: Int = 2048,
        hopSize: Int = 512,
        minF0Hz: Double = 85.0,
        maxF0Hz: Double = 400.0,
        sampleRate: Double = 16_000.0,
        threshold: Float = 0.1
    ) {
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.threshold = threshold

        // Convert Hz bounds to period bounds in samples.
        self.minPeriod = max(1, Int(sampleRate / maxF0Hz))
        self.maxPeriod = Int(sampleRate / minF0Hz)

        self.differenceBuffer = [Float](repeating: 0, count: maxPeriod + 1)
        self.cmndfBuffer      = [Float](repeating: 0, count: maxPeriod + 1)
    }

    // MARK: - Public API

    /// Extracts per-frame fundamental period estimates from a voiced signal.
    ///
    /// Unvoiced frames (CMNDF never dips below threshold) are silently dropped.
    /// The caller receives only confident period estimates.
    ///
    /// - Parameter signal: Normalised Float32 samples from AudioRingBuffer.
    /// - Returns: Array of period estimates in samples. Empty if no voiced frames found.
    func extractPeriods(from signal: [Float]) -> [Float] {
        let frameCount = max(0, (signal.count - frameSize) / hopSize + 1)
        var periods = [Float]()
        periods.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            let frame = Array(signal[start ..< start + frameSize])

            if let period = detectPeriod(in: frame) {
                periods.append(period)
            }
        }

        return periods
    }

    // MARK: - Private: YIN Core

    private func detectPeriod(in frame: [Float]) -> Float? {
        computeDifferenceFunction(frame: frame)
        computeCMNDF()

        // Find the first tau in [minPeriod, maxPeriod] where CMNDF dips below threshold.
        for tau in minPeriod..<maxPeriod {
            guard tau + 1 < cmndfBuffer.count else { break }
            if cmndfBuffer[tau] < threshold && cmndfBuffer[tau] <= cmndfBuffer[tau + 1] {
                return parabolicInterpolation(around: tau)
            }
        }

        // No threshold crossing — fall back to the global minimum if it is
        // reasonably low, otherwise treat the frame as unvoiced.
        var searchSlice = Array(cmndfBuffer[minPeriod..<min(maxPeriod, cmndfBuffer.count)])
        var minVal: Float = 0
        var minIdx: vDSP_Length = 0
        vDSP_minvi(&searchSlice, 1, &minVal, &minIdx, vDSP_Length(searchSlice.count))

        guard minVal < 0.3 else { return nil }
        return parabolicInterpolation(around: minPeriod + Int(minIdx))
    }

    // MARK: - YIN Step 2: Difference Function
    // d[tau] = Σ (x[t] - x[t + tau])^2 over the frame half.

    private func computeDifferenceFunction(frame: [Float]) {
        let halfFrame = frameSize / 2

        differenceBuffer[0] = 0

        for tau in 1...maxPeriod {
            guard tau + halfFrame <= frame.count else {
                differenceBuffer[tau] = 0
                continue
            }

            // d[tau] = Σ (x[t] - x[t+tau])^2
            // = Σ x[t]^2 + Σ x[t+tau]^2 - 2 Σ x[t]*x[t+tau]
            var x    = Array(frame[0..<halfFrame])
            var xTau = Array(frame[tau..<(tau + halfFrame)])

            var diff = [Float](repeating: 0, count: halfFrame)
            vDSP_vsub(&x, 1, &xTau, 1, &diff, 1, vDSP_Length(halfFrame))

            var squaredSum: Float = 0
            vDSP_svesq(&diff, 1, &squaredSum, vDSP_Length(halfFrame))
            differenceBuffer[tau] = squaredSum
        }
    }

    // MARK: - YIN Step 3: Cumulative Mean Normalised Difference Function

    private func computeCMNDF() {
        cmndfBuffer[0] = 1.0

        var runningSum: Float = 0
        for tau in 1...maxPeriod {
            runningSum += differenceBuffer[tau]
            if runningSum == 0 {
                cmndfBuffer[tau] = 1.0
            } else {
                cmndfBuffer[tau] = differenceBuffer[tau] * Float(tau) / runningSum
            }
        }
    }

    // MARK: - YIN Step 5: Parabolic Interpolation
    // Refines the integer period estimate to sub-sample accuracy.

    private func parabolicInterpolation(around tau: Int) -> Float {
        let lower = tau - 1
        let upper = tau + 1

        guard lower >= 0, upper < cmndfBuffer.count else {
            return Float(tau)
        }

        let s0 = cmndfBuffer[lower]
        let s1 = cmndfBuffer[tau]
        let s2 = cmndfBuffer[upper]

        let denominator = s0 - 2 * s1 + s2
        guard abs(denominator) > 1e-10 else { return Float(tau) }

        let delta = 0.5 * (s0 - s2) / denominator
        return Float(tau) + delta
    }
}
