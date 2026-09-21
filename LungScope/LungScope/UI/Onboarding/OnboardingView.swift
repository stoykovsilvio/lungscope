import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "lungs.fill",
            iconColor: .teal,
            title: "Welcome to LungScope",
            body: "A daily 30-second respiratory check, entirely on your device.\n\nNo audio is uploaded. No data ever leaves your phone."
        ),
        OnboardingPage(
            icon: "mic.circle.fill",
            iconColor: .teal,
            title: "How to perform the assessment",
            body: "Find a quiet room and hold your iPhone 30–40 cm from your mouth.\n\nYou will be asked to perform 3 forced coughs, followed by a sustained \"Ahhh\" vowel for 10 seconds.\n\nBreathe normally between steps."
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: .teal,
            title: "Understanding your scores",
            body: "The Airway Constriction Index (ACI) measures airway resistance — lower is healthier.\n\nThe Vocal Harmony Stability Score (VHSS) measures vocal consistency — higher is healthier.\n\nLungScope is a personal wellness tool. It is not a medical device and cannot diagnose any condition."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            actionButton
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .padding(.top, 16)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Page

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(page.iconColor)

            Text(page.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Button

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    private var actionButton: some View {
        Button {
            if isLastPage {
                hasSeenOnboarding = true
            } else {
                withAnimation { currentPage += 1 }
            }
        } label: {
            Text(isLastPage ? "Get Started" : "Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}
