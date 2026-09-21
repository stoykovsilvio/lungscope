import Testing
import CoreML
@testable import LungScope

struct FeatureVectorTests {

    private func makeVector() -> FeatureVector {
        FeatureVector(
            mfccMean:         [Float](repeating: -10.0, count: 13),
            mfccStdDev:       [Float](repeating:   2.0, count: 13),
            spectralFlatness: 0.45,
            jitter:           0.012,
            shimmer:          0.024
        )
    }

    @Test func multiArrayLengthIs29() throws {
        let array = try makeVector().toMLMultiArray()
        #expect(array.count == 29)
    }

    @Test func featureOrderIsCorrect() throws {
        let v = makeVector()
        let array = try v.toMLMultiArray()
        // Indices 0–12: mfccMean
        #expect(abs(Float(truncating: array[0])  - v.mfccMean[0])    < 1e-5)
        #expect(abs(Float(truncating: array[12]) - v.mfccMean[12])   < 1e-5)
        // Indices 13–25: mfccStdDev
        #expect(abs(Float(truncating: array[13]) - v.mfccStdDev[0])  < 1e-5)
        #expect(abs(Float(truncating: array[25]) - v.mfccStdDev[12]) < 1e-5)
        // Index 26: spectralFlatness
        #expect(abs(Float(truncating: array[26]) - v.spectralFlatness) < 1e-5)
        // Index 27: jitter
        #expect(abs(Float(truncating: array[27]) - v.jitter)           < 1e-5)
        // Index 28: shimmer
        #expect(abs(Float(truncating: array[28]) - v.shimmer)          < 1e-5)
    }

    @Test func noNaNOrInfInMultiArray() throws {
        let array = try makeVector().toMLMultiArray()
        for i in 0..<array.count {
            let v = Float(truncating: array[i])
            #expect(v.isFinite)
        }
    }
}
