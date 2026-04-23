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
- *Corner radii slightly rounder than system.* 28pt on top-level cards is a few points past Apple's proportional default — deliberate lean into the consumer-fintech look.

The philosophy we're following: *use Apple's APIs and typography/color semantics correctly, but break from Apple's restraint on where glass and rich backgrounds appear.* That's how consumer fintech apps look native on iOS 26 without feeling like a system app.

## Design baseline

- **Backdrop:** `SpectraBackdrop` (gradient + chroma clouds) on every top-level tab NavigationStack. Glass needs something to refract.
- **Chrome:** Navigation bar is transparent (`.toolbarBackground(.hidden, for: .navigationBar)`); toolbar actions are `.buttonStyle(.glass)` pills. Content scrolls under.
- **Surfaces:** Content sits in `.glassEffect(.regular.tint(.white.opacity(~0.03)), in: .rect(cornerRadius: ~28))` cards. Top-level = 28pt, nested/detail = 24pt.
- **Typography:** system text styles (`.largeTitle.weight(.bold)`, `.title`, `.headline`, etc.). No `design: .rounded` + `weight: .black` outside icon artwork.
- **Colors:** `.secondary` / `.tertiary` / `.quaternary` for text tints. Never `Color.primary.opacity(X)` for text.
- **Buttons:** `.buttonStyle(.glass)` + `.buttonStyle(.glassProminent)` for interactive pills. `GlassEffectContainer` for paired primary/secondary actions.

## Corner radius inventory

Actual values in the codebase:

| Radius | Where |
|--------|-------|
| 28pt | All top-level tab hero/container cards — Dashboard portfolio hero + assets-wallets card, History section cards + empty state, Staking 2 cards, Donations hero + addresses card, About hero + narrative + ethos cards, TransactionDetail hero amount card, `spectraDetailCard` helper, lock-screen glass card, **ChainWiki intro card + row cards + section cards + hero card** |
| 25pt | ChainWiki 50×50 badge (half-size = visually round) |
| 24pt | **Default `spectraCardFill` radius** — most detail/nested cards: WalletFlowViews cards, SendFlowViews card, ReceiveFlowViews primary card, Dashboard asset-group detail, WalletSetupViews final cards, ChainWiki 82pt badge |
| 22pt | AddWalletEntryView entry cards |
| 20pt | WalletSetupViews chain chip background |
| 18pt | ReceiveFlowViews small nested card, TransactionDetail `.ultraThinMaterial` chips, ChainWiki accessory chips, default `spectraInputFieldStyle` radius |
| 16pt | WalletFlowViews seed-phrase input, WalletSetupViews input fields + warning boxes |
| 14pt | SendPrimarySectionsView chips, DecimalDisplaySettingsView, TokenRegistrySettingsView, WalletSetupViews selected-chip states |
| 12pt | WalletFlowViews inputs + hex index pickers |
| 10pt | WalletSetupViews orange warning pills, compact word-picker slots |
| size-relative | CoinBadge = `size × 0.3`, SpectraLogo = `size × 0.28` |

Typical band: **24pt on nested cards, 28pt on top-level tab surfaces.** 10–18pt for inline chips and inputs.

## Liquid Glass API usage sites

### `SpectraBackdrop` (gradient + chroma backdrop)
- [DashboardViews.swift:23](DashboardViews.swift#L23)
- [HistoryView.swift:60](HistoryView.swift#L60)
- [StakingView.swift:6](StakingView.swift#L6)
- [DonationsView.swift:13](DonationsView.swift#L13)

### `.toolbarBackground(.hidden, for: .navigationBar)` (floating nav bar)
- [DashboardViews.swift:35](DashboardViews.swift#L35)
- [HistoryView.swift:120](HistoryView.swift#L120)
- [StakingView.swift:37](StakingView.swift#L37)
- [DonationsView.swift:33](DonationsView.swift#L33)
- [SettingsViews.swift:123](SettingsViews.swift#L123)

### `.glassEffect(...)` on surfaces/cards

**Dashboard** ([DashboardViews.swift](DashboardViews.swift)):
- L123 — assets/wallets card (`.interactive()`, 28pt)
- L649 — portfolio hero card (28pt)

**History** ([HistoryView.swift](HistoryView.swift)):
- L68 — empty-state card (28pt)
- L108 — transaction section cards (`.interactive()`, 28pt)

**Staking** ([StakingView.swift](StakingView.swift)):
- L14 — intro card (28pt)
- L33 — "Why staking matters" card (28pt)

**Donations** ([DonationsView.swift](DonationsView.swift)):
- L20 — hero card (28pt)
- L29 — addresses card (28pt)

**About** ([AboutView.swift](AboutView.swift)):
- L42 — hero card (28pt)
- L50 — narrative card (28pt)
- L62 — ethos card (28pt)

**Lock screen / helpers** ([ContentView.swift](ContentView.swift)):
- L6 — `SpectraInputFieldChrome` (glass input field)
- L28 — `spectraDetailCard` helper (28pt)
- L70 — lock-screen card (28pt)

**Helper** ([IconUIHelpers.swift](IconUIHelpers.swift)):
- L272 — `spectraCardFill` helper (routes all legacy card-fill sites through glass)
- L294 — SpectraLogo glass backing (`size × 0.28`)

### `.buttonStyle(.glass)` (glass pill buttons)

**Dashboard** ([DashboardViews.swift](DashboardViews.swift)):
- L647 — portfolio navigate chevron
- L663 — Send button (inside `GlassEffectContainer`)

**Donations** ([DonationsView.swift](DonationsView.swift)):
- L56 — copy address chip
- L62 — QR code chip

**Send / Receive** :
- [SendPrimarySectionsView.swift:136](SendPrimarySectionsView.swift#L136) — scan QR
- [ReceiveFlowViews.swift:104](ReceiveFlowViews.swift#L104) — share QR

**WalletFlow** ([WalletFlowViews.swift](WalletFlowViews.swift)):
- L189 — wallet action
- L401, L421, L429 — wallet detail actions (export, reveal, delete)

**WalletSetup** ([WalletSetupViews.swift](WalletSetupViews.swift)):
- L320 — word-count picker
- L331 — advanced toggle
- L691, L703 — nav back/primary
- L960 — chip picker

**TransactionDetail** ([TransactionDetailView.swift](TransactionDetailView.swift)):
- L156 — recheck button
- L249 — secondary action

### `.buttonStyle(.glassProminent)` (prominent glass pills)

- [ContentView.swift:69](ContentView.swift#L69) — unlock button
- [DashboardViews.swift:667](DashboardViews.swift#L667) — Receive button
- [SendFlowViews.swift:79](SendFlowViews.swift#L79) — submit send
- [TransactionDetailView.swift:146](TransactionDetailView.swift#L146) — primary recheck
- [TransactionDetailView.swift:187](TransactionDetailView.swift#L187) — primary action
- [WalletFlowViews.swift:501](WalletFlowViews.swift#L501) — wallet primary
- [WalletSetupViews.swift:658](WalletSetupViews.swift#L658) — setup primary (Import)

### `GlassEffectContainer` (paired morphing group)
- [DashboardViews.swift:658](DashboardViews.swift#L658) — Dashboard Send + Receive pair

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

When adding a new card:
```swift
VStack { ... }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
```
Or (legacy, but equivalent):
```swift
VStack { ... }.padding(20).spectraBubbleFill().spectraCardFill(cornerRadius: 24)
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

## Don'ts

- No `.buttonStyle(.glass)` on `ToolbarItem` buttons — iOS 26 auto-glasses toolbar items and stacking explicit `.glass` on top creates double-chip padding.
- No `.ultraThinMaterial` / `.thinMaterial` on new surfaces — prefer `.glassEffect`. (Existing ones in SendPrimarySectionsView/TokenRegistrySettingsView/TransactionDetailView/DecimalDisplaySettingsView are legacy.)
- No `Color.primary.opacity(X)` in `.foregroundStyle(...)`. Use `.secondary` / `.tertiary` / `.quaternary`.
- No `.font(.system(size: X, weight: .black, design: .rounded))` on chrome text. Only allowed inside icon artwork (SpectraLogo "S" glyph, CoinBadge fallback letter).
- Don't revert tab screens to `List(.insetGrouped)` — the user explicitly rejected that direction.
- Don't strip `SpectraBackdrop` from tab roots — glass needs something to refract.
