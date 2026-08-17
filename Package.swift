// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "searchads-sdk",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SearchAdsKit", targets: ["SearchAdsKit"]),
    ],
    targets: [
        .target(name: "SearchAdsKit"),
    ]
)
