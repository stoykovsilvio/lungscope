import Accelerate

/// Computes a magnitude spectrum from a time-domain Float32 signal using
/// Apple's vDSP FFT. All intermediate buffers are pre-allocated at init time.
/// Thread-safe for concurrent reads on separate instances; a single instance
/// must not be called concurrently.
final class FFTProcessor {

    // MARK: - Configuration

    let fftSize: Int
    let hopSize: Int

    // MARK: - Pre-allocated Working Buffers

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var windowBuffer: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var splitComplex: DSPSplitComplex

    // MARK: - Derived Constants

    /// Number of unique magnitude bins: fftSize/2 + 1 (DC through Nyquist).
    var magnitudeBinCount: Int { fftSize / 2 + 1 }

    // MARK: - Initialisation

    /// - Parameters:
    ///   - fftSize: Must be a power of two. Recommended: 512 for 16kHz audio
    ///     (32ms frame, 4Hz frequency resolution).
    ///   - hopSize: Frame advance in samples. 256 = 50% overlap.
    init(fftSize: Int = 512, hopSize: Int = 256) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0,
                     "FFTProcessor: fftSize must be a power of two.")

        self.fftSize = fftSize
        self.hopSize = hopSize
        self.log2n = vDSP_Length(log2(Float(fftSize)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("FFTProcessor: failed to create vDSP FFT setup.")
        }
        self.fftSetup = setup

        // Hann window: w(n) = 0.5 × (1 − cos(2π·n / (N−1)))
        // Reduces spectral leakage by tapering frame edges to zero.
        self.windowBuffer = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&windowBuffer, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.real = [Float](repeating: 0, count: fftSize / 2)
        self.imag = [Float](repeating: 0, count: fftSize / 2)
        self.splitComplex = DSPSplitComplex(realp: &self.real, imagp: &self.imag)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Public API

    /// Computes per-frame magnitude spectra for an entire signal.
    ///
    /// - Parameter signal: Normalised Float32 samples from AudioRingBuffer.
    /// - Returns: 2D array [frameIndex][binIndex], magnitude in linear scale.
    ///   Number of frames = floor((signal.count − fftSize) / hopSize) + 1.
    func magnitudeSpectra(from signal: [Float]) -> [[Float]] {
        let frameCount = max(0, (signal.count - fftSize) / hopSize + 1)
        var spectra = [[Float]](repeating: [Float](repeating: 0, count: magnitudeBinCount),
                                count: frameCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            let frame = Array(signal[start ..< start + fftSize])
            spectra[frameIndex] = computeMagnitudeSpectrum(frame: frame)
        }

        return spectra
    }

    // MARK: - Private

    private func computeMagnitudeSpectrum(frame: [Float]) -> [Float] {
        // 1. Apply Hann window in-place.
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, windowBuffer, 1, &windowed, 1, vDSP_Length(fftSize))

        // 2. Pack real signal into split-complex format required by vDSP.
        //    Interprets even samples as real, odd samples as imaginary.
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                vDSP_ctoz(complex, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }

        // 3. Execute in-place forward FFT.
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // 4. Compute magnitude: |X[k]| = sqrt(real[k]² + imag[k]²).
        //    vDSP_zvabs computes this over the split-complex vector.
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // 5. Scale: vDSP_fft_zrip output is scaled by 2 relative to a
        //    full-length DFT. Divide by fftSize to obtain true magnitudes.
        var scale = Float(fftSize)
        var scaledMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_vsdiv(&magnitudes, 1, &scale, &scaledMagnitudes, 1, vDSP_Length(fftSize / 2))

        // 6. Append the Nyquist bin (stored in imag[0] by vDSP convention).
        var result = [Float](repeating: 0, count: magnitudeBinCount)
        result[0..<fftSize / 2] = scaledMagnitudes[0..<fftSize / 2]
        result[fftSize / 2] = abs(splitComplex.imagp[0]) / Float(fftSize)

        return result
    }
}
