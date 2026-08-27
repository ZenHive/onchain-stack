# Agent Wishlist — onchain

**AI agents are first-class consumers of this library.** This documents what agents want from onchain — use cases that inform future roadmap tasks.

See [ROADMAP.md](ROADMAP.md) for current work. See [CHANGELOG.md](CHANGELOG.md) for completed work.

---

## What onchain gives agents

Onchain is an agent's **hands** — the ability to read chain state, simulate outcomes, and execute transactions programmatically. No wallets, no UIs, no human approval flows. Pure function calls that return structured data.

## Use cases

### DeFi Position Management (beyond Aave)

- **Multi-protocol health monitoring** — Monitor health factors across Aave, Compound, Morpho, Euler simultaneously. Rebalance the weakest position first. Requires generic contract call (task 18) + protocol-specific ABIs via codegen (Phase 5).
- **Automated liquidation protection** — Health factor drops to 1.15. Simulate adding collateral vs repaying debt, compare gas costs, pick the cheaper option, sign, submit. End-to-end autonomous decision without human in the loop.
- **Cross-protocol refinancing** — Detect when borrowing rates on protocol A exceed protocol B. Simulate the full migration (repay A, supply B, borrow B), verify health factor safety, execute if profitable.

### Simulation as Cognition (Phase 6 — revm)

- **"Think before you act"** — Simulate 50 strategies in milliseconds before committing to one on-chain. revm is an agent's inner monologue for financial decisions.
- **DAO governance impact analysis** — "What happens to the treasury if proposal #47 passes?" Simulate the on-chain effects of each governance option before voting programmatically.
- **Gas optimization** — Simulate transactions at different gas prices to find the minimum that gets included. Batch operations during low-gas windows.
- **Risk-free exploration** — An agent learning a new protocol can simulate every possible interaction without spending real ETH. Exploration becomes free.

### Trading & Arbitrage

- **Cross-DEX arbitrage** — Read prices on Uniswap, SushiSwap, Curve simultaneously, simulate the route via revm, execute if profitable. Pure ephemeral: read → simulate → sign → submit.
- **MEV-aware execution** — Understand sandwich attack risk before submitting. Use private transaction submission (Phase 7) when the simulated MEV exposure exceeds threshold.
- **Multi-chain portfolio rebalancing** — If onchain supports L2s (Arbitrum, Optimism, Base), simulate bridge costs + slippage before committing to cross-chain moves.

### Autonomous Operations

- **Contract interaction without pre-coded wrappers** — Contract codegen (Phase 5) means agents can interact with *any* verified contract they discover. No human needs to write a wrapper first. Agent autonomy at the protocol level.
- **Token approval hygiene** — Audit and revoke unnecessary token approvals across all protocols. Read all approvals, assess risk, revoke the dangerous ones.
- **NFT operations** — Bid on auctions, mint on schedule, manage collections. Interact with any NFT contract via codegen.
- **ENS management** — Resolve names, manage registrations, update records programmatically.

### The Pattern

An agent using onchain follows this loop:
1. **Perceive** — Read chain state (eth_call, getLogs, balances)
2. **Simulate** — Test strategies locally (revm)
3. **Decide** — Pick the best option (pure computation)
4. **Act** — Sign and submit (Signer)
5. **Verify** — Check receipt, confirm outcome

Every step is a pure function call returning structured data. No UI, no wallet popups, no human approval. The agent IS the user.
