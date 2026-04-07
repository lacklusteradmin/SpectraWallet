# Spectra Testing Workflow

This project uses a layered test workflow so regressions are caught early and failures are easy to diagnose.

## 1. Fast deterministic unit tests

- Scope: pure parsing/mapping logic and service behavior with mocked networking.
- Mechanism: `ReplaySpectraNetworkClient` + `SpectraNetworkRouter`.
- Rule: no live network calls in unit tests.

## 2. Shared network test harness

- Base class: `SpectraNetworkTestCase`.
- Behavior:
  - Installs a fresh replay client in `setUp()`.
  - Resets the network router in `tearDown()`.
  - Provides `assertThrowsURLErrorCode(...)` helper for consistent failure assertions.

This avoids repeated boilerplate and prevents test pollution across suites.

## 3. Fallback and failure-path testing

For each chain service, add at least:

- Happy path test (primary endpoint success).
- Fallback path test (primary endpoint failure, secondary success).
- Deterministic error-path test (all providers fail with expected error surface).

Current examples:

- `BitcoinBalanceServiceTests`
- `LitecoinBalanceServiceTests`
- `ReplaySpectraNetworkClientTests`

## 4. Diagnostics and export tests

Keep one suite focused on support tooling stability:

- diagnostics bundle schema/version,
- export/import compatibility,
- non-empty environment fields.

Current example:

- `DiagnosticsBundleTests`

## 5. Build and test gates

- Run full build before merge.
- Run all tests from `Spectra.xctestplan`.
- Code coverage is enabled in the test plan to keep visibility into untested areas.

## 6. Authoring rules for new tests

- Use explicit fixture payloads with minimal required fields.
- Keep assertions behavior-focused (output and side effects), not implementation-detail focused.
- Prefer one behavior per test.
- Name tests in Given/When/Then style where practical.

