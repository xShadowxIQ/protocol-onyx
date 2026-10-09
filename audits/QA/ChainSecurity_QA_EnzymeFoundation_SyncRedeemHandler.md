---
Title:    Extensive QA
Author:   ChainSecurity
Date:     08. Oct, 2026
Client:   Enzyme Foundation
---

# Extensive QA


This document reflects an extensive, time-limited QA focused on identifying potential high-impact security vulnerabilities in the code within scope. This QA is not a comprehensive security audit nor does it target finding all vulnerabilities. Instead, it provides a best-effort assessment of whether the code meets core security properties that protect the system's funds, and highlights areas that may require deeper analysis like a full audit or other security measures.


## SyncRedeemHandler - Synchronous Redeem Flow

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff fd6bc5c..58c9d4d`:

```
src/
├── ccip/
│   └── DepositorWallet.sol                                           [MODIFY]
├── components/issuance/
│   ├── deposit-handlers/
│   │   ├── ERC7540LikeDepositQueue.sol                               [MODIFY]
│   │   └── SyncDepositHandler.sol                                    [MODIFY]
│   ├── hooks/chainlink-ace/
│   │   ├── ChainlinkAceSyncRedeemHandlerPostRedeemValidator.sol      [NEW]
│   │   └── extractors/
│   │       └── ChainlinkAceSyncRedeemHandlerPostRedeemExtractor.sol  [NEW]
│   ├── interfaces/
│   │   └── ISyncRedeemHandlerPostRedeemHook.sol                      [NEW]
│   └── redeem-handlers/
│       ├── ERC7540LikeRedeemQueue.sol                                [MODIFY]
│       ├── SharesBurnHandler.sol                                     [MODIFY]
│       └── SyncRedeemHandler.sol                                     [NEW]
└── shares/
    └── Shares.sol                                                    [MODIFY]
```

The modifications to existing files are formatting-only and were confirmed to be equivalent after applying the same formatter. `SharesDeployer.sol` is an internal deployment helper and is out of scope.

### Overview

`SyncRedeemHandler` allows shareholders to burn their shares in exchange for a pro-rated amount of a single configured ERC20 asset, paid from the asset balance held by `Shares` within one transaction. It is the synchronous counterpart of `ERC7540LikeRedeemQueue`.

A redemption requires a non-zero share amount, a cached share price within `maxSharePriceStaleness` and a non-expired rate for the redeem asset. The exit fee is settled on the gross shares, the value of the net shares is converted to the asset amount (reverting if it is 0), and the gross shares are burned from and the assets paid to the caller. Finally, the optional post-redeem hook is called.

`ChainlinkAceSyncRedeemHandlerPostRedeemValidator` and `ChainlinkAceSyncRedeemHandlerPostRedeemExtractor` implement this hook for Chainlink ACE, mirroring their `SyncDepositHandler` counterparts.

### Trust Model

* **Admin / Owner**: Trusted to configure the handler, hook, share values, asset rates and fees correctly and to keep sufficient liquidity in `Shares`. Can block individual redeemers or disable sync redemptions.
* **Other components** (`Shares`, `ValuationHandler`, `FeeHandler`): Trusted to return correct share prices, asset conversions and exit fee amounts. The share price is a cached value. Registered redeem handlers are fully trusted by `Shares`.
* **Post-redeem hook / Chainlink ACE**: Trusted to be correctly configured, as a compliance safety net for an honest admin. Misconfigurations can fail open, e.g., a hook with a non-reverting fallback or a default-allow engine without policies.
* **Redemption asset**: Assumed to be a standard ERC20 with constant decimals and without callbacks, fee-on-transfer, rebasing, pausing or blacklisting.

### Risk

* **Stale share price and round trips.** Redeeming at a cached share price ahead of a share value update shifts losses onto the remaining shareholders.
  * *QA Confidence*: High. The staleness check is identical to `SyncDepositHandler`'s (`0` only accepts a same-block price, `type(uint24).max` disables the check), and fees make round trips in the same asset unprofitable when they exceed the share price move.
  * *System Risk*: Medium. Low, provided fees and `maxSharePriceStaleness` are configured such that round trips are unprofitable.

* **Mispriced asset rates.** Redemptions convert at admin-set asset rates that can deviate from the market until they expire. With different deposit and redeem assets, a deposit followed by a redemption becomes a swap at these rates.
  * *QA Confidence*: High. Expired or unset rates revert. Rates have no maximum expiry and are updated independently of the share value.
  * *System Risk*: Medium. Low, provided rates are refreshed together with the share value and expire quickly.

* **Incorrect share, asset or fee calculation.** Wrong pricing, fee or rounding math could over- or under-pay redeemers at the expense of the remaining shareholders.
  * *QA Confidence*: High. The calculation mirrors `SyncDepositHandler` and `ERC7540LikeRedeemQueue`: the exit fee is taken on the gross shares and the net shares are valued at the current share price, rounded down in favor of the vault (except for the exit fee). An exception is a stored share value of 0, which is priced at a default of 1 value unit per share.
  * *System Risk*: High. An incorrect calculation directly impacts every redemption.

* **Inconsistent fund movement.** Shares could be burned without payout, or assets paid out without burning shares.
  * *QA Confidence*: High. `burnFor()` and `withdrawAssetTo()` are both called unconditionally in `redeem()`.
  * *System Risk*: High. Burning without paying causes a direct loss for the redeemer, and paying without burning drains the remaining shareholders.

* **Redemption DoS.** Redemptions could be blocked, e.g., by insufficient liquidity, stale pricing, expired asset rates or misconfiguration.
  * *QA Confidence*: High. Every cause is recoverable by the admin, and gas does not depend on user input.
  * *System Risk*: Low. Redemptions are delayed but no funds are at risk.

* **Broken access control.** A bug could allow unauthorized configuration changes or redemptions outside the redeem constraints, e.g., burning another holder's shares.
  * *QA Confidence*: High. The admin functions are restricted to the admin or owner, `init` can only run once, and `redeem()` always burns the caller's own shares and pays the caller.
  * *System Risk*: Medium. A bypass would allow configuration changes or redemptions at the expense of other holders.

* **Compliance bypass.** Redemptions could escape holder restrictions, as the post-redeem hook is the only per-holder gate, the shares transfer validator does not apply, and the hook or its policies could be wired or configured incorrectly.
  * *QA Confidence*: High. The handler passes the redeemer, the gross shares and the net assets to the hook, the validator only accepts calls from its handler, and the extractor matches the `SyncDepositHandler` extractor.
  * *System Risk*: Medium. Low, provided per-holder restrictions are enforced through a correctly configured post-redeem hook.

### Findings

* **Note** : If a share value update results in 0 (e.g., after a total loss), `getSharePrice()` returns a default price of 1 value unit per share, so holders of worthless shares can redeem against the fee reserve or new deposits.

* **Note** : With different deposit and redeem assets, a deposit followed by a redemption is an atomic swap at the admin-set asset rates, net of fees and independent of the share price. If a rate diverges from the market (e.g., during a depeg), any accepted depositor can swap until the vault's balance of the redeem asset is exhausted.

* **Note** : `Shares.burnFor()` does not consult the shares transfer validator, so a holder whose transfers are blocked can still redeem and receive the assets immediately. Vaults relying on the transfer validator should enforce the same restriction in the post-redeem hook.

* **Note** : If the handler is registered before the post-redeem hook is set, holders can redeem without the hook's policies being evaluated. `SharesDeployer` sets the hook before registering the handler.

* **Note** : The pre-existing `FeeHandler` rounds exit fee shares down, in favor of the redeemer, so each sync redemption can underpay the exit fee by less than one share-wei.

---

# Limitations and Use of This Report
This report was created at the client's request and is provided "as-is." The ChainSecurity Terms of Business apply. All rights reserved. (c) by ChainSecurity.

This QA was performed within a limited scope and timeframe, and cannot guarantee finding all vulnerabilities. We draw attention to the fact that, due to inherent limitations in any software development process, an inherent risk remains that even major failures can remain undetected. The report reflects our assessment of the code at a specific point in time and does not account for subsequent changes to the code, environment, or third-party dependencies. Use of the report and implementation of any recommendations is at the client's discretion and risk.
