# iOS UI reference

Spectra targets iOS 26 with a fintech-native visual language: Coinbase / Robinhood / Revolut DNA, system typography, rich color, and Liquid Glass used more aggressively than Apple uses it in first-party apps.

This document is the source of truth for Spectra's iOS UI rules. [AGENTS.md](../AGENTS.md) only points here to avoid duplicating design guidance.

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
- [`spectraInputFieldStyle` and `spectraDetailCard`](../swift/ViewExtensions.swift)

## Source map

Use these files as current examples. This list intentionally avoids line numbers because UI files move frequently.

Top-level tab patterns:

- [DashboardViews.swift](../swift/views/DashboardViews.swift)
- [HistoryView.swift](../swift/views/HistoryView.swift)
- [StakingView.swift](../swift/views/StakingView.swift)
- [SettingsViews.swift](../swift/views/SettingsViews.swift)

Hero and detail card patterns:

- [DashboardViews.swift](../swift/views/DashboardViews.swift) for asset details
- [WalletFlowViews.swift](../swift/views/WalletFlowViews.swift) for wallet details
- [StakingView.swift](../swift/views/StakingView.swift) for staking details
- [ReceiveFlowViews.swift](../swift/views/ReceiveFlowViews.swift) for receive details
- [ChainWikiViews.swift](../swift/views/ChainWikiViews.swift) for compact interactive cards
- [DonationsView.swift](../swift/views/DonationsView.swift) and [AboutView.swift](../swift/views/AboutView.swift) for informational pages

Artwork and backdrop:

- [ImageRendering.swift](../swift/views/ImageRendering.swift)

## Patterns

### Top-level tab

```swift
NavigationStack {
    ZStack {
        SpectraBackdrop().ignoresSafeArea()
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: SpectraLayout.sectionSpacing) {
                contentCard
            }
            .padding(.horizontal, SpectraLayout.screenHorizontal)
            .padding(.top, SpectraLayout.screenTop)
            .padding(.bottom, SpectraLayout.screenBottom)
        }
    }
    .navigationTitle(...)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button { ... } label: { Image(systemName: "plus") }
        }
    }
}
```

Top-level cards use the shared `28pt` radius:

```swift
VStack { ... }
    .padding(SpectraLayout.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(
        .regular.tint(.white.opacity(0.03)),
        in: .rect(cornerRadius: SpectraLayout.cardCornerRadius)
    )
```

### Main business detail

```swift
ScrollView(showsIndicators: false) {
    LazyVStack(spacing: 16) {
        heroCard
        statsCard
        contentCard
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 24)
}
.background(SpectraBackdrop().ignoresSafeArea())
.navigationTitle(...)
.navigationBarTitleDisplayMode(.inline)
.toolbarBackground(.hidden, for: .navigationBar)
```

Hero cards use `28pt` and a slightly stronger tint:

```swift
HStack { ... }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
```

Ordinary detail cards use `24pt`:

```swift
VStack { ... }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
```

### Stat card

Detail-page key/value rows use an orange SF Symbol, a secondary label, and a primary value:

```swift
VStack(alignment: .leading, spacing: 12) {
    statRow(label: "Total Amount", value: "...", icon: "scalemass.fill")
    Divider().opacity(0.4)
    statRow(label: "Total Value", value: "...", icon: "dollarsign.circle.fill")
}
.padding(20)
.frame(maxWidth: .infinity, alignment: .leading)
.glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
```

### Action buttons

Use glass button styles outside toolbars:

```swift
GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button { ... } label: { ... }
            .buttonStyle(.glass)

        Button { ... } label: { ... }
            .buttonStyle(.glassProminent)
    }
}
```

Tint stand-alone actions semantically:

```swift
Button { ... } label: { Label("Edit Name", systemImage: "pencil") }
    .buttonStyle(.glass)
    .tint(.orange)

Button(role: .destructive) { ... } label: { Label("Delete", systemImage: "trash") }
    .buttonStyle(.glass)
    .tint(.red)
```

## Don'ts

- Do not add `.buttonStyle(.glass)` to `ToolbarItem` buttons.
- Do not use `Color.primary.opacity(...)` in text foreground styles.
- Do not use rounded black display typography outside icon artwork.
- Do not replace a top-level tab with `Form` or `List(.insetGrouped)`.
- Do not remove `SpectraBackdrop` from top-level tabs or main business detail roots.
- Do not stack custom glass effects unnecessarily or apply them to every small element.
- Do not add new `.ultraThinMaterial` or `.thinMaterial` surfaces when `.glassEffect` is appropriate.
