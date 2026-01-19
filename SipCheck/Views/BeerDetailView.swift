import SwiftUI

struct BeerDetailView: View {
    @EnvironmentObject private var drinkStore: DrinkStore
    @Environment(\.dismiss) private var dismiss

    let drink: Drink

    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false

    // Edit state
    @State private var editedName: String = ""
    @State private var editedBrand: String = ""
    @State private var editedStyle: String = ""
    @State private var editedRating: Rating = .neutral
    @State private var editedType: DrinkType = .regular
    @State private var editedNotes: String = ""

    var body: some View {
        Form {
            // Details section
            Section {
                if isEditing {
                    TextField("Name", text: $editedName)
                    TextField("Brewery", text: $editedBrand)
                    StylePicker(selectedStyle: $editedStyle)
                    Picker("Type", selection: $editedType) {
                        ForEach(DrinkType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } else {
                    LabeledContent("Name", value: drink.name)
                    if !drink.brand.isEmpty {
                        LabeledContent("Brewery", value: drink.brand)
                    }
                    LabeledContent("Style", value: drink.style)
                    LabeledContent("Type", value: drink.drinkType.displayName)
                }
            } header: {
                Text("Details")
            }

            // Rating section
            Section {
                if isEditing {
                    RatingPicker(rating: $editedRating)
                } else {
                    HStack {
                        Text("Your Rating")
                        Spacer()
                        Text("\(drink.rating.emoji) \(drink.rating.displayName)")
                    }
                }
            } header: {
                Text("Rating")
            }

            // Notes section
            Section {
                if isEditing {
                    TextField("Notes", text: $editedNotes, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    if let notes = drink.notes, !notes.isEmpty {
                        Text(notes)
                    } else {
                        Text("No notes")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            } header: {
                Text("Notes")
            }

            // Metadata section
            Section {
                LabeledContent("Added", value: drink.dateAdded.formatted(date: .abbreviated, time: .shortened))
            }

            // Delete section
            if isEditing {
                Section {
                    Button("Delete Beer", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(drink.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        enterEditMode()
                    }
                    isEditing.toggle()
                }
            }
        }
        .confirmationDialog("Delete Beer?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                drinkStore.deleteDrink(drink)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func enterEditMode() {
        editedName = drink.name
        editedBrand = drink.brand
        editedStyle = drink.style
        editedRating = drink.rating
        editedType = drink.drinkType
        editedNotes = drink.notes ?? ""
    }

    private func saveChanges() {
        var updatedDrink = drink
        updatedDrink.name = editedName
        updatedDrink.brand = editedBrand
        updatedDrink.style = editedStyle
        updatedDrink.rating = editedRating
        updatedDrink.drinkType = editedType
        updatedDrink.notes = editedNotes.isEmpty ? nil : editedNotes
        drinkStore.updateDrink(updatedDrink)
    }
}

struct BeerDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BeerDetailView(drink: Drink.preview)
                .environmentObject(DrinkStore())
        }
    }
}
