import SwiftUI

/// Theme selection, designed to be embedded at the top of Settings.
///
/// Inline rather than a pushed screen, for a mechanical reason. Changing theme has
/// to force a rebuild — `Theme` resolves through a static that SwiftUI's dependency
/// tracking cannot see — and a rebuild pops navigation. A pushed picker would eject
/// you the instant you tapped a theme, so trying three would mean three round
/// trips. Inline, the rebuild lands you exactly where you were.
struct ThemeSection: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.Space.m) {
                    ForEach(ThemeCatalog.all) { theme in
                        Button {
                            themeManager.select(theme)
                        } label: {
                            ThemeSwatch(
                                theme: theme,
                                isSelected: theme.id == themeManager.theme.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.name)
                        .accessibilityAddTraits(
                            theme.id == themeManager.theme.id ? [.isSelected] : []
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.Space.xs) {
                    Text(themeManager.theme.name)
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)

                    if themeManager.theme.supportsBothAppearances {
                        Text("· follows system")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkFaint)
                    }
                }

                Text(themeManager.theme.blurb)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.vertical, Metrics.Space.xs)
        } header: {
            Text("Appearance")
        }
    }
}

/// A miniature of the theme, drawn from *its* palette rather than the active one,
/// so each swatch shows what it would actually look like.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        let palette = theme.light ?? theme.dark ?? ThemeCatalog.cobalt.dark!

        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(UIColor(rgb: palette.ink)))
                .frame(width: 30, height: 5)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(UIColor(rgb: palette.inkMuted)))
                .frame(width: 18, height: 4)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color(UIColor(rgb: palette.accent)))
                    .frame(width: 9, height: 9)

                Circle()
                    .fill(Color(UIColor(rgb: palette.inflow)))
                    .frame(width: 9, height: 9)

                Circle()
                    .fill(Color(UIColor(rgb: palette.pending)))
                    .frame(width: 9, height: 9)
            }
        }
        .padding(Metrics.Space.s)
        .frame(width: 64, height: 64, alignment: .topLeading)
        .background(
            Color(UIColor(rgb: palette.canvas)),
            in: RoundedRectangle(cornerRadius: Metrics.Radius.inset, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.inset, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : Color(UIColor(rgb: palette.hairline)),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent, Theme.surface)
                    .offset(x: 5, y: 5)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
