import Foundation

struct DiagnosticResult: Identifiable, Codable, Equatable {

    let id: UUID
    let timestamp: Date

    // Both scores are guaranteed [0, 1] — precondition fires in debug builds.
    let airwayConstrictionIndex: Float
    let vocalHarmonyStabilityScore: Float

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        airwayConstrictionIndex: Float,
        vocalHarmonyStabilityScore: Float
    ) {
        precondition((0.0...1.0).contains(airwayConstrictionIndex),
                     "DiagnosticResult: airwayConstrictionIndex \(airwayConstrictionIndex) out of [0, 1].")
        precondition((0.0...1.0).contains(vocalHarmonyStabilityScore),
                     "DiagnosticResult: vocalHarmonyStabilityScore \(vocalHarmonyStabilityScore) out of [0, 1].")
        self.id = id
        self.timestamp = timestamp
        self.airwayConstrictionIndex = airwayConstrictionIndex
        self.vocalHarmonyStabilityScore = vocalHarmonyStabilityScore
    }
}
