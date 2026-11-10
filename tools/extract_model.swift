// SPDX-License-Identifier: GPL-3.0-or-later
// Recover a Core Data model (.momd) from the Z_MODELCACHE table of a Core Data SQLite store,
// verify it with Core Data's own compatibility check, and write it as a .momd directory.
//
//   extract_model selftest <scratch_dir>
//   extract_model extract  <store.sqlite (a COPY)> <out.momd>
//
// Never writes to the input store (opened read-only / immutable).
import CoreData
import Foundation
import SQLite3

func die(_ msg: String) -> Never { FileHandle.standardError.write((msg + "\n").data(using: .utf8)!); exit(1) }

func readModelCache(_ path: String) -> Data? {
    var db: OpaquePointer?
    let uri = "file:\(path)?immutable=1"
    guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT Z_CONTENT FROM Z_MODELCACHE LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
        print("no Z_MODELCACHE table: \(String(cString: sqlite3_errmsg(db)))"); return nil
    }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_blob(stmt, 0) else { print("Z_MODELCACHE empty"); return nil }
    return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, 0)))
}

func candidates(_ d: Data) -> [(String, Data)] {
    var out: [(String, Data)] = [("raw", d)]
    let algs: [(String, NSData.CompressionAlgorithm)] = [("zlib", .zlib), ("lzfse", .lzfse), ("lzma", .lzma), ("lz4", .lz4)]
    var inputs: [(String, Data)] = [("", d)]
    if d.count > 2 && d[d.startIndex] == 0x78 { inputs.append(("hdr-stripped ", d.dropFirst(2))) }  // zlib header
    for (prefix, input) in inputs {
        for (name, alg) in algs {
            if let x = try? (input as NSData).decompressed(using: alg) as Data, !x.isEmpty { out.append((prefix + name, x)) }
        }
    }
    return out
}

func unarchiveModel(_ d: Data) -> NSManagedObjectModel? {
    guard let u = try? NSKeyedUnarchiver(forReadingFrom: d) else { return nil }
    u.requiresSecureCoding = false
    let obj = u.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    u.finishDecoding()
    if let m = obj as? NSManagedObjectModel { return m }
    if let o = obj { print("  archive root is \(type(of: o)), not NSManagedObjectModel") }
    return nil
}

func storeMetadata(_ url: URL) -> [String: Any] {
    do {
        return try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: [NSReadOnlyPersistentStoreOption: true])
    } catch { die("cannot read store metadata: \(error)") }
}

func extract(store: String, out: String, name: String) {
    let storeURL = URL(fileURLWithPath: store)
    guard let blob = readModelCache(store) else { die("FAIL: no model cache in store") }
    let head = blob.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
    print("Z_MODELCACHE blob: \(blob.count) bytes, starts: \(head)")
    var model: NSManagedObjectModel?
    for (how, data) in candidates(blob) {
        if let m = unarchiveModel(data) { print("  decoded via: \(how)"); model = m; break }
    }
    guard let model = model else { die("FAIL: could not decode the cached model") }
    let meta = storeMetadata(storeURL)
    let compatible = model.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta)
    print("entities: \(model.entities.count)   compatible with store metadata: \(compatible)")
    guard compatible else { die("FAIL: cached model does not match the store") }

    let momd = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: momd)
    do {
        try FileManager.default.createDirectory(at: momd, withIntermediateDirectories: true)
        let mom = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        try mom.write(to: momd.appendingPathComponent("\(name).mom"))
        let info: [String: Any] = ["NSManagedObjectModel_CurrentVersionName": name,
                                   "NSManagedObjectModel_VersionHashes": [name: model.entityVersionHashesByName]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            .write(to: momd.appendingPathComponent("VersionInfo.plist"))
    } catch { die("FAIL writing momd: \(error)") }

    guard let reloaded = NSManagedObjectModel(contentsOf: momd) else { die("FAIL: written .momd does not load") }
    let ok = reloaded.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta)
    print("reloaded \(momd.lastPathComponent): entities=\(reloaded.entities.count) compatible=\(ok)")
    guard ok else { die("FAIL: reloaded .momd not compatible") }
    print("OK: \(out)")
}

func selftest(dir: String) {
    let d = URL(fileURLWithPath: dir)
    try? FileManager.default.removeItem(at: d)
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let model = NSManagedObjectModel()
    let e = NSEntityDescription(); e.name = "Thing"; e.managedObjectClassName = "NSManagedObject"
    let a = NSAttributeDescription(); a.name = "title"; a.attributeType = .stringAttributeType; a.isOptional = true
    let n = NSAttributeDescription(); n.name = "when"; n.attributeType = .dateAttributeType; n.isOptional = true
    e.properties = [a, n]
    model.entities = [e]
    let storeURL = d.appendingPathComponent("Test.sqlite")
    let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
    let store = try! psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL,
                                            options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]])
    let moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    moc.persistentStoreCoordinator = psc
    let o = NSEntityDescription.insertNewObject(forEntityName: "Thing", into: moc)
    o.setValue("hello", forKey: "title"); o.setValue(Date(), forKey: "when")
    try! moc.save()
    try! psc.remove(store)
    print("selftest store created")
    extract(store: storeURL.path, out: d.appendingPathComponent("Test.momd").path, name: "Test")
}

let args = CommandLine.arguments
if args.count == 3 && args[1] == "selftest" { selftest(dir: args[2]) }
else if args.count == 4 && args[1] == "extract" { extract(store: args[2], out: args[3], name: "WhatsAppChat") }
else { die("usage: extract_model selftest <dir> | extract <store.sqlite> <out.momd>") }
