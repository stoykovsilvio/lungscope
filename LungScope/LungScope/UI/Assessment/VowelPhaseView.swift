import SwiftUI

struct VowelPhaseView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Vowel Phase")
                .font(.title2.weight(.semibold))

            Text("Say \"Ahhh\" in a steady, comfortable pitch.\nKeep going until the circle fills.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.teal, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)

                VStack(spacing: 4) {
                    Text(String(format: "%.1f", viewModel.vowelTimeRemaining))
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                    Text("seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            Spacer()
        }
    }

    private var progress: CGFloat {
        CGFloat(1.0 - viewModel.vowelTimeRemaining / 10.0)
    }
}
