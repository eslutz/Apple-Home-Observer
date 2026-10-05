import Foundation
import Security
import CryptoKit
import HomeKit
import Darwin
import OSLog

struct KeyVault {
    static let service = ObserverConfiguration.bundleIdentifier + ".archive"
    static func key() throws -> SymmetricKey {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"v1",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) }
        let key = SymmetricKey(size:.bits256); let data = key.withUnsafeBytes { Data($0) }
        let add: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"v1",kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let added = SecItemAdd(add as CFDictionary,nil); guard added == errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(added)) }; return key
    }
}
struct Health: Codable {
    var schema = "apple-home-health/v1"; var timestamp = Date(); var authorized = false; var inventoryReady = false
    var homeCount = 0; var selectedHomeAvailable = false; var accessoryCount = 0; var accessoriesWithoutRoom = 0; var accessoriesWithoutServiceData = 0
    var lastBackup: Date?; var lastDaily: Date?; var lastReconcile: Date?; var driftTotal = 0; var unplannedDriftTotal = 0; var movementFailuresTotal = 0; var unavailable = 0; var coverageGaps = 0; var loggingHealthy = true; var error: String?
}
struct BlindPositionReading: Equatable {
    var current: Double?
    var target: Double?
    var updatedAt: Date
}
enum BlindCommandOutcome: Equatable {
    case waiting
    case reportedTargetReached
    case timedOut
    case alreadyWithinTolerance
    case noMeasuredTravel

    var title: String {
        switch self {
        case .waiting: "Waiting for HomeKit-reported position"
        case .reportedTargetReached: "HomeKit reported the target within tolerance"
        case .timedOut: "No target position was reported before timeout"
        case .alreadyWithinTolerance: "Already within target tolerance"
        case .noMeasuredTravel: "Target changed; no measured travel time is saved"
        }
    }
}
@MainActor final class Runtime: ObservableObject {
    static var auditMode: String? {
        #if OBSERVER_ACCEPTANCE
        return ProcessInfo.processInfo.environment["OBSERVER_UI_AUDIT"] ?? "populated"
        #elseif DEBUG
        return ProcessInfo.processInfo.environment["OBSERVER_UI_AUDIT"]
        #else
        return nil
        #endif
    }
    let adapter = HomeAdapter(observe: Runtime.auditMode == nil)
    var homeChoices: [NamedObject] {
        if Self.auditMode != nil, let inventory { return [NamedObject(id: selectedID, name: inventory.name)] }
        return adapter.homes.map { NamedObject(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
    }
    @Published var status = "Waiting for Home Data permission"
    @Published var inventory: HomeSnapshot?
    @Published var archives: [SnapshotIndex] = []
    @Published var preview: RestorePreview?
    @Published var busy = false
    @Published var restoreStatus = ""
    @Published var recoveryJournals: [RestoreJournal] = []
    var recoveryJournalID: String?
    var journalCheckFailed = false
    @Published var selectedID = UserDefaults.standard.string(forKey:"homeID") ?? "" { didSet { UserDefaults.standard.set(selectedID,forKey:"homeID"); inventory = nil; candidate = nil; previousTargets.removeAll(); blindReadings.removeAll(); blindOutcomes.removeAll(); watchdog = MovementWatchdog(travelSeconds:60); configureStore(); adapter.selectedID = selectedID } }
    @Published var recoveryExported = UserDefaults.standard.bool(forKey:"recoveryExported")
    @Published var blindReadings: [String:BlindPositionReading] = [:]
    @Published var blindOutcomes: [String:BlindCommandOutcome] = [:]
    static let monitoringExportBookmarkKey = "monitoringExportBookmark"
    static var monitoringExportDirectory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(ObserverConfiguration.monitoringFolder, isDirectory: true)
    }
    @Published var monitoringExportConfigured = UserDefaults.standard.data(forKey: monitoringExportBookmarkKey) != nil
    @Published var monitoringExportStatus = "Not connected"
    let root: URL
    private var localLoggingHealthy = true
    private var exportEventsHealthy = true
    private var instanceLock: Int32 = -1
    var key: SymmetricKey?
    var store: SnapshotStore?
    var health = Health()
    private var candidate: HomeSnapshot?
    private var inventoryGate = InventoryGate()
    @Published var pendingInventory: HomeSnapshot?
    private var debounce: Task<Void,Never>?
    private var timer: Timer?
    private var previousTargets: [String:Double] = [:]
    private var watchdog = MovementWatchdog(travelSeconds:60)
    private var tickCount = 0
    var plannedUntil: Date?
    private var travelBudgets: [String:Double] = [:]
    var savedForRestore: HomeSnapshot?
    var importedArchive: Data?
    var importRecoveryKey: SymmetricKey?
    @Published var restoreMappings: [String:String] = [:]
    init() {
        if let mode = Self.auditMode {
            // Audits never initialize HomeKit, Keychain, archives, bookmarks, or timers.
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ObserverUIAudit")
            selectedID = ""; recoveryExported = false; monitoringExportConfigured = false
            key = SymmetricKey(size: .bits256)
            status = "Choose a Home to observe"
            if mode != "empty" {
                selectedID = "00000000-0000-0000-0000-000000000001"
                inventory = HomeSnapshot(homeID: selectedID, name: "Sample Home", rooms: [NamedObject(id: "audit-room", name: "Living Room")], accessories: [AccessoryRecord(id: "audit-blind", name: "Living Room Blind", roomID: "audit-room", manufacturer: "Sample", model: "Blind", services: [ServiceRecord(id: "audit-service", name: "Blind", type: "sample", characteristics: [CharacteristicRecord(id: "audit-position", type: HMCharacteristicTypeCurrentPosition, readable: true)])])], coverage: [CoverageGap(objectID: selectedID, reason: "Pairing secrets and hub settings require separate recovery.")])
                health.inventoryReady = true; health.authorized = true; health.accessoryCount = 1; health.coverageGaps = 1
                blindReadings["audit-blind"] = BlindPositionReading(current: 45, target: 45, updatedAt: Date())
                archives = [SnapshotIndex(file: "audit-snapshot.aho", date: Date(timeIntervalSince1970: 1791000000), reason: .baseline, digest: "synthetic")]
                health.lastBackup = archives.first?.date; health.lastReconcile = Date()
                status = "Observing sample inventory for accessibility testing"
                if mode == "many-backups" {
                    archives = (0..<130).map { SnapshotIndex(file: "sample-\($0).aho", date: Date(timeIntervalSince1970: 1791000000 + Double($0 * 86400)), reason: .daily, digest: "synthetic") }
                }
                if mode == "busy" { busy = true }
                if mode == "incomplete" { health.inventoryReady = false; status = "Sample inventory is incomplete" }
                if mode == "error" { health.error = "sample_error"; status = "Sample refresh failed. Try again." }
                if mode == "recovery" || mode == "interrupted" {
                    var saved = inventory!; saved.name = "Sample restored Home"
                    savedForRestore = saved; preview = try? RestorePlanner.preview(saved: saved, current: inventory!)
                    if mode == "interrupted", let preview {
                        var journal = RestoreJournal(predecessorFile: "sample-predecessor.aho", preview: preview)
                        journal.id = "sample-journal"; journal.state = "interrupted"
                        recoveryJournals = [journal]
                    }
                }
            }
            return
        }
        root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AppleHomeObserver")
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            instanceLock = open(root.appendingPathComponent("instance.lock").path,O_RDWR | O_CREAT | O_NOFOLLOW,0o600)
            guard instanceLock >= 0, flock(instanceLock,LOCK_EX | LOCK_NB) == 0 else { status = "Another observer instance is already running. This window is inactive."; return }
        } catch { status = "Private observer directory unavailable"; return }
        do { key = try KeyVault.key(); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]) }
        catch { status = "Archive setup failed: \(String(describing:error))"; health.error = "archive_setup" }
        health.driftTotal = UserDefaults.standard.integer(forKey:"driftTotal")
        health.unplannedDriftTotal = UserDefaults.standard.integer(forKey:"unplannedDriftTotal")
        if let data = UserDefaults.standard.data(forKey:"travelBudgets"), let decoded = try? Coding.decode([String:Double].self,data) { travelBudgets = decoded.filter { $0.value.isFinite && (1...600).contains($0.value) } }
        health.movementFailuresTotal = UserDefaults.standard.integer(forKey:"movementFailuresTotal")
        configureStore()
        refreshJournals()
        adapter.selectedID = selectedID
        adapter.changed = { [weak self] in self?.schedule() }
        adapter.state = { [weak self] a,c in self?.observe(a,c) }
        timer = Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }
    func configureStore() {
        guard Self.auditMode == nil else { return }
        store = nil; archives = []; preview = nil; recoveryJournalID = nil; inventoryGate = InventoryGate(); pendingInventory = nil; health.inventoryReady = false; health.lastBackup = nil; health.lastDaily = nil; health.lastReconcile = nil
        guard let uuid = UUID(uuidString:selectedID), let key else { return }
        do {
            store = try SnapshotStore(root:root.appendingPathComponent("archives").appendingPathComponent(uuid.uuidString),key:key)
            archives = try store!.index(); health.lastBackup = archives.last?.date; health.lastDaily = archives.last(where: { $0.reason == .daily })?.date
        } catch { status = "Archive setup failed"; health.error = "archive_setup" }
    }
    func schedule() { debounce?.cancel(); debounce = Task { [weak self] in try? await Task.sleep(for:.seconds(5)); guard !Task.isCancelled else { return }; self?.reconcile() } }
    func tick() {
        tickCount += 1
        if tickCount == 1 || tickCount % 10 == 0 { reconcile(); adapter.attach(); adapter.readPositions() }
        for id in watchdog.expire(now:Date().timeIntervalSince1970) { health.movementFailuresTotal += 1; blindOutcomes[id] = .timedOut; event("apple_home.movement_timeout",attributes:["accessory.id":id]) }
        if health.inventoryReady, inventory != nil, BackupSchedule.dailyDue(now:Date(),lastDaily:health.lastDaily), !busy { backup(.daily) }
        writeHealth()
    }
    func reconcile(approveRemoval: Bool = false) {
        guard Self.auditMode == nil else { status = "Sample inventory refreshed"; return }
        guard !busy else { return }
        health.authorized = adapter.authorized
        health.homeCount = adapter.homes.count
        health.selectedHomeAvailable = adapter.home != nil
        let capturedAccessories = adapter.home?.accessories ?? []
        health.accessoryCount = capturedAccessories.count
        health.accessoriesWithoutRoom = capturedAccessories.filter { $0.room == nil }.count
        health.accessoriesWithoutServiceData = capturedAccessories.filter { !$0.services.contains { !$0.characteristics.isEmpty } }.count
        do {
            let snapshot = try adapter.snapshot()
            health.error = nil
            let known = inventory ?? (try? store?.loadLatest())
            if inventory == nil, let known, known.homeID == snapshot.homeID { inventory = known }
            let predecessor = known?.homeID == snapshot.homeID ? known : nil
            let decision = inventoryGate.evaluate(snapshot,previous:predecessor,approveRemoval:approveRemoval)
            guard decision == .ready else {
                health.inventoryReady = false; pendingInventory = snapshot
                if decision == .removalNeedsReview {
                    status = "Inventory lost known identities. Review missing objects before accepting a replacement backup."
                    event("apple_home.inventory_hold",attributes:["change.count":predecessor.map { SnapshotDiff.compare($0,snapshot).count } ?? 0])
                } else { status = "Waiting for two matching complete Home inventories"; schedule() }
                writeHealth(); return
            }
            pendingInventory = nil
            inventory = snapshot; health.inventoryReady = true; health.lastReconcile = Date(); health.coverageGaps = snapshot.coverage.count
            health.unavailable = adapter.home?.accessories.filter { !$0.isReachable }.count ?? 0
            if let predecessor {
                let diff = SnapshotDiff.compare(predecessor,snapshot)
                if !diff.isEmpty {
                    health.driftTotal += diff.count
                    let planned = plannedUntil.map { Date() < $0 } ?? false
                    if !planned { health.unplannedDriftTotal += diff.count }
                    for d in diff { event("apple_home.metadata_changed",attributes:["object.id":d.objectID,"change.kind":d.kind,"change.planned":planned,"before":d.before ?? "","after":d.after ?? ""]) }
                    backup(.change)
                }
            } else {
                if archives.isEmpty { backup(.baseline) }
                else if let old = try store?.loadLatest(), old.homeID == snapshot.homeID {
                    let changes = SnapshotDiff.compare(old,snapshot)
                    if !changes.isEmpty { health.driftTotal += changes.count; health.unplannedDriftTotal += changes.count; event("apple_home.reconcile_gap",attributes:["change.count":changes.count]); backup(.change) }
                }
            }
            status = "Observing \(snapshot.accessories.count) accessories; \(snapshot.coverage.count) recovery coverage notices"
            health.error = nil
        } catch {
            inventoryGate = InventoryGate(); pendingInventory = nil; health.inventoryReady = false
            if !health.authorized { health.error = "home_permission_missing"; status = "Waiting for Home Data permission" }
            else if selectedID.isEmpty { health.error = "home_not_selected"; status = "Choose a Home to observe" }
            else if !health.selectedHomeAvailable { health.error = "selected_home_unavailable"; status = "The selected Home is not currently available to HomeKit" }
            else if health.accessoryCount == 0 { health.error = "home_has_no_accessories"; status = "HomeKit returned no accessories for the selected Home" }
            else if health.accessoriesWithoutServiceData > 0 { health.error = "accessory_service_data_incomplete"; status = "HomeKit accessory service data is incomplete; inventory is held" }
            else { health.error = "home_snapshot_invalid"; status = "HomeKit returned an incomplete inventory. Existing snapshots remain protected." }
            if let failure = adapter.lastCaptureFailure { health.error = failure }
        }
        writeHealth()
    }
    func backup(_ reason: SnapshotReason) {
        guard Self.auditMode == nil else { status = "Sample backup action verified"; return }
        guard !busy, let previous = inventory, let store, adapter.authorized, health.inventoryReady else { return }
        do {
            var snapshot = try adapter.snapshot()
            guard inventoryGate.evaluate(snapshot,previous:previous) == .ready else { throw ObserverError.invalidSnapshot }
            snapshot.capturedAt = Date()
            let item = try store.save(snapshot,reason:reason,protecting:Set(recoveryJournals.filter { $0.preview.homeID == snapshot.homeID }.map(\.predecessorFile))); archives = try store.index(); health.lastBackup = item.date; if reason == .daily { health.lastDaily = item.date }; event("apple_home.backup_saved",attributes:["backup.reason":reason.rawValue,"archive.file":item.file]); health.error = nil }
        catch { health.inventoryReady = false; health.error = "backup_failed"; status = "Backup failed: \(String(describing:error))"; event("apple_home.backup_failed",attributes:[:],severity:"ERROR") }; writeHealth()
    }
    func observe(_ a: HMAccessory,_ c: HMCharacteristic?) {
        let id = a.uniqueIdentifier.uuidString
        health.unavailable = adapter.home?.accessories.filter { !$0.isReachable }.count ?? 0
        guard let c, let value = c.value as? NSNumber else { writeHealth(); return }
        let number = value.doubleValue
        if c.characteristicType == HMCharacteristicTypeCurrentPosition || c.characteristicType == HMCharacteristicTypeTargetPosition {
            let characteristics = a.services.flatMap(\.characteristics)
            func reportedValue(_ type: String) -> Double? {
                guard let number = characteristics.first(where: { $0.characteristicType == type })?.value as? NSNumber else { return nil }
                let reported = number.doubleValue
                return reported.isFinite && (0...100).contains(reported) ? reported : nil
            }
            blindReadings[id] = BlindPositionReading(current:reportedValue(HMCharacteristicTypeCurrentPosition),target:reportedValue(HMCharacteristicTypeTargetPosition),updatedAt:Date())
        }
        if c.characteristicType == HMCharacteristicTypeTargetPosition {
            // Initial/cached target is not evidence of a new command.
            if let previous = previousTargets[id], previous != number {
                let current = a.services.flatMap(\.characteristics).first { $0.characteristicType == HMCharacteristicTypeCurrentPosition }?.value as? NSNumber
                if let current {
                    let currentValue = current.doubleValue
                    if let budget = travelBudgets[id] {
                        watchdog.target(device:id,value:number,current:currentValue,now:Date().timeIntervalSince1970,travelSeconds:budget)
                        blindOutcomes[id] = abs(number - currentValue) <= 5 ? .alreadyWithinTolerance : .waiting
                    } else if abs(number - currentValue) > 5 { blindOutcomes[id] = .noMeasuredTravel }
                    event("apple_home.target_observed",attributes:["accessory.id":id,"target":number,"current":currentValue])
                }
            }
            previousTargets[id] = number
        } else if c.characteristicType == HMCharacteristicTypeCurrentPosition {
            let reachedTarget = watchdog.position(device:id,value:number)
            event("apple_home.position_observed",attributes:["accessory.id":id,"position":number])
            if reachedTarget {
                blindOutcomes[id] = .reportedTargetReached
                event("apple_home.position_target_reached",attributes:["accessory.id":id,"position":number])
            }
        }
        writeHealth()
    }
    @discardableResult func mark(_ id: String,target:Double,travel:Double) -> Bool {
        guard let a = adapter.home?.accessories.first(where: { $0.uniqueIdentifier.uuidString == id }), let current = a.services.flatMap(\.characteristics).first(where: { $0.characteristicType == HMCharacteristicTypeCurrentPosition })?.value as? NSNumber else { return false }
        // A marker records the externally issued command; this app does not move the blind.
        guard current.doubleValue.isFinite, (0...100).contains(current.doubleValue), travel.isFinite, (1...600).contains(travel), target.isFinite, (0...100).contains(target) else { return false }
        travelBudgets[id] = travel; UserDefaults.standard.set(try? Coding.encode(travelBudgets),forKey:"travelBudgets")
        watchdog.target(device:id,value:target,current:current.doubleValue,now:Date().timeIntervalSince1970,travelSeconds:travel)
        blindOutcomes[id] = abs(target - current.doubleValue) <= 5 ? .alreadyWithinTolerance : .waiting
        event("apple_home.reproduction_marker",attributes:["accessory.id":id,"target":target,"current":current.doubleValue,"travel.seconds":travel])
        return true
    }
    func chooseMonitoringExportFolder(_ selectedURL: URL) {
        let expected = Self.monitoringExportDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard selectedURL.standardizedFileURL.resolvingSymlinksInPath().path == expected.path else {
            monitoringExportStatus = "Choose the dedicated folder shown below."
            return
        }
        guard selectedURL.startAccessingSecurityScopedResource() else {
            monitoringExportStatus = "macOS did not grant access. Choose the folder again."
            return
        }
        defer { selectedURL.stopAccessingSecurityScopedResource() }
        do {
            #if targetEnvironment(macCatalyst)
            let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let bookmarkOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let bookmark = try selectedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.monitoringExportBookmarkKey)
            monitoringExportConfigured = true
            try FileManager.default.createDirectory(at: expected, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try seedMonitoringEvents(in: expected)
            exportEventsHealthy = true
            monitoringExportStatus = "Connected. Health and event logs are exporting."
            writeHealth()
        } catch {
            monitoringExportStatus = "Folder access could not be saved. Choose the folder again."
            monitoringExportConfigured = false
            UserDefaults.standard.removeObject(forKey: Self.monitoringExportBookmarkKey)
        }
    }
    func removeMonitoringExportAccess() {
        UserDefaults.standard.removeObject(forKey: Self.monitoringExportBookmarkKey)
        monitoringExportConfigured = false
        exportEventsHealthy = false
        writeHealth()
        monitoringExportStatus = "Access removed. Existing export files were left in place."
    }
    private func withMonitoringExport<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.monitoringExportBookmarkKey) else { throw ObserverError.unsafePath }
        var stale = false
        #if targetEnvironment(macCatalyst)
        let bookmarkOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let bookmarkOptions: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let logger = Logger(subsystem: ObserverConfiguration.bundleIdentifier, category: "MonitoringExport")
        let folder: URL
        do {
            folder = try URL(resolvingBookmarkData: bookmark, options: bookmarkOptions, relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            logger.error("Bookmark resolution failed, code \((error as NSError).code, privacy: .public)")
            throw error
        }
        let expected = Self.monitoringExportDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.standardizedFileURL.resolvingSymlinksInPath().path == expected.path else {
            logger.error("Bookmark rejected: dedicated folder mismatch")
            throw ObserverError.unsafePath
        }
        guard folder.startAccessingSecurityScopedResource() else {
            logger.error("Bookmark rejected: security-scoped access unavailable")
            throw ObserverError.unsafePath
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR, info.st_mode & 0o077 == 0 else {
            logger.error("Export directory rejected: ownership, permissions or type")
            throw ObserverError.unsafePath
        }
        if stale {
            #if targetEnvironment(macCatalyst)
            let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let creationOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            // Renew only the already-authorized, validated dedicated folder.
            let renewed = try folder.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(renewed, forKey: Self.monitoringExportBookmarkKey)
            logger.notice("Renewed stale monitoring folder bookmark")
        }
        return try operation(folder)
    }
    private func seedMonitoringEvents(in directory: URL) throws {
        for name in ["events.jsonl", "events.previous.jsonl"] {
            let source = root.appendingPathComponent(name)
            let destination = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path), !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try PrivateFiles.write(PrivateFiles.read(source, maximum: 4 * 1024 * 1024), to: destination)
        }
    }
    private func appendEvent(_ line: Data, in directory: URL) throws {
        let log = directory.appendingPathComponent("events.jsonl")
        if let info = try? log.resourceValues(forKeys: [.fileSizeKey]), (info.fileSize ?? 0) + line.count > 4 * 1024 * 1024 {
            let previous = directory.appendingPathComponent("events.previous.jsonl")
            if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
            try FileManager.default.moveItem(at: log, to: previous)
        }
        let fd = open(log.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw ObserverError.unsafePath }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1, (info.st_mode & S_IFMT) == S_IFREG, info.st_mode & 0o077 == 0 else { throw ObserverError.unsafePath }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: line)
    }
    func event(_ name: String, attributes: [String:Any], severity: String = "INFO") {
        guard Self.auditMode == nil else { return }
        let value: [String:Any] = ["schema":"home-network-otel-json","schema_version":1,"timestamp":ISO8601DateFormatter().string(from:Date()),"severity_text":severity,"severity_number":severity == "ERROR" ? 17 : 9,"body":name,"event_name":name,"resource":["service.name":"apple-home-observer","service.instance.id":ObserverConfiguration.bundleIdentifier,"host.name":ProcessInfo.processInfo.hostName,"deployment.environment.name":"local"],"attributes":attributes]
        do {
            let line = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data([10])
            do { try appendEvent(line, in: root); localLoggingHealthy = true }
            catch { localLoggingHealthy = false }
            if monitoringExportConfigured {
                do {
                    try withMonitoringExport { try appendEvent(line, in: $0) }
                    exportEventsHealthy = true
                } catch {
                    exportEventsHealthy = false
                    monitoringExportStatus = "Folder access needs attention. Choose the folder again."
                }
            } else { exportEventsHealthy = false }
        } catch {
            localLoggingHealthy = false
            exportEventsHealthy = false
        }
        health.loggingHealthy = localLoggingHealthy && monitoringExportConfigured && exportEventsHealthy
        writeHealth()
    }
    func writeHealth() {
        guard Self.auditMode == nil else { return }
        health.timestamp = Date()
        UserDefaults.standard.set(health.driftTotal, forKey: "driftTotal")
        UserDefaults.standard.set(health.unplannedDriftTotal, forKey: "unplannedDriftTotal")
        UserDefaults.standard.set(health.movementFailuresTotal, forKey: "movementFailuresTotal")
        health.loggingHealthy = localLoggingHealthy && monitoringExportConfigured && exportEventsHealthy
        let privateHealth = root.appendingPathComponent("health.json")
        do { try PrivateFiles.write(Coding.encode(health), to: privateHealth) }
        catch { localLoggingHealthy = false; health.loggingHealthy = false; status = "Health publication failed"; return }
        guard monitoringExportConfigured else { monitoringExportStatus = "Not connected"; return }
        do {
            try withMonitoringExport { try PrivateFiles.write(Coding.encode(health), to: $0.appendingPathComponent("health.json")) }
            monitoringExportStatus = "Connected. Health and event logs are exporting."
        } catch {
            health.loggingHealthy = false
            try? PrivateFiles.write(Coding.encode(health), to: privateHealth)
            monitoringExportStatus = "Folder access needs attention. Choose the folder again."
        }
    }
    struct MappingChoice: Identifiable { var id:String; var name:String; var candidates:[NamedObject] }
    var mappingChoices: [MappingChoice] {
        guard let saved = savedForRestore, let current = inventory else { return [] }
        var choices: [MappingChoice] = []
        for a in saved.accessories {
            let targetID = restoreMappings[a.id] ?? a.id
            if !current.accessories.contains(where: { $0.id == a.id }) { choices.append(.init(id:a.id,name:"Accessory: " + a.name,candidates:current.accessories.map { .init(id:$0.id,name:$0.name) })) }
            guard let target = current.accessories.first(where: { $0.id == targetID }) else { continue }
            for s in a.services {
                let serviceID = restoreMappings[s.id] ?? s.id
                if !target.services.contains(where: { $0.id == s.id }) { choices.append(.init(id:s.id,name:"Service: " + s.name,candidates:target.services.filter { $0.type == s.type }.map { .init(id:$0.id,name:$0.name) })) }
                guard let t = target.services.first(where: { $0.id == serviceID }) else { continue }
                for c in s.characteristics where !t.characteristics.contains(where: { $0.id == c.id }) {
                    choices.append(.init(id:c.id,name:"Characteristic: " + c.type,candidates:t.characteristics.filter { $0.type == c.type }.map { .init(id:$0.id,name:$0.type + " " + $0.id) }))
                }
            }
        }
        return choices
    }
    func importArchive(_ url: URL) {
        guard Self.auditMode == nil else { status = "Sample snapshot import verified"; return }
        recoveryJournalID = nil
        do {
            importedArchive = try PrivateFiles.read(url,maximum:ArchiveCodec.maximumBytes)
            guard let data = importedArchive, let key = importRecoveryKey ?? key else { throw ObserverError.invalidArchive }
            savedForRestore = try ArchiveCodec.open(data,key:key); rebuildPreview()
        } catch { status = "Archive could not be authenticated. Import its private recovery key if this is from another installation."; preview = nil }
    }
    func importRecovery(_ url: URL) {
        guard Self.auditMode == nil else { status = "Sample recovery-key import verified"; return }
        do {
            let data = try PrivateFiles.read(url,maximum:128)
            importRecoveryKey = try RecoveryKeyCodec.decode(data)
            if let encrypted = importedArchive { savedForRestore = try ArchiveCodec.open(encrypted,key:importRecoveryKey!); rebuildPreview() }
        } catch { status = "Recovery-key import failed. Check its format and owner-only file permissions."; preview = nil }
    }
    func rebuildPreview() {
        do { guard let saved = savedForRestore else { throw ObserverError.invalidArchive }; preview = try RestorePlanner.preview(saved:saved,current:adapter.snapshot(),mappings:restoreMappings.filter { !$0.value.isEmpty }) }
        catch { status = "Preview refused: \(String(describing:error))"; preview = nil }
    }
    func makePreview(_ item: SnapshotIndex) {
        if Self.auditMode != nil, let inventory { var saved = inventory; saved.name = "Sample restored Home"; savedForRestore = saved; preview = try? RestorePlanner.preview(saved: saved, current: inventory); return }
        do { guard let store else { throw ObserverError.invalidArchive }; let saved = try store.load(item); let current = try adapter.snapshot(); recoveryJournalID = nil; restoreMappings = [:]; savedForRestore = saved; preview = try RestorePlanner.preview(saved:saved,current:current) }
        catch { status = "Preview failed: \(String(describing:error))"; preview = nil }
    }
}
