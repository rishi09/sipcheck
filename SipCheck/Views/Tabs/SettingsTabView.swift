import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var journalStore: JournalStore

    @Environment(\.dismiss) private var dismiss

    @AppStorage("preferredScanProvider") private var preferredScanProvider: String = "auto"
    @AppStorage("followUpNotificationsEnabled") private var followUpNotificationsEnabled: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true
    @AppStorage("hasConfirmedAge") private var hasConfirmedAge: Bool = true

    @State private var showResetOnboardingAlert = false
    @State private var showClearDataAlert = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Scanning
                Section {
                    Picker("AI Provider", selection: $preferredScanProvider) {
                        Text("Auto (Recommended)").tag("auto")
                        Text("OpenAI Vision only").tag("openai")
                    }
                    Text("Auto uses fast text recognition first, falling back to AI vision.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Scanning")
                }

                // MARK: - Notifications
                Section {
                    Toggle(isOn: $followUpNotificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow-up reminders")
                            Text("We'll ask a few hours after you scan")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Remind me to log beers I want to try")
                }

                // MARK: - Account / Data
                Section {
                    Button("Replay Onboarding") {
                        showResetOnboardingAlert = true
                    }
                    .alert("Replay Onboarding?", isPresented: $showResetOnboardingAlert) {
                        Button("Replay", role: .destructive) {
                            // Dismiss this sheet first; if we flip the flags while the
                            // sheet is up, the RootView swap happens underneath it and
                            // never becomes visible. Flip them after dismissal settles.
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                hasConfirmedAge = false
                                hasCompletedOnboarding = false
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Takes you back through the age gate and intro screens right now.")
                    }

                    Button("Clear All Data") {
                        showClearDataAlert = true
                    }
                    .foregroundColor(.red)
                    .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                        Button("Delete Everything", role: .destructive) {
                            let allIndices = IndexSet(drinkStore.drinks.indices)
                            drinkStore.deleteDrinks(at: allIndices, from: drinkStore.drinks)
                            scanStore.deleteAllScans()
                            journalStore.deleteAllEntries()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all your beers and scans. This cannot be undone.")
                    }
                    // Available in TestFlight builds too so testers can populate
                    // sample data (which then syncs to iCloud). Remove before the
                    // public App Store release.
                    Button("Seed Sample Data") {
                        drinkStore.seedSampleData()
                        scanStore.seedSampleData()
                        journalStore.seedSampleData()
                    }
                } header: {
                    Text("Account / Data")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    Link("Privacy Policy", destination: URL(string: "https://rishi09.github.io/sipcheck/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://rishi09.github.io/sipcheck/terms")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
        .accessibilityIdentifier("settingsTab")
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(DrinkStore())
            .environmentObject(ScanStore())
            .environmentObject(JournalStore())
    }
}
