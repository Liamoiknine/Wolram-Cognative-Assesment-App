// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CognitiveAssessmentApp",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CognitiveAssessmentApp",
            targets: ["CognitiveAssessmentApp"]
        )
    ],
    targets: [
        .target(
            name: "CognitiveAssessmentApp",
            path: "Sources"
        )
    ]
)

