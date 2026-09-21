import Testing
import Foundation
@testable import LungScope

private func makeSine(frequency: Float, duration: Float, sampleRate: Float = 16_000) -> [Float] {
    let count = Int(duration * sampleRate)
    return (0..<count).map { sin(2 * .pi * frequency * Float($0) / sampleRate) }
}

// MARK: - JitterCalculator

struct JitterCalculatorTests {

    @Test func perfectPeriodsGiveZeroJitter() {
        let periods = [Float](repeating: 80.0, count: 100)
        #expect(JitterCalculator.compute(from: periods) < 0.001)
    }

    @Test func knownPerturbationMatchesExpected() {
        // Alternating 80 / 81.6 → difference = 1.6, mean ≈ 80.8 → jitter ≈ 0.0198
        var periods = [Float]()
        for i in 0..<100 { periods.append(i % 2 == 0 ? 80.0 : 81.6) }
        let jitter = JitterCalculator.compute(from: periods)
        #expect(abs(jitter - 0.0198) < 0.002)
    }

    @Test func singlePeriodReturnsZero() {
        #expect(JitterCalculator.compute(from: [80.0]) == 0.0)
    }

    @Test func emptyPeriodsReturnsZero() {
        #expect(JitterCalculator.compute(from: []) == 0.0)
    }
}

// MARK: - ShimmerCalculator

struct ShimmerCalculatorTests {

    @Test func constantAmplitudeGivesNearZeroShimmer() {
        let signal = makeSine(frequency: 200, duration: 10)
        let periods = [Float](repeating: 80.0, count: 150)
        let shimmer = ShimmerCalculator.compute(from: signal, periods: periods)
        #expect(shimmer < 0.01)
    }

    @Test func emptyPeriodsReturnsZero() {
        let signal = makeSine(frequency: 200, duration: 1)
        #expect(ShimmerCalculator.compute(from: signal, periods: []) == 0.0)
    }
}

// MARK: - PitchDetector

struct PitchDetectorTests {

    @Test func pureSineDetectedWithinOnePct() {
        let detector = PitchDetector()
        let signal = makeSine(frequency: 200, duration: 2)
        let periods = detector.extractPeriods(from: signal)
        #expect(!periods.isEmpty)
        let expected: Float = 16_000 / 200  // 80 samples
        let meanPeriod = periods.reduce(0, +) / Float(periods.count)
        #expect(abs(meanPeriod - expected) / expected < 0.01)
    }

    @Test func silenceReturnsEmptyPeriods() {
        let detector = PitchDetector()
        let silence = [Float](repeating: 0, count: 32_000)
        #expect(detector.extractPeriods(from: silence).isEmpty)
    }
}
