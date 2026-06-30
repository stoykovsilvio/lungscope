import Accelerate

/// Constructs a triangular Mel-scale filterbank and applies it to magnitude
/// spectra produced by FFTProcessor. Output is a matrix of log filterbank
/// energies, one row per frame, used as input to MFCCExtractor.
final class MelFilterbank {

    // MARK: - Configuration

    let filterCount: Int
    let fftSize: Int
    let sampleRate: Double

    // MARK: - Pre-allocated Filter Matrix

    /// Shape: [filterCount × magnitudeBinCount]. Row-major storage.
    /// Pre-computed at init; applied via matrix-vector multiply at runtime.
    private let filterMatrix: [Float]
    private let magnitudeBinCount: Int

    // MARK: - Initialisation

    /// - Parameters:
    ///   - filterCount: Number of Mel filters. 26 is standard for MFCC extraction.
    ///   - fftSize: Must match the FFTProcessor instance's fftSize.
    ///   - sampleRate: Must match AudioFormat.sampleRate (16,000 Hz).
    ///   - lowFreqHz: Lower frequency bound of the filterbank. Default 80 Hz.
    ///   - highFreqHz: Upper frequency bound. Default 7,600 Hz (below Nyquist).
    init(filterCount: Int = 26,
         fftSize: Int = 512,
         sampleRate: Double = AudioFormat.sampleRate,
         lowFreqHz: Double = 80.0,
         highFreqHz: Double = 7_600.0) {

        self.filterCount = filterCount
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.magnitudeBinCount = fftSize / 2 + 1

        self.filterMatrix = MelFilterbank.buildFilterMatrix(
            filterCount: filterCount,
            magnitudeBinCount: magnitudeBinCount,
            sampleRate: sampleRate,
            lowFreqHz: lowFreqHz,
            highFreqHz: highFreqHz
        )
    }

    // MARK: - Public API

    /// Applies the filterbank to a sequence of magnitude spectra, returning
    /// log-compressed filterbank energies.
    ///
    /// - Parameter spectra: Output of FFTProcessor.magnitudeSpectra(from:).
    ///   Shape: [frameCount × magnitudeBinCount].
    /// - Returns: [frameCount × filterCount] matrix of log filterbank energies.
    func apply(to spectra: [[Float]]) -> [[Float]] {
        spectra.map { spectrum in
            var energies = [Float](repeating: 0, count: filterCount)

            // Matrix-vector multiply: energies = filterMatrix × spectrum
            // filterMatrix is [filterCount × magnitudeBinCount] (row-major)
            // spectrum is [magnitudeBinCount]
            // Result is [filterCount]
            vDSP_mmul(filterMatrix, 1,
                      spectrum,    1,
                      &energies,   1,
                      vDSP_Length(filterCount),
                      1,
                      vDSP_Length(magnitudeBinCount))

            // Log compression: log(max(energy, ε)) — floor at ε to avoid log(0).
            // vvlogf operates on the entire array in a single vectorised call.
            var floored = energies.map { max($0, 1e-10) }
            var logEnergies = [Float](repeating: 0, count: filterCount)
            var count = Int32(filterCount)
            vvlogf(&logEnergies, &floored, &count)

            return logEnergies
        }
    }

    // MARK: - Private: Filter Matrix Construction

    private static func buildFilterMatrix(filterCount: Int,
                                          magnitudeBinCount: Int,
                                          sampleRate: Double,
                                          lowFreqHz: Double,
                                          highFreqHz: Double) -> [Float] {
        let lowMel  = hertzToMel(lowFreqHz)
        let highMel = hertzToMel(highFreqHz)

        // Compute filterCount+2 equally spaced Mel-scale centre frequencies,
        // then convert back to Hz and to FFT bin indices.
        let melPoints = (0...(filterCount + 1)).map { i -> Double in
            lowMel + Double(i) * (highMel - lowMel) / Double(filterCount + 1)
        }
        let hzPoints  = melPoints.map { melToHertz($0) }
        let binPoints = hzPoints.map { Int(($0 / (sampleRate / 2)) * Double(magnitudeBinCount - 1)) }

        // Build row-major filter matrix: filterCount rows × magnitudeBinCount cols.
        var matrix = [Float](repeating: 0, count: filterCount * magnitudeBinCount)

        for m in 0..<filterCount {
            let left   = binPoints[m]
            let centre = binPoints[m + 1]
            let right  = binPoints[m + 2]

            // Rising slope: bins [left, centre]
            for k in left..<centre {
                let weight = Float(k - left) / Float(centre - left)
                matrix[m * magnitudeBinCount + k] = weight
            }
            // Falling slope: bins [centre, right]
            for k in centre..<right {
                let weight = Float(right - k) / Float(right - centre)
                matrix[m * magnitudeBinCount + k] = weight
            }
        }

        return matrix
    }

    // MARK: - Mel Scale Conversions

    /// O'Shaughnessy (1987) Mel formula: mel = 2595 × log₁₀(1 + Hz/700)
    private static func hertzToMel(_ hz: Double) -> Double {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    private static func melToHertz(_ mel: Double) -> Double {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }
}
