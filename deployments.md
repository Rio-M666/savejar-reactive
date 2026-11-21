# Deployments (testnet)

Status: **deploy-ready, not yet deployed — blocked on burner funding only.**
All contracts compile, all 17 local tests pass (including a full-loop simulation),
RPC endpoints for both chains are verified reachable from this machine, and
`deploy-all.sh` performs the entire deployment + demo loop in one run.

- Burner (testnet only): `0x0DA57685B06768515563AC4c34edf9c43352AD3D`
  (key in `burner/TESTNET-ONLY-burner.txt` and `.env`, both gitignored)
  - Sepolia balance at last check (2026-11-21): 0 ETH
  - Lasna balance at last check (2026-11-21): 0 lREACT (comes from the faucet swap
    inside deploy-all.sh, once the burner holds Sepolia ETH)
- SaveJar (Ethereum Sepolia, 11155111): TBD
- AutoSaveReactive (Reactive Lasna, 5318007): TBD
- Demo deposit tx (Sepolia): TBD
- Reactive tx (Lasna): TBD
- Callback tx (Sepolia): TBD

## The one remaining step before deployment

Send **≥ 0.35 Sepolia ETH** to the burner address above from any Sepolia faucet
(e.g. a web faucet — this step needs a human/browser; the VM could not obtain
testnet ETH from the CLI alone). Then:

```bash
cd ~/workspace/buildathons/reactive-omni
./deploy-all.sh   # faucet swap -> deploy jar -> deploy RSC -> configure -> demo deposit
```

This file is rewritten with real addresses and tx hashes by that script. After it
runs, record the Lasna reactive tx and the Sepolia callback tx here (instructions
are printed by the script and in DEMO.md's shot checklist).
