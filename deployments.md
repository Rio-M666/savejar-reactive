# Deployments (testnet)

Status: **DEPLOYED AND VERIFIED — the full Sepolia → Lasna → Sepolia loop has
completed on-chain.** A 0.1 ETH demo deposit automatically moved 0.02 ETH (20%)
into the locked savings bucket with no further user transaction.

- Burner (testnet only): 0x0DA57685B06768515563AC4c34edf9c43352AD3D
- SaveJar (Ethereum Sepolia, 11155111): 0x20F8E42683f7F03A477b0aB2474258F3E6B7F301
  - https://sepolia.etherscan.io/address/0x20F8E42683f7F03A477b0aB2474258F3E6B7F301
- AutoSaveReactive (Reactive Lasna, 5318007): 0xfb6A0D0b930694047251CB684F8589D43A58635b
  - https://lasna.reactscan.net/address/0xfb6A0D0b930694047251CB684F8589D43A58635b

## The verified demo loop (all three legs)

- Demo deposit tx (Sepolia): 0x71141abed7d678ef4ae8b8e32aee3f2c256de7abc5b077d34d773be473fe0e2a
  - https://sepolia.etherscan.io/tx/0x71141abed7d678ef4ae8b8e32aee3f2c256de7abc5b077d34d773be473fe0e2a
- Reactive tx (Lasna): 0x7d1fe519a7ca88bf0f0e26c78f09afb677776da16484fe0315c42d5340b1760d
  - https://lasna.reactscan.net/tx/0x7d1fe519a7ca88bf0f0e26c78f09afb677776da16484fe0315c42d5340b1760d
  - Emits `CutAccrued(burner, 0.02 ETH, 0.02 ETH)` and `SweepRequested(burner, 0.02 ETH)`.
- Callback tx (Sepolia): 0x5e22224220dfbf4e182fed21e61913032fb91ad68c5fa6befe69ebccada297bb
  - https://sepolia.etherscan.io/tx/0x5e22224220dfbf4e182fed21e61913032fb91ad68c5fa6befe69ebccada297bb
  - `deliverCallback` via the Sepolia callback proxy; emits
    `SaveApplied(burner, 0.02 ETH, newSavedTotal 0.02 ETH, unlockTime 1795848744)`.

## Verified end state (read on-chain after the callback)

```bash
cast call 0x20F8E42683f7F03A477b0aB2474258F3E6B7F301 "saved(address)(uint256)" 0x0DA57685B06768515563AC4c34edf9c43352AD3D --rpc-url $SEPOLIA_RPC_URL
# → 20000000000000000  (0.02 ETH — saved automatically)
cast call 0x20F8E42683f7F03A477b0aB2474258F3E6B7F301 "spendable(address)(uint256)" 0x0DA57685B06768515563AC4c34edf9c43352AD3D --rpc-url $SEPOLIA_RPC_URL
# → 80000000000000000  (0.08 ETH)
```

- `unlockTime(burner)` = 1795848744 (deposit time + 7 days, as configured).
- Jar debt to the callback proxy after delivery: 0. Fee reserve remaining: ~0.01 ETH.
- Local test suite after all changes: `forge test` — 17 passed, 0 failed.

## Deployment history — read this before re-running anything

The working pair above is the **second** deployment. The first attempt failed in
an instructive way and its contracts are still on-chain (unused):

- Pair #1: SaveJar `0x7138fda0ae8c6097B15a9814Ca0B3aD9A2C74478`,
  AutoSaveReactive `0x3A8C8c65C3D3b675db34f075c4B37b586302f220`.
- Its demo deposit (0x401841945191c57a85d7991c76efe7e469beed524d74e7a598488e1b88c8ffff)
  reacted on Lasna (0xdf583735ecf08eba531a6a1af384a424e0adc6f67b104bf268ab9a703a0409a9)
  and the callback **was** delivered to Sepolia within one block
  (0xa4bff63656231366cbce12d13bcf6b6fedb773d8416ee5e7ee81e945c510edb6) — but
  `applySave` **ran out of gas** inside the delivery.
- Root cause: the Sepolia callback proxy withholds `_extraGas` (150,000, for its
  own accounting) and `_maxChargeGas` (50,000, for payment settlement) from the
  delivery budget before forwarding the remainder (see Reactive docs,
  "Economy & System Interactions → Gas Limits"). Our requested limit of 300,000
  left only **57,114 gas** for `applySave`, which needs more (two fresh storage
  slots + event). The proxy still charged the jar for the failed delivery
  (3,843,486 wei from the fee reserve); no debt remained.
- Fix: `CALLBACK_GAS_LIMIT` in `src/AutoSaveReactive.sol` raised 300,000 →
  1,000,000. The fee is charged on gas actually used, so the higher limit costs
  nothing extra. Because `SaveJar.setReactiveContract` is one-time by design,
  the fix required deploying a fresh jar + reactive pair (the pair above).

Script fixes applied to `deploy-all.sh` along the way (kept minimal, same intent):

- `forge create` now passes `--broadcast` — Foundry 1.10 otherwise does a dry
  run and deploys nothing (this killed the very first run after its faucet swap,
  tx 0x78b3a8aa13952765f0c8beab35d0f76f5579eba42dee169fd6e8528b85f09933).
- Step 4 extracts the deposit tx hash from `cast send`'s text receipt instead of
  parsing `--json` output (the JSON parse threw mid-run on the first deployment;
  that run's deposit was then fired manually with the identical command).
- The faucet swap in step 0 ran once per script run (three times total across
  attempts); the burner holds surplus lREACT on Lasna as a result. Harmless.

## Still to do (later steps, not part of this deployment)

- Record the demo video per DEMO.md. Note its shot checklist asks for one prior
  successful loop as a fallback — the loop recorded above serves as exactly that.
- Push to GitHub and submit to DoraHacks with the three tx hashes above.
