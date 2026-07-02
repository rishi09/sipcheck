import SwiftUI

/// Pre-populated data for AddBeerView, typically sourced from a prior scan
struct AddBeerPrefill {
    var name: String = ""
    var style: String = BeerStyle.other.rawValue
    var abv: Double? = nil
    /// When this log originated from a scan, the scan's id so the two can be linked.
    var scanId: UUID? = nil
}

struct AddBeerView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @EnvironmentObject private var journalStore: JournalStore
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    var prefill: AddBeerPrefill?

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var style: String = BeerStyle.other.rawValue
    @State private var rating: Rating = .neutral
    @State private var notes: String = ""
    @State private var drinkType: DrinkType = .regular
    @State private var abvText: String = ""
    @State private var capturedImage: UIImage?

    @State private var isProcessingImage = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(prefill: AddBeerPrefill? = nil) {
        self.prefill = prefill
    }

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
                        .accessibilityIdentifier("beerName")
                    TextField("Brewery (Optional)", text: $brand)
                        .accessibilityIdentifier("breweryName")
                    StylePicker(selectedStyle: $style)
                    Picker("Type", selection: $drinkType) {
                        ForEach(DrinkType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("ABV % (Optional)", text: $abvText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("abvField")
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
                if errorMessage != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan failed -- fill in the details manually.")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
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
                    // The save Task keeps running after dismissal — letting
                    // Cancel fire mid-save looks like a cancel but still logs
                    // the beer a moment later.
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBeer()
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveBeer")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: capturedImage) { oldValue, newValue in
                if let image = newValue, oldValue == nil {
                    processImageWithAI(image)
                }
            }
            .onAppear {
                if let prefill = prefill {
                    if !prefill.name.isEmpty { name = prefill.name }
                    if prefill.style != BeerStyle.other.rawValue { style = prefill.style }
                    if let abv = prefill.abv { abvText = String(format: "%.1f", abv) }
                }
            }
        }
    }

    private func processImageWithAI(_ image: UIImage) {
        isProcessingImage = true
        errorMessage = nil

        Task {
            do {
                let result = try await ScanningPipeline.shared.scan(image: image)
                await MainActor.run {
                    if let extractedName = result.beerInfo.name, !extractedName.isEmpty {
                        name = extractedName
                    }
                    if let extractedBrand = result.beerInfo.brand, !extractedBrand.isEmpty {
                        brand = extractedBrand
                    }
                    if let extractedStyle = result.beerInfo.style {
                        style = extractedStyle.rawValue
                    }
                    if let extractedAbv = result.beerInfo.abv {
                        abvText = String(format: "%.1f", extractedAbv)
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
        // The async save awaits photo compression (hundreds of ms) before
        // dismissing; without this guard a double-tap created duplicate
        // Drink + JournalEntry records that skewed the taste profile.
        guard !isSaving else { return }
        isSaving = true

        let drinkId = UUID()
        let abv = Double(abvText)
        let imageCopy = capturedImage

        Task {
            var photoFileName: String?
            if let image = imageCopy {
                photoFileName = await drinkStore.savePhoto(image, for: drinkId)
            }

            let drink = Drink(
                id: drinkId,
                name: name.trimmingCharacters(in: .whitespaces),
                brand: brand.trimmingCharacters(in: .whitespaces),
                style: style,
                rating: rating,
                type: drinkType,
                notes: notes.isEmpty ? nil : notes,
                photoFileName: photoFileName,
                abv: abv
            )

            // Mirror into the journal so it appears in the Journal tab's "Tried" list
            let journalRating: Int
            switch rating {
            case .like:    journalRating = 5
            case .neutral: journalRating = 3
            case .dislike: journalRating = 1
            }
            let entry = JournalEntry(
                beerName: name.trimmingCharacters(in: .whitespaces),
                brand: brand.trimmingCharacters(in: .whitespaces),
                style: style,
                abv: abv,
                rating: journalRating,
                notes: notes.isEmpty ? nil : notes,
                photoFileName: photoFileName,
                linkedScanId: prefill?.scanId
            )

            await MainActor.run {
                drinkStore.addDrink(drink)
                journalStore.addEntry(entry)
                // If this log came from a scan, link the two and clear its
                // want-to-try flag so it leaves the Journal's Want to Try list.
                if let scanId = prefill?.scanId,
                   var scan = scanStore.scans.first(where: { $0.id == scanId }) {
                    scan.linkedJournalId = entry.id
                    scan.wantToTry = false
                    scanStore.updateScan(scan)
                }
                dismiss()
            }
        }
    }
}

struct AddBeerView_Previews: PreviewProvider {
    static var previews: some View {
        AddBeerView()
            .environmentObject(DrinkStore())
            .environmentObject(JournalStore())
            .environmentObject(ScanStore())
    }
}
