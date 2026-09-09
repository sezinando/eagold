# EAGOLD — R1 FIRST ENGINE v1.1

## 1. Classification

R1.1 is **not a new business rule**. It is an admission-control sublayer of R1.

- **R1.0 — Core First:** creates the initial BUY STOP and SELL STOP.
- **R1.1 — First Admission Control:** decides whether a new FIRST cycle is allowed to be created.

This follows the modular-design principle of keeping functionally independent modules weakly coupled and allowing one module to be changed without changing the rest of the system. MetaQuotes/MQL5 documentation describes modular EAs in terms of functional completeness, logical independence and minimized data links between modules. 

## 2. R1.0 Core Contract

When the EAGOLD system is flat:

- BUY FIRST price = `Ask + FirstStep`
- SELL FIRST price = `Bid - FirstStep`
- initial volume = `Lot`
- order type = pending STOP

The core calculation is frozen by this specification.

## 3. R1.1 Admission Contract

R1.1 is a **pre-execution authorization layer**.

It may return only:

- `ALLOW` — R1 Core may create the new FIRST cycle.
- `BLOCK` — R1 Core must not create the new FIRST cycle.

R1.1 must not:

- modify existing orders;
- delete existing orders;
- close positions;
- move stops;
- change the lot of an existing order/position;
- execute R4, R5, R7, R9, R10 or R11 actions;
- change `FirstStep` dynamically;
- change the existing lot progression.

### Atomic initial-cycle rule

When Admission Control is enabled, BUY and SELL FIRST admission is evaluated before either order is created. If either side fails an enabled gate, the **entire new FIRST cycle is blocked**. This prevents a partial initial seed from being created and subsequently being interpreted by the existing lifecycle logic as a reason to create an R7 restart on the blocked side.

## 4. Master Switch

`EnableR1AdmissionGate=false` is the compatibility/default mode.

With the master switch OFF, the R1 path remains the previous v0.104 behavior.

The individual controls are also OFF by default.

## 5. Implemented v1.1 Gates

### 5.1 Broker Guard

Checks:

- symbol trade permission when the trade-permission subgate is enabled;
- minimum pending-order distance using `MODE_STOPLEVEL`;
- optional additional safety buffer in points.

MQL4 documents `MODE_STOPLEVEL`, `MODE_TRADEALLOWED`, `MODE_MINLOT`, `MODE_LOTSTEP`, `MODE_MAXLOT` and `MODE_FREEZELEVEL` as symbol properties available through `MarketInfo()`. `MODE_STOPLEVEL` may be dynamic even when it reports zero. 

`MODE_FREEZELEVEL` is documented primarily as a restriction on modifying, cancelling or closing orders inside the freeze zone. It is therefore **not used as an artificial R1 creation blocker** in this version.

### 5.2 Lot Guard

Validates the requested R1 lot against the broker's:

- `MODE_MINLOT`;
- `MODE_MAXLOT`;
- `MODE_LOTSTEP`.

The first implementation rejects an invalid lot instead of silently changing it. This preserves deterministic behavior and avoids hidden strategy changes.

### 5.3 Margin Guard

Uses `AccountFreeMarginCheck()` to verify the account can support the requested volume and, optionally, leaves at least `R1MinFreeMarginAfterOrder` free margin.

MQL4 documents `AccountFreeMarginCheck()` as returning the free margin remaining after the specified market operation at the current price, with error 134 when funds are insufficient. Because R1 creates pending orders, this check is intentionally treated as an admission safety approximation, not as a replacement for the broker's eventual pending-order margin calculation. 

### 5.4 Trade Permission Guard

Checks `MODE_TRADEALLOWED` for the symbol.

## 6. Decision Audit

The R1 admission layer records the latest decision in runtime state and optionally logs:

- `ALLOW / BLOCK`;
- the reason;
- decision timestamp.

Examples:

- `R1 ADMISSION: BLOCK reason=BROKER_STOPLEVEL`
- `R1 ADMISSION: BLOCK reason=BROKER_MIN_LOT`
- `R1 ADMISSION: BLOCK reason=INSUFFICIENT_MARGIN`
- `R1 ADMISSION: ALLOW reason=ALL_ENABLED_GATES_PASS`

## 7. Reserved Future Gates

The following controls remain outside v1.1 implementation and must be introduced independently:

- relative spread;
- spread expansion/stability;
- quote-quality guard;
- tick-gap guard;
- volatility regime guard;
- trend/range regime guard;
- session gate;
- news gate;
- R1 cooldown;
- FIRST expiration.

Each future control must have its own enable switch and must preserve the same non-interference contract.

## 8. Input Responsibility Regions

The EAGOLD input section is organized into explicit responsibility regions:

1. General / Identity
2. Core Money / Lot Progression
3. R1 First Engine / Core
4. R1.1 First Admission Control
5. R4 / R5 / R7 Lifecycle
6. R9 Exposure Controller
7. R10 Exposure Reduction
8. R11 Recovery Step Control
9. UI / Panel

This organization is intentional. MetaQuotes documentation and examples treat EA inputs as externally configurable parameters, and modular EA documentation recommends separating responsibilities into independent modules. 

## 9. Non-Interference Contract

> **R1.1 may prevent the creation of a new FIRST cycle, but it has no authority over anything that already exists.**

If a FIRST order has already been created, a later spread, margin, regime or other condition must not cause R1.1 to delete or modify it.

R1.1 only participates at the point where a new FIRST cycle is about to be created.

## 10. Testing Strategy

The implementation must be tested incrementally:

1. v0.105 with `EnableR1AdmissionGate=false` — baseline equivalence.
2. Master ON, all individual gates OFF — framework equivalence.
3. Broker Guard only.
4. Lot Guard only.
5. Margin Guard only.
6. Trade Permission Guard only.
7. Combinations, one gate at a time.

No regime, news, adaptive-step or adaptive-lot behavior should be introduced in the same change as these foundational controls.

## 11. Architectural Principle

R1.1 follows the pattern:

`Input -> Process -> Decision -> Output`

It does not perform trading execution itself. The R1 Core remains the only component responsible for creating the FIRST orders.

This separation is aligned with modular EA guidance that modules should be functionally complete, logically independent and communicate through limited interfaces. 
