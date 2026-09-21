import Testing
import Foundation
@testable import LungScope

private func makeSine(frequency: Float, duration: Float, sampleRate: Float = 16_000) -> [Float] {
    let count = Int(duration * sampleRate)
    return (0..<count).map { sin(2 * .pi * frequency * Float($0) / sampleRate) }
}

struct AudioAnalysisActorTests {

    private let actor = AudioAnalysisActor()

    @Test func featureVectorHasCorrectShape() async throws {
        let cough = makeSine(frequency: 1_000, duration: 5)
        let vowel = makeSine(frequency: 200,   duration: 10)
        let features = try await actor.analyse(cough: cough, vowel: vowel)
        #expect(features.mfccMean.count   == 13)
        #expect(features.mfccStdDev.count == 13)
        #expect(features.spectralFlatness >= 0)
        #expect(features.spectralFlatness <= 1)
    }

    @Test func jitterIsNearZeroForPureSine() async throws {
        let cough = makeSine(frequency: 1_000, duration: 5)
        let vowel = makeSine(frequency: 200,   duration: 10)
        let features = try await actor.analyse(cough: cough, vowel: vowel)
        #expect(features.jitter < 0.05)
    }

    @Test func throwsForTruncatedCoughBuffer() async {
        let shortCough = makeSine(frequency: 1_000, duration: 1)
        let vowel      = makeSine(frequency: 200,   duration: 10)
        var didThrow = false
        do {
            _ = try await actor.analyse(cough: shortCough, vowel: vowel)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test func allFeaturesAreFinite() async throws {
        let cough = makeSine(frequency: 1_000, duration: 5)
        let vowel = makeSine(frequency: 200,   duration: 10)
        let f = try await actor.analyse(cough: cough, vowel: vowel)
        // Hoist allSatisfy outside #expect to avoid rethrows inference in macro expansion.
        let mfccMeanFinite   = f.mfccMean.allSatisfy   { $0.isFinite }
        let mfccStdDevFinite = f.mfccStdDev.allSatisfy { $0.isFinite }
        #expect(mfccMeanFinite)
        #expect(mfccStdDevFinite)
        #expect(f.spectralFlatness.isFinite)
        #expect(f.jitter.isFinite)
        #expect(f.shimmer.isFinite)
    }
}
