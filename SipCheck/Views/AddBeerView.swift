import SwiftUI

/// Pre-populated data for AddBeerView, typically sourced from a prior scan.
/// Identifiable so presenters can use sheet(item:) — the isPresented + if-let
/// pattern raced state writes and presented blank sheets.
struct AddBeerPrefill: Identifiable {
    let id = UUID()
    var name: String = ""
    var brand: String = ""
    var style: String = BeerStyle.other.rawValue
    var abv: Double? = nil
    /// The in-memory frame is used for the immediate scan -> log transition.
    /// `photoFileName` covers later entry from Want to Try / notifications.
    var capturedImage: UIImage? = nil
    var photoFileName: String? = nil
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
    @State private var isRestoringPhoto = false

    init(prefill: AddBeerPrefill? = nil) {
        self.prefill = prefill
        _capturedImage = State(initialValue: prefill?.capturedImage)
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
                            .clipShape(RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous))

                        if isProcessingImage {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, SipSpacing.s)
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
                .listRowBackground(SipColors.surface)

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
                .listRowBackground(SipColors.surface)

                // Rating section
                Section {
                    RatingPicker(rating: $rating)
                } header: {
                    Text("Your Rating")
                }
                .listRowBackground(SipColors.surface)

                // Notes section
                Section {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes (Optional)")
                }
                .listRowBackground(SipColors.surface)

                // Error message
                if errorMessage != nil {
                    Section {
                        VStack(alignment: .leading, spacing: SipSpacing.xs) {
                            Text("Couldn't read the label — fill in what you know.")
                                .foregroundColor(SipColors.destructive)
                                .font(SipTypography.subhead)
                        }
                    }
                    .listRowBackground(SipColors.surface)
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
                    if isRestoringPhoto {
                        isRestoringPhoto = false
                    } else {
                        processImage(image)
                    }
                }
            }
            .onAppear {
                if let prefill = prefill {
                    if !prefill.name.isEmpty { name = prefill.name }
                    if !prefill.brand.isEmpty { brand = prefill.brand }
                    if prefill.style != BeerStyle.other.rawValue { style = prefill.style }
                    if let abv = prefill.abv { abvText = String(format: "%.1f", abv) }
                    restorePersistedPhotoIfNeeded(prefill)
                }
            }
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessingImage = true
        errorMessage = nil

        Task {
            let ocr = await VisionOCRService.extractText(from: image)
            let text = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                await MainActor.run {
                    errorMessage = "Could not read the label."
                    isProcessingImage = false
                }
                return
            }

            // Populate from OCR + the bundled catalog immediately. Logging a
            // beer must never wait for a remote verdict request.
            let resolved = BeerResolver.resolve(recognizedText: text, using: BundledCatalog.shared)
            let firstLine = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? text
            let resolvedName = resolved.confidence != nil ? resolved.name : firstLine

            await MainActor.run {
                if name.isEmpty { name = String(resolvedName.prefix(80)) }
                if brand.isEmpty, let brewery = resolved.brewery { brand = brewery }
                if style == BeerStyle.other.rawValue, let foundStyle = resolved.style {
                    style = foundStyle.rawValue
                }
                if abvText.isEmpty, let foundABV = resolved.abv {
                    abvText = String(format: "%.1f", foundABV)
                }
                isProcessingImage = false
            }

            // Optional bounded refinement fills remaining blanks in place.
            guard ScanningPipeline.shared.canEnrich,
                  BeerResolver.shouldEnrich(resolved),
                  let enrichment = await ScanningPipeline.shared.enrich(
                    text: text,
                    image: image,
                    deviceVerdict: .yourCall
                  ) else { return }

            await MainActor.run {
                if name == resolvedName, let betterName = enrichment.name { name = betterName }
                if brand.isEmpty, let betterBrand = enrichment.brand { brand = betterBrand }
                if style == BeerStyle.other.rawValue, let betterStyle = enrichment.style {
                    style = betterStyle.rawValue
                }
                if abvText.isEmpty, let betterABV = enrichment.abv {
                    abvText = String(format: "%.1f", betterABV)
                }
            }
        }
    }

    private func restorePersistedPhotoIfNeeded(_ prefill: AddBeerPrefill) {
        guard capturedImage == nil, let fileName = prefill.photoFileName else { return }
        isRestoringPhoto = true
        Task {
            let image = await drinkStore.loadPhotoAsync(named: fileName)
            await MainActor.run {
                capturedImage = image
                if image == nil { isRestoringPhoto = false }
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
