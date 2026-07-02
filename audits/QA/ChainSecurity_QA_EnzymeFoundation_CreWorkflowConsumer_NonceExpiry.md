---
Title:    Extensive QA
Author:   ChainSecurity
Date:     25. Jun, 2026
Client:   Enzyme Foundation
---

# Extensive QA


This document reflects an extensive, time-limited QA focused on identifying potential high-impact security vulnerabilities in the code within scope. This QA is not a comprehensive security audit nor does it target finding all vulnerabilities. Instead, it provides a best-effort assessment of whether the code meets core security properties that protect the system's funds, and highlights areas that may require deeper analysis like a full audit or other security measures.


## CRE Workflow Consumer: Nonce & Expiration Protection

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff 15b8145..607bfd1`:

```
src/components/automations/chainlink-cre/CreWorkflowConsumer.sol  [MODIFY]
```

### Overview

The prior QA carried a Note that a reverting `onReport` is retried by the Chainlink `KeystoneForwarder`. As the client uses this consumer to drive `ValuationHandler.updateShareValue`, a revert (typically from a misconfiguration, e.g. a missing access-control grant or the consumer not yet a `user` on the forwarder) could see the report re-executed later against changed state, pushing a stale share value.

To protect against this, the code now wraps the payload in a new `Report` struct `{ nonce, expiresAt, calls }` and adds two checks to `onReport`: an expiry check (`block.timestamp <= expiresAt`) and a strict-sequential nonce check (`nonce == lastNonce + 1`). An expired or already-consumed report can no longer be re-executed. The two checks cover different cases: the nonce enforces ordering and blocks replays, while `expiresAt` bounds staleness, since the nonce advance is rolled back if the forwarded call reverts. `lastNonce` starts at `0`, so the workflow's first nonce is `1`.

### Trust Model

* Chainlink `KeystoneForwarder` and the DON are trusted to verify DON signatures and to prevent replay of an already-succeeded transmission. The forwarder does not dedup on report contents and can retry a failed delivery, so freshness across deliveries is an application responsibility.
* The off-chain CRE workflow is trusted to assign monotonically increasing nonces (`+1` each report) and to set a sensible `expiresAt` (no on-chain upper bound is enforced on the expiry window).
* Admin/owner is trusted for forwarder whitelist configuration and workflow-ID management.
* Whitelisted `(target, selector)` pairs on the `LimitedAccessLimitedCallForwarder` are assumed appropriate for the use case.

### Risk

* **Re-execution of a stale or duplicated report.** A transient `onReport` revert leaves the transmission re-deliverable, so the same (or an out-of-order) report could execute later against changed state.
  * *QA Confidence*: High. The forwarder already blocks re-delivery of a succeeded transmission, so the gap is a failed delivery retried later. Strict sequencing rejects duplicate and out-of-order deliveries, and `expiresAt` bounds staleness. Note that `lastNonce` is advanced before `executeCalls` and rolled back on a revert, so the nonce alone does not stop re-delivery of a reverted report; `expiresAt` is the actual bound there. The two checks are complementary.
  * *System Risk*: Low (reduced from the prior assessment). Residual staleness is bounded by the (off-chain-controlled) expiry window, and any executed call is still bounded by the forwarder whitelist.

* **Liveness / permanent pipeline halt.** Strict `nonce == lastNonce + 1` with gaps rejected means that if a nonce can never be successfully consumed, because its report keeps reverting until `expiresAt`, or its forwarded call reverts indefinitely, then no later report can ever be accepted, since the gap can never be filled.
  * *QA Confidence*: High. Confirmed there is no on-chain setter to advance `lastNonce` and no skip path, so the halt is permanent on-chain. Recovery is off-chain only: the workflow must re-emit nonce `N` with a fresh `expiresAt` before it lapses (or a new consumer instance is deployed).
  * *System Risk*: Low to Medium. Availability only (no fund loss or stale execution); the blast radius is the automation pipeline stalling, recoverable by the trusted workflow operator.

* **Logic error in the nonce/expiry validation.** A flaw in the new ordering, decoding, or arithmetic could let a duplicate or out-of-order report through, or corrupt the nonce state machine.
  * *QA Confidence*: High. The single `==` check rejects replays, lower nonces, and gaps; `lastNonce = 0` forces first nonce `1`; the arithmetic cannot under/overflow. `abi.decode(_report, (Report))` is bounds-checked, so a malformed report reverts rather than misinterpreting fields. Corroborated by the added tests.
  * *System Risk*: Low. The added logic is minimal and directly auditable.

### Findings

* **Note** : strict sequencing has no on-chain escape hatch. If a nonce can never be successfully consumed before its `expiresAt`, no later report is ever accepted. The potential DoS is prevented by the off-chain workflow reusing old (stuck) nonces: it can re-emit that nonce with a fresh expiry, and it can also re-emit it with corrected or benign `calls` so the stuck nonce actually succeeds and the sequence advances. Only if the workflow cannot re-emit at all is the fallback redeploying the consumer, as there is no on-chain way to advance `lastNonce`. It is expected that the off-chain workflows handle the nonce and expiry mechanics elegantly.



# Limitations and Use of This Report
This report was created at the client's request and is provided "as-is." The ChainSecurity Terms of Business apply. All rights reserved. (c) by ChainSecurity.

This QA was performed within a limited scope and timeframe, and cannot guarantee finding all vulnerabilities. We draw attention to the fact that, due to inherent limitations in any software development process, an inherent risk remains that even major failures can remain undetected. The report reflects our assessment of the code at a specific point in time and does not account for subsequent changes to the code, environment, or third-party dependencies. Use of the report and implementation of any recommendations is at the client's discretion and risk.
