import Foundation
import os

/// Represents the current active phase of a single assessment session.
/// This value is written by the UI coordinator and read inside the
/// AVAudioEngine tap callback — the atomic storage guarantee is the
/// only thread-safety mechanism required.
enum RecordingPhase {
    case idle
    case cough
    case vowel
}

/// A thread-safe wrapper around RecordingPhase for use across the
/// real-time audio thread and the UI coordinator thread.
///
/// Uses a nonisolated(unsafe) var protected by OSAllocatedUnfairLock —
/// the only lock primitive safe to acquire on a real-time audio thread
/// because it never causes thread priority inversion.
final class AtomicRecordingPhase: @unchecked Sendable {

    private var _phase: RecordingPhase = .idle
    private var _lock = OSAllocatedUnfairLock()

    var phase: RecordingPhase {
        get { _lock.withLock { _phase } }
        set { _lock.withLock { _phase = newValue } }
    }

    func transition(to newPhase: RecordingPhase) {
        _lock.withLock { _phase = newPhase }
    }
}
