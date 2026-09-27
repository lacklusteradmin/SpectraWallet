import SwiftUI

/// One card holding a list, one row per element, with inset dividers between
/// rows — the list the home and history tabs draw.
///
/// A list is rows in a card, never a card per row: a card of cards stacks
/// glass on glass, and a column of cards spends a card's padding and gap on
/// every row. Each row applies `spectraRowPadding()` inside its own button
/// label, so the padding is part of the tap target.
struct SpectraRowGroup<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var title: String? = nil
    /// Right of the title, such as a count.
    var trailing: String? = nil
    let data: Data
    /// Where a divider starts. The default runs it under the text of a row
    /// that leads with a 36pt badge.
    var dividerInset: CGFloat = SpectraLayout.rowDividerInset
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack(spacing: SpectraLayout.Space.s) {
                    Text(title).font(.headline)
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.horizontal, SpectraLayout.rowHorizontal)
                .padding(.vertical, SpectraLayout.cardHeaderVertical)
                Divider().opacity(0.25)
            }
            // Lazy so a long list, such as the wiki's, builds only the rows on screen.
            LazyVStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                    row(element)
                    if index < data.count - 1 {
                        Divider().padding(.leading, dividerInset).opacity(0.25)
                    }
                }
            }
            .padding(.vertical, SpectraLayout.Space.xs)
        }
        .frame(maxWidth: .infinity)
        .spectraCardFill()
    }
}
