# Harness Build Spec

> The full build spec lives outside the repo. This file captures the **§3 addendum**
> implemented in this repo: seeding a deterministic position book so tasks 1 & 2 have real
> positions to verify against.

## Build Spec Addendum — Seed a deterministic position book

A live run surfaced one root problem: there is **no pre-seeded borrower on the fork**, so the
candidate has nothing to verify against. Both the task-1 verification ("prove a borrower's HF
recomputes after the oracle swap") and the task-2 scenario ("who would be affected by your
parameter change") silently assume a live position exists. On an empty target market the
candidate burns ~20 min hunting for a position, tries to `deal`/supply/borrow one themselves,
and hits `cannot borrow` on a pool with no counter-asset liquidity — at which point the session
stops producing signal.

`deal`-ing the candidate collateral does **not** fix this: it gives them the collateral token
but no borrow-side liquidity and no existing affected user. The fix is to seed the book.

### §3a. Seed a position book (`ForkBase.seedPositionBook`, called from `00_DeployHarness` and the fork entrypoints)

All of this targets the **same market the tasks key off** — `ORACLE_MIGRATION_TARGET`
(default: wETH). Collateral = that asset, so the task-1 oracle swap and task-2 LT/LTV changes
both move these positions.

1. **Guarantee borrow-side liquidity first.** Do not assume the fork has organic stablecoin
   liquidity. Pick a borrow asset (`SEED_BORROW_ASSET`, default USDC). From a dedicated LP
   address (`SEED_LP`, an anvil account that is **not** account 0): `deal` it a large amount of
   the borrow-asset underlying, `approve` the Pool, and `pool.supply(...)`. This is what makes
   the candidate's own experiments work too.
2. **Open 2–3 borrower positions at known health factors.** Dedicated addresses
   (`SEED_BORROWER_1..N`, not account 0, so the candidate's own positions never collide). Seed
   a **spread**: one comfortable (`HF ≈ 2.0`) and one near the edge (`HF ≈ 1.15`). This gives
   task 2 real texture — lowering LTV leaves both untouched (only new borrows affected) while
   lowering LT pushes the near-edge position toward liquidation. All positions end **HF > 1**.
3. **Compute the borrow amount off the fork — do not hardcode.** Read decimals, the oracle
   price, and the reserve's liquidation threshold at runtime:
   ```
   collateralBase = collateralAmount * oracle.getAssetPrice(collateral) / 10**collateralDecimals
   targetDebtBase = (collateralBase * liquidationThresholdBps / 10000) / targetHF
   borrowAmount   = targetDebtBase * 10**borrowDecimals / oracle.getAssetPrice(borrowAsset)
   ```
   `liquidationThresholdBps` comes from `AaveProtocolDataProvider.getReserveConfigurationData`.
   Never assume 8-decimal feeds or 18-decimal tokens — discover both.
4. **Parameterize** `SEED_TARGET_HF_1/2`, `SEED_COLLATERAL_AMOUNT`, `SEED_BORROW_ASSET`,
   `SEED_LP`, `SEED_BORROWER_*` in `addresses.json` / `.env.example`. Working defaults are
   provided; unset/zero fails loudly.
5. **Mock-price sanity for task 1.** The candidate's new mock aggregator should be set close to
   the live price (matching decimals) so the oracle swap demonstrates HF recomputation without
   instantly liquidating the seeded book.

> **Implementation note — where the book lives.** The harness entrypoints fork **in-process**
> (`createSelectFork`) per invocation, so the book is created per-run and **deterministically**
> (computed from pinned-block on-chain prices → identical every time) via cheatcodes
> (`deal`/prank). `seedPositionBook()` is called from `ReadState`, tasks 1 & 2, the tests, and
> `00_DeployHarness`. In the live `setup.sh --broadcast` flow, cheatcode state isn't persisted
> by the broadcast; the deterministic per-invocation seed is the supported path (consistent
> with how `ReadState`/tasks already `createSelectFork`).

### §3b. `ReadState.s.sol` extension

In addition to reserves + per-asset source + config, it prints for the target market:
**available borrow liquidity**, **supply/borrow caps and current usage**, and the **HF of each
seeded position** (plus the seed borrow-asset's depth). Turns a "why does my borrow revert"
dead end into a 5-second read, and lets the candidate watch the book move before/after a change.

### §3c. README edits (candidate-facing)

- **Task 2 — the scenario is written down** (no live improv): a post-incident de-risk of the
  WETH market with existing positions to reason about and verify against.
- **One line on funds:** the candidate wallet is a fresh EOA; to open their *own* position they
  `deal` themselves collateral — but a seeded book already exists to reason about, so this is
  optional.

### What this fixes

Task 1 verification (HF recomputes) and task 2 scenario (aggregate position impact) both work
out of the box; the `cannot borrow` empty-pool dead end is gone; and the candidate's 90 minutes
go to judgment and code rather than to manufacturing a position.
