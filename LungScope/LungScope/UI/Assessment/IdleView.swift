import SwiftUI

struct IdleView: View {
    @EnvironmentObject private var viewModel: AssessmentViewModel
    @State private var showingDashboard = false
    @State private var showingReminder  = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.teal)

            VStack(spacing: 8) {
                Text("LungScope")
                    .font(.largeTitle.weight(.semibold))
                Text("30-second morning respiratory check")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Cough three times, then sustain an 'Ahhh' for 10 seconds.\nAll analysis happens on-device. No audio ever leaves your phone.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    Task { await viewModel.startAssessment() }
                } label: {
                    Text("Begin Assessment")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showingDashboard = true
                } label: {
                    Label("View History", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.teal.opacity(0.1))
                        .foregroundStyle(.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    showingReminder = true
                } label: {
                    Label("Set Daily Reminder", systemImage: "bell")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.teal.opacity(0.1))
                        .foregroundStyle(.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $showingDashboard) {
            DashboardView()
                .environmentObject(viewModel.resultsStore)
        }
        .sheet(isPresented: $showingReminder) {
            ReminderSettingsView()
        }
        .alert("Microphone Access Required",
               isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { } }
               )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
