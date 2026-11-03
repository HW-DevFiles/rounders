// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RoundersSim", platforms: [.iOS(.v17), .macOS(.v14)], products: [
 .library(name: "RoundersSim", targets: ["RoundersSim"]),
 .library(name: "RoundersContent", targets: ["RoundersContent"]),
 .library(name: "RoundersInput", targets: ["RoundersInput"]),
 .executable(name: "ReplayCheck", targets: ["ReplayCheck"])
], targets: [
 .target(name: "RoundersSim"),
 .target(name: "RoundersContent", dependencies: ["RoundersSim"], resources: [.process("Resources")]),
 .target(name: "RoundersInput", dependencies: ["RoundersSim"]),
 .executableTarget(name: "ReplayCheck", dependencies: ["RoundersSim", "RoundersContent"]),
 .testTarget(name: "RoundersSimTests", dependencies: ["RoundersSim", "RoundersContent", "RoundersInput"])
])
