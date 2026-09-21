import Foundation

enum TrendAlert: Equatable {
    case notEnoughData
    case stable
    case improving(delta: Float)
    case worsening(delta: Float)
}

struct TrendAnalyser {

    private static let minimumSamples = 3
    private static let windowSize     = 5
    private static let threshold: Float = 0.05

    // Analyses the last `windowSize` ACI values and returns a trend direction.
    // Needs at least `minimumSamples` to produce a meaningful result.
    static func analyse(_ results: [DiagnosticResult]) -> TrendAlert {
        let window = results
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(windowSize)
            .map(\.airwayConstrictionIndex)

        guard window.count >= minimumSamples else { return .notEnoughData }

        let delta = window.last! - window.first!

        if delta >  threshold { return .worsening(delta: delta) }
        if delta < -threshold { return .improving(delta: abs(delta)) }
        return .stable
    }
}
