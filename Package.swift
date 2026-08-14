// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SoundOneControl",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "SoundOneControl", targets: ["SoundOneControl"]),
    .executable(name: "SoundOneBluetoothAgent", targets: ["SoundOneBluetoothAgent"]),
  ],
  targets: [
    .executableTarget(
      name: "SoundOneControl",
      path: "Sources/SoundOneControl",
      linkerSettings: [
        .linkedFramework("Carbon"),
        .linkedFramework("IOBluetooth"),
      ]
    ),
    .testTarget(
      name: "SoundOneControlTests",
      dependencies: ["SoundOneControl"],
      path: "Tests/SoundOneControlTests"
    ),
    .executableTarget(
      name: "SoundOneBluetoothAgent",
      path: "Sources/SoundOneBluetoothAgent",
      linkerSettings: [.linkedFramework("IOBluetooth")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
