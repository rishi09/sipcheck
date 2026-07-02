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
    @State private var showingTasteEditor = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Scanning (debug-only: provider choice is a dev knob, not a user setting)
                #if DEBUG
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
                #endif

                // MARK: - Taste
                Section {
                    Button("Edit taste preferences") {
                        showingTasteEditor = true
                    }
                } header: {
                    Text("Taste")
                } footer: {
                    Text("Retake the quick quiz — verdicts follow your answers.")
                }

                // MARK: - Notifications
                Section {
                    Toggle(isOn: $followUpNotificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow-up reminders")
                            Text("We'll check in a day or two after you save one")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Notifications")
                }

                // MARK: - Export
                Section {
                    Button {
                        exportAsCSV()
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Export my data")
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
                    .foregroundColor(SipColors.destructive)
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
            .sheet(isPresented: $showingTasteEditor) {
                TastePreferencesEditorView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .accessibilityIdentifier("settingsTab")
    }

    // MARK: - Export (relocated from StatsView; WO-8 deletes the originals)

    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(drinkStore.drinks) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.json")
        try? data.write(to: tempURL)
        exportURL = tempURL
        showingExportSheet = true
    }

    private func exportAsCSV() {
        var csv = "Name,Brand,Style,Rating,ABV,Type,Notes,Date\n"
        for drink in drinkStore.drinks {
            let name = drink.name.replacingOccurrences(of: ",", with: ";")
            let brand = drink.brand.replacingOccurrences(of: ",", with: ";")
            let notes = (drink.notes ?? "").replacingOccurrences(of: ",", with: ";")
            let abv = drink.abv.map { String(format: "%.1f", $0) } ?? ""
            let date = drink.dateAdded.formatted(.iso8601)
            csv += "\(name),\(brand),\(drink.style),\(drink.rating.displayName),\(abv),\(drink.drinkType.displayName),\(notes),\(date)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sipcheck-export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = tempURL
        showingExportSheet = true
    }
}

// MARK: - Taste Preferences Editor
// Deep-links to the taste quiz *content* only — no age-gate or onboarding reset.
// (OnboardingView's TasteQuizPage is file-private, so the quiz layout is
// mirrored here against the same TastePreferences store; the option strings
// themselves are single-sourced from TastePreferences.)

private struct TastePreferencesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    // Single-sourced from TastePreferences — must be the exact strings the
    // onboarding quiz offers, since both write the same saved-answer keys.
    private let vibeOptions = TastePreferences.vibeOptions
    private let adventureOptions = TastePreferences.adventureOptions
    private let dislikeOptions = TastePreferences.dislikeOptions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Same 10-second quiz — change anything, verdicts update instantly.")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                        .padding(.top, SipSpacing.s)

                    quizQuestion(
                        question: "Pick your vibe",
                        options: vibeOptions
                    ) { option in
                        selectedVibe == option
                    } onTap: { option in
                        selectedVibe = option
                    }

                    quizQuestion(
                        question: "How adventurous?",
                        options: adventureOptions
                    ) { option in
                        selectedAdventure == option
                    } onTap: { option in
                        selectedAdventure = option
                    }

                    quizQuestion(
                        question: "Anything you hate?",
                        questionSuffix: "(optional)",
                        options: dislikeOptions
                    ) { option in
                        selectedDislikes.contains(option)
                    } onTap: { option in
                        if selectedDislikes.contains(option) {
                            selectedDislikes.remove(option)
                        } else {
                            selectedDislikes.insert(option)
                        }
                    }

                    Button(action: { dismiss() }) {
                        Text("Done")
                    }
                    .buttonStyle(SipPrimaryButtonStyle())
                    .padding(.top, SipSpacing.s)
                    .padding(.bottom, SipSpacing.xl)
                }
                .padding(.horizontal, SipSpacing.xl)
            }
            .background(SipColors.background.ignoresSafeArea())
            .navigationTitle("Taste Preferences")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            restoreSavedAnswers()
        }
        .onChange(of: selectedVibe) { _, _ in persistAnswers() }
        .onChange(of: selectedAdventure) { _, _ in persistAnswers() }
        .onChange(of: selectedDislikes) { _, _ in persistAnswers() }
    }

    private func quizQuestion(
        question: String,
        questionSuffix: String? = nil,
        options: [String],
        isSelected: @escaping (String) -> Bool,
        onTap: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            HStack(spacing: SipSpacing.xs) {
                Text(question)
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                if let suffix = questionSuffix {
                    Text(suffix)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: SipSpacing.s)],
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(options, id: \.self) { option in
                    Button(action: { onTap(option) }) {
                        Text(option)
                    }
                    .buttonStyle(SipChipStyle(isSelected: isSelected(option)))
                }
            }
        }
    }

    /// Mirror of the onboarding quiz's restore: start from what the user
    /// already said so opening the editor never blanks real answers.
    private func restoreSavedAnswers() {
        let saved = TastePreferences.current
        if selectedVibe == nil, !saved.vibe.isEmpty { selectedVibe = saved.vibe }
        if selectedAdventure == nil, !saved.adventure.isEmpty { selectedAdventure = saved.adventure }
        if selectedDislikes.isEmpty, !saved.dislikes.isEmpty { selectedDislikes = Set(saved.dislikes) }
    }

    /// Write-through on every selection change — same semantics as the quiz,
    /// so answers survive swiping the sheet away without tapping Done.
    private func persistAnswers() {
        TastePreferences.save(
            vibe: selectedVibe ?? "",
            adventure: selectedAdventure ?? "",
            dislikes: selectedDislikes.joined(separator: ",")
        )
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
