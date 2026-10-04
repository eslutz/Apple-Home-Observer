import SwiftUI
import UniformTypeIdentifiers

struct PrivateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { guard let d = configuration.file.regularFileContents else { throw ObserverError.invalidArchive }; data = d }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
