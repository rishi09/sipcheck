import XCTest
@testable import SipCheck

/// Invariants for the onboarding avoid-seed ("stay away") and go-to style
/// channels in TasteScorer + TastePreferences.
final class TasteScorerSeedTests: XCTestCase {

    // MARK: - Fixtures

    /// Preferences with everything defaulted except the fields under test.
    private func prefs(
        vibe: String = "",
        adventure: String = "",
        dislikes: [String] = [],
        seedStyles: [String] = [],
        goToStyles: [String] = [],
        avoidStyles: [String] = [],
        goToBeers: [String] = [],
        avoidBeers: [String] = []
    ) -> TastePreferences {
        TastePreferences(
            vibe: vibe,
            adventure: adventure,
            dislikes: dislikes,
            seedStyles: seedStyles,
            goToStyles: goToStyles,
            avoidStyles: avoidStyles,
            goToBeers: goToBeers,
            avoidBeers: avoidBeers
        )
    }

    private var emptyProfile: TasteProfile { TasteProfile() }

    // MARK: - 1. Avoid seed alone vetoes the style

    func testAvoidSeededStyleIsSkipItWithSteerClearReason() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertLessThanOrEqual(assessment.score, -5.5)
        XCTAssertTrue(
            assessment.shortReason.contains("you steer clear of stout"),
            "Got reason: \(assessment.shortReason)"
        )
    }

    // MARK: - 2. Vibe cannot cancel an explicit avoid pick

    func testVibeDoesNotCancelAvoidSeed() {
        let preferences = prefs(vibe: "Dark & Roasty", avoidStyles: ["Stout"])

        let stout = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: preferences
        )
        XCTAssertEqual(stout.verdict, .skipIt, "Explicit stay-away must beat a vibe match")

        // A sibling dark style stays boosted by the vibe (+2.0 -> tryIt).
        let porter = TasteScorer.assess(
            name: "Dock Porter",
            style: .porter,
            abv: nil,
            profile: emptyProfile,
            preferences: preferences
        )
        XCTAssertEqual(porter.verdict, .tryIt)
        XCTAssertEqual(porter.score, 2.0, accuracy: 0.0001)
    }

    // MARK: - 3. Stay-away remains a hard constraint

    func testRatedLikeHistoryDoesNotSoftenHardAvoidSeed() {
        var profile = TasteProfile()
        profile.favoriteStyles = [(style: "Stout", count: 5)]

        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: profile,
            preferences: prefs(avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.score, -5.5, accuracy: 0.0001)
        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertTrue(
            assessment.shortReason.contains("you steer clear of stout"),
            "Got reason: \(assessment.shortReason)"
        )
    }

    // MARK: - 4. Avoid wins style-key conflicts against seed and go-to

    func testAvoidWinsWhenStyleIsAlsoSeeded() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(seedStyles: ["Stout"], avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        // The +1.5 seed weight must never be applied on top of the avoid penalty.
        XCTAssertEqual(assessment.score, -5.5, accuracy: 0.0001)
    }

    func testAvoidWinsWhenStyleIsAlsoGoTo() {
        let assessment = TasteScorer.assess(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(goToStyles: ["Stout"], avoidStyles: ["Stout"])
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        // The +2.0 go-to weight must never be applied on top of the avoid penalty.
        XCTAssertEqual(assessment.score, -5.5, accuracy: 0.0001)
    }

    func testOverlappingGoToRemainsAvailableForEditingWhileAvoidWinsScoring() {
        let defaults = UserDefaults.standard
        let keys = ["tasteGoToStyles", "tasteGoToStyleChipsJSON", "tasteAvoidStyles"]
        let originals = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("Stout", forKey: "tasteGoToStyles")
        defaults.removeObject(forKey: "tasteGoToStyleChipsJSON")
        defaults.set("Stout", forKey: "tasteAvoidStyles")

        XCTAssertEqual(TastePreferences.savedGoToStyles, ["Stout"])
        XCTAssertEqual(TastePreferences.current.goToStyles, [])
        XCTAssertEqual(TastePreferences.current.avoidStyles, ["Stout"])

        defaults.set("", forKey: "tasteAvoidStyles")
        XCTAssertEqual(TastePreferences.current.goToStyles, ["Stout"],
                       "Clearing the avoid must reveal, not erase, the independent go-to answer")
    }

    // MARK: - 5. Menu ranking: quiz dislike (-5.0) ranks ahead of avoid seed (-5.5)

    func testQuizDislikeRanksAheadOfAvoidSeed() {
        let preferences = prefs(dislikes: ["Really Sour"], avoidStyles: ["Stout"])
        let profile = emptyProfile

        let sour = TasteScorer.AssessedCandidate(
            name: "Puckerfest",
            style: .sour,
            abv: nil,
            assessment: TasteScorer.assess(
                name: "Puckerfest", style: .sour, abv: nil,
                profile: profile, preferences: preferences
            )
        )
        let stout = TasteScorer.AssessedCandidate(
            name: "Midnight Roast",
            style: .stout,
            abv: nil,
            assessment: TasteScorer.assess(
                name: "Midnight Roast", style: .stout, abv: nil,
                profile: profile, preferences: preferences
            )
        )

        XCTAssertEqual(sour.assessment.score, -5.0, accuracy: 0.0001)
        XCTAssertEqual(stout.assessment.score, -5.5, accuracy: 0.0001)
        XCTAssertTrue(TasteScorer.ranksAhead(sour, stout, profile: profile, preferences: preferences))
        XCTAssertFalse(TasteScorer.ranksAhead(stout, sour, profile: profile, preferences: preferences))
    }

    // MARK: - 6. Regression pin: empty avoid/go-to leaves scores unchanged

    func testEmptyAvoidAndGoToLeaveScoresUnchanged() {
        // Pre-change fixture: vibe + adventure + quiz dislike + beer-derived seed,
        // with the NEW fields empty. Scores must match the pre-change formula.
        let preferences = prefs(
            vibe: "Hoppy & Bitter",
            adventure: "Mix It Up",
            dislikes: ["Really Sour"],
            seedStyles: ["Wheat"]
        )
        let profile = emptyProfile

        let ipa = TasteScorer.assess(
            name: "Hop Cannon", style: .ipa, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(ipa.score, 2.0, accuracy: 0.0001)   // vibe weight
        XCTAssertEqual(ipa.verdict, .tryIt)

        let wheat = TasteScorer.assess(
            name: "Cloud Cover", style: .wheat, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(wheat.score, 1.5, accuracy: 0.0001) // seed weight
        XCTAssertEqual(wheat.verdict, .yourCall)

        let sour = TasteScorer.assess(
            name: "Puckerfest", style: .sour, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(sour.score, -5.0, accuracy: 0.0001) // quiz dislike
        XCTAssertEqual(sour.verdict, .skipIt)

        let lager = TasteScorer.assess(
            name: "Crisp One", style: .lager, abv: nil,
            profile: profile, preferences: preferences
        )
        XCTAssertEqual(lager.score, 0.2, accuracy: 0.0001) // neutral, "Mix It Up"
        XCTAssertEqual(lager.verdict, .yourCall)
    }

    // MARK: - 7. saveAvoidSelections preserves typed channels and empties

    func testSaveAvoidSelectionsPreservesTypedChannelsAndExplicitEmpties() {
        let defaults = UserDefaults.standard
        let keys = [
            "avoidBeers", "avoidBeersJSON", "tasteAvoidBeersJSON",
            "tasteAvoidStyleChipsJSON", "tasteAvoidStyles"
        ]
        let originals = keys.map { ($0, defaults.string(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("Porter", forKey: "tasteAvoidStyles")
        TastePreferences.saveAvoidSelections(
            beers: ["Guinness"],
            styleChips: ["Sour"]
        )
        XCTAssertEqual(defaults.string(forKey: "tasteAvoidStyles"), "Sour")

        TastePreferences.saveAvoidSelections(
            beers: ["Guinness"],
            styleChips: ["Sour"],
            avoidStyles: ["Stout", "Sour"]
        )
        XCTAssertEqual(defaults.string(forKey: "avoidBeers"), "Guinness,Sour")
        XCTAssertEqual(TastePreferences.savedAvoidBeers, ["Guinness"])
        XCTAssertEqual(TastePreferences.savedAvoidStyleChips, ["Sour"])
        XCTAssertEqual(defaults.string(forKey: "tasteAvoidStyles"), "Sour,Stout")

        TastePreferences.saveAvoidSelections(
            beers: ["IPA"],
            styleChips: [],
            avoidStyles: []
        )
        XCTAssertEqual(TastePreferences.savedAvoidBeers, ["IPA"])
        XCTAssertEqual(TastePreferences.savedAvoidStyleChips, [])
        XCTAssertEqual(TastePreferences.current.avoidBeers, ["IPA"])
        XCTAssertEqual(TastePreferences.current.avoidStyles, [])
        let isolatedAvoidPreferences = prefs(
            avoidStyles: TastePreferences.current.avoidStyles,
            avoidBeers: TastePreferences.current.avoidBeers
        )
        XCTAssertEqual(
            TasteScorer.assess(
                name: "IPA",
                style: nil,
                abv: nil,
                profile: emptyProfile,
                preferences: isolatedAvoidPreferences
            ).verdict,
            .skipIt
        )
        XCTAssertEqual(
            TasteScorer.assess(
                name: "Other IPA",
                style: .ipa,
                abv: nil,
                profile: emptyProfile,
                preferences: isolatedAvoidPreferences
            ).verdict,
            .yourCall
        )

        // Clearing the picker must write PRESENT-but-empty values (never nil):
        // an empty seed value is authoritative and must propagate.
        TastePreferences.saveAvoidSelections(beers: [], styleChips: [], avoidStyles: [])
        XCTAssertEqual(defaults.string(forKey: "avoidBeers"), "")
        XCTAssertEqual(defaults.string(forKey: "tasteAvoidStyles"), "")
        XCTAssertEqual(TastePreferences.savedAvoidBeers, [])
    }

    // MARK: - 8. Go-to style chip scores at the vibe weight

    func testGoToStyleScoresTryIt() {
        let assessment = TasteScorer.assess(
            name: "Hop Cannon",
            style: .ipa,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(goToStyles: ["IPA"])
        )
        XCTAssertEqual(assessment.score, 2.0, accuracy: 0.0001)
        XCTAssertEqual(assessment.verdict, .tryIt)
    }

    func testEveryOnboardingBeerMapsToAColdStartStyle() {
        for beer in onboardingBeerOptions {
            XCTAssertNotNil(
                TastePreferences.styleForOnboardingBeer(beer),
                "Missing cold-start style for \(beer)"
            )
        }
        XCTAssertEqual(TastePreferences.styleForOnboardingBeer("Lagunitas"), .ipa)
        XCTAssertEqual(TastePreferences.styleForOnboardingBeer("Guinness"), .stout)
    }

    func testPreferenceStyleResolutionNeverUsesFuzzyOrAmbiguousCatalogFacts() {
        let catalog = BundledCatalog(seed: [
            (name: "Shared Name", brewery: "Catalog Brewing", style: "American IPA", coarse: "ipa", abv: 6.8),
            (name: "Shared Name", brewery: "Local Cellars", style: "Pilsner", coarse: "pilsner", abv: 4.9),
            (name: "Neighborhood Bloom", brewery: "Block Eight", style: "American IPA", coarse: "ipa", abv: 6.5)
        ])

        XCTAssertEqual(
            TastePreferences.locallyResolvedStyles(for: ["Shared Name"], catalog: catalog),
            []
        )
        XCTAssertEqual(
            TastePreferences.locallyResolvedStyles(for: ["Neighborhood Bloom Reserve"], catalog: catalog),
            []
        )
        XCTAssertEqual(
            TastePreferences.locallyResolvedStyles(for: ["Neighborhood Bloom"], catalog: catalog),
            ["IPA"]
        )
        XCTAssertEqual(
            TastePreferences.locallyResolvedStyles(for: ["Taproom Hazy IPA"], catalog: catalog),
            ["IPA"]
        )
    }

    func testNamedGoToBeerGetsExplicitGoToWeight() {
        let defaults = UserDefaults.standard
        let keys = [
            "knownBeers", "tasteGoToBeers", "tasteGoToBeersJSON", "tasteGoToStyleChipsJSON",
            "tasteSeedStyles", "tasteGoToStyles", "avoidBeers",
            "avoidBeersJSON", "tasteAvoidBeersJSON",
            "tasteAvoidStyleChipsJSON", "tasteAvoidStyles"
        ]
        let originals = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("", forKey: "avoidBeers")
        defaults.set("[]", forKey: "avoidBeersJSON")
        defaults.set("[]", forKey: "tasteAvoidBeersJSON")
        defaults.set("[]", forKey: "tasteAvoidStyleChipsJSON")
        defaults.set("", forKey: "tasteAvoidStyles")
        TastePreferences.saveGoTo(beers: ["Lagunitas"], styleChips: [], seedStyles: ["IPA"])

        XCTAssertEqual(defaults.string(forKey: "tasteSeedStyles"), "IPA")
        XCTAssertEqual(defaults.string(forKey: "tasteGoToStyles"), "IPA")
        XCTAssertEqual(TastePreferences.savedGoToStyles, [])
        XCTAssertEqual(TastePreferences.savedGoToBeers, ["Lagunitas"])
        let assessment = TasteScorer.assess(
            name: "Two Hearted",
            style: .ipa,
            abv: 7.0,
            profile: emptyProfile,
            preferences: TastePreferences.current
        )
        XCTAssertEqual(assessment.verdict, .tryIt)

        TastePreferences.saveGoToSelections(beers: [], styleChips: [])
        XCTAssertEqual(TastePreferences.savedGoToStyles, [])
        XCTAssertEqual(TastePreferences.current.goToStyles, [])
    }

    func testUnknownNamedGoToIsActionableWithoutCatalogFacts() {
        let assessment = TasteScorer.assess(
            name: "Neighborhood One-Off",
            style: nil,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(goToBeers: ["Neighborhood One-Off"])
        )

        XCTAssertEqual(assessment.verdict, .tryIt)
        XCTAssertEqual(assessment.score, 2.0, accuracy: 0.0001)
        XCTAssertTrue(assessment.shortReason.contains("exact beer"))
    }

    func testUnknownNamedStayAwayBeatsExactHistoricalLike() {
        let drinks = [Drink(name: "Neighborhood One-Off", style: "Other", rating: .like)]
        let assessment = TasteScorer.assessWithExactHistory(
            name: "Neighborhood One-Off",
            style: nil,
            abv: nil,
            drinks: drinks,
            profile: TasteProfile.build(from: drinks),
            preferences: prefs(
                goToBeers: ["Neighborhood One-Off"],
                avoidBeers: ["Neighborhood One-Off"]
            )
        )

        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertLessThanOrEqual(assessment.score, -5.5)
        XCTAssertTrue(assessment.shortReason.contains("stay-away"))
    }

    func testNamedPreferenceDoesNotFuzzyMatchAnotherBeer() {
        let assessment = TasteScorer.assess(
            name: "Neighborhood One-Off Reserve",
            style: nil,
            abv: nil,
            profile: emptyProfile,
            preferences: prefs(avoidBeers: ["Neighborhood One-Off"])
        )

        XCTAssertEqual(assessment.verdict, .yourCall)
    }

    func testNamedPreferencesPersistImmediatelyAndRoundTripNamesContainingCommas() {
        let defaults = UserDefaults.standard
        let keys = [
            "knownBeers", "tasteGoToBeers", "tasteGoToBeersJSON", "tasteGoToStyleChipsJSON",
            "tasteSeedStyles", "tasteGoToStyles", "avoidBeers",
            "avoidBeersJSON", "tasteAvoidBeersJSON",
            "tasteAvoidStyleChipsJSON", "tasteAvoidStyles"
        ]
        let originals = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originals {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        defaults.set("Stout", forKey: "tasteSeedStyles")
        defaults.set("Stout", forKey: "tasteGoToStyles")
        TastePreferences.saveGoToSelections(
            beers: ["Small Batch, Lot 7"],
            styleChips: ["Sour"]
        )
        TastePreferences.saveAvoidSelections(
            beers: ["Barrel Trial, No. 2"],
            styleChips: []
        )

        XCTAssertEqual(defaults.string(forKey: "tasteSeedStyles"), "")
        XCTAssertEqual(defaults.string(forKey: "tasteGoToStyles"), "Sour")
        XCTAssertEqual(TastePreferences.current.goToBeers, ["Small Batch, Lot 7"])
        XCTAssertEqual(TastePreferences.current.avoidBeers, ["Barrel Trial, No. 2"])
        XCTAssertTrue(TastePreferences.goToSelectionsAreCurrent(
            beers: ["Small Batch, Lot 7"],
            styleChips: ["Sour"]
        ))
        XCTAssertTrue(TastePreferences.avoidSelectionsAreCurrent(
            beers: ["Barrel Trial, No. 2"],
            styleChips: []
        ))

        TastePreferences.saveGoToSelections(beers: ["Newer Choice"], styleChips: [])
        TastePreferences.saveAvoidSelections(beers: ["Newer Avoid"], styleChips: [])
        XCTAssertFalse(TastePreferences.goToSelectionsAreCurrent(
            beers: ["Small Batch, Lot 7"],
            styleChips: ["Sour"]
        ))
        XCTAssertFalse(TastePreferences.avoidSelectionsAreCurrent(
            beers: ["Barrel Trial, No. 2"],
            styleChips: []
        ))

        TastePreferences.saveGoTo(
            beers: ["Small Batch, Lot 7"],
            styleChips: [],
            seedStyles: []
        )
        TastePreferences.saveAvoidSelections(
            beers: ["Barrel Trial, No. 2"],
            styleChips: [],
            avoidStyles: []
        )

        XCTAssertEqual(TastePreferences.savedGoToBeers, ["Small Batch, Lot 7"])
        XCTAssertEqual(TastePreferences.savedAvoidBeers, ["Barrel Trial, No. 2"])
        XCTAssertEqual(TastePreferences.current.goToBeers, ["Small Batch, Lot 7"])
        XCTAssertEqual(TastePreferences.current.avoidBeers, ["Barrel Trial, No. 2"])
    }

    func testManyLikesOutweighOneHistoricalDislike() {
        let drinks = (0..<10).map { _ in
            Drink(name: UUID().uuidString, style: "IPA", rating: .like)
        } + [Drink(name: "One miss", style: "IPA", rating: .dislike)]
        let assessment = TasteScorer.assess(
            name: "Two Hearted",
            style: .ipa,
            abv: nil,
            profile: TasteProfile.build(from: drinks),
            preferences: prefs()
        )

        XCTAssertEqual(assessment.verdict, .tryIt)
        XCTAssertEqual(assessment.score, 3.0, accuracy: 0.0001)
        XCTAssertTrue(assessment.shortReason.contains("matches your history"))
    }

    func testHistoricalDislikesStillWinWhenTheyOutnumberLikes() {
        let drinks = [
            Drink(name: "Liked once", style: "Stout", rating: .like),
            Drink(name: "Miss 1", style: "Stout", rating: .dislike),
            Drink(name: "Miss 2", style: "Stout", rating: .dislike),
            Drink(name: "Miss 3", style: "Stout", rating: .dislike)
        ]
        let assessment = TasteScorer.assess(
            name: "Dark Beer",
            style: .stout,
            abv: nil,
            profile: TasteProfile.build(from: drinks),
            preferences: prefs()
        )

        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertEqual(assessment.score, -1.5, accuracy: 0.0001)
    }

    func testExactPriorRatingOverridesAggregateStyleVerdict() {
        let base = TasteScorer.assess(
            name: "Known Beer",
            style: .paleAle,
            abv: nil,
            profile: TasteProfile(),
            preferences: prefs()
        )

        XCTAssertEqual(TasteScorer.applyingExactRating(.like, to: base).verdict, .tryIt)
        XCTAssertEqual(TasteScorer.applyingExactRating(.dislike, to: base).verdict, .skipIt)
        XCTAssertEqual(TasteScorer.applyingExactRating(.neutral, to: base).verdict, .yourCall)
        XCTAssertEqual(TasteScorer.applyingExactRating(nil, to: base).verdict, base.verdict)
    }

    func testExactHistoryDoesNotCrossSameNameBreweries() {
        let drinks = [
            Drink(name: "Shared Name", brand: "Catalog Brewing", style: "IPA", rating: .dislike),
            Drink(name: "Shared Name", brand: "Local Cellars", style: "Pilsner", rating: .like)
        ]
        let profile = TasteProfile.build(from: drinks)

        let local = TasteScorer.assessWithExactHistory(
            name: "Shared Name",
            brewery: "Local Cellars",
            style: .pilsner,
            abv: nil,
            drinks: drinks,
            profile: profile,
            preferences: prefs()
        )
        let catalog = TasteScorer.assessWithExactHistory(
            name: "Shared Name",
            brewery: "Catalog Brewing",
            style: .ipa,
            abv: nil,
            drinks: drinks,
            profile: profile,
            preferences: prefs()
        )

        XCTAssertEqual(local.verdict, .tryIt)
        XCTAssertEqual(catalog.verdict, .skipIt)
    }

    func testExactLikeCannotOverrideExplicitStayAwayStyle() {
        let hardAvoid = TasteScorer.assess(
            name: "Known Sour",
            style: .sour,
            abv: nil,
            profile: TasteProfile(),
            preferences: prefs(avoidStyles: [BeerStyle.sour.rawValue])
        )

        let result = TasteScorer.applyingExactRating(.like, to: hardAvoid)
        XCTAssertEqual(result.verdict, .skipIt)
        XCTAssertEqual(result.score, hardAvoid.score, accuracy: 0.0001)
        XCTAssertTrue(result.shortReason.contains("steer clear"))
    }

    // MARK: - Behavioral persona stress tests

    func testAddingPositiveRatingNeverLowersGoToRecommendation() {
        let preferences = prefs(goToStyles: ["IPA"])
        let before = TasteScorer.assess(
            name: "House IPA", style: .ipa, abv: nil,
            profile: TasteProfile(), preferences: preferences
        )
        let after = TasteScorer.assess(
            name: "House IPA", style: .ipa, abv: nil,
            profile: TasteProfile.build(from: [
                Drink(name: "Liked IPA", style: "IPA", rating: .like)
            ]),
            preferences: preferences
        )

        XCTAssertEqual(before.verdict, .tryIt)
        XCTAssertEqual(after.verdict, .tryIt)
        XCTAssertGreaterThanOrEqual(after.score, before.score)
    }

    func testAddingDislikeNeverRaisesRecommendation() {
        let before = TasteScorer.assess(
            name: "House Porter", style: .porter, abv: nil,
            profile: TasteProfile(), preferences: prefs()
        )
        let after = TasteScorer.assess(
            name: "House Porter", style: .porter, abv: nil,
            profile: TasteProfile.build(from: [
                Drink(name: "Missed Porter", style: "Porter", rating: .dislike)
            ]),
            preferences: prefs()
        )

        XCTAssertLessThanOrEqual(after.score, before.score)
        XCTAssertEqual(after.verdict, .skipIt)
    }

    func testAddingDislikeCannotSoftenQuizDislike() {
        let preferences = prefs(dislikes: ["Really Sour"])
        let before = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: nil,
            profile: TasteProfile(), preferences: preferences
        )
        let drinks = [Drink(name: "Missed Sour", style: "Sour", rating: .dislike)]
        let after = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: nil,
            profile: TasteProfile.build(from: drinks), preferences: preferences
        )

        XCTAssertLessThanOrEqual(after.score, before.score)
        XCTAssertEqual(after.verdict, .skipIt)
    }

    func testUntrustedNameCannotApplyExactHistoryOverride() {
        let drinks = [Drink(name: "Centennial IPA", style: "IPA", rating: .like)]
        let assessment = TasteScorer.assessWithExactHistory(
            name: "Centennial IPA",
            style: .paleAle,
            abv: nil,
            drinks: drinks,
            profile: TasteProfile(),
            preferences: prefs(),
            allowExactMatch: false
        )

        XCTAssertEqual(assessment.verdict, .yourCall)
        XCTAssertFalse(assessment.shortReason.contains("exact beer"))
    }

    func testOnboardingBeerConflictsUseResolvedStyle() {
        XCTAssertTrue(TastePreferences.onboardingBeer("Bud Light", conflictsWith: ["Lager"]))
        XCTAssertTrue(TastePreferences.onboardingBeer("Modelo", conflictsWith: ["Lager"]))
        XCTAssertFalse(TastePreferences.onboardingBeer("Guinness", conflictsWith: ["Lager"]))
    }

    func testFamiliarityFirstLagerLoyalistTriesAdjacentPilsnerAndSkipsSour() {
        let history = (0..<8).map { index in
            Drink(name: "Light Lager \(index)", style: "Light Lager", rating: .like, abv: 4.2)
        }
        let profile = TasteProfile.build(from: history)
        let preferences = prefs(
            adventure: "Stick to Favorites",
            goToStyles: [BeerStyle.lager.rawValue]
        )

        let craftPilsner = TasteScorer.assess(
            name: "Craft Pilsner", style: .pilsner, abv: 4.8,
            profile: profile, preferences: preferences
        )
        let fruitSour = TasteScorer.assess(
            name: "Raspberry Sour", style: .sour, abv: 5.0,
            profile: profile, preferences: preferences
        )

        XCTAssertEqual(craftPilsner.verdict, .tryIt)
        XCTAssertEqual(fruitSour.verdict, .skipIt)
        XCTAssertTrue(fruitSour.shortReason.contains("outside the styles"))
    }

    func testCautiousLightLagerLoyalistDoesNotTreatPaleAleAsAdjacent() {
        let profile = TasteProfile.build(from: (0..<8).map { index in
            Drink(name: "Light Lager \(index)", style: "Light Lager", rating: .like, abv: 4.2)
        })
        let assessment = TasteScorer.assess(
            name: "Bitter American Pale Ale",
            style: .paleAle,
            abv: 5.5,
            profile: profile,
            preferences: prefs(
                adventure: "Stick to Favorites",
                goToStyles: [BeerStyle.lager.rawValue]
            )
        )

        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertTrue(assessment.shortReason.contains("outside the styles"))
    }

    func testNewlyResolvedSourReScoresUnknownVerdictForLagerLoyalist() {
        let drinks = (0..<8).map { index in
            Drink(name: "Light Lager \(index)", style: "Light Lager", rating: .like, abv: 4.2)
        }
        let profile = TasteProfile.build(from: drinks)
        let preferences = prefs(
            adventure: "Stick to Favorites",
            goToStyles: [BeerStyle.lager.rawValue]
        )

        let initial = TasteScorer.assessWithExactHistory(
            name: "Raspberry Eclipse",
            style: nil,
            abv: nil,
            drinks: drinks,
            profile: profile,
            preferences: preferences
        )
        let enriched = TasteScorer.assessWithExactHistory(
            name: "Raspberry Eclipse",
            style: .sour,
            abv: 5.0,
            drinks: drinks,
            profile: profile,
            preferences: preferences
        )

        XCTAssertEqual(initial.verdict, .yourCall)
        XCTAssertEqual(enriched.verdict, .skipIt)
    }

    func testDarkMaltRegularTriesPorterAndSkipsDistantStyles() {
        let preferences = prefs(
            adventure: "Stick to Favorites",
            goToStyles: [BeerStyle.stout.rawValue],
            avoidStyles: [BeerStyle.sour.rawValue]
        )

        let porter = TasteScorer.assess(
            name: "Dock Porter", style: .porter, abv: nil,
            profile: TasteProfile(), preferences: preferences
        )
        let ipa = TasteScorer.assess(
            name: "West Coast IPA", style: .ipa, abv: nil,
            profile: TasteProfile(), preferences: preferences
        )
        let sour = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: nil,
            profile: TasteProfile(), preferences: preferences
        )

        XCTAssertEqual(porter.verdict, .tryIt)
        XCTAssertEqual(ipa.verdict, .skipIt)
        XCTAssertEqual(sour.verdict, .skipIt)
    }

    func testSourPreferenceIsIndependentFromGenericAdventure() {
        let genericExplorer = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: 5.0,
            profile: TasteProfile(),
            preferences: prefs(adventure: "Give Me the Weird Stuff")
        )
        let sourSpecialist = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: 5.0,
            profile: TasteProfile(),
            preferences: prefs(
                adventure: "Give Me the Weird Stuff",
                goToStyles: [BeerStyle.sour.rawValue]
            )
        )

        XCTAssertEqual(genericExplorer.verdict, .yourCall)
        XCTAssertEqual(sourSpecialist.verdict, .tryIt)
    }

    func testSparseHistoryDoesNotCreateConfidentDistantStyleRejection() {
        let profile = TasteProfile.build(from: [
            Drink(name: "One Wheat", style: "Wheat", rating: .like, abv: 5.2)
        ])
        let assessment = TasteScorer.assess(
            name: "House Sour", style: .sour, abv: 5.0,
            profile: profile,
            preferences: prefs(adventure: "Stick to Favorites")
        )

        XCTAssertEqual(assessment.verdict, .yourCall)
    }

    func testHistoricalStyleAliasesContributeToRecommendations() {
        let profile = TasteProfile.build(from: [
            Drink(name: "Light One", style: "Light Lager", rating: .like, abv: 4.2),
            Drink(name: "Light Two", style: "Light Lager", rating: .like, abv: 4.4)
        ])
        let assessment = TasteScorer.assess(
            name: "Crisp Lager", style: .lager, abv: 4.5,
            profile: profile, preferences: prefs()
        )

        XCTAssertEqual(assessment.verdict, .tryIt)
        XCTAssertTrue(assessment.shortReason.contains("matches your history"))
    }
}
