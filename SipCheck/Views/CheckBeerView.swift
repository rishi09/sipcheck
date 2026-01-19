import SwiftUI

struct CheckBeerView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var checkResult: CheckResult?
    @State private var errorMessage: String?

    enum CheckResult {
        case found(drink: Drink, recommendation: String)
        case notFound(name: String, recommendation: String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let result = checkResult {
                    resultView(for: result)
                } else if isProcessing {
                    processingView
                } else {
                    inputView
                }
            }
            .padding()
            .navigationTitle("Check Beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var inputView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Check if you've tried a beer")
                .font(.headline)
                .foregroundColor(.secondary)

            // Camera option
            CameraCaptureButton(capturedImage: $capturedImage)
                .padding(.horizontal)

            Text("or")
                .foregroundColor(.secondary)

            // Search option
            HStack {
                TextField("Search by name...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button("Search") {
                    searchBeer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }

            Spacer()
        }
        .onChange(of: capturedImage) { _, newValue in
            if let image = newValue {
                processImage(image)
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
            }

            ProgressView()
                .scaleEffect(1.5)

            Text("Analyzing...")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func resultView(for result: CheckResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                switch result {
                case .found(let drink, let recommendation):
                    foundView(drink: drink, recommendation: recommendation)
                case .notFound(let name, let recommendation):
                    notFoundView(name: name, recommendation: recommendation)
                }

                Button("Check Another") {
                    resetState()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func foundView(drink: Drink, recommendation: String) -> some View {
        VStack(spacing: 16) {
            // Beer name
            Text(drink.name)
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            // Status
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("You've tried this!")
            }
            .font(.headline)

            // Your rating
            VStack(spacing: 8) {
                Text("Your rating: \(drink.rating.emoji) \(drink.rating.displayName)")
                    .font(.subheadline)

                if let notes = drink.notes, !notes.isEmpty {
                    Text("Notes: \"\(notes)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Divider()

            // AI Recommendation
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Recommendation", systemImage: "sparkles")
                    .font(.headline)

                Text(recommendation)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func notFoundView(name: String, recommendation: String) -> some View {
        VStack(spacing: 16) {
            // Beer name
            Text(name)
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            // Status
            HStack {
                Image(systemName: "plus.circle")
                    .foregroundColor(.blue)
                Text("Haven't tried yet")
            }
            .font(.headline)

            Divider()

            // AI Recommendation
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Recommendation", systemImage: "sparkles")
                    .font(.headline)

                Text(recommendation)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)

            // Add button
            Button {
                addBeerFromCheck(name: name)
            } label: {
                Label("Add to my beers", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    private func searchBeer() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Check local database
                let matchedDrink = drinkStore.findMatch(for: query)

                // Get AI recommendation
                let recommendation = try await OpenAIService.shared.getRecommendation(
                    for: query,
                    existingDrink: matchedDrink,
                    drinkHistory: drinkStore.drinks
                )

                await MainActor.run {
                    if let drink = matchedDrink {
                        checkResult = .found(drink: drink, recommendation: recommendation)
                    } else {
                        checkResult = .notFound(name: query, recommendation: recommendation)
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Extract beer info from image
                let extracted = try await OpenAIService.shared.extractBeerInfo(from: image)
                let beerName = extracted.name ?? "Unknown Beer"

                // Check local database
                let matchedDrink = drinkStore.findMatch(for: beerName)

                // Get AI recommendation
                let recommendation = try await OpenAIService.shared.getRecommendation(
                    for: beerName,
                    existingDrink: matchedDrink,
                    drinkHistory: drinkStore.drinks
                )

                await MainActor.run {
                    if let drink = matchedDrink {
                        checkResult = .found(drink: drink, recommendation: recommendation)
                    } else {
                        checkResult = .notFound(name: beerName, recommendation: recommendation)
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func addBeerFromCheck(name: String) {
        let drink = Drink(name: name, rating: .neutral)
        drinkStore.addDrink(drink)
        dismiss()
    }

    private func resetState() {
        searchText = ""
        capturedImage = nil
        checkResult = nil
        errorMessage = nil
    }
}

struct CheckBeerView_Previews: PreviewProvider {
    static var previews: some View {
        CheckBeerView()
            .environmentObject(DrinkStore())
    }
}
