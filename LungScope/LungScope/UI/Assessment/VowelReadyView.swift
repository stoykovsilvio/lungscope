import SwiftUI

struct VowelReadyView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lungs.fill")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.teal)

            VStack(spacing: 10) {
                Text("Great job!")
                    .font(.title2.weight(.semibold))

                Text("Take a moment to catch your breath.\n\nWhen you're ready, tap the button below to begin the 10-second vocal phase. Sustain an open \"Ahhh\" for as long as the timer runs.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                viewModel.startVowelRecording()
            } label: {
                Text("Begin Vocal Phase")
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
