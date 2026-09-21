import SwiftUI

struct TrendBannerView: View {
    let trend: TrendAlert

    var body: some View {
        switch trend {
        case .notEnoughData, .stable:
            EmptyView()
        case .improving(let delta):
            banner(
                icon: "arrow.down.circle.fill",
                color: .teal,
                title: "Improving",
                message: "Your airway constriction has decreased by \(Int(delta * 100))% over your last few assessments."
            )
        case .worsening(let delta):
            banner(
                icon: "arrow.up.circle.fill",
                color: .orange,
                title: "Monitor closely",
                message: "Your airway constriction has increased by \(Int(delta * 100))% over your last few assessments. Consider consulting a doctor if this continues."
            )
        }
    }

    private func banner(icon: String, color: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
