// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AppleHomeObserver", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "ObserverCore", targets: ["ObserverCore"]), .executable(name:"aho-verify",targets:["ArchiveVerify"])], targets: [.target(name: "ObserverCore"), .executableTarget(name:"ArchiveVerify",dependencies:["ObserverCore"]), .testTarget(name: "ObserverCoreTests", dependencies: ["ObserverCore"])])
