;; contract title 
;; nn-trade-executor-advanced

;; <add a description here> 
;; This smart contract acts as the on-chain execution layer for off-chain 
;; Neural Network (NN) generated trading signals. 
;; Due to the high computational costs of running NNs on-chain, 
;; this contract relies on authorized "Oracles" (the NN backend or its delegates) 
;; to submit actionable trade signals securely.
;; 
;; New Features Added:
;; - Oracle Staking: Oracles must stake STX to submit trades, ensuring economic security.
;; - Pausability (Circuit Breaker): Contract can be paused in emergencies.
;; - Risk Limits: Daily trading volume caps per Oracle.
;; - Oracle Slashing: A mechanism to punish malicious or poorly-performing Oracles.
;; 
;; Security measures include:
;; - Replay Attack Protection: Ensures unique signal IDs.
;; - Stale Signal Prevention: Enforces block height expirations.
;; - Access Control: Strict whitelisting for Oracles.

;; constants 
;; The principal that deployed the contract (Admin)
(define-constant contract-owner tx-sender)

;; Error codes for security and validation failures
(define-constant err-unauthorized (err u100))
(define-constant err-stale-signal (err u101))
(define-constant err-signal-replayed (err u102))
(define-constant err-invalid-action (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-contract-paused (err u105))
(define-constant err-insufficient-stake (err u106))
(define-constant err-daily-limit-exceeded (err u107))
(define-constant err-no-stake-to-withdraw (err u108))
(define-constant err-already-authorized (err u109))
(define-constant err-not-authorized (err u110))

;; Minimum stake required for an Oracle to submit trades (in micro-STX)
(define-constant min-oracle-stake u50000000) ;; 50 STX

;; Maximum trade volume allowed per Oracle per day
(define-constant max-daily-volume u1000000000) ;; 1000 STX equivalent

;; data maps and vars 
;; Stores the authorized Oracles that are permitted to submit NN signals
(define-map authorized-oracles principal bool)

;; Tracks the amount of STX staked by each Oracle
(define-map oracle-stakes principal uint)

;; Tracks executed signals by their unique ID to prevent replay attacks
(define-map executed-signals uint bool)

;; Tracks daily trading volume per Oracle to enforce risk limits
;; Key: {oracle: principal, day: uint}, Value: uint (volume)
(define-map oracle-daily-volume {oracle: principal, day: uint} uint)

;; Keeps track of the most recently processed signal ID
(define-data-var last-signal-id uint u0)

;; Circuit breaker state to pause the contract in emergencies
(define-data-var contract-paused bool false)

;; Treasury address for slashed funds
(define-data-var treasury-address principal tx-sender)

;; private functions 
;; @desc Helper function to check if a caller is the contract owner
(define-private (is-owner (caller principal))
    (is-eq caller contract-owner)
)

;; @desc Helper function to check if the contract is active
(define-private (is-not-paused)
    (not (var-get contract-paused))
)

;; @desc Helper function to calculate the current "day" based on block height
;; Assuming ~144 blocks per day on Stacks
(define-private (get-current-day)
    (/ block-height u144)
)

;; public functions 

;; --- Admin Functions ---

;; @desc Pauses the contract to prevent any new trades (Circuit Breaker)
(define-public (pause-contract)
    (begin
        (asserts! (is-owner tx-sender) err-unauthorized)
        (ok (var-set contract-paused true))
    )
)

;; @desc Resumes the contract after an emergency
(define-public (resume-contract)
    (begin
        (asserts! (is-owner tx-sender) err-unauthorized)
        (ok (var-set contract-paused false))
    )
)

;; @desc Updates the treasury address where slashed funds go
(define-public (set-treasury-address (new-treasury principal))
    (begin
        (asserts! (is-owner tx-sender) err-unauthorized)
        (ok (var-set treasury-address new-treasury))
    )
)

;; @desc Authorizes a new Oracle to submit NN signals (Admin only)
;; @param oracle; The principal address of the new Oracle
(define-public (add-oracle (oracle principal))
    (begin
        ;; Security Check: Only the contract owner can add new oracles
        (asserts! (is-owner tx-sender) err-unauthorized)
        ;; Check if already authorized
        (asserts! (is-none (map-get? authorized-oracles oracle)) err-already-authorized)
        (ok (map-set authorized-oracles oracle true))
    )
)

;; @desc Removes an Oracle's authorization (Admin only)
;; @param oracle; The principal address to remove
(define-public (remove-oracle (oracle principal))
    (begin
        ;; Security Check: Only the contract owner can remove oracles
        (asserts! (is-owner tx-sender) err-unauthorized)
        (ok (map-delete authorized-oracles oracle))
    )
)

;; --- Oracle Staking Functions ---

;; @desc Allows an authorized Oracle to stake STX to begin trading
(define-public (stake-funds (amount uint))
    (let
        (
            (current-stake (default-to u0 (map-get? oracle-stakes tx-sender)))
            (is-authorized (default-to false (map-get? authorized-oracles tx-sender)))
        )
        (asserts! is-authorized err-not-authorized)
        (asserts! (is-not-paused) err-contract-paused)
        
        ;; Transfer STX from Oracle to this contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update stake record
        (ok (map-set oracle-stakes tx-sender (+ current-stake amount)))
    )
)

;; @desc Allows an Oracle to withdraw their stake (if not slashed)
(define-public (withdraw-stake (amount uint))
    (let
        (
            (current-stake (default-to u0 (map-get? oracle-stakes tx-sender)))
        )
        (asserts! (>= current-stake amount) err-no-stake-to-withdraw)
        
        ;; Transfer STX from contract back to Oracle
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        
        ;; Update stake record
        (ok (map-set oracle-stakes tx-sender (- current-stake amount)))
    )
)

;; --- Core Trade Execution ---

;; @desc Executes a trade based on a Neural Network signal
;; @param signal-id; Unique identifier for the NN signal to prevent replay attacks
;; @param action; u1 for BUY, u2 for SELL
;; @param amount; The amount of the asset to trade (must be > 0)
;; @param min-price; The minimum acceptable price (slippage protection)
;; @param expiration; The block height at which this signal becomes invalid
(define-public (execute-nn-trade
    (signal-id uint)
    (action uint)
    (amount uint)
    (min-price uint)
    (expiration uint)
)
    (let
        (
            (caller tx-sender)
            (is-oracle (default-to false (map-get? authorized-oracles caller)))
            (already-executed (default-to false (map-get? executed-signals signal-id)))
            (oracle-stake (default-to u0 (map-get? oracle-stakes caller)))
            (current-day (get-current-day))
            (daily-vol (default-to u0 (map-get? oracle-daily-volume {oracle: caller, day: current-day})))
        )
        ;; Security Check 1: Ensure contract is active
        (asserts! (is-not-paused) err-contract-paused)

        ;; Security Check 2: Ensure the caller is an authorized NN Oracle
        (asserts! is-oracle err-unauthorized)
        
        ;; Security Check 3: Ensure the Oracle has sufficient stake
        (asserts! (>= oracle-stake min-oracle-stake) err-insufficient-stake)

        ;; Security Check 4: Ensure the signal hasn't expired (prevent stale execution)
        (asserts! (< block-height expiration) err-stale-signal)

        ;; Security Check 5: Ensure this exact signal hasn't been executed before (prevent replay)
        (asserts! (not already-executed) err-signal-replayed)

        ;; Security Check 6: Validate action is either BUY (1) or SELL (2)
        (asserts! (or (is-eq action u1) (is-eq action u2)) err-invalid-action)

        ;; Security Check 7: Ensure trade amount is strictly positive
        (asserts! (> amount u0) err-invalid-amount)
        
        ;; Security Check 8: Enforce daily risk limits (prevent runaway AI draining funds)
        (asserts! (<= (+ daily-vol amount) max-daily-volume) err-daily-limit-exceeded)

        ;; Mark the signal as executed immediately to prevent re-entrancy and replay attacks
        (map-set executed-signals signal-id true)

        ;; Update the daily volume for the Oracle
        (map-set oracle-daily-volume {oracle: caller, day: current-day} (+ daily-vol amount))

        ;; Update the last-signal-id processed for tracking purposes
        (var-set last-signal-id signal-id)

        ;; Execute the trade logic
        ;; Note: In a production environment, this would interface with a DEX via traits (e.g., SIP-010)
        ;; Here we simulate the execution by emitting a structured print event
        (if (is-eq action u1)
            ;; BUY logic simulation
            (begin
                (print {
                    event: "NN_TRADE_EXECUTED",
                    action: "BUY",
                    signal-id: signal-id,
                    amount: amount,
                    min-price: min-price,
                    oracle: caller
                })
                (ok true)
            )
            ;; SELL logic simulation
            (begin
                (print {
                    event: "NN_TRADE_EXECUTED",
                    action: "SELL",
                    signal-id: signal-id,
                    amount: amount,
                    min-price: min-price,
                    oracle: caller
                })
                (ok true)
            )
        )
    )
)

;; =========================================================================
;; NEW FEATURE: ORACLE SLASHING MECHANISM (25+ Lines)
;; =========================================================================
;; @desc This newly added feature provides economic security against malicious
;; or faulty Neural Networks. If an Oracle submits a provably malicious trade
;; (e.g., front-running, extreme slippage parameters meant to drain liquidity),
;; the Admin can dispute the action.
;; 
;; This function will:
;; 1. Verify the caller is the Admin.
;; 2. Instantly revoke the Oracle's authorization.
;; 3. Confiscate (slash) their entire STX stake.
;; 4. Transfer the slashed STX to the DAO Treasury address.
;; 5. Emit a permanent slash event on-chain for auditing.
;; 
;; @param malicious-oracle; The principal of the offending Oracle.
;; @param reason-code; An identifier for the type of malicious activity.
(define-public (report-malicious-oracle (malicious-oracle principal) (reason-code uint))
    (let
        (
            ;; Retrieve the current stake of the malicious oracle
            (confiscated-amount (default-to u0 (map-get? oracle-stakes malicious-oracle)))
            (treasury (var-get treasury-address))
        )
        ;; Security Check: Only the Admin/Owner can execute a slash
        (asserts! (is-owner tx-sender) err-unauthorized)
        
        ;; Ensure the oracle actually has a stake to slash, or is authorized
        ;; Even if stake is 0, we still want to revoke and ban them.
        
        ;; Step 1: Revoke Authorization immediately
        (map-delete authorized-oracles malicious-oracle)
        
        ;; Step 2: Zero out their stake in the ledger
        (map-set oracle-stakes malicious-oracle u0)
        
        ;; Step 3: If they had a stake, transfer the locked STX to the treasury
        (if (> confiscated-amount u0)
            (begin
                ;; Transfer from contract to treasury
                (try! (as-contract (stx-transfer? confiscated-amount tx-sender treasury)))
                
                ;; Emit a detailed slash event
                (print {
                    event: "ORACLE_SLASHED",
                    oracle: malicious-oracle,
                    slashed-amount: confiscated-amount,
                    reason: reason-code,
                    treasury: treasury
                })
                (ok confiscated-amount)
            )
            (begin
                ;; Emit event even if no funds were slashed
                (print {
                    event: "ORACLE_BANNED",
                    oracle: malicious-oracle,
                    slashed-amount: u0,
                    reason: reason-code
                })
                (ok u0)
            )
        )
    )
)


