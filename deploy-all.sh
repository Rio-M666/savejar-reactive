#!/usr/bin/env bash
# SaveJar — full testnet deployment + live demo loop.
#
# Topology: SaveJar on Ethereum Sepolia (origin + destination),
#           AutoSaveReactive on Reactive Lasna.
#
# Prerequisites:
#   - .env filled in (see .env.example), burner funded with >= 0.35 Sepolia ETH.
#   - Foundry on PATH (forge / cast).
#
# What it does, in order:
#   0. Swap 0.1 Sepolia ETH -> 10 lREACT via the Reactive faucet contract.
#   1. Deploy SaveJar on Sepolia.
#   2. Deploy AutoSaveReactive on Lasna (with 1 lREACT for fees).
#   3. Point the jar at the reactive contract; seed the callback fee reserve.
#   4. Fire one demo deposit of 0.1 ETH and print everything needed to watch
#      the loop complete (the callback lands within seconds/minutes after).
#
# Addresses and tx hashes are written to deployments.md.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

set -a; source .env; set +a
: "${BURNER_PRIVATE_KEY:?set BURNER_PRIVATE_KEY in .env}"
SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
LASNA_RPC_URL="${LASNA_RPC_URL:-https://lasna-rpc.rnk.dev/}"

FAUCET=0x9b9BB25f1A81078C544C829c5EB7822d747Cf434          # Reactive faucet on Sepolia: 1 ETH -> 100 lREACT
PROXY=0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4           # Callback proxy on Ethereum Sepolia
SEPOLIA_ID=11155111
BURNER=$(cast wallet address --private-key "$BURNER_PRIVATE_KEY")
echo "Burner: $BURNER"
echo "Sepolia balance: $(cast balance "$BURNER" --rpc-url "$SEPOLIA_RPC_URL") wei"

echo "== 0. Faucet: 0.1 Sepolia ETH -> 10 lREACT =="
cast send "$FAUCET" "request(address)" "$BURNER" --value 0.1ether \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BURNER_PRIVATE_KEY"
sleep 10
echo "Lasna balance: $(cast balance "$BURNER" --rpc-url "$LASNA_RPC_URL") wei lREACT"

echo "== 1. Deploy SaveJar (Sepolia) =="
JAR=$(forge create --broadcast --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BURNER_PRIVATE_KEY" \
  src/SaveJar.sol:SaveJar --constructor-args "$PROXY" 604800 | awk '/Deployed to:/{print $3}')
echo "SaveJar: $JAR"

echo "== 2. Deploy AutoSaveReactive (Lasna) =="
# args: originChainId, destinationChainId, jar, saveBps=2000, threshold=0.01 ETH, dailyCap=0.05 ETH
RSC=$(forge create --broadcast --rpc-url "$LASNA_RPC_URL" --private-key "$BURNER_PRIVATE_KEY" --value 1ether \
  src/AutoSaveReactive.sol:AutoSaveReactive \
  --constructor-args "$SEPOLIA_ID" "$SEPOLIA_ID" "$JAR" 2000 10000000000000000 50000000000000000 \
  | awk '/Deployed to:/{print $3}')
echo "AutoSaveReactive: $RSC"

echo "== 3. Configure jar =="
JAR_ADDRESS=$JAR RSC_ADDRESS=$RSC \
  forge script script/ConfigureJar.s.sol --rpc-url "$SEPOLIA_RPC_URL" --broadcast

echo "== 4. Demo deposit: 0.1 ETH (expect a 0.02 ETH auto-save) =="
DEPOSIT_TX=$(cast send "$JAR" "deposit()" --value 0.1ether \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$BURNER_PRIVATE_KEY" | awk '/^transactionHash/{print $2}')
echo "Deposit tx: $DEPOSIT_TX"

cat > deployments.md <<EOF
# Deployments (testnet)

Filled in by deploy-all.sh — keep the tx hashes, the submission needs them.

- Burner (testnet only): $BURNER
- SaveJar (Ethereum Sepolia, 11155111): $JAR
  - https://sepolia.etherscan.io/address/$JAR
- AutoSaveReactive (Reactive Lasna, 5318007): $RSC
  - https://lasna.reactscan.net/address/$RSC
- Demo deposit tx (Sepolia): $DEPOSIT_TX
  - https://sepolia.etherscan.io/tx/$DEPOSIT_TX
- Reactive tx (Lasna): TODO — find via the RSC page on lasna.reactscan.net after the deposit
- Callback tx (Sepolia): TODO — the applySave delivery to SaveJar; find via the jar's
  SaveApplied event on sepolia.etherscan.io

## Verify the loop landed
\`\`\`bash
cast call $JAR "saved(address)(uint256)" $BURNER --rpc-url $SEPOLIA_RPC_URL   # expect 0.02 ETH = 20000000000000000
cast call $JAR "spendable(address)(uint256)" $BURNER --rpc-url $SEPOLIA_RPC_URL # expect 0.08 ETH
\`\`\`
EOF

echo
echo "Done. Watch for the callback, then verify:"
echo "  cast call $JAR \"saved(address)(uint256)\" $BURNER --rpc-url $SEPOLIA_RPC_URL"
echo "Record the Lasna reactive tx + Sepolia callback tx in deployments.md."
