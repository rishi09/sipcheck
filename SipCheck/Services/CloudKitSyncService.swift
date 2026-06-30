import Foundation
import CloudKit

/// Fire-and-forget CloudKit sync. All operations fail silently — local JSON is always authoritative.
/// Sync strategy: last-write-wins by `lastModifiedLocal`. Full sync on app launch.
final class CloudKitSyncService {
    static let shared = CloudKitSyncService()

    private let container = CKContainer(identifier: "iCloud.com.rishishah.sipcheck")
    private var db: CKDatabase { container.privateCloudDatabase }

    private init() {}

    /// Serializes CloudKit writes so a record's mutations apply in submission
    /// order — an edit's save can't be overtaken by a later tombstone save, which
    /// previously could resurrect/clobber a record (fire-and-forget Task.detached
    /// had no ordering guarantee).
    private actor WriteQueue {
        private var tail: Task<Void, Never> = Task {}
        func enqueue(_ op: @escaping () async -> Void) {
            let prev = tail
            tail = Task { await prev.value; await op() }
        }
    }
    private let writeQueue = WriteQueue()

    /// Enqueue a serialized save. On CKError.serverRecordChanged (a concurrent
    /// writer changed the record between fetch and save), refetch the server
    /// record, reapply our fields (local is authoritative), and retry once.
    private func saveRecord(_ recordType: String, _ id: UUID, _ populate: @escaping (CKRecord) -> Void) {
        Task { [self] in
            await writeQueue.enqueue {
                do {
                    let record = try await self.fetchOrCreate(recordType: recordType, id: id)
                    populate(record)
                    try await self.db.save(record)
                } catch let e as CKError where e.code == .serverRecordChanged {
                    if let server = try? await self.db.record(for: CKRecord.ID(recordName: id.uuidString)) {
                        populate(server)
                        _ = try? await self.db.save(server)
                    }
                } catch {
                    print("[CloudKit] save \(recordType) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Drink

    func save(_ drink: Drink) {
        saveRecord("Drink", drink.id) { [self] record in populate(record, from: drink) }
    }

    func fetchAllDrinks() async -> [Drink] {
        let query = CKQuery(recordType: "Drink", predicate: NSPredicate(value: true))
        guard let results = try? await db.records(matching: query, resultsLimit: 2000) else { return [] }
        return results.matchResults.compactMap { (_, result) -> Drink? in
            guard let record = try? result.get() else { return nil }
            return drinkFrom(record)
        }
    }

    // MARK: - Scan

    func save(_ scan: Scan) {
        saveRecord("Scan", scan.id) { [self] record in populate(record, from: scan) }
    }

    func fetchAllScans() async -> [Scan] {
        let query = CKQuery(recordType: "Scan", predicate: NSPredicate(value: true))
        guard let results = try? await db.records(matching: query, resultsLimit: 2000) else { return [] }
        return results.matchResults.compactMap { (_, result) -> Scan? in
            guard let record = try? result.get() else { return nil }
            return scanFrom(record)
        }
    }

    // MARK: - JournalEntry

    func save(_ entry: JournalEntry) {
        saveRecord("JournalEntry", entry.id) { [self] record in populate(record, from: entry) }
    }

    func fetchAllJournalEntries() async -> [JournalEntry] {
        let query = CKQuery(recordType: "JournalEntry", predicate: NSPredicate(value: true))
        guard let results = try? await db.records(matching: query, resultsLimit: 2000) else { return [] }
        return results.matchResults.compactMap { (_, result) -> JournalEntry? in
            guard let record = try? result.get() else { return nil }
            return journalEntryFrom(record)
        }
    }

    // MARK: - Full Sync (called on app launch)

    /// Fetches all remote records in parallel, returns merged arrays.
    /// Merge rule: if remote record is newer by lastModifiedLocal, it wins.
    func fullSync(
        localDrinks: [Drink],
        localScans: [Scan],
        localJournals: [JournalEntry]
    ) async -> (drinks: [Drink], scans: [Scan], journals: [JournalEntry]) {
        async let remoteDrinksTask = fetchAllDrinks()
        async let remoteScansTask = fetchAllScans()
        async let remoteJournalsTask = fetchAllJournalEntries()

        let (remoteDrinks, remoteScans, remoteJournals) = await (remoteDrinksTask, remoteScansTask, remoteJournalsTask)

        let mergedDrinks = merge(local: localDrinks, remote: remoteDrinks)
        let mergedScans = merge(local: localScans, remote: remoteScans)
        let mergedJournals = merge(local: localJournals, remote: remoteJournals)

        // Upload any local records that were missing from remote
        let remoteDrinkIDs = Set(remoteDrinks.map { $0.id })
        for drink in localDrinks where !remoteDrinkIDs.contains(drink.id) {
            save(drink)
        }
        let remoteScanIDs = Set(remoteScans.map { $0.id })
        for scan in localScans where !remoteScanIDs.contains(scan.id) {
            save(scan)
        }
        let remoteJournalIDs = Set(remoteJournals.map { $0.id })
        for entry in localJournals where !remoteJournalIDs.contains(entry.id) {
            save(entry)
        }

        return (mergedDrinks, mergedScans, mergedJournals)
    }

    // MARK: - Helpers

    private func merge<T: Identifiable & HasModifiedDate>(local: [T], remote: [T]) -> [T] where T.ID == UUID {
        var result = local
        let localByID = Dictionary(uniqueKeysWithValues: local.enumerated().map { ($0.element.id, $0.offset) })

        for remoteItem in remote {
            if let localIndex = localByID[remoteItem.id] {
                if cloudKitWins(remoteItem, over: result[localIndex]) {
                    result[localIndex] = remoteItem
                }
            } else {
                result.append(remoteItem)
            }
        }
        return result
    }

    private func fetchOrCreate(recordType: String, id: UUID) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        if let existing = try? await db.record(for: recordID) {
            return existing
        }
        return CKRecord(recordType: recordType, recordID: recordID)
    }

    // MARK: - CKRecord ↔ Model Mapping

    private func populate(_ record: CKRecord, from drink: Drink) {
        record["name"] = drink.name as CKRecordValue
        record["brand"] = drink.brand as CKRecordValue
        record["style"] = drink.style as CKRecordValue
        record["ratingValue"] = drink.ratingValue as CKRecordValue
        record["typeValue"] = drink.typeValue as CKRecordValue
        record["dateAdded"] = drink.dateAdded as CKRecordValue
        record["lastModifiedLocal"] = drink.lastModifiedLocal as CKRecordValue
        record["isDeleted"] = (drink.isDeleted ? 1 : 0) as CKRecordValue
        // Assign every optional unconditionally (nil clears the field). Writing only
        // when non-nil leaves the prior value on the fetched record, so clearing a
        // field never propagates and gets resurrected on the next sync.
        record["notes"] = drink.notes.map { $0 as CKRecordValue }
        record["abv"] = drink.abv.map { $0 as CKRecordValue }
        record["photoFileName"] = drink.photoFileName.map { $0 as CKRecordValue }
    }

    private func drinkFrom(_ record: CKRecord) -> Drink? {
        guard
            let idString = record.recordID.recordName as String?,
            let id = UUID(uuidString: idString),
            let name = record["name"] as? String
        else { return nil }

        var drink = Drink(
            id: id,
            name: name,
            brand: record["brand"] as? String ?? "",
            style: record["style"] as? String ?? "Other",
            rating: .neutral,
            notes: record["notes"] as? String,
            abv: record["abv"] as? Double
        )
        drink.ratingValue = record["ratingValue"] as? Int ?? 1
        drink.typeValue = record["typeValue"] as? Int ?? 1
        drink.dateAdded = record["dateAdded"] as? Date ?? Date()
        drink.lastModifiedLocal = record["lastModifiedLocal"] as? Date ?? drink.dateAdded
        drink.photoFileName = record["photoFileName"] as? String
        drink.isDeleted = (record["isDeleted"] as? Int ?? 0) == 1
        return drink
    }

    private func populate(_ record: CKRecord, from scan: Scan) {
        record["beerName"] = scan.beerName as CKRecordValue
        record["verdict"] = scan.verdict.rawValue as CKRecordValue
        record["explanation"] = scan.explanation as CKRecordValue
        record["timestamp"] = scan.timestamp as CKRecordValue
        record["wantToTry"] = (scan.wantToTry ? 1 : 0) as CKRecordValue
        record["lastModifiedLocal"] = scan.lastModifiedLocal as CKRecordValue
        record["isDeleted"] = (scan.isDeleted ? 1 : 0) as CKRecordValue
        record["style"] = scan.style.map { $0 as CKRecordValue }
        record["abv"] = scan.abv.map { $0 as CKRecordValue }
        record["linkedJournalId"] = scan.linkedJournalId.map { $0.uuidString as CKRecordValue }
        record["origin"] = scan.origin.map { $0 as CKRecordValue }
    }

    private func scanFrom(_ record: CKRecord) -> Scan? {
        guard
            let idString = record.recordID.recordName as String?,
            let id = UUID(uuidString: idString),
            let beerName = record["beerName"] as? String,
            let verdictRaw = record["verdict"] as? String,
            let verdict = Verdict(rawValue: verdictRaw)
        else { return nil }

        let linkedJournalId: UUID?
        if let linked = record["linkedJournalId"] as? String {
            linkedJournalId = UUID(uuidString: linked)
        } else {
            linkedJournalId = nil
        }

        var scan = Scan(
            id: id,
            beerName: beerName,
            style: record["style"] as? String,
            abv: record["abv"] as? Double,
            verdict: verdict,
            explanation: record["explanation"] as? String ?? "",
            timestamp: record["timestamp"] as? Date ?? Date(),
            wantToTry: (record["wantToTry"] as? Int ?? 0) == 1,
            linkedJournalId: linkedJournalId,
            origin: record["origin"] as? String
        )
        scan.lastModifiedLocal = record["lastModifiedLocal"] as? Date ?? scan.timestamp
        scan.isDeleted = (record["isDeleted"] as? Int ?? 0) == 1
        return scan
    }

    private func populate(_ record: CKRecord, from entry: JournalEntry) {
        record["beerName"] = entry.beerName as CKRecordValue
        record["brand"] = entry.brand as CKRecordValue
        record["style"] = entry.style as CKRecordValue
        record["rating"] = entry.rating as CKRecordValue
        record["dateLogged"] = entry.dateLogged as CKRecordValue
        record["lastModifiedLocal"] = entry.lastModifiedLocal as CKRecordValue
        record["isDeleted"] = (entry.isDeleted ? 1 : 0) as CKRecordValue
        record["abv"] = entry.abv.map { $0 as CKRecordValue }
        record["notes"] = entry.notes.map { $0 as CKRecordValue }
        record["photoFileName"] = entry.photoFileName.map { $0 as CKRecordValue }
        record["dateTried"] = entry.dateTried.map { $0 as CKRecordValue }
        record["linkedScanId"] = entry.linkedScanId.map { $0.uuidString as CKRecordValue }
    }

    private func journalEntryFrom(_ record: CKRecord) -> JournalEntry? {
        guard
            let idString = record.recordID.recordName as String?,
            let id = UUID(uuidString: idString),
            let beerName = record["beerName"] as? String
        else { return nil }

        let linkedScanId: UUID?
        if let linked = record["linkedScanId"] as? String {
            linkedScanId = UUID(uuidString: linked)
        } else {
            linkedScanId = nil
        }

        var entry = JournalEntry(
            id: id,
            beerName: beerName,
            brand: record["brand"] as? String ?? "",
            style: record["style"] as? String ?? "",
            abv: record["abv"] as? Double,
            rating: record["rating"] as? Int ?? 3,
            notes: record["notes"] as? String,
            photoFileName: record["photoFileName"] as? String,
            dateLogged: record["dateLogged"] as? Date ?? Date(),
            dateTried: record["dateTried"] as? Date,
            linkedScanId: linkedScanId
        )
        entry.lastModifiedLocal = record["lastModifiedLocal"] as? Date ?? entry.dateLogged
        entry.isDeleted = (record["isDeleted"] as? Int ?? 0) == 1
        return entry
    }
}

// MARK: - Protocol for merge helper

protocol HasModifiedDate {
    var lastModifiedLocal: Date { get }
    var isDeleted: Bool { get }
}

/// Decide whether a `remote` record should replace the `local` one (same id).
/// Newer `lastModifiedLocal` wins; on an exact timestamp tie a deletion wins, so a
/// delete is never silently lost to a concurrent edit with the same timestamp.
func cloudKitWins<T: HasModifiedDate>(_ remote: T, over local: T) -> Bool {
    if remote.lastModifiedLocal != local.lastModifiedLocal {
        return remote.lastModifiedLocal > local.lastModifiedLocal
    }
    return remote.isDeleted && !local.isDeleted
}
