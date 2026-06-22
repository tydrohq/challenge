# Tydro Challenge

A 90-minute, hands-on exercise on a **forked Tydro** environment. Tydro is a production
Aave-v3 lending market on the Ink chain; this repo forks it locally so you can act as a
risk/listing admin against real protocol state.

The harness removes all the setup friction (forking, admin permissions, deploying listing
dependencies, mock feeds, test tokens) so your time goes to judgment and code. **You start
with a plain EOA (anvil account 0) that already holds every admin role you need** — no
impersonation, no role-granting, just do the work.

There is deliberately more here than fits in 90 minutes. Scope it, prioritize, and explain
your reasoning as you go — how you think is as important as how much you finish.

---

## Requirements

- **[Foundry](https://getfoundry.sh)** (`forge`, `cast`, `anvil`) — the toolchain everything runs on:

  ```bash
  curl -L https://foundry.sh | bash && foundryup
  ```
- **[Node.js](https://nodejs.org)** — used by `script/setup.sh` to read `addresses.json` (live-fork path only).
- **[git](https://git-scm.com/downloads)** with submodule support — for `lib/aave-proposals-v3` (`git submodule update --init`).
- A reachable **Ink RPC endpoint** — a working public default is already in `.env.example`.

---

## Setup

```bash
cp .env.example .env          # working public-RPC defaults are filled in
forge install                 # vendored deps are a no-op; also inits the aave-proposals-v3 submodule

# Option A — live anvil fork (one command: fork + roles + mocks)
./script/setup.sh             # leaves anvil running at 127.0.0.1:8545

# Option B — just simulate against the fork (no separate node)
forge script script/ReadState.s.sol     # sanity check: prints all reserves + sources + config
```

`ReadState` is your launch check — it should print the reserve list with each asset's price
source and config without reverting. If that works, the fork and your roles are good.

Everything derives from a single address (`TYDRO_ADDRESSES_PROVIDER` in `addresses.json`);
Pool / Configurator / Oracle / ACL are read at runtime, never hardcoded.

---

## The tasks

Each task has a script stub under `script/tasks/` with the plumbing wired and the decisions
left to you. Run any of them with `forge script script/tasks/<file>`.

1. **Migrate an oracle** — `script/tasks/01_MigrateOracle.s.sol`
   Repoint the price source for the WETH market (`ORACLE_MIGRATION_TARGET`) to a new feed.

2. **Adjust listing params** — `script/tasks/02_AdjustParams.s.sol`
   This follows your oracle migration. The new feed is more conservative and updates more
   frequently; given recent volatility, propose the risk parameters you'd ship for the WETH
   market (collateral params and at least one cap). **There are existing positions on this
   market** — reason about who your change affects, and verify against them.

3. **List a new market** — `script/tasks/03_ListMarket.s.sol`
   List **DEMO**, a brand-new, thinly-traded token being onboarded for the first time. In
   volatility terms, think of it as comparable to a small-cap memecoin (PEPE-class price
   swings). The `initReserves` plumbing is provided by `ListingHelper.listMarket`; you choose
   and justify the full `ListingParams`.

You're free to work in tests instead of scripts if you prefer — whatever lets you move fast
and show your work.

> **Positions to work with.** The harness seeds a deterministic position book on the target
> (WETH) market — one comfortable position (HF ≈ 2.0) and one near the edge (HF ≈ 1.15), backed
> by seeded borrow-side liquidity — so tasks 1 and 2 have real positions to verify against.
> `ReadState` prints them. Your wallet is a fresh EOA with no token balances; to open your
> *own* position you can `deal` yourself collateral first, but the seeded book already exists to
> reason about, so that's optional.

---

## What's provided

```
src/
  interfaces/IAaveV3.sol      Aave v3 interfaces, pinned to Tydro's deployed version
  harness/
    BetterOracle.sol          settable Chainlink-style price feed (8-dec USD)
    MockERC20.sol             mintable 18-dec test token
    ListingHelper.sol         listMarket(...) — version-robust new-market plumbing
script/
  ForkBase.sol                loads addresses, derives contracts, grants your roles
  ReadState.s.sol             prints reserves + sources + config
  00_DeployHarness.s.sol      deploys the mocks
  setup.sh                    one-command live anvil setup
  tasks/                      the three task stubs (above)
lib/
  aave-proposals-v3/          Aave DAO governance-payload templates (git submodule)
addresses.json / .env.example  config
```

## Generating the oracle-migration payload (Task 1)

`lib/aave-proposals-v3` (git submodule) vendors the Aave DAO's
[aave-proposals-v3](https://github.com/aave-dao/aave-proposals-v3) governance templates. Tydro
is an Aave v3 market, so the same payload pattern Aave uses for production listing / oracle
changes can generate the Task-1 oracle migration (the `setAssetSources` change) in the
canonical Aave shape rather than an ad-hoc script.

It is a **reference / tooling** dependency: nothing under `src/` or `script/` imports it, so it
does not affect `forge build` / `forge test`. On a fresh clone, initialise it with:

```bash
git submodule update --init lib/aave-proposals-v3   # or: forge install
```

## Notes / gotchas

- Base currency is **USD at 8 decimals** (`BASE_CURRENCY_UNIT == 1e8`). All feed prices are
  8-dec. Keep test tokens 18-dec to avoid incidental decimals work.
- The new-market token implementations are **reused from an existing reserve** so they match
  Tydro's exact Aave version — that's what `ListingHelper` does for you. Don't deploy fresh
  token/IRM implementations.
- The fork is local and disposable. If anvil stops, re-run `./script/setup.sh`.

---

## Verifying your work

Run `forge test` (an end-to-end harness test lives in `test/`). For the live flow, after
`./script/setup.sh`, drive the running node with your task scripts (`--broadcast`) or `cast`.
