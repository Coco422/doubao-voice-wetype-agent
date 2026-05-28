// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "doubao-voice-wetype-agent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "doubao-voice-wetype-agent", targets: ["DoubaoVoiceWeTypeAgent"]),
        .executable(name: "im-switch", targets: ["IMSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "DoubaoVoiceWeTypeAgent",
            path: "Sources/DoubaoVoiceWeTypeAgent",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "IMSwitch",
            path: "Sources/IMSwitch"
        )
    ]
)
