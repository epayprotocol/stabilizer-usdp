# USD.P Stabilizer (USDP) — Smart Contract

Contract: [USDPStabilizer.sol](USDPStabilizer.sol)

Purpose
- On-chain stabilization logic that programmatically mints or burns USDP to steer the market price toward a target.
- Governed by deviation bands and adjustment rates, with cooldown windows, daily limits, and strict role-based access plus emergency controls.
- Exposes clear administrative APIs, runtime views, and detailed events for observability and governance.

---

## How It Works

Peg target, units, and rates
- Target and units:
  - Target price: [Solidity.TARGET_PRICE()](USDPStabilizer.sol:57)
  - Price decimals scaling: [Solidity.PRICE_DECIMALS()](USDPStabilizer.sol:59)
  - Basis points scaling for percentage math: [Solidity.BASIS_POINTS()](USDPStabilizer.sol:58)
- Deviation bands and adjustment rates:
  - Deviation thresholds: [Solidity.SMALL_DEVIATION()](USDPStabilizer.sol:62), [Solidity.MEDIUM_DEVIATION()](USDPStabilizer.sol:63), [Solidity.LARGE_DEVIATION()](USDPStabilizer.sol:64), [Solidity.EXTREME_DEVIATION()](USDPStabilizer.sol:65)
  - Band-specific adjustment rates: [Solidity.SMALL_ADJUSTMENT_RATE()](USDPStabilizer.sol:68), [Solidity.MEDIUM_ADJUSTMENT_RATE()](USDPStabilizer.sol:69), [Solidity.LARGE_ADJUSTMENT_RATE()](USDPStabilizer.sol:70)
  - Inferred: larger deviations map to larger adjustment rates to react proportionally.
- Price inputs (oracles):
  - Market oracle: [Solidity.usdpMarketOracle()](USDPStabilizer.sol:118)
  - Reference oracle: [Solidity.usdtOracle()](USDPStabilizer.sol:119)
  - Inferred: the contract derives an effective USDP/USD price using the two oracle inputs, then compares it to [Solidity.TARGET_PRICE()](USDPStabilizer.sol:57).

Stabilization flow
- Entrypoint: [Solidity.stabilize()](USDPStabilizer.sol:258)
  1) Price deviation check: [Solidity.checkPriceDeviation()](USDPStabilizer.sol:298)
     - Extreme deviations revert (≥ [Solidity.EXTREME_DEVIATION()](USDPStabilizer.sol:65)).
  2) Adjustment calculation: [Solidity.calculateAdjustment()](USDPStabilizer.sol:342)
  3) Execute action:
     - Mint path: [Solidity._executeMint()](USDPStabilizer.sol:396)
     - Burn path: [Solidity._executeBurn()](USDPStabilizer.sol:413)
     - Inferred: when market price is above target, mint; when below target, burn.
     - Inferred: execution interacts with [Solidity.usdpToken()](USDPStabilizer.sol:117) and may route via [Solidity.treasury()](USDPStabilizer.sol:120).
  4) State updates and bookkeeping: [Solidity._updateStateAfterStabilization()](USDPStabilizer.sol:474)
- Runtime gates and safety:
  - Cooldown guard: [Solidity.notInCooldown()](USDPStabilizer.sol:247) with bounds [Solidity.MIN_COOLDOWN()](USDPStabilizer.sol:73) and [Solidity.MAX_COOLDOWN()](USDPStabilizer.sol:74)
  - Emergency halt guard: [Solidity.notEmergencyHalted()](USDPStabilizer.sol:242)
  - Reentrancy guard: [Solidity.nonReentrant()](USDPStabilizer.sol:46)
- Daily limits
  - Daily reset period: [Solidity.DAILY_RESET_PERIOD()](USDPStabilizer.sol:75)
  - Event on reset: [Solidity.DailyLimitReset()](USDPStabilizer.sol:159)
  - Inferred: daily stabilization limits reset on the configured cadence.
- Accounting and statistics
  - Totals and counters: [Solidity.totalMintedForStabilization()](USDPStabilizer.sol:130), [Solidity.totalBurnedForStabilization()](USDPStabilizer.sol:131), [Solidity.stabilizationCount()](USDPStabilizer.sol:132), [Solidity.lastAdjustmentAmount()](USDPStabilizer.sol:133)

---

## Architecture and Components

- Single contract: [USDPStabilizer.sol](USDPStabilizer.sol)
- External references and dependencies:
  - USDP token: [Solidity.usdpToken()](USDPStabilizer.sol:117)
  - Oracles: [Solidity.usdpMarketOracle()](USDPStabilizer.sol:118), [Solidity.usdtOracle()](USDPStabilizer.sol:119)
  - Treasury: [Solidity.treasury()](USDPStabilizer.sol:120)
- Configuration and state
  - Parameter struct getter: [Solidity.params()](USDPStabilizer.sol:122)
  - State struct getter: [Solidity.state()](USDPStabilizer.sol:123)
- Initialization
  - Constructor: [Solidity.constructor()](USDPStabilizer.sol:183)
  - Inferred: constructor wires initial addresses and initial parameterization.
- Modifiers and gates
  - Ownership and admin: [Solidity.onlyOwner()](USDPStabilizer.sol:35)
  - Authorized stabilization: [Solidity.onlyAuthorizedStabilizer()](USDPStabilizer.sol:232)
  - Emergency operations: [Solidity.onlyEmergencyOperator()](USDPStabilizer.sol:237)
  - Runtime safety: [Solidity.notEmergencyHalted()](USDPStabilizer.sol:242), [Solidity.notInCooldown()](USDPStabilizer.sol:247), [Solidity.nonReentrant()](USDPStabilizer.sol:46)

---

## Roles and Access Control

- Owner
  - Administrative setters and governance:
    - Parameters: [Solidity.updateParameters()](USDPStabilizer.sol:511)
    - Assign roles: [Solidity.setAuthorizedStabilizer()](USDPStabilizer.sol:526), [Solidity.setEmergencyOperator()](USDPStabilizer.sol:534)
    - Infra: [Solidity.updateOracles()](USDPStabilizer.sol:555), [Solidity.updateTreasury()](USDPStabilizer.sol:566)
    - Ownership: [Solidity.transferOwnership()](USDPStabilizer.sol:572), [Solidity.acceptOwnership()](USDPStabilizer.sol:578)
  - Access modifier: [Solidity.onlyOwner()](USDPStabilizer.sol:35)
- Authorized Stabilizer
  - Permitted to invoke stabilization operations: [Solidity.stabilize()](USDPStabilizer.sol:258)
  - Access modifier: [Solidity.onlyAuthorizedStabilizer()](USDPStabilizer.sol:232)
- Emergency Operator
  - Emergency controls: [Solidity.emergencyHalt()](USDPStabilizer.sol:541)
  - Access modifier: [Solidity.onlyEmergencyOperator()](USDPStabilizer.sol:237)
  - Resume is owner-only: [Solidity.emergencyResume()](USDPStabilizer.sol:547)
- Public
  - Read-only views: [Solidity.getStabilizationStatus()](USDPStabilizer.sol:595), [Solidity.getStatistics()](USDPStabilizer.sol:628), [Solidity.getParameters()](USDPStabilizer.sol:644), [Solidity.getState()](USDPStabilizer.sol:650)

---

## Parameters and Configuration

- Constants defining targets, units, and controls:
  - Target/units: [Solidity.TARGET_PRICE()](USDPStabilizer.sol:57), [Solidity.PRICE_DECIMALS()](USDPStabilizer.sol:59), [Solidity.BASIS_POINTS()](USDPStabilizer.sol:58)
  - Deviation bands: [Solidity.SMALL_DEVIATION()](USDPStabilizer.sol:62), [Solidity.MEDIUM_DEVIATION()](USDPStabilizer.sol:63), [Solidity.LARGE_DEVIATION()](USDPStabilizer.sol:64), [Solidity.EXTREME_DEVIATION()](USDPStabilizer.sol:65)
  - Adjustment rates: [Solidity.SMALL_ADJUSTMENT_RATE()](USDPStabilizer.sol:68), [Solidity.MEDIUM_ADJUSTMENT_RATE()](USDPStabilizer.sol:69), [Solidity.LARGE_ADJUSTMENT_RATE()](USDPStabilizer.sol:70)
  - Cooldown bounds: [Solidity.MIN_COOLDOWN()](USDPStabilizer.sol:73), [Solidity.MAX_COOLDOWN()](USDPStabilizer.sol:74)
  - Daily reset: [Solidity.DAILY_RESET_PERIOD()](USDPStabilizer.sol:75)
- Tunable parameters
  - Update: [Solidity.updateParameters()](USDPStabilizer.sol:511)
  - Inspect: [Solidity.getParameters()](USDPStabilizer.sol:644), [Solidity.params()](USDPStabilizer.sol:122)
  - Inferred: parameters include stabilization rates/limits and timing windows; values must respect bounds (e.g., cooldown within min/max; rates in basis points).
- State and statistics
  - Inspect: [Solidity.getState()](USDPStabilizer.sol:650), [Solidity.getStatistics()](USDPStabilizer.sol:628)

---

## Operations Guide

Automated stabilization
- Entrypoint: [Solidity.stabilize()](USDPStabilizer.sol:258)
- Behavior
  - Reads oracles via [Solidity.checkPriceDeviation()](USDPStabilizer.sol:298)
  - Computes the required adjustment via [Solidity.calculateAdjustment()](USDPStabilizer.sol:342)
  - Executes mint or burn via [Solidity._executeMint()](USDPStabilizer.sol:396) or [Solidity._executeBurn()](USDPStabilizer.sol:413)
  - Finalizes with [Solidity._updateStateAfterStabilization()](USDPStabilizer.sol:474)
- Guards and limits
  - Cooldown: [Solidity.notInCooldown()](USDPStabilizer.sol:247)
  - Emergency: [Solidity.notEmergencyHalted()](USDPStabilizer.sol:242)
  - Reentrancy: [Solidity.nonReentrant()](USDPStabilizer.sol:46)
  - Daily resets: [Solidity.DAILY_RESET_PERIOD()](USDPStabilizer.sol:75) with [Solidity.DailyLimitReset()](USDPStabilizer.sol:159)
- Events:
  - [Solidity.PriceDeviationDetected()](USDPStabilizer.sol:147), [Solidity.StabilizationExecuted()](USDPStabilizer.sol:139)

Manual overrides
- Direct manual actions:
  - Mint: [Solidity.executeMint()](USDPStabilizer.sol:376)
  - Burn: [Solidity.executeBurn()](USDPStabilizer.sol:384)
- Inferred:
  - Designed for controlled interventions (e.g., oracle downtime or governance decisions).
  - Bypasses cooldown and daily limits (inferred from code paths).
  - Subject to role checks and expected to respect emergency halt via contract logic.

Emergency controls
- Halt and resume stabilization:
  - Halt: [Solidity.emergencyHalt()](USDPStabilizer.sol:541) (emergency operator)
  - Resume: [Solidity.emergencyResume()](USDPStabilizer.sol:547) (owner)
  - Events: [Solidity.EmergencyHalt()](USDPStabilizer.sol:155), [Solidity.EmergencyResume()](USDPStabilizer.sol:156)

Administrative setters and views
- Parameters: [Solidity.updateParameters()](USDPStabilizer.sol:511)
- Roles and infra: [Solidity.setAuthorizedStabilizer()](USDPStabilizer.sol:526), [Solidity.setEmergencyOperator()](USDPStabilizer.sol:534), [Solidity.updateOracles()](USDPStabilizer.sol:555), [Solidity.updateTreasury()](USDPStabilizer.sol:566)
- Ownership: [Solidity.transferOwnership()](USDPStabilizer.sol:572), [Solidity.acceptOwnership()](USDPStabilizer.sol:578)
- Views: [Solidity.getStabilizationStatus()](USDPStabilizer.sol:595), [Solidity.getStatistics()](USDPStabilizer.sol:628), [Solidity.getParameters()](USDPStabilizer.sol:644), [Solidity.getState()](USDPStabilizer.sol:650)

---

## Events

- Core stabilization
  - [Solidity.PriceDeviationDetected()](USDPStabilizer.sol:147): emitted when a deviation is measured.
  - [Solidity.StabilizationExecuted()](USDPStabilizer.sol:139): emitted after a mint/burn adjustment.
- Governance and configuration
  - [Solidity.ParametersUpdated()](USDPStabilizer.sol:157)
  - [Solidity.CooldownPeriodAdjusted()](USDPStabilizer.sol:158)
  - [Solidity.DailyLimitReset()](USDPStabilizer.sol:159)
  - [Solidity.AuthorizedStabilizerChanged()](USDPStabilizer.sol:161)
  - [Solidity.EmergencyOperatorChanged()](USDPStabilizer.sol:162)
  - [Solidity.OwnershipTransferred()](USDPStabilizer.sol:163)
- Emergency
  - [Solidity.EmergencyHalt()](USDPStabilizer.sol:155)
  - [Solidity.EmergencyResume()](USDPStabilizer.sol:156)

---

## Deployment Checklist

- Constructor
  - Initialize via: [Solidity.constructor()](USDPStabilizer.sol:183)
  - Inferred inputs: owner, [Solidity.usdpToken()](USDPStabilizer.sol:117), [Solidity.usdpMarketOracle()](USDPStabilizer.sol:118), [Solidity.usdtOracle()](USDPStabilizer.sol:119), [Solidity.treasury()](USDPStabilizer.sol:120)
  - Inferred non-zero requirements: owner, USDP token, and both oracles must be non-zero; treasury may be zero.
- Post-deploy configuration
  - Assign operators:
    - Set stabilizer: [Solidity.setAuthorizedStabilizer()](USDPStabilizer.sol:526)
    - Set emergency operator: [Solidity.setEmergencyOperator()](USDPStabilizer.sol:534)
  - Wire infrastructure if needed:
    - Oracles: [Solidity.updateOracles()](USDPStabilizer.sol:555)
    - Treasury: [Solidity.updateTreasury()](USDPStabilizer.sol:566)
  - Configure stabilization parameters within bounds:
    - [Solidity.updateParameters()](USDPStabilizer.sol:511)
    - Bounds: [Solidity.MIN_COOLDOWN()](USDPStabilizer.sol:73), [Solidity.MAX_COOLDOWN()](USDPStabilizer.sol:74), rates in [Solidity.BASIS_POINTS()](USDPStabilizer.sol:58)
  - Verify state and configuration:
    - [Solidity.getParameters()](USDPStabilizer.sol:644), [Solidity.getState()](USDPStabilizer.sol:650), [Solidity.getStatistics()](USDPStabilizer.sol:628), [Solidity.getStabilizationStatus()](USDPStabilizer.sol:595)
  - Ownership handover (if applicable):
    - [Solidity.transferOwnership()](USDPStabilizer.sol:572) then [Solidity.acceptOwnership()](USDPStabilizer.sol:578)
- Inferred operational readiness:
  - Ensure authorized addresses and oracles are correct before enabling regular stabilization cycles.

---

## Security Considerations and Limitations

- Access control
  - Administrative actions gated by [Solidity.onlyOwner()](USDPStabilizer.sol:35)
  - Stabilization actions gated by [Solidity.onlyAuthorizedStabilizer()](USDPStabilizer.sol:232)
  - Emergency controls gated by [Solidity.onlyEmergencyOperator()](USDPStabilizer.sol:237)
- Runtime safety
  - Reentrancy protection: [Solidity.nonReentrant()](USDPStabilizer.sol:46)
  - Emergency circuit breaker: [Solidity.notEmergencyHalted()](USDPStabilizer.sol:242), with [Solidity.emergencyHalt()](USDPStabilizer.sol:541)/[Solidity.emergencyResume()](USDPStabilizer.sol:547)
  - Throttling: cooldown via [Solidity.notInCooldown()](USDPStabilizer.sol:247) and daily reset [Solidity.DAILY_RESET_PERIOD()](USDPStabilizer.sol:75)
- Oracle dependencies
  - Uses [Solidity.usdpMarketOracle()](USDPStabilizer.sol:118) and [Solidity.usdtOracle()](USDPStabilizer.sol:119); oracle accuracy, freshness, and integrity are critical. (inferred)
  - Inferred limitation: no explicit staleness/round completeness checks on the USDT reference oracle beyond latestAnswer usage.
- Deviation handling
  - Extreme deviations revert the stabilization attempt (≥ [Solidity.EXTREME_DEVIATION()](USDPStabilizer.sol:65)); operators may choose to invoke [Solidity.emergencyHalt()](USDPStabilizer.sol:541) in such conditions. (inferred)
- Treasury and token flows
  - Adjustments interact with [Solidity.usdpToken()](USDPStabilizer.sol:117) and [Solidity.treasury()](USDPStabilizer.sol:120); ensure correct custody and permissions. (inferred)
- Manual overrides
  - [Solidity.executeMint()](USDPStabilizer.sol:376) and [Solidity.executeBurn()](USDPStabilizer.sol:384) bypass cooldown and daily limits (inferred); use with strong operational controls. (inferred)
- Other limitations
  - No DEX/AMM interactions or slippage controls present. (inferred)
  - Custom errors may be declared but string reverts are used in several paths. (inferred)
- Upgradeability
  - Not proxy-based; uses [Solidity.constructor()](USDPStabilizer.sol:183). (inferred)
- Gas and operational notes
  - O(1) execution with a small number of external calls; emits multiple events per stabilization. (inferred)

---

## References

Core entrypoints and flow
- Stabilize: [Solidity.stabilize()](USDPStabilizer.sol:258)
- Price deviation: [Solidity.checkPriceDeviation()](USDPStabilizer.sol:298)
- Adjustment calculation: [Solidity.calculateAdjustment()](USDPStabilizer.sol:342)
- Execute adjustment (internal): [Solidity._executeMint()](USDPStabilizer.sol:396), [Solidity._executeBurn()](USDPStabilizer.sol:413)
- Finalize state: [Solidity._updateStateAfterStabilization()](USDPStabilizer.sol:474)

Manual operations
- [Solidity.executeMint()](USDPStabilizer.sol:376), [Solidity.executeBurn()](USDPStabilizer.sol:384)

Administration and controls
- Parameters: [Solidity.updateParameters()](USDPStabilizer.sol:511)
- Roles and operators: [Solidity.setAuthorizedStabilizer()](USDPStabilizer.sol:526), [Solidity.setEmergencyOperator()](USDPStabilizer.sol:534)
- Emergency: [Solidity.emergencyHalt()](USDPStabilizer.sol:541), [Solidity.emergencyResume()](USDPStabilizer.sol:547)
- Infra: [Solidity.updateOracles()](USDPStabilizer.sol:555), [Solidity.updateTreasury()](USDPStabilizer.sol:566)
- Ownership: [Solidity.transferOwnership()](USDPStabilizer.sol:572), [Solidity.acceptOwnership()](USDPStabilizer.sol:578)

Views and getters
- Status and stats: [Solidity.getStabilizationStatus()](USDPStabilizer.sol:595), [Solidity.getStatistics()](USDPStabilizer.sol:628)
- Configuration and state: [Solidity.getParameters()](USDPStabilizer.sol:644), [Solidity.getState()](USDPStabilizer.sol:650), [Solidity.params()](USDPStabilizer.sol:122), [Solidity.state()](USDPStabilizer.sol:123)

Constants and invariants
- Target and units: [Solidity.TARGET_PRICE()](USDPStabilizer.sol:57), [Solidity.PRICE_DECIMALS()](USDPStabilizer.sol:59), [Solidity.BASIS_POINTS()](USDPStabilizer.sol:58)
- Bands and rates: [Solidity.SMALL_DEVIATION()](USDPStabilizer.sol:62), [Solidity.MEDIUM_DEVIATION()](USDPStabilizer.sol:63), [Solidity.LARGE_DEVIATION()](USDPStabilizer.sol:64), [Solidity.EXTREME_DEVIATION()](USDPStabilizer.sol:65), [Solidity.SMALL_ADJUSTMENT_RATE()](USDPStabilizer.sol:68), [Solidity.MEDIUM_ADJUSTMENT_RATE()](USDPStabilizer.sol:69), [Solidity.LARGE_ADJUSTMENT_RATE()](USDPStabilizer.sol:70)
- Timing: [Solidity.MIN_COOLDOWN()](USDPStabilizer.sol:73), [Solidity.MAX_COOLDOWN()](USDPStabilizer.sol:74), [Solidity.DAILY_RESET_PERIOD()](USDPStabilizer.sol:75)

External references
- Token and infra: [Solidity.usdpToken()](USDPStabilizer.sol:117), [Solidity.usdpMarketOracle()](USDPStabilizer.sol:118), [Solidity.usdtOracle()](USDPStabilizer.sol:119), [Solidity.treasury()](USDPStabilizer.sol:120)

Initialization
- [Solidity.constructor()](USDPStabilizer.sol:183)

Access, guards, and gates
- [Solidity.onlyOwner()](USDPStabilizer.sol:35), [Solidity.onlyAuthorizedStabilizer()](USDPStabilizer.sol:232), [Solidity.onlyEmergencyOperator()](USDPStabilizer.sol:237), [Solidity.notEmergencyHalted()](USDPStabilizer.sol:242), [Solidity.notInCooldown()](USDPStabilizer.sol:247), [Solidity.nonReentrant()](USDPStabilizer.sol:46)