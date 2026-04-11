import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            onboardingPage(
                icon: "mug.fill",
                title: "Never Waste a Sip Again",
                description: "Stood in the beer aisle not sure what to grab? SipCheck tells you in seconds.",
                tag: 0
            )
            onboardingPage(
                icon: "camera.fill",
                title: "Scan a Label, Get a Verdict",
                description: "TRY IT. SKIP IT. YOUR CALL. — based on what you like, not what beer nerds think.",
                tag: 1
            )
            onboardingPage(
                icon: "sparkles",
                title: "The More You Log, the Better It Gets",
                description: "Every beer you rate teaches SipCheck your taste. Recommendations get sharper every week.",
                tag: 2
            )
            beerPickerPage(tag: 3)
            tasteQuizPage(tag: 4)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func onboardingPage(icon: String, title: String, description: String, tag: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .tag(tag)
    }

    private func beerPickerPage(tag: Int) -> some View {
        BeerPickerPage(tag: tag, currentPage: $currentPage)
    }

    private func tasteQuizPage(tag: Int) -> some View {
        TasteQuizPage(tag: tag, hasCompletedOnboarding: $hasCompletedOnboarding)
    }
}

// MARK: - Beer Picker Page

private struct BeerPickerPage: View {
    let tag: Int
    @Binding var currentPage: Int

    @State private var selectedBeers: Set<String> = []
    @State private var showCoronaEgg = false

    private let beerOptions = [
        "Modelo", "Corona", "Heineken", "Blue Moon",
        "Sam Adams", "Guinness", "Sierra Nevada", "Lagunitas",
        "Hazy Little Thing", "Coors Light", "Bud Light", "Stella Artois",
        "Allagash White", "Dogfish Head", "Stone IPA", "Goose Island"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beers you've had before?")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Tap any you've tried. We'll use it to calibrate your taste.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)

                    // Beer chip grid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(beerOptions, id: \.self) { beer in
                            ChipButton(
                                label: beer,
                                isSelected: selectedBeers.contains(beer)
                            ) {
                                toggleBeer(beer)
                            }
                        }
                    }

                    // Spacer so content clears the fixed buttons
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 24)
            }

            // Fixed bottom area: toast + CTA + Skip
            VStack(spacing: 0) {
                // Corona easter egg toast
                if showCoronaEgg {
                    HStack(spacing: 10) {
                        Text("🏎️")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\"One quarter mile at a time.\"")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(SipColors.textPrimary)
                            Text("— Dominic Toretto")
                                .font(.caption)
                                .foregroundColor(SipColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SipColors.surface)
                            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 20)),
                            removal: .opacity.combined(with: .offset(y: 20))
                        )
                    )
                }

                // CTA
                VStack(spacing: 10) {
                    Button(action: advance) {
                        Text("Next →")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }

                    Button(action: advance) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .background(
                    // Subtle gradient to blend with scroll content
                    LinearGradient(
                        gradient: Gradient(colors: [Color(UIColor.systemBackground).opacity(0), Color(UIColor.systemBackground)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .tag(tag)
    }

    private func toggleBeer(_ beer: String) {
        let wasSelected = selectedBeers.contains(beer)
        if wasSelected {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
            if beer == "Corona" {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCoronaEgg = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showCoronaEgg = false
                    }
                }
            }
        }
    }

    private func advance() {
        let joined = selectedBeers.sorted().joined(separator: ",")
        UserDefaults.standard.set(joined, forKey: "knownBeers")
        withAnimation {
            currentPage = 4
        }
    }
}

// MARK: - Taste Quiz Page

private struct TasteQuizPage: View {
    let tag: Int
    @Binding var hasCompletedOnboarding: Bool

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    private let vibeOptions = ["Crisp & Light", "Hoppy & Bitter", "Dark & Roasty", "Fruity & Easy", "Sour & Weird"]
    private let adventureOptions = ["Stick to Favorites", "Mix It Up", "Give Me the Weird Stuff"]
    private let dislikeOptions = ["Super Bitter", "Very Dark", "Really Sour", "Wheat-y / Cloudy"]

    private var hasRequiredSelections: Bool {
        selectedVibe != nil && selectedAdventure != nil
    }

    private var ctaLabel: String {
        hasRequiredSelections ? "See My First Picks" : "Skip for now"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick — what do you like?")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Takes 10 seconds. Makes recommendations way better.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)

                // Q1: Vibe
                QuizQuestion(
                    question: "Pick your vibe",
                    options: vibeOptions,
                    multiSelect: false,
                    selectedSingle: $selectedVibe,
                    selectedMulti: .constant([])
                )

                // Q2: Adventure
                QuizQuestion(
                    question: "How adventurous?",
                    options: adventureOptions,
                    multiSelect: false,
                    selectedSingle: $selectedAdventure,
                    selectedMulti: .constant([])
                )

                // Q3: Dislikes (optional)
                QuizQuestion(
                    question: "Anything you hate?",
                    questionSuffix: "(optional)",
                    options: dislikeOptions,
                    multiSelect: true,
                    selectedSingle: .constant(nil),
                    selectedMulti: $selectedDislikes
                )

                // CTA
                Button(action: saveAndContinue) {
                    Text(ctaLabel)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(14)
                }
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 24)
        }
        .tag(tag)
    }

    private func saveAndContinue() {
        UserDefaults.standard.set(selectedVibe ?? "", forKey: "tasteVibe")
        UserDefaults.standard.set(selectedAdventure ?? "", forKey: "tasteAdventure")
        UserDefaults.standard.set(selectedDislikes.joined(separator: ","), forKey: "tasteDislikes")
        hasCompletedOnboarding = true
    }
}

// MARK: - Quiz Question

private struct QuizQuestion: View {
    let question: String
    var questionSuffix: String? = nil
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(question)
                    .font(.headline)
                if let suffix = questionSuffix {
                    Text(suffix)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            ChipGrid(
                options: options,
                multiSelect: multiSelect,
                selectedSingle: $selectedSingle,
                selectedMulti: $selectedMulti
            )
        }
    }
}

// MARK: - Chip Grid

private struct ChipGrid: View {
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(options, id: \.self) { option in
                ChipButton(
                    label: option,
                    isSelected: multiSelect
                        ? selectedMulti.contains(option)
                        : selectedSingle == option
                ) {
                    if multiSelect {
                        if selectedMulti.contains(option) {
                            selectedMulti.remove(option)
                        } else {
                            selectedMulti.insert(option)
                        }
                    } else {
                        selectedSingle = option
                    }
                }
            }
        }
    }
}

// MARK: - Chip Button

private struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
