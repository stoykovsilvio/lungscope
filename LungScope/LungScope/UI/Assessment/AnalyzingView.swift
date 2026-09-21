import SwiftUI

struct AnalyzingView: View {
    @State private var statusText = "Analysing your recording…"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { statusText = "Running inference…" }
        }
    }
}
