---
name: update-pricing
description: Add or update model pricing in TokenScope's manual pricing catalog. Use when a provider ships a new model, changes token prices, or when cost estimates show "—" for a model that should be priced.
---

# Update the pricing catalog

TokenScope estimates costs from a manually maintained catalog. Every price change touches three places — code, docs, and tests — and all three must stay in sync.

## Steps

1. **Get authoritative prices.** Ask the user for the source, or check the provider's official pricing page. Prices are USD per million tokens: input, cache write (creation), cache read, output. Never guess prices.

2. **Update the code** — `src/Core/Pricing/PricingCatalog.swift`:
   - Rates live in `rates(provider:model:)` (~line 57), matched on `model.lowercased()` prefixes. Add a new match case in the right provider branch with a `Rates(inputPerMillion:cacheCreationPerMillion:cacheReadPerMillion:outputPerMillion:)` entry using `Decimal(string:)` (follow the existing pattern, no force-unwrap).
   - Put more specific model-name prefixes BEFORE broader ones so they match first.
   - Bump `sourceVersion` (~line 23) to today's date (`YYYY-MM-DD`).

3. **Update the docs** — `docs/PRICING_CATALOG.md`: add/update the model row with the same numbers and note the source + date.

4. **Update tests** — `tests/NormalizerTests/PricingCatalogTests.swift`: add or adjust an assertion covering the new model's rates (input, cache write, cache read, output) and one `estimatedCost` calculation.

5. **Verify**: `swift test` must be green. Grep the model name across `src docs tests` to confirm all three places agree.

6. **Changelog**: add a bullet under `## Unreleased` in `CHANGELOG.md` (e.g. "Updated pricing catalog for <model> (<date>)").

## Edge cases

- A model with no cache pricing: leave `cacheCreationPerMillion`/`cacheReadPerMillion` as `nil` — the code falls back to the input rate.
- Codex models: cache-read tokens are subtracted from input tokens before pricing (see `estimatedCost`, ~line 38) — don't double-count when writing test expectations.
- Renamed/aliased models: add the new prefix, keep the old one for historical log data.
