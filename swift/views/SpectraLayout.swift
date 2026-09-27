import SwiftUI

/// Shared layout and Liquid Glass tokens. [docs/IOS-UI.md](../../docs/IOS-UI.md)
/// is the authority for every value here; this file is where the document is
/// spelled in Swift, so a screen never restates a number the document owns.
enum SpectraLayout {
    /// The spacing scale. Every padding, stack spacing and spacer minimum in a
    /// view is one of these steps; the named layout values below are steps too.
    enum Space {
        /// Between two lines of one text pair (title over subtitle).
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let screenHorizontal: CGFloat = Space.l
    static let screenTop: CGFloat = Space.s
    static let screenBottom: CGFloat = Space.l
    static let sectionSpacing: CGFloat = Space.m
    static let cardPadding: CGFloat = Space.l
    static let cardHeaderVertical: CGFloat = Space.m
    static let rowHorizontal: CGFloat = Space.l
    static let rowVertical: CGFloat = Space.s
    /// Where a row divider starts: the row inset, a 36pt badge and the gap
    /// after it, so the line runs under the text rather than the badge.
    static let rowDividerInset: CGFloat = rowHorizontal + 36 + Space.m

    /// Corner radii. Three steps, named for the surface: a surface nested
    /// inside another takes the next step down.
    enum Radius {
        /// Cards of every kind: tab and hero cards, detail cards, row cards
        /// and inline notice banners.
        static let card: CGFloat = 20
        /// Surfaces inside a card: inputs, address blocks, chips and pills.
        static let inner: CGFloat = 14
        /// Dense controls, icon backplates and single-character slots.
        static let control: CGFloat = 10
    }

    /// Liquid Glass tints. Two neutral steps and no third: a surface is either
    /// elevated or it is content. Coloured glass (an accent, warning or red
    /// notice) carries its own colour and is not one of these.
    enum GlassTint {
        /// Hero and header cards, inputs, chips and icon backplates.
        static let elevated: Color = .white.opacity(0.04)
        /// Ordinary content cards.
        static let content: Color = .white.opacity(0.03)
    }
}

/// Semantic colours that must not follow the theme. The theme colour is the
/// asset catalog's AccentColor, written `.tint` or `Color.accentColor`; a
/// warning has to read as a warning whatever that colour is, so it is fixed
/// here. Declared on `ShapeStyle` so `.spectraWarning` works both where a
/// `Color` and where any shape style is expected.
extension ShapeStyle where Self == Color {
    /// Pending, in-progress and incomplete states, and warnings.
    static var spectraWarning: Color { .orange }
}

extension View {
    /// The screen inset every scrolling page uses, top-level tab or detail.
    func spectraScreenPadding() -> some View {
        padding(.horizontal, SpectraLayout.screenHorizontal)
            .padding(.top, SpectraLayout.screenTop)
            .padding(.bottom, SpectraLayout.screenBottom)
    }

    func spectraNumericTextLayout(minimumScaleFactor: CGFloat = 0.62) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScaleFactor).allowsTightening(true)
    }

    /// Ordinary content card: the content tint on the card radius.
    func spectraCardFill(cornerRadius: CGFloat = SpectraLayout.Radius.card) -> some View {
        glassEffect(.regular.tint(SpectraLayout.GlassTint.content), in: .rect(cornerRadius: cornerRadius))
    }

    /// Elevated glass surface: hero and header cards, and the smaller
    /// interactive surfaces — inputs, chips, icon backplates — that sit above
    /// content rather than being content.
    func spectraElevatedFill(cornerRadius: CGFloat = SpectraLayout.Radius.card) -> some View {
        glassEffect(.regular.tint(SpectraLayout.GlassTint.elevated), in: .rect(cornerRadius: cornerRadius))
    }

    /// A selectable surface whose selected state is an opaque accent fill.
    /// Glass is the unselected state only: where the selected label is white
    /// text, the fill behind it has to stay opaque to keep the label legible,
    /// so that state is a solid accent rather than an accent-tinted glass.
    @ViewBuilder
    func spectraSelectableFill(isSelected: Bool, accent: Color, cornerRadius: CGFloat) -> some View {
        if isSelected {
            background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(accent))
        } else {
            spectraElevatedFill(cornerRadius: cornerRadius)
        }
    }
}
