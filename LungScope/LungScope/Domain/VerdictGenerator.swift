import Foundation

enum VerdictSeverity {
    case good, caution, concern
}

struct Verdict {
    let title: String
    let detail: String
    let severity: VerdictSeverity
}

struct VerdictGenerator {

    static func generate(from result: DiagnosticResult) -> Verdict {
        let aci  = aciBand(result.airwayConstrictionIndex)
        let vhss = vhssBand(result.vocalHarmonyStabilityScore)

        switch (aci, vhss) {

        case (.normal, .stable):
            return Verdict(
                title:    "Respiratory function appears normal",
                detail:   "No significant airway constriction or vocal irregularity detected. Keep up your daily assessments to track changes over time.",
                severity: .good
            )

        case (.normal, .mild):
            return Verdict(
                title:    "Airway constriction is normal",
                detail:   "Some vocal irregularity was detected. This is often caused by dehydration, fatigue, or talking before the assessment. Try again after resting your voice.",
                severity: .caution
            )

        case (.normal, .irregular):
            return Verdict(
                title:    "Airway constriction is normal",
                detail:   "Notable vocal irregularity detected. If your voice feels strained or hoarse, allow it to rest and repeat the assessment tomorrow.",
                severity: .caution
            )

        case (.mild, .stable):
            return Verdict(
                title:    "Mild airway constriction detected",
                detail:   "Your vocal stability is good. Mild constriction can result from a dry environment or recent physical activity. Monitor over the next few days.",
                severity: .caution
            )

        case (.mild, .mild):
            return Verdict(
                title:    "Mild constriction with some vocal irregularity",
                detail:   "Both scores show mild changes. This may be an early sign of respiratory irritation. Consider repeating the assessment tomorrow morning.",
                severity: .caution
            )

        case (.mild, .irregular):
            return Verdict(
                title:    "Mild constriction with notable vocal irregularity",
                detail:   "Both your airway and vocal stability show changes. If this pattern continues over the next two to three days, consider speaking with a healthcare professional.",
                severity: .concern
            )

        case (.elevated, .stable):
            return Verdict(
                title:    "Elevated airway constriction detected",
                detail:   "Your vocal stability is good, which is a positive sign. However, elevated constriction warrants attention. If this is unusual for you, consult a healthcare professional.",
                severity: .concern
            )

        case (.elevated, .mild):
            return Verdict(
                title:    "Elevated constriction with some vocal irregularity",
                detail:   "Both your airway and vocal stability show significant changes. We recommend consulting a healthcare professional if you experience any symptoms such as shortness of breath or chest tightness.",
                severity: .concern
            )

        case (.elevated, .irregular):
            return Verdict(
                title:    "Elevated constriction and vocal irregularity detected",
                detail:   "Both scores are outside the normal range. This does not replace a clinical diagnosis, but we recommend consulting a healthcare professional, particularly if you experience breathing difficulty.",
                severity: .concern
            )
        }
    }

    // MARK: - Private

    private enum ACIBand { case normal, mild, elevated }
    private enum VHSSBand { case stable, mild, irregular }

    private static func aciBand(_ v: Float) -> ACIBand {
        if v < 0.31 { return .normal }
        if v < 0.61 { return .mild }
        return .elevated
    }

    private static func vhssBand(_ v: Float) -> VHSSBand {
        if v > 0.65 { return .stable }
        if v > 0.40 { return .mild }
        return .irregular
    }
}
