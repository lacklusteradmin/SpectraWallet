# iOS UI reference

Spectra targets iOS 26 with system typography, rich color and Liquid Glass.

This document is the source of truth for Spectra's iOS UI rules.

## Product decision

Apple describes Liquid Glass as a distinct functional layer for controls and navigation and advises against using it in the content layer. Spectra intentionally departs from that guidance by placing important body content on glass cards over `SpectraBackdrop`.

That departure is deliberate, not an interpretation of Apple's recommendation. Keep the hierarchy legible, avoid stacking glass on glass, and limit custom glass effects when a standard system control already provides the correct behavior.

Official references:

- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)

## Design baseline

- **Backdrop:** Keep `SpectraBackdrop` behind every top-level tab. Re-add it at main business detail roots such as asset, wallet, staking, and receive destinations. Settings-style utility details may continue to use system `Form` layouts.
- **Top-level tabs:** Use `ScrollView` plus glass cards with internal dividers. Do not use `List(.insetGrouped)` or `Form` for a main tab.
- **Chrome:** Hide the navigation bar background with `.toolbarBackground(.hidden, for: .navigationBar)` when content should scroll beneath it.
- **Toolbar actions:** Use standard `ToolbarItem` buttons and menus. iOS 26 places toolbar items on Liquid Glass automatically, so do not add `.buttonStyle(.glass)` inside a toolbar.
- **Cards:** Use a subtle white glass tint. Hero cards use `0.04`; ordinary content cards use `0.03`.
- **Buttons:** Use `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` for stand-alone actions outside toolbars. Tint primary actions orange and destructive actions red.
- **Typography:** Use system text styles such as `.largeTitle.weight(.bold)`, `.title`, `.headline`, and `.body`.
- **Text colors:** Use semantic styles such as `.primary`, `.secondary`, `.tertiary`, and `.quaternary`. Do not use `Color.primary.opacity(...)` for text.
- **Artwork exception:** Decorative icon artwork, including `SpectraLogo`, may use custom fonts, color opacity, and glass effects.

## Corner radii

The radius communicates hierarchy:

| Radius | Usage |
| --- | --- |
| 28pt | Top-level tab cards and hero/header cards |
| 24pt | Ordinary detail cards, nested content cards, `spectraCardFill`, and `spectraDetailCard` |
| 22pt | Compact interactive row cards |
| 16–18pt | Inputs, inset address blocks, chips, and small nested surfaces |
| 10–14pt | Inline pills, icon backplates, and dense controls |
| size-relative | Icon artwork such as the `SpectraLogo` backing |

Shared values and helpers live in:

- [`SpectraLayout` and `spectraCardFill`](../swift/views/ImageRendering.swift)
- [`spectraInputFieldStyle` and `spectraDetailCard`](../swift/views/ViewExtensions.swift)

## Examples in the app

- [DashboardViews.swift](../swift/views/DashboardViews.swift): top-level tab,
  hero cards and asset detail rows.
- [ReceiveFlowViews.swift](../swift/views/ReceiveFlowViews.swift): business detail layout.
- [ChainWikiViews.swift](../swift/views/ChainWikiViews.swift): compact interactive cards.

Use `SpectraLayout` for top-level spacing and padding. Main business details use
20pt horizontal, 16pt top and 24pt bottom padding, with 16pt between cards;
card content has 20pt padding. Detail navigation titles are inline.

Detail key/value rows use an orange SF Symbol, a secondary label and a primary
value, 12pt row spacing and dividers at 0.4 opacity. Group adjacent glass actions
with `GlassEffectContainer(spacing: 12)`.

## Additional constraints

- Rounded black display typography is reserved for icon artwork.
- Avoid custom glass on every small element or stacked glass surfaces.
- Do not add `.ultraThinMaterial` or `.thinMaterial` where `.glassEffect` is appropriate.
