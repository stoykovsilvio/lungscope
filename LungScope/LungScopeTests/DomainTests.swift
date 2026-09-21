import Testing
import Foundation
@testable import LungScope

// MARK: - DiagnosticResult

struct DiagnosticResultTests {

    @Test func codableRoundTrip() throws {
        let original = DiagnosticResult(airwayConstrictionIndex: 0.42,
                                        vocalHarmonyStabilityScore: 0.71)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DiagnosticResult.self, from: data)
        #expect(decoded == original)
    }

    @Test func floatPrecision() throws {
        let original = DiagnosticResult(airwayConstrictionIndex: 0.123456789,
                                        vocalHarmonyStabilityScore: 0.987654321)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DiagnosticResult.self, from: data)
        #expect(abs(decoded.airwayConstrictionIndex - original.airwayConstrictionIndex) < 1e-6)
        #expect(abs(decoded.vocalHarmonyStabilityScore - original.vocalHarmonyStabilityScore) < 1e-6)
    }

    @Test func distinctUUIDsAreNotEqual() {
        let a = DiagnosticResult(airwayConstrictionIndex: 0.5, vocalHarmonyStabilityScore: 0.5)
        let b = DiagnosticResult(airwayConstrictionIndex: 0.5, vocalHarmonyStabilityScore: 0.5)
        #expect(a != b)
    }

    @Test func boundaryValuesAreValid() {
        let lo = DiagnosticResult(airwayConstrictionIndex: 0.0, vocalHarmonyStabilityScore: 0.0)
        let hi = DiagnosticResult(airwayConstrictionIndex: 1.0, vocalHarmonyStabilityScore: 1.0)
        #expect(lo.airwayConstrictionIndex == 0.0)
        #expect(hi.vocalHarmonyStabilityScore == 1.0)
    }
}

// MARK: - AssessmentSession

struct AssessmentSessionTests {

    @Test func codableRoundTrip() throws {
        let session = AssessmentSession(coughSampleCount: 80_000, vowelSampleCount: 160_000)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(AssessmentSession.self, from: data)
        #expect(decoded == session)
    }

    @Test func expectedWindowSizes() {
        #expect(AudioFormat.coughWindowSamples == 80_000)
        #expect(AudioFormat.vowelWindowSamples == 160_000)
    }
}

// MARK: - AppPhase

struct AppPhaseTests {

    @Test func idleIsIdle() {
        let phase = AppPhase.idle
        #expect(phase == .idle)
    }

    @Test func resultsCaseEqualityMatchesDiagnosticResult() {
        let r = DiagnosticResult(airwayConstrictionIndex: 0.3, vocalHarmonyStabilityScore: 0.7)
        #expect(AppPhase.results(r) == .results(r))
    }

    @Test func resultsCaseInequalityWithDifferentUUID() {
        let a = DiagnosticResult(airwayConstrictionIndex: 0.3, vocalHarmonyStabilityScore: 0.7)
        let b = DiagnosticResult(airwayConstrictionIndex: 0.3, vocalHarmonyStabilityScore: 0.7)
        #expect(AppPhase.results(a) != .results(b))
    }

    @Test func distinctCasesAreNotEqual() {
        #expect(AppPhase.idle != .coughRecording)
        #expect(AppPhase.coughRecording != .vowelRecording)
        #expect(AppPhase.vowelRecording != .analyzing)
    }
}
