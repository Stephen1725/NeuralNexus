# NeuralNexus: Advanced NN Trade Executor

## Overview

**NeuralNexus** is a professional-grade, high-assurance on-chain execution layer designed for the Stacks blockchain. I have engineered this contract to facilitate the seamless integration of off-chain Neural Network (NN) intelligence with secure, trust-minimized smart contract execution. 

Because running heavy machine learning inference on-chain is computationally prohibitive due to gas limits and the clarity VM's architecture, NeuralNexus utilizes a robust **Oracle-Delegate model**. This allows high-frequency, AI-driven trading signals to be validated and executed on-chain while maintaining rigorous security standards through economic collateral, volume gating, and administrative oversight.

---

## Core Philosophy

The primary objective of NeuralNexus is to solve the "Trust Gap" between off-chain signal providers and on-chain liquidity. By implementing a staking and slashing framework, I ensure that Oracles are economically incentivized to act honestly. If an Oracle provides malicious or faulty signals, their collateral is seized, protecting the integrity of the protocol and its stakeholders.

---

## Key Features & Security Modules

### 🛡️ Economic Security (Oracle Staking)
I have built a staking requirement where Oracles must lock a minimum of **50 STX** (`u50000000` micro-STX) to gain execution privileges. This ensures that every participant has "skin in the game."

### ⚡ Circuit Breaker (Pausability)
In the event of a market anomaly or a detected exploit in the NN backend, I have included a global `pause-contract` function. When toggled by the admin, all trade executions are halted immediately to protect the treasury.

### 📊 Risk Management (Daily Volume Caps)
To prevent "runaway AI" scenarios where a bug might drain funds through rapid-fire trading, I implemented a **Daily Trading Volume Cap**. Each Oracle is limited to **1000 STX** equivalent in volume per ~24-hour period (calculated as 144 Stacks blocks).

### 🗡️ Automated Slashing
The contract includes a sophisticated slashing mechanism. The Admin can report a malicious Oracle, which results in:
* Immediate revocation of authorization.
* Total confiscation of the Oracle's STX stake.
* Automatic transfer of funds to a designated DAO Treasury.
* Permanent on-chain audit trail of the ban.

### 🔐 Replay & Stale Signal Protection
* **Unique IDs:** Every signal must have a unique ID, tracked in the `executed-signals` map to prevent replay attacks.
* **TTL (Time-to-Live):** Signals include an expiration block height. If a signal isn't processed before the expiration, it is rejected as "stale."

---

## Technical Specification

### Constants & Configuration
| Constant | Value | Description |
| :--- | :--- | :--- |
| `min-oracle-stake` | 50 STX | Minimum micro-STX required to trade. |
| `max-daily-volume` | 1000 STX | Maximum trade volume per Oracle per day. |
| `contract-owner` | tx-sender | The administrative principal (deployer). |

### Error Codes
| Code | Constant | Description |
| :--- | :--- | :--- |
| `u100` | `err-unauthorized` | Caller lacks administrative or oracle rights. |
| `u101` | `err-stale-signal` | Signal has passed its block height expiration. |
| `u102` | `err-signal-replayed` | This signal ID has already been executed. |
| `u105` | `err-contract-paused` | Action blocked by active circuit breaker. |
| `u106` | `err-insufficient-stake` | Oracle stake has fallen below the 50 STX floor. |
| `u107` | `err-daily-limit-exceeded` | Oracle hit the daily 1000 STX volume cap. |

---

## Detailed Function Guide

### Private Helper Functions
These internal functions are designed for modularity and gas efficiency, handling the core logic checks that power the public interface.

* **`is-owner (caller principal)`**: 
    I use this to gate administrative actions. It compares the `tx-sender` against the `contract-owner` constant.
* **`is-not-paused`**: 
    A boolean check on the `contract-paused` data variable. This is prepended to all state-changing operations to ensure the circuit breaker is respected.
* **`get-current-day`**: 
    I designed this to normalize block heights into 24-hour "days" (assuming 144 blocks/day). This serves as the key for the `oracle-daily-volume` map, allowing for automated rolling limits.

### Public & External Functions

#### Admin & Governance
* **`pause-contract` / `resume-contract`**: 
    Allows me to halt or restart the execution engine. This is critical for emergency responses to external market volatility or identified software bugs.
* **`add-oracle` / `remove-oracle`**: 
    Standard whitelisting functions. I ensure that only the contract owner can manage the pool of authorized signal providers.
* **`set-treasury-address`**: 
    Updates the destination for slashed funds. I built this to ensure that confiscated stakes can be routed to a DAO or community-managed wallet.

#### Staking Operations
* **`stake-funds (amount uint)`**: 
    I designed this for authorized Oracles to deposit their collateral. It handles the `stx-transfer?` call and updates the `oracle-stakes` map. It requires the Oracle to already be whitelisted.
* **`withdraw-stake (amount uint)`**: 
    Allows an Oracle to reclaim their STX. I have implemented strict checks to ensure an Oracle cannot withdraw more than their current balance or funds that have been slashed.

#### Trade Execution & Slashing
* **`execute-nn-trade`**: 
    The core entry point. This function runs an 8-point security check (authorization, pause-state, stake floor, expiration, replay, action validity, amount positivity, and volume limits). Once passed, it records the execution and updates volume metrics.
* **`report-malicious-oracle`**: 
    The "nuclear option" for protocol safety. I programmed this to perform an atomic "revoke and seize" operation. It removes authorization and transfers the Oracle's entire stake to the treasury in a single transaction.

---

## Contribution Guidelines

I welcome contributions to the NeuralNexus project. To maintain the quality and security of the codebase, please adhere to the following workflow:

1.  **Fork the Repository**: Create a dedicated branch for your feature or bug fix.
2.  **Clarity Best Practices**: Ensure all new functions use `asserts!` for validation and provide descriptive error codes.
3.  **Local Testing**: Use `clarinet test` to verify that your changes do not break existing staking or execution logic.
4.  **Submit a Pull Request**: Describe your changes in detail and include logs from your test runs.

---

## License

```text
MIT License

Copyright (c) 2026 NeuralNexus Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Disclaimer
I provide this contract as an advanced framework for AI trading execution. However, smart contracts are inherently experimental. Trading involves significant financial risk. The developers of NeuralNexus are not responsible for financial losses resulting from Neural Network inaccuracies, market volatility, or oracle failure. Use at your own risk.
