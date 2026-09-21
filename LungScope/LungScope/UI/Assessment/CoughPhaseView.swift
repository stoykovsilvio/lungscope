import SwiftUI
import Combine

struct CoughPhaseView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Cough Phase")
                .font(.title2.weight(.semibold))
                .padding(.top, 48)

            Text("Cough forcefully three times.\nPause briefly between each cough.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            WaveformView()
                .frame(height: 120)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

            Spacer()

            Button {
                viewModel.transitionToVowelPhase()
            } label: {
                Text("Done Coughing")
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
