# Demo video script — SaveJar (target: 2:30, hard limit 3:00)

**Format:** screen recording, two explorer tabs pre-opened (Sepolia Etherscan for the
jar, Lasna ReactScan for the reactive contract), one terminal. Record the deposit
*live* — the callback landing on its own is the whole pitch. Have `deployments.md`
open in a third tab for the closing shot.

| Time | On screen | Narration (key points) |
|---|---|---|
| 0:00–0:20 | Title + the jar's Etherscan page, buckets at 0 | "Getting paid on-chain is easy. Saving a cut of it is a manual chore — so it doesn't happen. SaveJar turns saving into a rule you set once." |
| 0:20–0:45 | DESIGN.md architecture diagram / README | "One contract on Sepolia holds my money in two buckets: spendable and saved. A reactive contract on Lasna watches it. My rule: save 20% of every deposit, sweep once it reaches 0.01 ETH, cap 0.05 a day, lock it for 7 days." |
| 0:45–1:05 | Terminal: `cast call` spendable/saved = 0 | "Right now: nothing saved. Watch what I *don't* do next — I make one ordinary deposit, and I never touch the savings side." |
| 1:05–1:25 | Terminal: deposit 0.1 ETH tx; Etherscan deposit tx | "One deposit, 0.1 ETH. That's the only transaction I sign in this entire demo." |
| 1:25–1:50 | Lasna ReactScan: reactive tx appears on AutoSaveReactive | "Lasna saw the event in about a second. The reactive contract did the maths itself — 20% cut, threshold check, daily cap — and requested a callback. No bot, no keeper, nobody's server." |
| 1:50–2:10 | Etherscan: callback tx into the jar, `SaveApplied` event; `cast call` saved = 0.02 ETH | "And the callback landed back on Sepolia: 0.02 ETH moved into locked savings. Full loop: deposit, reaction, callback — three transactions, I signed one." |
| 2:10–2:25 | Terminal: `withdrawSaved` reverts (StillLocked); small second deposit 0.02 ETH → cut accrues but no sweep (below threshold) | "Two details that make it a real rule, not a demo trick: locked means locked — even I can't withdraw for 7 days. And tiny deposits don't waste gas on callbacks; their cuts pile up until they're worth sweeping." |
| 2:25–2:30 | deployments.md with the three tx hashes | "Set it, forget it, and the chain keeps the promise. Code, addresses and every tx hash are in the repo." |

**Shot checklist before recording**

- [ ] Burner funded; contracts deployed; `deployments.md` filled in (see deploy-all.sh)
- [ ] One *prior* successful loop already on-chain as a fallback if the live callback is slow
- [ ] Explorer tabs zoomed so addresses/hashes are legible; terminal font ≥ 16pt
- [ ] Backup plan: if the live callback takes > 60 s, cut to the fallback loop's tx hashes
      and narrate over them — the fallback is the same code path, already on-chain
