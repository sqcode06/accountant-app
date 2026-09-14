import SwiftUI

/// Switches the home-screen icon between the six colourways.
///
/// Deliberately *not* tied to the theme picker. Changing the icon makes iOS show
/// a system alert every single time — "You have changed the icon for…" — which
/// cannot be suppressed. Firing that on every theme change would make trying
/// themes actively unpleasant, so picking an icon is its own explicit act.
@MainActor
final class AppIconManager: ObservableObject {

    struct Option: Identifiable, Hashable {
        /// Matches the theme id, so the picker can draw each in its own colours.
        let id: String
        let name: String

        /// The asset-catalog name, or nil for the primary icon.
        ///
        /// iOS models "the default icon" as `nil` rather than a name, so this
        /// mirrors that instead of inventing a sentinel.
        let alternateName: String?
    }

    static let options: [Option] = [
        Option(id: "cobalt", name: "Cobalt", alternateName: nil),
        Option(id: "ember", name: "Ember", alternateName: "AppIcon-Ember"),
        Option(id: "graphite", name: "Graphite", alternateName: "AppIcon-Graphite"),
        Option(id: "indigo", name: "Indigo", alternateName: "AppIcon-Indigo"),
        Option(id: "moss", name: "Moss", alternateName: "AppIcon-Moss"),
        Option(id: "paper", name: "Paper", alternateName: "AppIcon-Paper")
    ]

    @Published private(set) var currentAlternateName: String?
    @Published private(set) var lastFailure: String?

    init() {
        currentAlternateName = UIApplication.shared.alternateIconName
    }

    var isSupported: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var currentOption: Option {
        Self.options.first { $0.alternateName == currentAlternateName } ?? Self.options[0]
    }

    func select(_ option: Option) async {
        guard isSupported, option.alternateName != currentAlternateName else { return }

        do {
            try await UIApplication.shared.setAlternateIconName(option.alternateName)
            currentAlternateName = option.alternateName
            lastFailure = nil
        } catch {
            // Read the truth back rather than assuming the change stuck.
            currentAlternateName = UIApplication.shared.alternateIconName
            lastFailure = error.localizedDescription
        }
    }
}
