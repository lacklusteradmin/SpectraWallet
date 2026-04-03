# Spectra Localization Guide

## Ownership Rules

- Use `Localizable.xcstrings` for short UI strings:
  - buttons
  - navigation titles
  - alerts
  - menu items
  - transient status messages
- Use feature JSON content files under `Resources/Localization/<locale>/` for:
  - screen-specific long-form copy
  - explanatory paragraphs
  - feature configuration copy
  - grouped format strings owned by one feature

## String Authoring Rules

- Prefer full phrases over stitching together sentence fragments.
- Do not use leading or trailing whitespace inside localized keys or values.
- Avoid building titles from generic fragments unless the grammar is stable across locales.
- Keep crypto asset, token, protocol, provider, and chain names canonical unless the glossary explicitly says otherwise.
- Prefer one semantic key per concept instead of duplicating near-identical English sentences.

## Terminology Rules

- Do not directly translate coin or token names such as `Bitcoin`, `Ethereum`, `Solana`, `USDT`, or `USDC`.
- Keep protocol and provider acronyms canonical: `RPC`, `EVM`, `API`, `JSON`, `URL`, `HTTP`, `nonce`.
- Use glossary-approved translations for wallet-security terms such as `seed phrase`, `private key`, `watch-only`, and `self-custodial`.

## Review Checklist

- Check English, `zh-Hans`, and `zh-Hant` in the running UI.
- Verify dynamic values read naturally with placeholders inserted.
- Check truncation in navigation bars, buttons, cards, and alerts.
- Check that diagnostics, settings, and import flow use consistent terminology.
- Remove stale string-catalog entries instead of leaving orphaned translations behind.
