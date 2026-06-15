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

## Setup

```bash
cp .env.example .env          # working public-RPC defaults are filled in
forge install                 # (deps are vendored; this is a no-op if so)

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
   Change an existing reserve's collateral parameters and at least one cap.

3. **List a new market** — `script/tasks/03_ListMarket.s.sol`
   List a fresh asset. The `initReserves` plumbing is provided by `ListingHelper.listMarket`;
   you choose and justify the `ListingParams`.

4. **Build an ERC-4626 vault** — `src/vault/PortfolioVault.sol` + `script/tasks/04_PortfolioVault.s.sol`
   Implement a vault that holds a fixed-weight portfolio across two markets (the new market
   and the WETH market). Deploy and exercise it with the script.

You're free to work in tests instead of scripts if you prefer — whatever lets you move fast
and show your work.

---

## What's provided

```
src/
  interfaces/IAaveV3.sol      Aave v3 interfaces, pinned to Tydro's deployed version
  harness/
    BetterOracle.sol          settable Chainlink-style price feed (8-dec USD)
    MockERC20.sol             mintable 18-dec test token
    MockSwapRouter.sol        oracle-priced base<->WETH swap (for the vault)
    ListingHelper.sol         listMarket(...) — version-robust new-market plumbing
  vault/PortfolioVault.sol    STARTER (implement the TODOs)
script/
  ForkBase.sol                loads addresses, derives contracts, grants your roles
  ReadState.s.sol             prints reserves + sources + config
  00_DeployHarness.s.sol      deploys the mocks
  setup.sh                    one-command live anvil setup
  tasks/                      the four task stubs (above)
addresses.json / .env.example  config
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
