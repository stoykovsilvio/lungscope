import SwiftUI

struct AssessmentCoordinatorView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        ZStack {
            switch viewModel.appPhase {
            case .idle:
                IdleView()
            case .coughRecording:
                CoughPhaseView()
            case .vowelReady:
                VowelReadyView()
            case .vowelRecording:
                VowelPhaseView()
            case .analyzing:
                AnalyzingView()
            case .results(let result):
                ResultsView(result: result)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.appPhase)
        .fullScreenCover(isPresented: .constant(!hasSeenOnboarding)) {
            OnboardingView()
        }
    }
}
