import SwiftUI

/// One chain in a picker: badge, name, tags, gas token and a trailing mark.
///
/// Drawn inside a `SpectraRowGroup`, by the setup page's short list and by the
/// full list behind it, so the two cannot drift into different shapes.
struct ChainSelectionRow: View {
    let descriptor: ChainSelectionDescriptor
    let isSelected: Bool
    /// A multi-select list marks unselected rows with an empty circle, so the
    /// rows read as toggles; a single choice marks only the chosen row.
    let allowsMultipleSelection: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            spectraHaptic(.light)
            toggle()
        } label: {
            HStack(spacing: SpectraLayout.Space.m) {
                CoinBadge(
                    artworkName: descriptor.artworkName, fallbackText: descriptor.symbol,
                    color: descriptor.color, size: 36
                )
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(descriptor.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(descriptor.tagLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: SpectraLayout.Space.s)
                Text(descriptor.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SpectraLayout.Space.s)
                    .padding(.vertical, SpectraLayout.Space.xs)
                    .background(Capsule(style: .continuous).fill(SpectraLayout.insetFill))
                selectionMark
            }
            .spectraRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.tint)
        } else if allowsMultipleSelection {
            Image(systemName: "circle").font(.title3).foregroundStyle(.tertiary)
        }
    }
}
