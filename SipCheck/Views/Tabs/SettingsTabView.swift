import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var journalStore: JournalStore

    @AppStorage("preferredScanProvider") private var preferredScanProvider: String = "auto"
    @AppStorage("followUpNotificationsEnabled") private var followUpNotificationsEnabled: Bool = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true

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
                    Button("Reset Onboarding") {
                        showResetOnboardingAlert = true
                    }
                    .alert("Reset Onboarding?", isPresented: $showResetOnboardingAlert) {
                        Button("Reset", role: .destructive) {
                            hasCompletedOnboarding = false
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will show the intro screens next time you open the app.")
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
