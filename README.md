# SaveJar — set-and-forget savings, enforced by a reactive contract

**Reactive Omni Buildathon · "Set It and Forget It" track**

You get paid on-chain. You mean to save 20% of it. You don't — because saving is a
manual chore. SaveJar makes it a rule you set once:

1. **Deposit** ETH into your SaveJar on Ethereum Sepolia. It sits in a *spendable* bucket.
2. A **reactive contract on Reactive Lasna** watches every deposit, computes your
   savings cut (20%), accumulates small cuts until they reach a sweep threshold,
   enforces a daily cap — and then, **with no transaction from you**, calls back.
3. The callback moves the money into a **time-locked savings bucket** (7 days).
   Locked means locked: the contract, not your willpower, enforces the rule.

No bot. No keeper. No "remember to move money on payday." One setup, then it just runs.

Design rationale, judging-criteria mapping and limitations: **[DESIGN.md](DESIGN.md)**.
Demo video script: **[DEMO.md](DEMO.md)**. Deployment record: **[deployments.md](deployments.md)**.

## How it works

```
 Sepolia                 Lasna                     Sepolia
 SaveJar ──Deposit──▶ AutoSaveReactive ──callback──▶ SaveJar.applySave
 spendable            cut=20% · accumulate          saved (locked 7d)
                      threshold · daily cap
```

- `src/SaveJar.sol` — origin + destination contract. Per-user `spendable` / `saved`
  buckets, `Deposit` event, and `applySave()` which only the Sepolia callback proxy
  (`0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`) may call, and only with this jar's
  reactive contract injected as the first payload argument (RVM ID authentication).
- `src/AutoSaveReactive.sol` — deployed on Lasna. Subscribes to `Deposit` in its
  constructor via the Reactive system contract (`0x8888…8888`), keeps per-user
  accrual state, and requests callbacks with `requestCallbackV_1_0`
  (300k gas, above the 100k network minimum). It decides *whether* and *how much*
  to sweep — remove it and nothing moves.

Rule parameters (demo deployment): cut **20%**, sweep threshold **0.01 ETH**,
daily cap **0.05 ETH/user**, lock **7 days**.

## Run the tests

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge test
```

17 tests, including `FullLoop.t.sol`, which simulates the complete
Sepolia → Lasna → Sepolia loop locally (mock system contract etched at the real
system address, callback delivered through a mock proxy with the RVM ID injected)
and asserts that a 0.1 ETH deposit ends up as 0.08 spendable / 0.02 locked —
without the user signing anything after the deposit.

## Deploy to testnet

You need a wallet with **≥ 0.35 Sepolia ETH** (testnet only — use a burner).
That covers the lREACT faucet swap, both deployments, configuration and one demo
deposit. lREACT comes from the Reactive faucet contract on Sepolia
(`0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`, 1 ETH → 100 lREACT); the deploy
script performs the swap itself.

```bash
cp .env.example .env   # fill in BURNER_PRIVATE_KEY
./deploy-all.sh
```

The script deploys both contracts, wires them together, fires a demo deposit of
0.1 ETH, and writes all addresses + the deposit tx hash into `deployments.md`.
Within seconds/minutes the callback lands; verify:

```bash
cast call <JAR> "saved(address)(uint256)" <YOUR_ADDRESS> --rpc-url $SEPOLIA_RPC_URL
# → 20000000000000000  (0.02 ETH — saved automatically)
```

Step-by-step manual deployment (same result, via the Foundry scripts in
`script/`): deploy `SaveJar` on Sepolia → swap Sepolia ETH for lREACT at the
faucet → deploy `AutoSaveReactive` on Lasna with 1 lREACT → run `ConfigureJar`
on Sepolia → deposit.

## Project layout

```
src/        SaveJar.sol · AutoSaveReactive.sol
test/       SaveJar.t.sol · AutoSaveReactive.t.sol · FullLoop.t.sol · mocks/
script/     DeploySepolia · DeployReactive · ConfigureJar
lib/        reactive-lib-omni (official Reactive library — a dependency)
DESIGN.md   concept, track fit, judging-criteria mapping
DEMO.md     <3-minute demo video script
deploy-all.sh · deployments.md
```

## Notes

- Testnet only. The user's real wallets are never involved; deployment uses a
  fresh burner (see `burner/`, gitignored, clearly labeled TESTNET-ONLY).
- Built on the official `reactive-lib-omni`. Original code is the two contracts
  in `src/` plus tests and scripts.
