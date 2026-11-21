# Design Note — SaveJar (Reactive Omni Buildathon, "Set It and Forget It" track)

## The concept

**SaveJar — a savings rule you set once, enforced by a reactive contract forever.**

Getting paid on-chain is easy; *saving* a cut of every payment is a manual chore, so it
mostly doesn't happen. SaveJar turns "I should save 20% of everything I receive" into a
one-time setup:

1. The user deposits ETH into their **SaveJar** contract on Ethereum Sepolia. Funds sit in a
   *spendable* bucket. (In a production version this jar would sit on the chain where the
   user actually gets paid — Sepolia is the demo stand-in.)
2. A **reactive contract on Reactive Lasna** watches the jar's `Deposit` events. For every
   deposit it computes the user's savings cut (default 20%), accumulates small cuts until
   they reach a sweep threshold, enforces a per-day cap, and then — with no user
   transaction, no bot, no keeper — requests a callback to Sepolia.
3. The callback moves the accumulated cut from *spendable* into a **time-locked savings
   bucket** inside the same jar. Locked funds can't be withdrawn until the lock expires
   (default 7 days), which is the whole point: the rule is enforced by the contract, not
   by willpower.

The user signs exactly one transaction per deposit (the deposit itself, which they'd make
anyway). Everything after that happens on its own. That is the track brief in one sentence:
*"is this something you'd actually leave running?"* — yes, because there is nothing to run.

## Why this fits "Set It and Forget It"

- **Personal automation, any supported chain** — the track allows any chain Reactive
  supports; Ethereum Sepolia is both an origin and a destination, so the full loop
  (Sepolia → Lasna → Sepolia) runs on testnet with one faucet to feed.
- **Usefulness over speed** — the track explicitly says speed matters less than
  usefulness. Saving discipline is a real, well-understood problem (it's why payroll
  auto-enrolment and round-up apps exist off-chain).
- **No smart-contract experience barrier for the user** — the end user never deploys or
  configures anything on-chain beyond depositing; the rule parameters (cut %, threshold,
  daily cap, lock) are set at setup time.
- **Deliberately not** a DCA bot or a security tripwire — entries for both already exist
  in this track (a WETH auto-DCA with crash guard, and an approval tripwire). SaveJar is a
  different, everyday-money problem.

## How it maps to the judging criteria

| Criterion | How SaveJar answers it |
|---|---|
| **Execution** | Full loop is on-chain and demonstrable in seconds: deposit tx on Sepolia → reactive tx on Lasna → callback tx on Sepolia moving funds into the locked bucket. Tx hashes for all three legs go in the submission (see `deployments.md`). Entries without reactive txs + callbacks "aren't scored further" — this entry is built around producing exactly those artifacts. |
| **Integration** | The reactive contract is not a relay. It holds per-user state (accrued cut, daily totals), does the maths (basis-point cut, dust accumulation to a sweep threshold, daily-cap enforcement) and *decides whether and how much* to sweep. Remove it and nothing moves. |
| **Usefulness** | Automates a savings habit people demonstrably fail at manually; parameters (cut %, threshold, cap, lock length) map to real budgeting behaviour — e.g. freelancers/creators paid on-chain who want a forced savings or tax-reserve cut of every payment. |
| **Craft** | Small, readable contracts (~150 lines of original code) on top of the official `reactive-lib-omni`; a Foundry test suite that simulates the entire loop locally (mock system contract etched at the real system address, mock callback delivery); deployment scripts; this note; a <3-minute demo script (`DEMO.md`). |

## Architecture

```
 Ethereum Sepolia                          Reactive Lasna                Ethereum Sepolia
 ┌──────────────┐   Deposit(user, amt)    ┌──────────────────┐  callback ┌──────────────┐
 │   SaveJar    │ ────── event ─────────▶ │ AutoSaveReactive │ ────────▶ │   SaveJar    │
 │  spendable{} │                          │  cut = amt × bps │ applySave │  saved{}     │
 │  saved{}     │ ◀────── callback ────── │  accumulate dust │ (via      │  (locked)    │
 └──────────────┘   delivered by proxy     │  threshold + cap │  proxy)   └──────────────┘
                                           └──────────────────┘
```

- `src/SaveJar.sol` — origin + destination. Buckets per user, `Deposit` event,
  `applySave()` callable only by the Sepolia callback proxy
  (`0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`) with the reactive contract's address
  injected as the first payload argument (RVM ID authentication, per Reactive docs).
- `src/AutoSaveReactive.sol` — the reactive contract. Subscribes to `Deposit` on Sepolia
  in its constructor via the system contract (`0x8888…8888`), keeps per-user accrual
  state, and requests callbacks with `requestCallbackV_1_0` (gas limit 300k, above the
  100k minimum the docs require).
- Chains: origin = destination = Ethereum Sepolia (11155111); reactive = Lasna (5318007).

## Parameters used in the demo deployment

- Savings cut: 2,000 bps (20%) · Sweep threshold: 0.01 ETH · Daily cap: 0.05 ETH/user
- Lock: 7 days for the "real" configuration; the demo script deploys with the same values
  and explains the lock rather than shortening it, so what judges see is the real rule.

## Known limitations (stated honestly)

- The jar holds the funds it manages; a multi-chain version (get paid on Base, save on
  Ethereum) is a configuration change — the reactive contract already takes origin and
  destination chain IDs independently — but the demo keeps one chain for a clean loop.
- Amounts above the daily cap simply stay spendable; they are not queued for the next day.
- Testnet only. No mainnet deployment is part of this entry.
