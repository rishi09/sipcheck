import SwiftUI

/// Detail/edit sheet for a logged beer — opened by tapping a row in the
/// Journal. Rating and notes are editable; the entry can be deleted.
struct JournalEntryDetailView: View {
    @EnvironmentObject private var journalStore: JournalStore
    @Environment(\.dismiss) private var dismiss

    let entry: JournalEntry
    @State private var rating: Int
    @State private var notes: String
    @State private var showingDeleteConfirm = false

    init(entry: JournalEntry) {
        self.entry = entry
        _rating = State(initialValue: entry.rating)
        _notes = State(initialValue: entry.notes ?? "")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: entry.dateTried ?? entry.dateLogged)
    }

    private var metadata: String {
        var parts: [String] = []
        if !entry.style.isEmpty { parts.append(entry.style) }
        if let abv = entry.abv { parts.append(String(format: "%.1f%% ABV", abv)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SipColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(SipColors.surface)
                                    .frame(width: 72, height: 72)
                                Image(systemName: "mug.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(SipColors.primary)
                            }
                            .padding(.bottom, 6)

                            Text(entry.beerName)
                                .font(SipTypography.title)
                                .foregroundColor(SipColors.textPrimary)
                                .multilineTextAlignment(.center)

                            if !entry.brand.isEmpty {
                                Text(entry.brand)
                                    .font(SipTypography.subhead)
                                    .foregroundColor(SipColors.textSecondary)
                            }

                            if !metadata.isEmpty {
                                Text(metadata)
                                    .font(SipTypography.caption)
                                    .foregroundColor(SipColors.textSecondary)
                            }

                            Text("Tried \(formattedDate)")
                                .font(SipTypography.caption)
                                .foregroundColor(SipColors.textSecondary)
                        }
                        .padding(.top, 8)

                        // Editable star rating
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 28))
                                        .foregroundColor(star <= rating ? SipColors.starFilled : SipColors.starEmpty)
                                }
                                .accessibilityIdentifier("detailStar_\(star)")
                            }
                        }

                        // Editable notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(SipTypography.subhead)
                                .foregroundColor(SipColors.textSecondary)
                            TextField("What did you think?", text: $notes, axis: .vertical)
                                .lineLimit(3...8)
                                .font(SipTypography.body)
                                .foregroundColor(SipColors.textPrimary)
                                .padding(12)
                                .background(SipColors.surface)
                                .cornerRadius(12)
                                .accessibilityIdentifier("detailNotes")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Delete
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Text("Delete from Journal")
                                .font(SipTypography.headline)
                                .foregroundColor(SipColors.destructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(SipColors.destructive, lineWidth: 1.5)
                                )
                        }
                        .accessibilityIdentifier("detailDelete")
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Beer Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = entry
                        updated.rating = rating
                        updated.notes = notes.isEmpty ? nil : notes
                        journalStore.updateEntry(updated)
                        dismiss()
                    }
                    .disabled(rating == entry.rating && notes == (entry.notes ?? ""))
                }
            }
            .confirmationDialog(
                "Delete \(entry.beerName)?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    journalStore.deleteEntry(entry)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct JournalEntryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        JournalEntryDetailView(entry: JournalEntry(
            beerName: "Guinness Draught",
            brand: "Guinness",
            style: "Stout",
            abv: 4.2,
            rating: 4,
            notes: "Smooth, creamy."
        ))
        .environmentObject(JournalStore(
            storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-journal-detail"),
            useSeedData: false
        ))
    }
}
