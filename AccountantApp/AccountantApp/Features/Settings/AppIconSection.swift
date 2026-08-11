import SwiftUI

/// Home-screen icon picker, sitting under Appearance beside the theme swatches.
///
/// Each option is drawn with `BrandMark` in that theme's own brand colours rather
/// than loading the packaged PNG. Alternate app icon assets are not reliably
/// addressable as ordinary images at runtime, and the mark is vector anyway — so
/// the preview is the same geometry the icon is generated from.
struct AppIconSection: View {
    @EnvironmentObject private var iconManager: AppIconManager

    var body: some View {
        Section {
            if iconManager.isSupported {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.Space.m) {
                        ForEach(AppIconManager.options) { option in
                            Button {
                                Task { await iconManager.select(option) }
                            } label: {
                                IconSwatch(
                                    option: option,
                                    isSelected: option.id == iconManager.currentOption.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                            .accessibilityAddTraits(
                                option.id == iconManager.currentOption.id ? [.isSelected] : []
                            )
                        }
                    }
                    .padding(.vertical, Metrics.Space.xs)
                }
                .listRowInsets(EdgeInsets(
                    top: Metrics.Space.s,
                    leading: Metrics.Space.l,
                    bottom: Metrics.Space.s,
                    trailing: 0
                ))

                if let failure = iconManager.lastFailure {
                    Text(failure)
                        .font(.uiCaption)
                        .foregroundStyle(Theme.deficit)
                }
            } else {
                Text("This device does not support changing the app icon.")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
        } header: {
            Text("App icon")
        } footer: {
            Text("iOS shows a confirmation the first time an app changes its icon. Picking one here does not change your theme.")
        }
    }
}

private struct IconSwatch: View {
    let option: AppIconManager.Option
    let isSelected: Bool

    var body: some View {
        let palette = ThemeCatalog.theme(id: option.id).light
            ?? ThemeCatalog.theme(id: option.id).dark
            ?? ThemeCatalog.cobalt.dark!

        VStack(spacing: Metrics.Space.xs) {
            BrandMark(
                size: 60,
                ground: Color(rgb: palette.brandGround),
                ink: Color(rgb: palette.brandInk)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 60 * 0.2237, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.hairline,
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            }

            Text(option.name)
                .font(.uiCaption)
                .foregroundStyle(isSelected ? Theme.ink : Theme.inkMuted)
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
