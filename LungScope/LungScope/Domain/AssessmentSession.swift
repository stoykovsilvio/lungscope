import Foundation

struct AssessmentSession: Identifiable, Codable, Equatable {

    let id: UUID
    let startDate: Date

    // Expected to be close to AudioFormat.coughWindowSamples (80_000).
    // Significantly lower signals the user stopped the cough phase early.
    let coughSampleCount: Int

    // Expected to be close to AudioFormat.vowelWindowSamples (160_000).
    let vowelSampleCount: Int

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        coughSampleCount: Int,
        vowelSampleCount: Int
    ) {
        self.id = id
        self.startDate = startDate
        self.coughSampleCount = coughSampleCount
        self.vowelSampleCount = vowelSampleCount
    }
}
