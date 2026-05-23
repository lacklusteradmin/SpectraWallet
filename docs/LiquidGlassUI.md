# Liquid Glass UI reference

Spectra's visual language on iOS 26. Fintech-native interpretation of Liquid Glass (Robinhood/Coinbase/Revolut DNA) — glass-forward, not Apple-faithful-minimal.

## Apple's design philosophy (and how Spectra relates)

Apple's iOS design philosophy has been remarkably consistent since iOS 7, and iOS 26's Liquid Glass is an evolution, not a reset. Three principles anchor it:

**1. Deference to content.** The UI exists to surface content, not compete with it. Chrome (nav bars, toolbars, tab bars) is translucent and recedes; content is opaque and foregrounded. In iOS 26 this is literal — glass chrome refracts content scrolling behind it, so the content is visible *through* the UI.

**2. Clarity through hierarchy.** Size, weight, spacing, and color do the work of separating importance — not borders, shadows, or gradients. Apple's typography uses a small set of system styles (`.largeTitle`, `.title`, `.headline`, `.body`, `.caption`) at standard weights. Semantic colors (`.primary`, `.secondary`, `.tertiary`) adapt automatically to Dynamic Type, dark/light mode, and Increase Contrast. Hand-picked opacity ramps (`Color.primary.opacity(0.72)`) break this.

**3. Depth as a communicative tool.** Layers and translucency convey "this floats above that" — sheets above content, toolbars above lists, popovers above everything. `.glassEffect` isn't decoration; it signals "this is a floating layer, content lives behind it." Apple is restrained about when to use it: toolbars, tab bars, sheets, Control Center tiles, Camera mode switcher — *not* body content like list rows.

**Proportionality.** Corner radii scale with surface size: inline chips get ~10pt, small controls 14–18pt, medium cards ~20pt, large sheets ~28–32pt. Apple hasn't published the exact numbers (I was wrong twice guessing them); the principle is that a large surface with a small corner reads as cheap, and a small surface with a large corner reads as amateur.

**Motion as meaning.** Transitions carry hierarchy: push = going deeper, modal sheet = temporary detour, dismiss = returning. Motion isn't decoration; it's wayfinding. iOS 26 adds glass morphing (`GlassEffectContainer`) as a new motion verb — paired elements melt into each other rather than appearing as separate chips.

**What Spectra keeps from Apple:**
- System typography exclusively for chrome text (no display fonts)
- Semantic colors (`.secondary`, `.tertiary`) over opacity ramps
- Glass reserved for surfaces and controls, not decorative fills
- `GlassEffectContainer` for paired primary/secondary actions
- Floating nav bar via `.toolbarBackground(.hidden)` so content scrolls under

**What Spectra departs from:**
- *Body content on glass cards.* Apple's own apps (Mail, Settings, Notes, Home) use `List(.insetGrouped)` with opaque `.systemGroupedBackground` rows. Spectra puts body content on glass over a rich backdrop — that's the fintech signature. Valid, just non-Apple.
- *Custom gradient wallpaper.* Apple apps render against system neutral backgrounds. Spectra ships `SpectraBackdrop`. This is what makes our glass *look* like glass; it's also what makes the app read as "crypto" rather than "system."
- *Corner radii tuned by density.* Primary phone tabs use a tighter 24pt card radius for scan-friendly density; richer detail/hero surfaces keep 28pt where the extra roundness still feels proportional.

The philosophy we're following: *use Apple's APIs and typography/color semantics correctly, but break from Apple's restraint on where glass and rich backgrounds appear.* That's how consumer fintech apps look native on iOS 26 without feeling like a system app.

## Design baseline

- **Backdrop:** `SpectraBackdrop` (gradient + chroma clouds) on every top-level tab NavigationStack **and on every detail destination** (asset, wallet, staking-chain). Glass needs something to refract.
- **Chrome:** Navigation bar is transparent (`.toolbarBackground(.hidden, for: .navigationBar)`); toolbar actions are `.buttonStyle(.glass)` pills. Content scrolls under.
- **Surfaces:** Content sits in `.glassEffect(.regular.tint(.white.opacity(~0.03)), in: .rect(cornerRadius: 24...28))` cards. Primary phone tabs use the shared `SpectraLayout` compact metrics; detail and narrative surfaces can stay roomier.
- **Hero card opacity:** Hero/header cards use `tint(.white.opacity(0.04))` (slightly stronger). Stats/content cards use `0.03`. Two opacity bands create subtle depth without explicit borders.
- **Stat row pattern:** detail-page key/value rows lead with an SF Symbol in `.orange` + secondary label + primary value, separated by `Divider().opacity(0.4)`. Used across Asset detail, Wallet detail, Staking chain detail.
- **Typography:** system text styles (`.largeTitle.weight(.bold)`, `.title`, `.headline`, etc.). No `design: .rounded` + `weight: .black` outside icon artwork.
- **Colors:** `.secondary` / `.tertiary` / `.quaternary` for text tints. Never `Color.primary.opacity(X)` for text.
- **Buttons:** `.buttonStyle(.glass)` + `.buttonStyle(.glassProminent)` for interactive pills. Tint orange for primary actions, red for destructive. `GlassEffectContainer` for paired primary/secondary actions.

## Corner radius inventory

Actual values in the codebase:

| Radius | Where |
|--------|-------|
| 28pt | Roomier detail/narrative cards — **Staking chain-detail cards (hero/stats/actions/explanation)**, Donations hero + addresses card, About hero + narrative + ethos cards, TransactionDetail hero amount card, `spectraDetailCard` helper, lock-screen glass card, ChainWiki intro card + row cards + section cards + hero card, **Asset Group / Contracts detail (hero/stats/breakdown/contracts)**, **Wallet detail (hero/stats/holdings/address)** |
| 24pt | **Primary phone tab cards via `SpectraLayout.cardCornerRadius`** — Dashboard portfolio hero + assets-wallets card, History section cards + empty state, Staking intro/chain-picker/philosophy cards; also default `spectraCardFill` radius for legacy detail/nested cards |
| 22pt | AddWalletEntryView entry cards |
| 20pt | WalletSetupViews chain chip background |
| 18pt | ReceiveFlowViews small nested card, TransactionDetail `.ultraThinMaterial` chips, ChainWiki accessory chips, default `spectraInputFieldStyle` radius, Wallet detail address inset capsule |
| 16pt | WalletFlowViews seed-phrase input, WalletSetupViews input fields + warning boxes, **chain-selection chip cards (Setup + Staking chain tile)** |
| 14pt | SendPrimarySectionsView chips, DecimalDisplaySettingsView, TokenRegistrySettingsView, WalletSetupViews selected-chip states, **Staking action button rows** |
| 12pt | WalletFlowViews inputs + hex index pickers |
| 10pt | WalletSetupViews orange warning pills, compact word-picker slots, **Staking action-button leading-icon backplate** |
| size-relative | `SpectraLogo` glass backing = `size × 0.28` ([IconUIHelpers.swift:125](IconUIHelpers.swift#L125)) |

Coin/chain badges are rendered as **full circles** via `Circle()` ([IconUIHelpers.swift:55](IconUIHelpers.swift#L55)) — no per-instance corner radius applies. Sized 28pt – 60pt across the app (chip tiles 36pt, list rows 30–34pt, hero badges 52–60pt).

Typical band: **24–28pt on cards, 16–18pt on chips/tiles, 10–14pt on inline pills.**

## Liquid Glass API usage sites

### `SpectraBackdrop` (gradient + chroma backdrop)

Top-level tabs:
- [DashboardViews.swift:22](DashboardViews.swift#L22)
- [HistoryView.swift:60](HistoryView.swift#L60)
- [StakingView.swift:12](StakingView.swift#L12)
- [DonationsView.swift:13](DonationsView.swift#L13)

Detail destinations (added so glass refraction works after navigation push):
- [DashboardViews.swift:314](DashboardViews.swift#L314) — AssetGroupDetailView
- [DashboardViews.swift:340](DashboardViews.swift#L340) — AssetContractsDetailView
- [WalletFlowViews.swift:316](WalletFlowViews.swift#L316) — WalletDetailView
- [StakingView.swift:204](StakingView.swift#L204) — ChainStakingDetailView

### `.toolbarBackground(.hidden, for: .navigationBar)` (floating nav bar)

- [DashboardViews.swift:34](DashboardViews.swift#L34)
- [DashboardViews.swift:316](DashboardViews.swift#L316) — AssetGroupDetailView
- [DashboardViews.swift:342](DashboardViews.swift#L342) — AssetContractsDetailView
- [HistoryView.swift:120](HistoryView.swift#L120)
- [StakingView.swift:21](StakingView.swift#L21)
- [StakingView.swift:207](StakingView.swift#L207) — ChainStakingDetailView
- [DonationsView.swift:33](DonationsView.swift#L33)
- [SettingsViews.swift:123](SettingsViews.swift#L123)
- [WalletFlowViews.swift:320](WalletFlowViews.swift#L320) — WalletDetailView

### `.glassEffect(...)` on surfaces/cards

**Dashboard** ([DashboardViews.swift](DashboardViews.swift)):
- L122 — assets/wallets card (`.interactive()`, 24pt compact)
- L368 — `AssetDetailHeroCard` (28pt, `0.04` tint)
- L392 — `AssetSummaryStatsCard` (28pt)
- L440 — `AssetChainBreakdownCard` (28pt)
- L480 — `AssetContractsCard` (28pt)
- L730 — portfolio hero card (24pt compact, `0.04` tint)

**History** ([HistoryView.swift](HistoryView.swift)):
- L68 — empty-state card (24pt compact)
- L108 — transaction section cards (`.interactive()`, 24pt compact)

**Staking** ([StakingView.swift](StakingView.swift)) — chain hub:
- L34 — intro card (24pt compact, `0.04` tint)
- L52 — chain-picker card (24pt compact)
- L97 — philosophy card (24pt compact)

**Staking** chain detail (`ChainStakingDetailView`):
- L232 — hero card (28pt, `0.04` tint)
- L244 — stats card (28pt)
- L267 — actions card (28pt)
- L298 — "How it works" explanation card (28pt)

**Donations** ([DonationsView.swift](DonationsView.swift)):
- L20 — hero card (28pt)
- L29 — addresses card (28pt)

**About** ([AboutView.swift](AboutView.swift)):
- L42 — hero card (28pt)
- L50 — narrative card (28pt)
- L62 — ethos card (28pt)

**Wallet detail** ([WalletFlowViews.swift](WalletFlowViews.swift)):
- L451 — `walletHeroCard` (28pt, `0.04` tint)
- L470 — `walletStatsCard` (28pt)
- L507 — `walletHoldingsCard` (28pt)
- L532 — `walletAddressCard` (28pt)

**Lock screen / helpers** ([ContentView.swift](ContentView.swift)):
- L6 — `SpectraInputFieldChrome` (glass input field)
- L28 — `spectraDetailCard` helper (28pt)
- L70 — lock-screen card (28pt)

**Helper** ([IconUIHelpers.swift](IconUIHelpers.swift)):
- `spectraCardFill` helper (routes legacy card-fill sites through glass, 24pt default)
- SpectraLogo glass backing (`size × 0.28`)

### `.buttonStyle(.glass)` (glass pill buttons)

**Dashboard** ([DashboardViews.swift](DashboardViews.swift)):
- L745 — Send button (inside `GlassEffectContainer`)

**Donations** ([DonationsView.swift](DonationsView.swift)):
- L56 — copy address chip
- L62 — QR code chip

**Send / Receive**:
- [SendPrimarySectionsView.swift:136](SendPrimarySectionsView.swift#L136) — scan QR
- [ReceiveFlowViews.swift:104](ReceiveFlowViews.swift#L104) — share QR

**WalletFlow** ([WalletFlowViews.swift](WalletFlowViews.swift)):
- L524 — wallet address Copy button (`.tint(.orange)`)
- L545 — Edit Name (`.tint(.orange)`)
- L565 — Show Seed Phrase (`.tint(.orange)`)
- L573 — Delete Wallet (`.tint(.red)` for destructive)

**WalletSetup** ([WalletSetupViews.swift](WalletSetupViews.swift)):
- L329 — seed-length regenerate button (`.tint(.orange)`)
- L389 — "Browse all chains" sheet trigger (`.tint(.orange)`)
- L1019, L1042 — seed-phrase Paste / Copy (`.tint(.orange)`)
- L1062 — private-key Paste (`.tint(.orange)`)
- L784, L796, L1152 — primary navigation
- L691, L703 — nav back/primary

**TransactionDetail** ([TransactionDetailView.swift](TransactionDetailView.swift)):
- L156 — recheck button
- L249 — secondary action

### `.buttonStyle(.glassProminent)` (prominent glass pills)

- [ContentView.swift:69](ContentView.swift#L69) — unlock button
- [DashboardViews.swift:749](DashboardViews.swift#L749) — Receive button
- [SendFlowViews.swift:79](SendFlowViews.swift#L79) — submit send
- [TransactionDetailView.swift:146](TransactionDetailView.swift#L146) — primary recheck
- [TransactionDetailView.swift:187](TransactionDetailView.swift#L187) — primary action
- [WalletFlowViews.swift:388](WalletFlowViews.swift#L388) — wallet primary
- [WalletSetupViews.swift:751](WalletSetupViews.swift#L751) — setup primary (Import)
- [WalletSetupViews.swift:1231](WalletSetupViews.swift#L1231) — setup-flow primary toolbar

### `GlassEffectContainer` (paired morphing group)
- [DashboardViews.swift:740](DashboardViews.swift#L740) — Dashboard Send + Receive pair

## Patterns worth imitating

When adding a new top-level screen:
```swift
NavigationStack {
    ZStack {
        SpectraBackdrop().ignoresSafeArea()
        ScrollView { /* content cards */ }
    }
    .navigationTitle(...)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
        ToolbarItem(...) { Button(...).buttonStyle(.glass) }
    }
}
```

When adding a new detail destination (pushed from a top-level screen):
```swift
ScrollView {
    LazyVStack(spacing: 16) {
        heroCard
        statsCard
        contentCard
        // …
    }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
}
.background(SpectraBackdrop().ignoresSafeArea())   // ← always re-add at detail roots
.navigationTitle(...).navigationBarTitleDisplayMode(.inline)
.toolbarBackground(.hidden, for: .navigationBar)
```

When adding a new card:
```swift
VStack { ... }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
```

For a hero/header card use the slightly stronger `0.04` tint:
```swift
HStack { /* badge + title + subtitle */ }
    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
```

When adding a stat/key-value card (the canonical pattern across asset / wallet / staking detail):
```swift
VStack(alignment: .leading, spacing: 12) {
    statRow(label: "Total Amount", value: "...", icon: "scalemass.fill")
    Divider().opacity(0.4)
    statRow(label: "Total Value", value: "...", icon: "dollarsign.circle.fill")
    Divider().opacity(0.4)
    statRow(label: "Chains", value: "3", icon: "link.circle.fill")
}
.padding(20).frame(maxWidth: .infinity, alignment: .leading)
.glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
```
where `statRow` is:
```swift
HStack(spacing: 10) {
    Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.orange).frame(width: 22)
    Text(label).font(.subheadline).foregroundStyle(.secondary)
    Spacer(minLength: 12)
    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
        .multilineTextAlignment(.trailing)
}
```

When adding a primary/secondary button pair:
```swift
GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button { ... } label: { ... }.buttonStyle(.glass)
        Button { ... } label: { ... }.buttonStyle(.glassProminent)
    }
}
```

When adding a stand-alone action button on a detail page, **tint** it semantically:
```swift
Button { ... } label: { Label("Edit Name", systemImage: "pencil") }
    .buttonStyle(.glass).tint(.orange)            // primary

Button(role: .destructive) { ... } label: { Label("Delete", systemImage: "trash") }
    .buttonStyle(.glass).tint(.red)               // destructive
```

When adding a chain/asset selection chip grid (3-col, square):
```swift
Button { … } label: {
    VStack(spacing: 6) {
        ZStack(alignment: .topTrailing) {
            CoinBadge(...)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(descriptor.color)
                    .background(Circle().fill(Color.white.opacity(0.9)))
                    .offset(x: 4, y: -4)
            }
        }
        Text(descriptor.title).font(.caption2.weight(.semibold)).lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 72).padding(.vertical, 8).padding(.horizontal, 6)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
        isSelected ? descriptor.color.opacity(0.14) : Color.white.opacity(0.55)))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
        isSelected ? descriptor.color.opacity(0.9) : Color.primary.opacity(0.10),
        lineWidth: isSelected ? 1.5 : 1))
}
.buttonStyle(.plain)
```

## Don'ts

- No `.buttonStyle(.glass)` on `ToolbarItem` buttons — iOS 26 auto-glasses toolbar items and stacking explicit `.glass` on top creates double-chip padding.
- No `.ultraThinMaterial` / `.thinMaterial` on new surfaces — prefer `.glassEffect`. (Existing ones in SendPrimarySectionsView/TokenRegistrySettingsView/TransactionDetailView/DecimalDisplaySettingsView are legacy.)
- No `Color.primary.opacity(X)` in `.foregroundStyle(...)`. Use `.secondary` / `.tertiary` / `.quaternary`. (Hairline border strokes on chip/pill outlines are the one exception — those use `Color.primary.opacity(0.07–0.12)` deliberately as visual rhythm.)
- No `.font(.system(size: X, weight: .black, design: .rounded))` on chrome text. Only allowed inside icon artwork (SpectraLogo "S" glyph, CoinBadge fallback letter).
- Don't revert tab screens or detail destinations to `Form { Section { … } }` / `List(.insetGrouped)` — the Asset and Wallet detail pages were just migrated *away* from `Form` to glass cards. Stay on the new pattern.
- Don't strip `SpectraBackdrop` from tab roots **or detail roots** — glass needs something to refract on every navigated-to surface, not just the tab landing.
- Don't omit the orange leading icon on stat rows — the icon column is what makes the row visually scannable; without it the row reads as a generic label/value pair and loses the fintech voice.
