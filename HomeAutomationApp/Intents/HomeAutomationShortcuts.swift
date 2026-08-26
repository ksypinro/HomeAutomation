import AppIntents

/// Surfaces the intent in Shortcuts and Spotlight, and gives Siri phrases to
/// match against.
///
/// Every phrase must contain `\(.applicationName)` — that is a hard runtime
/// requirement, not a style choice.
struct HomeAutomationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResolveHomeCommandIntent(),
            phrases: [
                "Run a home command in \(.applicationName)",
                "Ask \(.applicationName) to run a command",
                "\(.applicationName) command"
            ],
            shortTitle: "Run Home Command",
            systemImageName: "house.fill"
        )
    }
}
