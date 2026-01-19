import SwiftUI

struct AddBeerView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var style: String = BeerStyle.other.rawValue
    @State private var rating: Rating = .neutral
    @State private var notes: String = ""
    @State private var drinkType: DrinkType = .regular
    @State private var capturedImage: UIImage?

    @State private var isProcessingImage = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Camera/Photo section
                Section {
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(12)

                        if isProcessingImage {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Analyzing label...")
                            }
                        }

                        Button("Retake Photo", role: .destructive) {
                            capturedImage = nil
                        }
                    } else {
                        CameraCaptureButton(capturedImage: $capturedImage)
                    }
                } header: {
                    Text("Photo (Optional)")
                }

                // Beer details section
                Section {
                    TextField("Beer Name", text: $name)
                    TextField("Brewery (Optional)", text: $brand)
                    StylePicker(selectedStyle: $style)
                    Picker("Type", selection: $drinkType) {
                        ForEach(DrinkType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } header: {
                    Text("Details")
                }

                // Rating section
                Section {
                    RatingPicker(rating: $rating)
                } header: {
                    Text("Your Rating")
                }

                // Notes section
                Section {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes (Optional)")
                }

                // Error message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBeer()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: capturedImage) { oldValue, newValue in
                if let image = newValue, oldValue == nil {
                    processImageWithAI(image)
                }
            }
        }
    }

    private func processImageWithAI(_ image: UIImage) {
        isProcessingImage = true
        errorMessage = nil

        Task {
            do {
                let result = try await OpenAIService.shared.extractBeerInfo(from: image)
                await MainActor.run {
                    if let extractedName = result.name, !extractedName.isEmpty {
                        name = extractedName
                    }
                    if let extractedBrand = result.brand, !extractedBrand.isEmpty {
                        brand = extractedBrand
                    }
                    if let extractedStyle = result.style {
                        style = extractedStyle.rawValue
                    }
                    isProcessingImage = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not read label: \(error.localizedDescription)"
                    isProcessingImage = false
                }
            }
        }
    }

    private func saveBeer() {
        let drink = Drink(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            style: style,
            rating: rating,
            type: drinkType,
            notes: notes.isEmpty ? nil : notes
        )

        drinkStore.addDrink(drink)
        dismiss()
    }
}

struct AddBeerView_Previews: PreviewProvider {
    static var previews: some View {
        AddBeerView()
            .environmentObject(DrinkStore())
    }
}
