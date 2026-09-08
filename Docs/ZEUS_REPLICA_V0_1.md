# ZEUS REPLICA V0.1

## Status

V0.1 is the first MT4 implementation of the reverse-engineered Zeus behavior. It is an **instrumented replica**, not a claim of source-code equivalence.

## Implemented

- Market/basket reconciliation.
- Independent BUY and SELL state evaluation.
- Initial pending orders:
  - BUY STOP = Ask + FirstStep.
  - SELL STOP = Bid - FirstStep.
- Normal candidate:
  - no market positions on side -> FirstStep;
  - one or more market positions -> MinDistance.
- Empirical Step fallback used in the controlled logs.
- Empirical lot engine:
  `min(Maxlot, NormalizeDouble(lot * K_Lot^n + n * PlusLot, DigitsLot))`
  where `n` is the number of existing market positions on the side.
- BUY STOP and SELL STOP execution.
- Pending-order trailing:
  - BUY: old price - StepTrallOrders > candidate;
  - SELL: old price + StepTrallOrders < candidate.
- Decision and event telemetry in the terminal journal.
- CSV telemetry files in the MT4 common files area:
  - `ZEUS_REPLICA_EVENTS.csv`
  - `ZEUS_REPLICA_SNAPSHOT.csv`

## Explicitly deferred

The following layers remain disabled/unimplemented until the controlled logs validate them in MT4:

- StopProfit execution.
- CloseBuySell imbalance protection.
- Homeopathy/Global CloseAll orchestration.
- MaxLoss / MaxLossCloseAll extreme branch.
- StopLoss branch.
- CloseBy pairing and residual-volume handling.
- Exact final creation-gate predicates.
- TwoMinDistance / TwoStep operational regime.

## Priority contract

The implementation follows the validated temporal ordering:

`EXIT -> EXECUTE -> RECONCILE -> BUY -> SELL -> TRAILING -> RECONCILE`

V0.1 contains no EXIT engine yet, so the active path is:

`MARKET -> RECONCILE -> INITIAL -> BUY -> SELL -> TRAILING -> RECONCILE`

BUY and SELL are independent machines. When both entry intents are generated in the same cycle, BUY is evaluated before SELL.

## Validation target

The next step is to run this EA against the same controlled XAUUSD tick/tester environment used for the original logs and compare:

1. pending creation timestamps/prices/lots;
2. pending activations;
3. pending modifications;
4. deletes;
5. later exit events once the exit engine is introduced.

A divergence is treated as evidence for a missing/incorrect rule; parameters must not be changed merely to force numerical matching.

## Controlled-test caveat

The original Strategy Tester runs reported an unmatched-data warning (`volume limit 8934 at 2026.09.02 16:00 exceeded`). This does not invalidate the controlled A/B behavioral comparison, but absolute performance results must not be treated as clean benchmark results.
