import SwiftUI

/// Detail/edit sheet for a logged beer — opened by tapping a row in the
/// Journal. Rating and notes are editable; the entry can be deleted.
struct JournalEntryDetailView: View {
    @EnvironmentObject private var journalStore: JournalStore
    @Environment(\.dismiss) private var dismiss

    let entry: JournalEntry
    /// Verdict from the scan this entry was logged from, when known —
    /// display-only, used for the "We said TRY IT" loop-closer line.
    let linkedVerdict: Verdict?
    @State private var rating: Int
    @State private var notes: String
    @State private var showingDeleteConfirm = false
    @ScaledMetric(relativeTo: .title) private var starSize: CGFloat = 28

    init(entry: JournalEntry, linkedVerdict: Verdict? = nil) {
        self.entry = entry
        self.linkedVerdict = linkedVerdict
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

    private var hasChanges: Bool {
        rating != entry.rating || notes != (entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Sheet surface separation: sheets rest one step above the canvas
                SipColors.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SipSpacing.xl) {
                        // Header
                        VStack(spacing: 6) {
                            // SRM style tile — a stout and a lager should look
                            // different (shared swatch: hairline keeps stout
                            // visible on the dark sheet)
                            StoredPhotoView(fileName: entry.photoFileName) {
                                SRMSwatch(style: entry.style.isEmpty ? nil : entry.style,
                                          cornerRadius: SipRadius.card)
                            }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous))
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
                        .padding(.top, SipSpacing.s)

                        // Loop-closer: what we predicted vs. how they rated it
                        if let verdict = linkedVerdict {
                            loopCloser(for: verdict)
                        }

                        // Editable star rating
                        HStack(spacing: SipSpacing.s) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: starSize))
                                        .foregroundColor(star <= rating ? SipColors.starFilled : SipColors.starEmpty)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityIdentifier("detailStar_\(star)")
                                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                            }
                        }

                        // Editable notes
                        VStack(alignment: .leading, spacing: SipSpacing.s) {
                            Text("Notes")
                                .font(SipTypography.subhead)
                                .foregroundColor(SipColors.textSecondary)
                            TextField("What did you think?", text: $notes, axis: .vertical)
                                .lineLimit(3...8)
                                .font(SipTypography.body)
                                .foregroundColor(SipColors.textPrimary)
                                .padding(SipSpacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                                        .fill(SipColors.surfaceElevated)
                                )
                                .accessibilityIdentifier("detailNotes")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Delete — demoted to quiet red text; Save is the screen's hero
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Text("Delete from Journal")
                                .font(SipTypography.subhead)
                                .foregroundColor(SipColors.destructive)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("detailDelete")
                        .padding(.top, SipSpacing.s)
                    }
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.bottom, SipSpacing.xl)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Save promoted to the primary, always-visible action. Its
                // disabled state now has real button chrome (elevated fill +
                // hairline, from SipPrimaryButtonStyle) — round-2 crit #4: a
                // surface-on-surface disabled Save read as placeholder text.
                Button("Save") {
                    var updated = entry
                    updated.rating = rating
                    updated.notes = notes.isEmpty ? nil : notes
                    journalStore.updateEntry(updated)
                    dismiss()
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .disabled(!hasChanges)
                .padding(.horizontal, SipSpacing.xl)
                .padding(.vertical, SipSpacing.m)
                .background(SipColors.surface)
                .overlay(alignment: .top) {
                    // Hairline seam so the pinned bar reads as chrome, not
                    // content floating at the sheet's bottom edge.
                    Rectangle()
                        .fill(SipColors.textSecondary.opacity(0.2))
                        .frame(height: 0.5)
                }
            }
            .navigationTitle("Beer Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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

    // MARK: - Loop closer ("We said TRY IT — you gave it ★★★★")

    private func loopCloser(for verdict: Verdict) -> some View {
        let style = VerdictStyle.style(for: verdict)
        return HStack(spacing: SipSpacing.s) {
            Image(systemName: style.symbol)
                .font(SipTypography.caption)
                .foregroundColor(style.color)

            (Text("We said \(style.word) — you gave it ")
                .foregroundColor(SipColors.textPrimary)
             + Text(String(repeating: "\u{2605}", count: max(1, min(rating, 5))))
                .foregroundColor(SipColors.starFilled))
                .font(SipTypography.subhead)
        }
        .padding(.horizontal, SipSpacing.l)
        .padding(.vertical, SipSpacing.s)
        .background(Capsule().fill(SipColors.surfaceElevated))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("We said \(style.word), you gave it \(rating) of 5 stars")
    }
}

struct JournalEntryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        JournalEntryDetailView(
            entry: JournalEntry(
                beerName: "Guinness Draught",
                brand: "Guinness",
                style: "Stout",
                abv: 4.2,
                rating: 4,
                notes: "Smooth, creamy."
            ),
            linkedVerdict: .tryIt
        )
        .environmentObject(JournalStore(
            storageDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-journal-detail"),
            useSeedData: false
        ))
        .environmentObject(DrinkStore())
    }
}
