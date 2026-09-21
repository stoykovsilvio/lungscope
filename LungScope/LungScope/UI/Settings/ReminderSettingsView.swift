import SwiftUI

struct ReminderSettingsView: View {
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour   = 8
    @AppStorage("reminderMinute")  private var reminderMinute = 0

    @Environment(\.dismiss) private var dismiss

    @State private var reminderTime: Date = {
        var c = DateComponents()
        c.hour   = UserDefaults.standard.integer(forKey: "reminderHour").nonZero ?? 8
        c.minute = UserDefaults.standard.integer(forKey: "reminderMinute")
        return Calendar.current.date(from: c) ?? Date()
    }()

    @State private var showDeniedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily Reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time",
                                   selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Text("You'll receive a daily notification at your chosen time to complete your morning respiratory assessment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await save() } }
                }
            }
            .alert("Notifications Disabled", isPresented: $showDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { reminderEnabled = false }
            } message: {
                Text("Allow notifications for LungScope in Settings to receive daily reminders.")
            }
        }
    }

    private func save() async {
        if reminderEnabled {
            let granted = await NotificationManager.shared.requestAuthorization()
            guard granted else {
                showDeniedAlert = true
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            reminderHour   = components.hour   ?? 8
            reminderMinute = components.minute ?? 0
            NotificationManager.shared.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
        } else {
            NotificationManager.shared.cancelReminder()
        }
        dismiss()
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
