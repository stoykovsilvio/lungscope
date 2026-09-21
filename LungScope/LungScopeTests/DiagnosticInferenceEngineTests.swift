import Testing
@testable import LungScope

struct DiagnosticInferenceEngineTests {

    private let engine = DiagnosticInferenceEngine()

    private func makeFeatures() -> FeatureVector {
        FeatureVector(
            mfccMean:         [Float](repeating: -8.0, count: 13),
            mfccStdDev:       [Float](repeating:  1.5, count: 13),
            spectralFlatness: 0.3,
            jitter:           0.015,
            shimmer:          0.03
        )
    }

    @Test func outputScoresAreInUnitRange() throws {
        let result = try engine.run(makeFeatures())
        #expect((0.0...1.0).contains(result.airwayConstrictionIndex))
        #expect((0.0...1.0).contains(result.vocalHarmonyStabilityScore))
    }

    @Test func outputIsDeterministic() throws {
        let features = makeFeatures()
        let r1 = try engine.run(features)
        let r2 = try engine.run(features)
        #expect(r1.airwayConstrictionIndex    == r2.airwayConstrictionIndex)
        #expect(r1.vocalHarmonyStabilityScore == r2.vocalHarmonyStabilityScore)
    }
}
