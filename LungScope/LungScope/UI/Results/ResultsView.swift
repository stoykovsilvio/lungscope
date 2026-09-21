import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel
    @EnvironmentObject private var store: ResultsStore
    let result: DiagnosticResult

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Assessment Complete")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 48)

                Text(result.timestamp, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VerdictCardView(verdict: VerdictGenerator.generate(from: result))
                    .padding(.horizontal, 24)

                ScoreGaugeView(
                    title: "Airway Constriction Index",
                    value: result.airwayConstrictionIndex,
                    lowLabel: "Normal",
                    midLabel: "Mildly Elevated",
                    highLabel: "Elevated",
                    // For ACI, lower is better — invert colour direction.
                    invertColour: true
                )

                ScoreGaugeView(
                    title: "Vocal Harmony Stability",
                    value: result.vocalHarmonyStabilityScore,
                    lowLabel: "Irregular",
                    midLabel: "Mildly Irregular",
                    highLabel: "Stable",
                    invertColour: false
                )

                TrendBannerView(trend: store.trend)
                    .padding(.horizontal, 32)

                Text("For personal wellness tracking only. Not a medical diagnostic device.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    viewModel.resetToIdle()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Verdict Card

private struct VerdictCardView: View {
    let verdict: Verdict

    private var accent: Color {
        switch verdict.severity {
        case .good:    return .teal
        case .caution: return .orange
        case .concern: return .red
        }
    }

    private var icon: String {
        switch verdict.severity {
        case .good:    return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .concern: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accent)
                Text(verdict.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            Text(verdict.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Score Gauge

private struct ScoreGaugeView: View {
    let title: String
    let value: Float
    let lowLabel: String
    let midLabel: String
    let highLabel: String
    let invertColour: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 20)

                RoundedRectangle(cornerRadius: 8)
                    .fill(gaugeColor)
                    .frame(width: max(20, CGFloat(value) * UIScreen.main.bounds.width * 0.75),
                           height: 20)
                    .animation(.easeOut(duration: 0.6), value: value)
            }
            .padding(.horizontal, 32)

            Text("\(Int(value * 100))%  —  \(bandLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var gaugeColor: Color {
        let pct = Double(value)
        if invertColour {
            return pct < 0.31 ? .teal : pct < 0.61 ? .orange : .red
        } else {
            return pct > 0.65 ? .teal : pct > 0.40 ? .orange : .red
        }
    }

    private var bandLabel: String {
        let pct = Double(value)
        if invertColour {
            if pct < 0.31 { return lowLabel }
            if pct < 0.61 { return midLabel }
            return highLabel
        } else {
            if pct > 0.65 { return highLabel }
            if pct > 0.40 { return midLabel }
            return lowLabel
        }
    }
}
