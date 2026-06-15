#!/usr/bin/env bash
# One-command live setup for the Tydro challenge.
#
#   ./script/setup.sh
#
# Starts an anvil fork of Ink at the pinned block, grants the candidate EOA (anvil
# account 0) every ACL role it needs by impersonating Tydro's ACL admin, and deploys the
# harness mocks. After this, the candidate uses account 0 for ALL writes with no further
# impersonation.
#
# Why cast impersonation for the role grants: Tydro's ACL admin is a CONTRACT, but it holds
# the ACL DEFAULT_ADMIN_ROLE directly (verified on-chain). anvil_impersonateAccount +
# `cast send --unlocked` lets us call addPoolAdmin/... AS that contract — no timelock dance.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] || { echo "ERROR: copy .env.example -> .env first"; exit 1; }
set -a; . ./.env; set +a

: "${INK_RPC_URL:?INK_RPC_URL unset}"
: "${FORK_BLOCK:?FORK_BLOCK unset}"
CANDIDATE="${CANDIDATE:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
ANVIL_RPC="${ANVIL_RPC:-http://127.0.0.1:8545}"

PROVIDER=$(node -e "console.log(require('./addresses.json').addressesProvider)")

echo ">> starting anvil fork of Ink @ $FORK_BLOCK ..."
anvil --fork-url "$INK_RPC_URL" --fork-block-number "$FORK_BLOCK" --silent &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
# wait for anvil
for i in $(seq 1 30); do
  cast block-number --rpc-url "$ANVIL_RPC" >/dev/null 2>&1 && break
  sleep 0.5
done

ACL=$(cast call "$PROVIDER" 'getACLManager()(address)' --rpc-url "$ANVIL_RPC")
ACLADMIN=$(cast call "$PROVIDER" 'getACLAdmin()(address)' --rpc-url "$ANVIL_RPC")
echo ">> ACLManager=$ACL  ACLAdmin=$ACLADMIN"

echo ">> impersonating ACL admin and granting roles to $CANDIDATE ..."
cast rpc anvil_impersonateAccount "$ACLADMIN" --rpc-url "$ANVIL_RPC" >/dev/null
cast rpc anvil_setBalance "$ACLADMIN" 0xDE0B6B3A7640000 --rpc-url "$ANVIL_RPC" >/dev/null # 1 ETH for gas
for fn in addPoolAdmin addRiskAdmin addAssetListingAdmin addEmergencyAdmin; do
  cast send "$ACL" "$fn(address)" "$CANDIDATE" --from "$ACLADMIN" --unlocked --rpc-url "$ANVIL_RPC" >/dev/null
  echo "   granted: $fn"
done
cast rpc anvil_stopImpersonatingAccount "$ACLADMIN" --rpc-url "$ANVIL_RPC" >/dev/null

echo ">> verifying candidate is a pool admin ..."
IS_ADMIN=$(cast call "$ACL" 'isPoolAdmin(address)(bool)' "$CANDIDATE" --rpc-url "$ANVIL_RPC")
echo "   isPoolAdmin($CANDIDATE) = $IS_ADMIN"

echo ">> deploying harness mocks ..."
forge script script/00_DeployHarness.s.sol \
  --rpc-url "$ANVIL_RPC" --broadcast --private-key "$PRIVATE_KEY" -vv

echo ""
echo ">> setup complete. anvil is running (pid $ANVIL_PID) at $ANVIL_RPC."
echo "   Press Ctrl-C to stop anvil."
wait $ANVIL_PID
