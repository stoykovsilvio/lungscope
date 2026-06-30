import AVFoundation

enum AudioFormat {

    // MARK: - Hardware Lock Constants
    // Sample rate and channel count are fixed for medical dataset alignment.
    // Any deviation will silently corrupt DSP feature extraction.
    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1

    // MARK: - Recording Window Sizes (in samples)
    static let coughWindowSamples: Int = Int(sampleRate) * 5             // 5s  = 80,000 samples
    static let vowelWindowSamples: Int = Int(sampleRate) * 10            // 10s = 160,000 samples

    // MARK: - Canonical AVAudioFormat
    /// Non-interleaved Float32 at 16kHz mono. AVAudioEngine's installTap only
    /// reliably delivers non-interleaved Float32 buffers regardless of the
    /// requested format — using this natively avoids a conversion step and
    /// ensures tap buffers can be passed directly to Accelerate vDSP functions.
    /// Samples are normalised to [-1.0, 1.0] by the hardware driver.
    ///
    /// Force-unwrap is intentional: failure here is an unrecoverable
    /// hardware incompatibility and a crash is the correct response.
    static let canonical: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            preconditionFailure("AudioFormat: failed to construct canonical 16kHz/Float32/mono format.")
        }
        return format
    }()

    // MARK: - Converter Factory
    /// Returns a pre-warmed AVAudioConverter from the device's native hardware
    /// format to our canonical format. Must be called once at engine startup,
    /// never inside the tap callback.
    static func makeConverter(from hardwareFormat: AVAudioFormat) -> AVAudioConverter? {
        guard hardwareFormat != canonical else { return nil }
        return AVAudioConverter(from: hardwareFormat, to: canonical)
    }
}
