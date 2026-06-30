import Foundation
import Accelerate

/// A fixed-capacity, pre-allocated ring buffer for storing raw Float32 PCM samples.
///
/// All memory is allocated once at initialisation. The write path is designed
/// to be called from the AVAudioEngine real-time tap callback and must never
/// allocate heap memory, trigger ARC operations, or call into the Swift runtime.
final class AudioRingBuffer {

    // MARK: - Storage

    private let capacity: Int
    private let buffer: UnsafeMutableBufferPointer<Float>
    private var writeHead: Int = 0
    private var storedCount: Int = 0

    // MARK: - Initialisation

    /// Allocates the backing store. Must be called before the audio engine starts.
    /// - Parameter capacity: Number of Float32 samples to store. Use
    ///   `AudioFormat.coughWindowSamples` or `AudioFormat.vowelWindowSamples`.
    init(capacity: Int) {
        self.capacity = capacity
        let raw = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        raw.initialize(repeating: 0, count: capacity)
        self.buffer = UnsafeMutableBufferPointer(start: raw, count: capacity)
    }

    deinit {
        buffer.baseAddress?.deallocate()
    }

    // MARK: - Write (Real-Time Safe)

    /// Writes samples from an AVAudioPCMBuffer's floatChannelData[0] array
    /// into the ring buffer. Safe to call from a real-time audio thread:
    /// no heap allocation, no ARC, no Swift runtime calls.
    ///
    /// - Parameters:
    ///   - pointer: Raw pointer to the source Float32 sample array.
    ///   - count: Number of samples to write.
    func write(from pointer: UnsafePointer<Float>, count: Int) {
        let writeCount = min(count, capacity)
        let firstChunk = min(writeCount, capacity - writeHead)
        let secondChunk = writeCount - firstChunk

        (buffer.baseAddress! + writeHead).initialize(from: pointer, count: firstChunk)

        if secondChunk > 0 {
            buffer.baseAddress!.initialize(from: pointer + firstChunk, count: secondChunk)
        }

        writeHead = (writeHead + writeCount) % capacity
        storedCount = min(storedCount + writeCount, capacity)
    }

    // MARK: - Read (Background Thread)

    /// Copies all stored samples into a contiguous [Float] array in
    /// chronological order. Samples are already normalised to [-1.0, 1.0]
    /// by the AVAudioEngine hardware driver — no further scaling required.
    ///
    /// Must only be called from a background thread after recording has stopped.
    ///
    /// - Returns: Float array of length `storedCount`, values in [-1.0, 1.0].
    func drainToFloat() -> [Float] {
        let count = storedCount
        guard count > 0 else { return [] }

        var floats = [Float](repeating: 0, count: count)

        // If the buffer has wrapped, oldest samples start at writeHead.
        let readHead = storedCount < capacity ? 0 : writeHead

        let firstChunk = min(count, capacity - readHead)
        let secondChunk = count - firstChunk

        // Use vDSP_mmov (vector memory move) for NEON-accelerated copy.
        vDSP_mmov(buffer.baseAddress! + readHead, &floats, vDSP_Length(firstChunk), 1,
                  vDSP_Length(firstChunk), vDSP_Length(firstChunk))

        if secondChunk > 0 {
            vDSP_mmov(buffer.baseAddress!, &floats[firstChunk], vDSP_Length(secondChunk), 1,
                      vDSP_Length(secondChunk), vDSP_Length(secondChunk))
        }

        return floats
    }

    // MARK: - Reset (Background Thread)

    /// Resets write head and sample count without deallocating memory.
    /// Call between assessment sessions to reuse the buffer.
    func reset() {
        writeHead = 0
        storedCount = 0
    }

    // MARK: - Diagnostics

    /// Number of samples currently stored.
    var count: Int { storedCount }

    /// True when the buffer has received at least `capacity` samples.
    var isFull: Bool { storedCount == capacity }
}
