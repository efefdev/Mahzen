// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Mahzen",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mahzen", targets: ["Mahzen"]),
    ],
    targets: [
        // Argon2 resmi referans uygulaması (CC0/Apache-2.0), değiştirilmeden alındı. Bkz. KAYNAK.txt
        .target(name: "CArgon2", exclude: ["LICENSE", "KAYNAK.txt"]),
        // Şifreleme ve kasa biçimi: arayüzden bağımsız, testlenebilir çekirdek.
        .target(name: "MahzenCore", dependencies: ["CArgon2"]),
        .executableTarget(name: "Mahzen", dependencies: ["MahzenCore"]),
        .testTarget(name: "MahzenCoreTests", dependencies: ["MahzenCore"]),
    ]
)
