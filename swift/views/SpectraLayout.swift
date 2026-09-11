import SwiftUI

/// Shared layout and Liquid Glass tokens. [docs/iosUI.md](../../docs/iosUI.md)
/// is the authority for every value here; this file is where the document is
/// spelled in Swift, so a screen never restates a number the document owns.
enum SpectraLayout {
    static let screenHorizontal: CGFloat = 14
    static let screenTop: CGFloat = 6
    static let screenBottom: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let cardHeaderVertical: CGFloat = 12
    static let rowHorizontal: CGFloat = 16
    static let rowVertical: CGFloat = 9

    /// Corner radii. The radius communicates hierarchy: a surface nested inside
    /// another takes the next step down, so the steps are named for the surface
    /// rather than the number.
    enum Radius {
        /// Top-level tab cards, hero and header cards.
        static let hero: CGFloat = 28
        /// Ordinary detail cards, nested content cards, grouped list containers.
        static let card: CGFloat = 24
        /// Compact row cards and inline notice banners.
        static let compact: CGFloat = 22
        /// Full-size inputs and inset address blocks.
        static let input: CGFloat = 18
        /// Compact inputs, chips and small nested surfaces.
        static let chip: CGFloat = 16
        /// Inline pills, dense inputs and small tinted surfaces.
        static let pill: CGFloat = 14
        /// Dense controls, icon backplates and single-character slots.
        static let control: CGFloat = 10
    }

    /// Liquid Glass tints. Two neutral steps and no third: a surface is either
    /// elevated or it is content. Accent-tinted glass (an orange or red notice)
    /// carries its own colour and is not one of these.
    enum GlassTint {
        /// Hero and header cards, inputs, chips and icon backplates.
        static let elevated: Color = .white.opacity(0.04)
        /// Ordinary content cards.
        static let content: Color = .white.opacity(0.03)
    }
}

extension View {
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
    func spectraElevatedFill(cornerRadius: CGFloat = SpectraLayout.Radius.hero) -> some View {
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
