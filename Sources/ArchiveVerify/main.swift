import Foundation
import CryptoKit
import ObserverCore

// Offline verification only. Key bytes are read from a private file, never arguments or output.
let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard arguments.count == 4, arguments[0] == "--archive", arguments[2] == "--key-file" else {
        throw NSError(domain:"usage: aho-verify --archive PATH --key-file PRIVATE_PATH",code:2)
    }
    let keyData = try PrivateFiles.read(URL(fileURLWithPath:arguments[3]),maximum:128)
    let key = try RecoveryKeyCodec.decode(keyData)
    let encrypted = try PrivateFiles.read(URL(fileURLWithPath:arguments[1]),maximum:ArchiveCodec.maximumBytes)
    let snapshot = try ArchiveCodec.open(encrypted,key:key)
    print("Authenticated archive verified: \(snapshot.accessories.count) accessories, \(snapshot.scenes.count) scenes, \(snapshot.automations.count) automations, \(snapshot.coverage.count) coverage notices.")
} catch {
    // Do not print arbitrary file contents, key material, Home names or serial numbers.
    FileHandle.standardError.write(Data("Archive verification failed; check paths, owner-only permissions, recovery key and archive integrity.\n".utf8))
    exit(1)
}
