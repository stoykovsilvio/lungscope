import AVFoundation
import Accelerate
import os.log

/// Owns and manages the AVAudioEngine session for a single assessment.
/// Responsible for: engine configuration, microphone permission, tap
/// installation, phase-gated ring buffer writes, and session teardown.
///
/// All public methods are async and must be called from a Swift structured
/// concurrency context. The real-time tap callback is the only synchronous
/// boundary — it writes into pre-allocated ring buffers via pointer arithmetic.
@MainActor
final class AudioEngine {

    // MARK: - Dependencies

    private let engine = AVAudioEngine()
    private let coughBuffer = AudioRingBuffer(capacity: AudioFormat.coughWindowSamples)
    private let vowelBuffer = AudioRingBuffer(capacity: AudioFormat.vowelWindowSamples)
    private let phaseController = AtomicRecordingPhase()
    private var converter: AVAudioConverter?

    private let log = OSLog(subsystem: "com.lungscope", category: "AudioEngine")

    // Callback fired on @MainActor at ≤30fps with one RMS value per ~512-sample window.
    // Assigned by AssessmentViewModel before the cough phase starts.
    var onWaveformSample: ((Float) -> Void)?

    // Running counter for downsampling tap frames to ≤30fps RMS posts.
    private var tapFrameAccumulator: Int = 0
    private let rmsPostInterval = 512

    // MARK: - Public Interface

    /// Requests microphone permission and prepares the engine.
    /// Must be called before `startCoughPhase()`.
    /// Throws if permission is denied or the engine cannot start.
    func prepare() async throws {
        try await requestMicrophonePermission()
        try configureEngine()
    }

    /// Arms the cough ring buffer and begins audio capture.
    func startCoughPhase() {
        coughBuffer.reset()
        phaseController.transition(to: .cough)
        os_log("Phase → cough", log: log, type: .debug)
    }

    /// Transitions capture from cough ring buffer to vowel ring buffer.
    func startVowelPhase() {
        vowelBuffer.reset()
        phaseController.transition(to: .vowel)
        os_log("Phase → vowel", log: log, type: .debug)
    }

    /// Pauses sample capture between phases without stopping the engine.
    /// The tap keeps running but writes nothing until the next phase starts.
    func pauseBetweenPhases() {
        phaseController.transition(to: .idle)
        os_log("Phase → idle (between phases)", log: log, type: .debug)
    }

    /// Stops capture and returns both buffers' samples for DSP analysis.
    /// Transitions phase to .idle so the tap stops writing.
    /// Returns: (coughSamples, vowelSamples) — both normalised Float32 arrays.
    func stopAndDrain() -> (cough: [Float], vowel: [Float]) {
        phaseController.transition(to: .idle)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        os_log("Engine stopped. Cough samples: %d, Vowel samples: %d",
               log: log, type: .debug, coughBuffer.count, vowelBuffer.count)
        return (coughBuffer.drainToFloat(), vowelBuffer.drainToFloat())
    }

    // MARK: - Private: Permission

    private func requestMicrophonePermission() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw AudioEngineError.microphonePermissionDenied
        }
    }

    // MARK: - Private: Engine Configuration

    private func configureEngine() throws {
        let inputNode = engine.inputNode

        // prepare() forces the hardware connection so outputFormat returns a
        // valid sample rate. Without it, the format can come back with rate 0.
        engine.prepare()

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        converter = AudioFormat.makeConverter(from: hardwareFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0,
                             bufferSize: 4096,
                             format: nil) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        try engine.start()
        os_log("Engine started. Hardware format: %@", log: log, type: .debug,
               hardwareFormat.description)
    }

    // MARK: - Private: Real-Time Tap Handler

    /// Called by AVAudioEngine on a real-time hardware thread.
    /// STRICT RULES: no heap allocation, no ARC, no Swift runtime calls,
    /// no locks (except OSAllocatedUnfairLock in phaseController).
    private func handleBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        let phase = phaseController.phase
        guard phase != .idle else { return }

        // If a converter exists, route samples through it first.
        if let converter {
            guard let converted = convertBuffer(inputBuffer, using: converter) else { return }
            writeBuffer(converted, to: phase)
        } else {
            writeBuffer(inputBuffer, to: phase)
        }
    }

    private func convertBuffer(_ input: AVAudioPCMBuffer,
                                using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let inputRate  = converter.inputFormat.sampleRate
        let outputRate = converter.outputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(input.frameLength) * outputRate / inputRate + 1)

        guard let output = AVAudioPCMBuffer(pcmFormat: AudioFormat.canonical,
                                            frameCapacity: outputCapacity) else { return nil }
        var error: NSError?
        var sourceDone = false

        converter.convert(to: output, error: &error) { _, outStatus in
            if sourceDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            sourceDone = true
            return input
        }

        return error == nil ? output : nil
    }

    private func writeBuffer(_ buffer: AVAudioPCMBuffer, to phase: RecordingPhase) {
        guard let channelData = buffer.floatChannelData else { return }
        let pointer = channelData[0]
        let frameCount = Int(buffer.frameLength)

        switch phase {
        case .cough:  coughBuffer.write(from: pointer, count: frameCount)
        case .vowel:  vowelBuffer.write(from: pointer, count: frameCount)
        case .idle:   break
        }

        // Post one RMS value to the waveform display callback every ~512 samples.
        // vDSP_rmsqv is real-time safe (no allocation). The DispatchQueue hop is
        // unavoidable here — the tap runs on the audio thread, not @MainActor.
        tapFrameAccumulator += frameCount
        if tapFrameAccumulator >= rmsPostInterval, let cb = onWaveformSample {
            tapFrameAccumulator = 0
            var rms: Float = 0
            vDSP_rmsqv(pointer, 1, &rms, vDSP_Length(frameCount))
            DispatchQueue.main.async { cb(rms) }
        }
    }
}

// MARK: - Errors

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required for lung assessment. Please enable it in Settings."
        }
    }
}
