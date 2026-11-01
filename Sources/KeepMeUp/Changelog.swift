import Foundation

struct ChangelogEntry: Identifiable {
    let version: String
    let items: [String]
    var id: String { version }
}

enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "1.5.4", items: [
            "Settings matches the menu's glass and color.",
            "A running timer shows its progress as a ring.",
            "A bigger About page with this changelog.",
        ]),
        ChangelogEntry(version: "1.5.2", items: [
            "The menu opens centered under the icon, with an arrow.",
            "A floating tab bar in Settings that slides between tabs.",
            "Timers say plainly what happens when they end.",
        ]),
        ChangelogEntry(version: "1.5.1", items: [
            "A new, simpler app icon.",
        ]),
        ChangelogEntry(version: "1.5.0", items: [
            "Keep running with the lid closed while charging.",
            "Only one KeepMeUp shows up in Spotlight.",
        ]),
        ChangelogEntry(version: "1.4.0", items: [
            "Permission buttons in the Commands tab.",
            "Native Apple Silicon build.",
            "The menu shows the Telegram connection status.",
        ]),
        ChangelogEntry(version: "1.3.0", items: [
            "Media, volume, brightness, Wi-Fi, clipboard and webcam commands.",
            "Battery, charger and online alerts, and daily schedules.",
        ]),
    ]
}
