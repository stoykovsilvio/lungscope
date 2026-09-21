import SwiftUI
import Combine
import AVFoundation

@MainActor
final class AssessmentViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var appPhase: AppPhase = .idle
    @Published private(set) var diagnosticResult: DiagnosticResult?
    @Published private(set) var waveformSamples: [Float] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var vowelTimeRemaining: TimeInterval = 10.0

    // MARK: - Private

    private let audioEngine      = AudioEngine()
    private let analysisActor    = AudioAnalysisActor()
    private let inferenceEngine  = DiagnosticInferenceEngine()
    private let healthKit        = HealthKitManager()
    let resultsStore             = ResultsStore()

    private var vowelTimer: Timer?
    private var currentSession: AssessmentSession?

    // MARK: - Assessment Control

    /// Requests microphone permission, configures the engine, and begins
    /// the cough recording phase.
    func startAssessment() async {
        errorMessage = nil
        do {
            await healthKit.requestAuthorization()
            try await audioEngine.prepare()
            audioEngine.onWaveformSample = { [weak self] rms in
                Task { @MainActor in self?.waveformSamples.append(rms) }
            }
            currentSession = AssessmentSession(coughSampleCount: 0, vowelSampleCount: 0)
            audioEngine.startCoughPhase()
            appPhase = .coughRecording
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops cough capture and moves to the ready screen so the user can
    /// catch their breath before the vowel phase begins.
    func transitionToVowelPhase() {
        guard appPhase == .coughRecording else { return }
        audioEngine.pauseBetweenPhases()
        appPhase = .vowelReady
    }

    /// Called from VowelReadyView when the user taps "Begin". Starts the
    /// 10-second vowel recording and the countdown timer.
    func startVowelRecording() {
        guard appPhase == .vowelReady else { return }
        audioEngine.startVowelPhase()
        appPhase = .vowelRecording
        vowelTimeRemaining = 10.0
        startVowelTimer()
    }

    /// Stops recording, runs DSP + ML inference, and transitions to results.
    func finishAssessment() async {
        vowelTimer?.invalidate()
        vowelTimer = nil

        let (coughSamples, vowelSamples) = audioEngine.stopAndDrain()
        currentSession = AssessmentSession(
            id: currentSession?.id ?? UUID(),
            startDate: currentSession?.startDate ?? Date(),
            coughSampleCount: coughSamples.count,
            vowelSampleCount: vowelSamples.count
        )
        appPhase = .analyzing

        do {
            let features = try await analysisActor.analyse(
                cough: coughSamples,
                vowel: vowelSamples
            )
            let result = try inferenceEngine.run(features)
            try? resultsStore.save(result)
            await healthKit.save(result)
            diagnosticResult = result
            appPhase = .results(result)
        } catch {
            errorMessage = error.localizedDescription
            appPhase = .idle
        }
    }

    /// Resets the view model back to the idle state for a new assessment.
    func resetToIdle() {
        appPhase = .idle
        diagnosticResult = nil
        waveformSamples = []
        errorMessage = nil
        vowelTimeRemaining = 10.0
        currentSession = nil
    }

    // MARK: - Private: Vowel Timer

    private func startVowelTimer() {
        vowelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.vowelTimeRemaining = max(0, self.vowelTimeRemaining - 0.1)
                if self.vowelTimeRemaining <= 0 {
                    self.vowelTimer?.invalidate()
                    self.vowelTimer = nil
                    await self.finishAssessment()
                }
            }
        }
    }
}
