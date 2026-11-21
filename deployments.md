# Deployments (testnet)

Status: **not yet deployed** — everything is built and tested locally; deployment is
one script run away once the burner wallet holds Sepolia ETH.

- Burner (testnet only): see `burner/TESTNET-ONLY-burner.txt`
- SaveJar (Ethereum Sepolia, 11155111): TBD
- AutoSaveReactive (Reactive Lasna, 5318007): TBD
- Demo deposit tx (Sepolia): TBD
- Reactive tx (Lasna): TBD
- Callback tx (Sepolia): TBD

To deploy: fund the burner with ≥ 0.35 Sepolia ETH, copy `.env.example` to `.env`,
fill in the burner key, then run `./deploy-all.sh`. This file is rewritten with the
real addresses and tx hashes by that script.
