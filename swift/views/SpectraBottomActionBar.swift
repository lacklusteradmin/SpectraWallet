import SwiftUI

/// The bar carrying a flow's back and primary actions, pinned under its
/// content with `safeAreaInset(edge: .bottom)`.
///
/// One implementation for the setup, send and receive flows, which had three.
/// They disagreed on the two things that decide how the bar meets the screen,
/// and each got one of them right:
///
/// - **What it is made of.** Send and receive used `.background(.regularMaterial)`,
///   an opaque slab that flattens the backdrop where
///   [docs/IOS-UI.md](../../docs/IOS-UI.md) asks for glass.
/// - **Where it stops.** `background(_ style:)` ignores the safe area by
///   default, which is the only reason those two reached the bottom edge.
///   Setup's `glassEffect` is clipped to the bar's own bounds, so its glass
///   ended in a seam above the tab bar with the backdrop showing below it.
///
/// Glass, in a background that ignores the bottom edge, is both at once.
struct SpectraBottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 12) { content }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background {
            Color.clear
                .glassEffect(.regular.tint(SpectraLayout.GlassTint.elevated), in: Rectangle())
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
